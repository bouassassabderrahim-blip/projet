// État de synchronisation de ce poste, rangé dans IndexedDB (pas dans le localStorage limité à 5 Mo)

export interface SyncState {
	/** Empreinte de chaque enregistrement tel que synchronisé : « collection␟id » → empreinte */
	base: Record<string, string>
	/** Date serveur de la dernière version vue : « collection␟id » → updated_at */
	seen: Record<string, string>
	/** Date serveur la plus récente reçue */
	lastPull: string | null
	/** Dernière version serveur connue de chaque enregistrement (fusion à trois versions) */
	snapshot: Record<string, unknown>
}

const DB = 'profitpilot-sync'
const STORE = 'kv'

export const emptyState = (): SyncState => ({ base: {}, seen: {}, lastPull: null, snapshot: {} })

function open(): Promise<IDBDatabase> {
	return new Promise((resolve, reject) => {
		if (typeof indexedDB === 'undefined') return reject(new Error('IndexedDB indisponible'))
		const req = indexedDB.open(DB, 1)
		req.onupgradeneeded = () => req.result.createObjectStore(STORE)
		req.onsuccess = () => resolve(req.result)
		req.onerror = () => reject(req.error)
	})
}

export async function loadState(dossier: string): Promise<SyncState> {
	try {
		const db = await open()
		return await new Promise((resolve) => {
			const req = db.transaction(STORE, 'readonly').objectStore(STORE).get(dossier)
			req.onsuccess = () => resolve({ ...emptyState(), ...((req.result as SyncState | undefined) ?? {}) })
			req.onerror = () => resolve(emptyState())
		})
	} catch {
		return emptyState()
	}
}

/**
 * Enregistre l'état. Si IndexedDB est indisponible (navigation privée…), l'état reste en mémoire :
 * la synchronisation continue, seul un rechargement de la page la fera repartir de zéro.
 */
export async function saveState(dossier: string, state: SyncState): Promise<void> {
	try {
		const db = await open()
		await new Promise<void>((resolve, reject) => {
			const tx = db.transaction(STORE, 'readwrite')
			tx.objectStore(STORE).put(state, dossier)
			tx.oncomplete = () => resolve()
			tx.onerror = () => reject(tx.error)
		})
	} catch {
		// IndexedDB indisponible : état gardé en mémoire
	}
}

export async function clearState(dossier: string): Promise<void> {
	try {
		const db = await open()
		await new Promise<void>((resolve) => {
			const tx = db.transaction(STORE, 'readwrite')
			tx.objectStore(STORE).delete(dossier)
			tx.oncomplete = () => resolve()
			tx.onerror = () => resolve()
		})
	} catch {
		// rien à effacer
	}
}
