// Moteur de synchronisation : envoie les modifications de ce poste, applique celles des autres postes.
// Granularité : l'enregistrement (une pièce, un client, un lot…). Le serveur arbitre : un envoi fait sur une
// version périmée est refusé et renvoyé ; le poste fusionne puis renvoie. Rien n'est écrasé en silence.
import { deviceId, randomId } from './config'
import { COLLECTIONS, VALUE_ID, fingerprint, readLocal, threeWayMerge, writeLocal, type CollectionSpec } from './collections'
import { StorageFullError } from './collections'
import { AuthError, OfflineError, PushError, SupabaseRemote, type Claim, type PushResult, type PushRow, type RemoteRow } from './remote'
import { emptyState, loadState, saveState, type SyncState } from './state'

export type SyncPhase = 'idle' | 'syncing' | 'ok' | 'offline' | 'auth' | 'error'

export interface SyncStatus {
	phase: SyncPhase
	/** Dernière synchronisation réussie (ms) */
	lastSync: number | null
	/** Modifications locales pas encore envoyées */
	pending: number
	/** Modifications des deux côtés sur un même champ : la version de ce poste a été gardée */
	conflicts: number
	message: string
}

const SEP = '␟'
const keyOf = (collection: string, id: string) => collection + SEP + id
/** Marge de relecture : une ligne validée côté serveur juste avant notre lecture peut porter une date un peu antérieure */
const OVERLAP_MS = 15_000
const INTERVAL_MS = 4_000
/** Envois refusés (modifiés ailleurs entre-temps) : fusion puis nouvel envoi, au plus 3 fois par synchro */
const MAX_ROUNDS = 3
/** Envois sans réponse gardés par enregistrement */
const MAX_PENDING = 5

const minus = (iso: string, ms: number) => new Date(new Date(iso).getTime() - ms).toISOString()
/** Comparaison de dates serveur par leur valeur (indépendante du fuseau renvoyé) */
const isLater = (a: string, b: string | null) => !b || new Date(a).getTime() > new Date(b).getTime()
const hashOf = (x: unknown) => (x === undefined ? undefined : fingerprint(x))

export class SyncEngine {
	readonly remote: SupabaseRemote
	private readonly dossier: string
	private readonly device: string
	private state: SyncState = emptyState()
	private loaded = false
	private busy: Promise<void> | null = null
	private timer: number | null = null
	private listeners = new Set<(s: SyncStatus) => void>()
	status: SyncStatus = { phase: 'idle', lastSync: null, pending: 0, conflicts: 0, message: '' }

	constructor(remote: SupabaseRemote, dossier: string, device = deviceId()) {
		this.remote = remote
		this.dossier = dossier
		this.device = device
	}

	/** Mémorise la version serveur de référence d'un enregistrement (empreinte + copie pour la fusion) */
	private remember(k: string, data: unknown | undefined) {
		if (data === undefined) {
			delete this.state.base[k]
			delete this.state.snapshot[k]
		} else {
			this.state.base[k] = fingerprint(data)
			this.state.snapshot[k] = JSON.parse(JSON.stringify(data)) as unknown
		}
	}

	subscribe(fn: (s: SyncStatus) => void): () => void {
		this.listeners.add(fn)
		fn(this.status)
		return () => this.listeners.delete(fn)
	}

	private setStatus(patch: Partial<SyncStatus>) {
		this.status = { ...this.status, ...patch }
		for (const fn of this.listeners) fn(this.status)
	}

	private releaseLock: (() => void) | null = null
	private stopped = false
	/** Un autre onglet de ce poste synchronise : celui-ci attend son tour et ne synchronise pas */
	private waiting = false

	/**
	 * Démarre la synchro automatique. Plusieurs onglets ouverts sur le même poste : un seul synchronise
	 * (verrou du navigateur) ; si on le ferme, un autre onglet prend aussitôt le relais.
	 */
	start() {
		this.stopped = false
		this.setStatus({ phase: 'idle', message: 'Synchronisé par un autre onglet ouvert sur ce poste' })
		const locks = (navigator as Navigator & { locks?: LockManager }).locks
		if (!locks) return this.beginLoop()
		this.waiting = true
		void locks.request(`profitpilot-sync:${this.dossier}`, () => {
			this.waiting = false
			if (this.stopped) return
			this.beginLoop()
			return new Promise<void>((resolve) => {
				this.releaseLock = resolve
			})
		})
	}

