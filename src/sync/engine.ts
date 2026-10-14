// Moteur de synchronisation : envoie les modifications de ce poste, applique celles des autres postes.
// Granularité : l'enregistrement (une pièce, un client, un lot…), dernier enregistré gagnant.
import { COLLECTIONS, VALUE_ID, fingerprint, localOrder, readLocal, threeWayMerge, writeLocal, type CollectionSpec } from './collections'
import { AuthError, OfflineError, SupabaseRemote, type RemoteRow } from './remote'
import { emptyState, loadState, saveState, type SyncState } from './state'

export type SyncPhase = 'idle' | 'syncing' | 'ok' | 'offline' | 'auth' | 'error'

export interface SyncStatus {
	phase: SyncPhase
	/** Dernière synchronisation réussie (ms) */
	lastSync: number | null
	/** Modifications locales pas encore envoyées */
	pending: number
	/** Modifications des deux côtés sur un même enregistrement : la version de ce poste a été gardée */
	conflicts: number
	message: string
}

const SEP = '␟'
const keyOf = (collection: string, id: string) => collection + SEP + id
/** Marge de relecture : une ligne validée côté serveur juste avant notre lecture peut porter une date un peu antérieure */
const OVERLAP_MS = 15_000
const INTERVAL_MS = 4_000

const minus = (iso: string, ms: number) => new Date(new Date(iso).getTime() - ms).toISOString()
/** Comparaison de dates serveur par leur valeur (indépendante du fuseau renvoyé) */
const isLater = (a: string, b: string | null) => !b || new Date(a).getTime() > new Date(b).getTime()

export class SyncEngine {
	readonly remote: SupabaseRemote
	private readonly dossier: string
	private state: SyncState = emptyState()
	private loaded = false
	private busy: Promise<void> | null = null
	private timer: number | null = null
	private listeners = new Set<(s: SyncStatus) => void>()
	status: SyncStatus = { phase: 'idle', lastSync: null, pending: 0, conflicts: 0, message: '' }

	constructor(remote: SupabaseRemote, dossier: string) {
		this.remote = remote
		this.dossier = dossier
	}

	/** Mémorise la version serveur connue d'un enregistrement (empreinte + copie pour la fusion) */
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

	start() {
		if (this.timer !== null) return
		void this.syncNow()
		this.timer = window.setInterval(() => void this.syncNow(), INTERVAL_MS)
		window.addEventListener('online', this.onOnline)
	}

	stop() {
		if (this.timer !== null) window.clearInterval(this.timer)
		this.timer = null
		window.removeEventListener('online', this.onOnline)
	}

	private onOnline = () => void this.syncNow()

	private async ensureLoaded() {
		if (this.loaded) return
		this.state = await loadState(this.dossier)
		this.loaded = true
	}

	/** Une seule synchronisation à la fois ; un appel pendant une synchro attend la fin de celle-ci */
	syncNow(): Promise<void> {
		this.busy ??= this.run().finally(() => {
			this.busy = null
		})
		return this.busy
	}

	private async run() {
		this.setStatus({ phase: this.status.phase === 'ok' ? 'ok' : 'syncing' })
		try {
			await this.ensureLoaded()
			const since = this.state.lastPull ? minus(this.state.lastPull, OVERLAP_MS) : null
			this.applyRemote(await this.remote.pull(since))
			const changes = this.localChanges()
			if (changes.length) {
				await this.remote.push(changes.map((c) => c.row))
				for (const c of changes) this.remember(c.k, c.row.deleted ? undefined : c.row.data)
			}
			await saveState(this.dossier, this.state)
			this.setStatus({ phase: 'ok', lastSync: Date.now(), pending: 0, message: '' })
		} catch (e) {
			const pending = this.loaded ? this.localChanges().length : 0
			if (e instanceof OfflineError) this.setStatus({ phase: 'offline', pending, message: 'Hors ligne : les modifications partiront au retour de la connexion.' })
			else if (e instanceof AuthError) this.setStatus({ phase: 'auth', pending, message: `Connexion refusée : ${e.message}` })
			else this.setStatus({ phase: 'error', pending, message: e instanceof Error ? e.message : String(e) })
		}
	}

