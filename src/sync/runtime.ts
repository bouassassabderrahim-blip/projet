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

/**
 * Numéro définitif attribué par le serveur (null en mode un seul poste).
 * Lève une erreur hors ligne : on ne valide pas de pièce sans numéro partagé, pour éviter tout doublon.
 */
export async function allocateNumber(kind: string, year: number, min: number): Promise<number | null> {
	if (!isSyncActive() || !engine) return null
	return engine.remote.nextNumber(kind, year, min)
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