	private beginLoop() {
		if (this.timer !== null || this.stopped) return
		void this.syncNow()
		this.timer = window.setInterval(() => void this.syncNow(), INTERVAL_MS)
		window.addEventListener('online', this.onOnline)
	}

	stop() {
		this.stopped = true
		if (this.timer !== null) window.clearInterval(this.timer)
		this.timer = null
		window.removeEventListener('online', this.onOnline)
		this.releaseLock?.()
		this.releaseLock = null
	}

	/** Cet onglet est-il celui qui synchronise ? */
	get active(): boolean {
		return this.timer !== null
	}

	private onOnline = () => void this.syncNow()

	private async ensureLoaded() {
		if (this.loaded) return
		this.state = await loadState(this.dossier)
		this.loaded = true
	}

	/** Une seule synchronisation à la fois ; un appel pendant une synchro attend la fin de celle-ci */
	syncNow(): Promise<void> {
		if (this.waiting) return Promise.resolve()
		this.busy ??= this.run().finally(() => {
			this.busy = null
		})
		return this.busy
	}

	private async run() {
		this.setStatus({ phase: this.status.phase === 'ok' ? 'ok' : 'syncing' })
		try {
			await this.cycle()
			this.setStatus({ phase: 'ok', lastSync: Date.now(), pending: 0, message: '' })
		} catch (e) {
			// Ce qui a été reçu et confirmé avant l'erreur reste acquis
			if (this.loaded) await saveState(this.dossier, this.state)
			const pending = this.loaded ? this.localChanges().length : 0
			if (e instanceof OfflineError) this.setStatus({ phase: 'offline', pending, message: 'Hors ligne : les modifications partiront au retour de la connexion.' })
			else if (e instanceof AuthError) this.setStatus({ phase: 'auth', pending, message: `Connexion refusée : ${e.message}` })
			else this.setStatus({ phase: 'error', pending, message: e instanceof Error ? e.message : String(e) })
		}
	}

	/** Une synchronisation : réception, puis envoi conditionnel (refus → fusion → nouvel envoi) */
	private async cycle() {
		await this.ensureLoaded()
		const since = this.state.lastPull ? minus(this.state.lastPull, OVERLAP_MS) : null
		await this.receive(await this.remote.pull(since), true)
		for (let round = 0; round < MAX_ROUNDS; round++) {
			const changes = this.localChanges()
			if (changes.length === 0) break
			const rows: PushRow[] = changes.map((c) => ({ ...c.row, rev: `${this.device}.${randomId()}`, expected: this.state.seen[c.k] ?? null }))
			// Envoi noté avant de partir : si la réponse se perd, on reconnaîtra notre écriture à la relecture.
			// Une écriture réussie est toujours relue avant l'envoi suivant : quelques envois en attente suffisent.
			for (const r of rows) {
				const k = keyOf(r.collection, r.id)
				this.state.pending[k] = [...(this.state.pending[k] ?? []), { rev: r.rev, data: r.deleted ? null : r.data, deleted: r.deleted }].slice(-MAX_PENDING)
			}
			await saveState(this.dossier, this.state)
			const sent = new Map(rows.map((r) => [keyOf(r.collection, r.id), r]))
			let result: PushResult
			try {
				result = await this.remote.push(rows)
			} catch (e) {
				// Paquets déjà écrits avant l'erreur : confirmés tout de suite
				if (!(e instanceof PushError)) throw e
				this.confirm(e.partial.accepted, sent)
				throw e.original
			}
			this.confirm(result.accepted, sent)
			if (result.rejected.length === 0) break
			// Refusé : notre envoi n'a pas été écrit ; on fusionne avec la version serveur avant de renvoyer
			for (const row of result.rejected) {
				const k = keyOf(row.collection, row.id)
				const rev = sent.get(k)?.rev
				const list = this.state.pending[k]?.filter((p) => p.rev !== rev)
				if (list?.length) this.state.pending[k] = list
				else delete this.state.pending[k]
			}
			await this.receive(result.rejected)
		}
		await saveState(this.dossier, this.state)
	}

	/** Envois écrits par le serveur : ils deviennent la version de référence */
	private confirm(accepted: PushResult['accepted'], sent: Map<string, PushRow>) {
		for (const a of accepted) {
			const k = keyOf(a.collection, a.id)
			const r = sent.get(k)
			if (!r) continue
			this.remember(k, r.deleted ? undefined : r.data)
			this.state.seen[k] = a.updated_at
			delete this.state.pending[k]
		}
	}