	/** Applique les lignes reçues, sauf sur un enregistrement modifié localement et pas encore envoyé */
	private applyRemote(rows: RemoteRow[]) {
		if (rows.length === 0) return
		const bySpec = new Map<string, RemoteRow[]>()
		for (const r of rows) {
			const list = bySpec.get(r.collection) ?? []
			list.push(r)
			bySpec.set(r.collection, list)
			if (r.updated_at && isLater(r.updated_at, this.state.lastPull)) this.state.lastPull = r.updated_at
		}
		let conflicts = this.status.conflicts
		// Les collections qui partagent une clé (articles et leur méta) sont écrites l'une après l'autre
		for (const spec of COLLECTIONS) {
			const incoming = bySpec.get(spec.name)
			if (!incoming) continue
			const local = readLocal(spec)
			const order = localOrder(spec)
			let changed = false
			for (const row of incoming) {
				const k = keyOf(spec.name, row.id)
				if (row.updated_at && this.state.seen[k] === row.updated_at) continue
				if (row.updated_at) this.state.seen[k] = row.updated_at
				if (row.deleted && spec.appendOnly) continue
				const current = local.get(row.id)
				const localHash = current === undefined ? undefined : fingerprint(current)
				const remoteHash = row.deleted ? undefined : fingerprint(row.data)
				if (localHash === remoteHash) {
					this.remember(k, row.deleted ? undefined : row.data)
					continue
				}
				// Modifié sur ce poste depuis la dernière version synchronisée
				const dirty = localHash !== this.state.base[k]
				let result: unknown
				if (row.deleted) {
					if (current !== undefined && spec.protect?.(current)) result = current // pièce validée : on la garde et on la renvoie
					else if (dirty) {
						conflicts++ // modifié ici, supprimé ailleurs : la modification l'emporte
						continue
					} else result = undefined
				} else if (current === undefined) {
					if (dirty && !spec.protect?.(row.data)) {
						conflicts++ // supprimé ici, modifié ailleurs : la suppression l'emporte
						continue
					}
					result = row.data
				} else if (spec.merge) {
					// Règles métier : jamais de retour en arrière d'une pièce, règlements additionnés
					result = dirty ? spec.merge(current, row.data) : spec.merge(row.data, current)
					if (dirty) conflicts++
				} else if (dirty) {
					// Modifié des deux côtés : fusion champ par champ à partir de la dernière version commune
					const base = this.state.snapshot[k]
					if (base === undefined) {
						conflicts++ // pas de version commune : la version de ce poste sera envoyée
						continue
					}
					const merged = threeWayMerge(base, current, row.data, spec.deltaFields)
					if (merged.conflict) conflicts++
					result = merged.result
				} else result = row.data

				// La version serveur devient la référence ; si le résultat en diffère, il sera renvoyé
				this.remember(k, row.deleted ? undefined : row.data)
				if (result === undefined) {
					if (local.delete(row.id)) changed = true
				} else if (fingerprint(result) !== localHash) {
					if (!local.has(row.id)) order.push(row.id)
					local.set(row.id, result)
					changed = true
				}
			}
			if (changed) writeLocal(spec, local, order)
		}
		if (conflicts !== this.status.conflicts) this.setStatus({ conflicts })
	}

	/** Enregistrements locaux différents de leur dernière version synchronisée */
	private localChanges(): { k: string; hash: string | undefined; row: RemoteRow }[] {
		const out: { k: string; hash: string | undefined; row: RemoteRow }[] = []
		for (const spec of COLLECTIONS) {
			const local = readLocal(spec)
			for (const [id, data] of local) {
				const k = keyOf(spec.name, id)
				const hash = fingerprint(data)
				if (this.state.base[k] !== hash) out.push({ k, hash, row: { collection: spec.name, id, data, deleted: false } })
			}
			if (spec.appendOnly) continue
			// Supprimé sur ce poste depuis la dernière synchro : on propage la suppression
			const prefix = spec.name + SEP
			for (const k of Object.keys(this.state.base)) {
				if (!k.startsWith(prefix)) continue
				const id = k.slice(prefix.length)
				if (!local.has(id)) out.push({ k, hash: undefined, row: { collection: spec.name, id, data: null, deleted: true } })
			}
		}
		return out
	}

	pendingCount(): number {
		return this.loaded ? this.localChanges().length : 0
	}

	/** Premier poste : envoie toutes les données locales vers un dossier en ligne vide */
	async uploadAll(): Promise<number> {
		this.state = emptyState()
		this.loaded = true
		const changes = this.localChanges()
		await this.remote.push(changes.map((c) => c.row))
		for (const c of changes) if (!c.row.deleted) this.remember(c.k, c.row.data)
		// La relecture suivante reprendra nos propres envois (sans effet : empreintes identiques)
		await saveState(this.dossier, this.state)
		return changes.length
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
			// Collection absente en ligne : on l'efface localement (sauf réglages sans valeur en ligne)
			if (records.size === 0 && spec.kind === 'value') {
				if (!bySpec.has(spec.name)) continue
			}
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
export type { CollectionSpec }
