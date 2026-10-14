// Configuration du mode multi-postes (stockée hors des clés « profitpilot: » : jamais synchronisée ni sauvegardée)

export const CONFIG_KEY = 'profitpilot-sync:config'

export interface SyncConfig {
	/** Adresse du projet Supabase, ex. https://abcd.supabase.co */
	url: string
	/** Clé publique du projet (anon / publishable) */
	anonKey: string
	/** Identifiant du dossier partagé (une société = un dossier) */
	dossier: string
	/** Compte de connexion de ce poste */
	email: string
	refreshToken: string
	/** Ce poste a rejoint le dossier (envoi initial ou récupération faits) */
	joined: boolean
}

export function loadConfig(): SyncConfig | null {
	try {
		const raw = localStorage.getItem(CONFIG_KEY)
		if (!raw) return null
		const c = JSON.parse(raw) as Partial<SyncConfig>
		if (typeof c.url !== 'string' || typeof c.anonKey !== 'string' || typeof c.dossier !== 'string') return null
		return {
			url: c.url,
			anonKey: c.anonKey,
			dossier: c.dossier,
			email: c.email ?? '',
			refreshToken: c.refreshToken ?? '',
			joined: c.joined === true,
		}
	} catch {
		return null
	}
}

export function saveConfig(config: SyncConfig | null) {
	try {
		if (config) localStorage.setItem(CONFIG_KEY, JSON.stringify(config))
		else localStorage.removeItem(CONFIG_KEY)
	} catch {
		// stockage indisponible
	}
}

/** Adresse nettoyée : https, sans barre finale */
export function normalizeUrl(url: string): string {
	return url.trim().replace(/\/+$/, '')
}

/** Code de connexion à transmettre aux autres postes (adresse, clé publique, dossier ; jamais de mot de passe) */
export function encodeInvite(c: Pick<SyncConfig, 'url' | 'anonKey' | 'dossier'>): string {
	const json = JSON.stringify({ u: c.url, k: c.anonKey, d: c.dossier })
	const bytes = new TextEncoder().encode(json)
	let bin = ''
	for (const b of bytes) bin += String.fromCharCode(b)
	return 'PP1-' + btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function decodeInvite(code: string): Pick<SyncConfig, 'url' | 'anonKey' | 'dossier'> | null {
	try {
		const body = code.trim().replace(/^PP1-/, '').replace(/-/g, '+').replace(/_/g, '/')
		const bin = atob(body + '='.repeat((4 - (body.length % 4)) % 4))
		const json = new TextDecoder().decode(Uint8Array.from(bin, (ch) => ch.charCodeAt(0)))
		const o = JSON.parse(json) as { u?: unknown; k?: unknown; d?: unknown }
		if (typeof o.u !== 'string' || typeof o.k !== 'string' || typeof o.d !== 'string') return null
		return { url: o.u, anonKey: o.k, dossier: o.d }
	} catch {
		return null
	}
}

/** Identifiant de dossier : minuscules, chiffres et tirets */
export const isValidDossier = (d: string) => /^[a-z0-9][a-z0-9-]{1,40}$/.test(d)