	/**
	 * Prépare puis applique des lignes reçues du serveur. Seule une lecture complète (fromPull) fait avancer
	 * la date de dernière lecture : une ligne refusée à l'envoi peut être plus récente que d'autres pas encore lues.
	 */
	private async receive(rows: RemoteRow[], fromPull = false) {
		if (rows.length === 0) return
		// Envoi sans réponse (coupure) puis ligne réécrite par un autre poste : le serveur dit si notre envoi a été écrit
		const unknown: string[] = []
		for (const r of rows) {
			const k = keyOf(r.collection, r.id)
			const pending = this.state.pending[k]
			if (pending && r.updated_at !== this.state.seen[k] && !pending.some((p) => p.rev === r.rev)) unknown.push(...pending.map((p) => p.rev))
		}
		this.applyRemote(rows, await this.remote.appliedRevs(unknown), fromPull)
	}

	/**
	 * Applique les lignes reçues en respectant les modifications de ce poste pas encore envoyées.
	 * L'état (versions de référence) n'avance qu'une fois les données écrites dans le navigateur :
	 * si le stockage est plein, rien n'est perdu, tout sera réappliqué à la synchro suivante.
	 */
	private applyRemote(rows: RemoteRow[], applied: Set<string>, fromPull: boolean) {
		const bySpec = new Map<string, RemoteRow[]>()
		let lastPull = this.state.lastPull
		for (const r of rows) {
			const list = bySpec.get(r.collection) ?? []
			list.push(r)
			bySpec.set(r.collection, list)
			if (fromPull && r.updated_at && isLater(r.updated_at, lastPull)) lastPull = r.updated_at
		}
		let conflicts = this.status.conflicts
		// Les collections qui partagent une clé (articles et leur méta) sont écrites l'une après l'autre
		for (const spec of COLLECTIONS) {
			const incoming = bySpec.get(spec.name)
			if (!incoming) continue
			const local = readLocal(spec)
			const order = [...local.keys()]
			let changed = false
			const accepted: { k: string; row: RemoteRow }[] = []
			for (const row of incoming) {
				const k = keyOf(spec.name, row.id)
				if (row.updated_at && this.state.seen[k] === row.updated_at) continue
				accepted.push({ k, row })
				if (row.deleted && spec.appendOnly) continue

				// Version de référence : la dernière reçue, ou notre propre envoi s'il a été écrit sans que nous le sachions
				let base: string | undefined = this.state.base[k]
				let snapshot = this.state.snapshot[k]
				let known = k in this.state.base || k in this.state.seen
				const mine = [...(this.state.pending[k] ?? [])].reverse().find((p) => p.rev === row.rev || applied.has(p.rev))
				if (mine) {
					base = mine.deleted ? undefined : fingerprint(mine.data)
					snapshot = mine.deleted ? undefined : mine.data
					known = true
				}

				const current = local.get(row.id)
				const localHash = hashOf(current)
				const remoteHash = row.deleted ? undefined : fingerprint(row.data)
				// Modifié sur ce poste depuis la version de référence
				const dirty = known && localHash !== base
				let result: unknown
				if (!known) {
					// Jamais vu sur ce poste (réglage créé sur deux postes, état de synchro perdu) : la version en ligne fait foi
					if (row.deleted) result = current !== undefined && spec.protect?.(current) ? current : undefined
					else if (current !== undefined && spec.merge) result = spec.merge(current, row.data, undefined).result
					else result = row.data
					if (current !== undefined && hashOf(result) !== localHash) conflicts++
				} else if (localHash === remoteHash && !(dirty && spec.deltaFields)) {
					result = current
				} else if (row.deleted) {
					if (current !== undefined && spec.protect?.(current)) result = current // pièce validée : on la garde et on la renvoie
					else if (dirty && current !== undefined) {
						conflicts++ // modifié ici, supprimé ailleurs : la modification l'emporte
						result = current
					} else result = undefined
				} else if (current === undefined) {
					if (dirty && !spec.protect?.(row.data)) {
						conflicts++ // supprimé ici, modifié ailleurs : la suppression l'emporte
						result = undefined
					} else result = row.data
				} else if (spec.merge) {
					// Règles métier : jamais de retour en arrière d'une pièce, règlements additionnés
					const merged = spec.merge(current, row.data, dirty ? snapshot : undefined)
					if (merged.conflict) conflicts++
					result = merged.result
				} else if (dirty) {
					// Modifié des deux côtés : fusion champ par champ à partir de la dernière version commune
					if (snapshot === undefined) {
						conflicts++
						result = row.data
					} else {
						const merged = threeWayMerge(snapshot, current, row.data, spec.deltaFields)
						if (merged.conflict) conflicts++
						result = merged.result
					}
				} else result = row.data

				// Si le résultat diffère de la version serveur, il sera envoyé (sur la base de cette version)
				if (result === undefined) {
					if (local.delete(row.id)) changed = true
				} else if (hashOf(result) !== localHash) {
					if (!local.has(row.id)) order.push(row.id)
					local.set(row.id, result)
					changed = true
				}
			}
			if (changed) writeLocal(spec, local, order) // StorageFullError : rien n'est marqué comme reçu
			for (const { k, row } of accepted) {
				this.remember(k, row.deleted ? undefined : row.data)
				if (row.updated_at) this.state.seen[k] = row.updated_at
				delete this.state.pending[k]
			}
		}
		this.state.lastPull = lastPull
		if (conflicts !== this.status.conflicts) this.setStatus({ conflicts })
	}

