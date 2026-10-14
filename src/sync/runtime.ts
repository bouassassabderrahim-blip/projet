// Instance unique du moteur de synchronisation pour ce poste
import { useSyncExternalStore } from 'react'
import { loadConfig, saveConfig, type SyncConfig } from './config'
import { SyncEngine, type SyncStatus } from './engine'
import { SupabaseRemote } from './remote'

let engine: SyncEngine | null = null
let status: SyncStatus | null = null
const listeners = new Set<() => void>()
let unsubscribe: (() => void) | null = null

function notify() {
	for (const fn of listeners) fn()
}

/** Crée le client et le moteur pour une configuration (sans démarrer la synchro automatique) */
export function createEngine(config: SyncConfig): SyncEngine {
	stopEngine()
	const remote = new SupabaseRemote(config.url, config.anonKey, config.dossier, config.refreshToken, config.email)
	// Le jeton de rafraîchissement change à chaque renouvellement : on garde le dernier
	remote.onSession = (s) => {
		const current = loadConfig()
		if (current) saveConfig({ ...current, refreshToken: s.refreshToken, email: s.email })
	}
	remote.latestRefreshToken = () => loadConfig()?.refreshToken
	engine = new SyncEngine(remote, config.dossier)
	unsubscribe = engine.subscribe((s) => {
		status = s
		notify()
	})
	return engine
}

/** Au lancement : reprend la synchro si ce poste a rejoint un dossier */
export function startFromConfig() {
	const config = loadConfig()
	if (!config?.joined || engine) return
	createEngine(config).start()
}

export function stopEngine() {
	engine?.stop()
	unsubscribe?.()
	unsubscribe = null
	engine = null
	status = null
	notify()
}

export function currentEngine(): SyncEngine | null {
	return engine
}

/** Mode multi-postes actif sur ce poste */
export function isSyncActive(): boolean {
	return engine !== null && loadConfig()?.joined === true
}

/** Relance une synchronisation dès que possible (sans effet si un autre onglet de ce poste synchronise) */
export function syncSoon() {
	void engine?.syncNow()
}

const DONE_KEY = 'profitpilot-sync:done-actions'

function doneActions(): string[] {
	try {
		const list: unknown = JSON.parse(localStorage.getItem(DONE_KEY) ?? '[]')
		return Array.isArray(list) ? list.filter((x): x is string => typeof x === 'string') : []
	} catch {
		return []
	}
}

/**
 * Action unique sur une pièce (validation, annulation, retour de dépôt) en mode multi-postes :
 * le serveur ne l'accorde qu'à un seul poste (et attribue le numéro définitif d'une validation) ;
 * entre deux onglets du même poste, un verrou du navigateur et une marque locale évitent le doublon.
 * En mode un seul poste, l'action est appliquée directement (numéro null).
 * Renvoie 'already' si un autre poste ou onglet l'a déjà faite : rien n'est appliqué ici.
 * Lève une erreur hors ligne : on n'agit pas sans l'accord du serveur.
 */
export async function runDocAction(
	request: { docId: string; action: string; kind: string; year: number; min: number },
	apply: (number: number | null) => void,
): Promise<'applied' | 'already'> {
	const config = loadConfig()
	const current = engine
	if (!current || !config?.joined) {
		apply(null)
		return 'applied'
	}
	const mark = `${config.dossier}:${request.docId}:${request.action}`
	const run = async (): Promise<'applied' | 'already'> => {
		if (doneActions().includes(mark)) return 'already'
		const claim = await current.claim(request.docId, request.action, request.kind, request.year, request.min)
		if (claim.already) {
			syncSoon()
			return 'already'
		}
		apply(claim.number)
		try {
			localStorage.setItem(DONE_KEY, JSON.stringify([...doneActions(), mark].slice(-300)))
		} catch {
			// stockage plein : seul le verrou protège encore les autres onglets
		}
		return 'applied'
	}
	const locks = (navigator as Navigator & { locks?: LockManager }).locks
	return locks ? locks.request(`profitpilot-doc:${mark}`, run) : run()
}

export function useSyncStatus(): SyncStatus | null {
	return useSyncExternalStore(
		(fn) => {
			listeners.add(fn)
			return () => listeners.delete(fn)
		},
		() => status,
	)
}