	/** Enregistrements locaux différents de leur version de référence */
	private localChanges(): { k: string; row: RemoteRow }[] {
		const out: { k: string; row: RemoteRow }[] = []
		for (const spec of COLLECTIONS) {
			const local = readLocal(spec)
			for (const [id, data] of local) {
				const k = keyOf(spec.name, id)
				if (this.state.base[k] !== fingerprint(data)) out.push({ k, row: { collection: spec.name, id, data, deleted: false } })
			}
			if (spec.appendOnly) continue
			// Supprimé sur ce poste depuis la dernière synchro : on propage la suppression
			const prefix = spec.name + SEP
			for (const k of Object.keys(this.state.base)) {
				if (!k.startsWith(prefix)) continue
				const id = k.slice(prefix.length)
				if (!local.has(id)) out.push({ k, row: { collection: spec.name, id, data: null, deleted: true } })
			}
		}
		return out
	}

	pendingCount(): number {
		return this.loaded ? this.localChanges().length : 0
	}

	/** Action unique sur une pièce (validation, annulation…) : un seul poste l'obtient */
	claim(docId: string, action: string, kind: string, year: number, min: number): Promise<Claim> {
		return this.remote.claim(docId, action, this.device, kind, year, min)
	}

	/** Premier poste : envoie toutes les données locales vers un dossier en ligne vide */
	async uploadAll(): Promise<number> {
		this.state = emptyState()
		this.loaded = true
		const count = this.localChanges().length
		await this.cycle()
		return count
	}

	/** Nouveau poste : remplace les données locales par celles du dossier en ligne */
	async downloadAll(): Promise<number> {
		const rows = await this.remote.pull(null)
		const state = emptyState()
		const bySpec = new Map<string, RemoteRow[]>()
		for (const r of rows) {
			bySpec.set(r.collection, [...(bySpec.get(r.collection) ?? []), r])
			if (r.updated_at) {
				state.seen[keyOf(r.collection, r.id)] = r.updated_at
				if (isLater(r.updated_at, state.lastPull)) state.lastPull = r.updated_at
			}
		}
		let count = 0
		for (const spec of COLLECTIONS) {
			const records = new Map<string, unknown>()
			const order: string[] = []
			for (const r of bySpec.get(spec.name) ?? []) {
				if (r.deleted) continue
				records.set(r.id, r.data)
				order.push(r.id)
				state.base[keyOf(spec.name, r.id)] = fingerprint(r.data)
				state.snapshot[keyOf(spec.name, r.id)] = r.data
				count++
			}
			// Réglage absent en ligne : on garde celui de ce poste (il sera envoyé)
			if (records.size === 0 && spec.kind === 'value' && !bySpec.has(spec.name)) continue
			writeLocal(spec, records, order)
		}
		this.state = state
		this.loaded = true
		await saveState(this.dossier, this.state)
		return count
	}
}

/** Valeur « _ » d'une collection de type value : exportée pour les tests */
export const VALUE_RECORD_ID = VALUE_ID
export { StorageFullError }
export type { CollectionSpec }
