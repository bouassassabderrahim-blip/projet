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
/**
 * Adresse du projet nettoyée. Accepte aussi ce qu'on copie souvent par erreur : l'adresse de la page
 * Supabase (supabase.com/dashboard/project/<identifiant>/…), l'identifiant seul (20 lettres),
 * l'adresse sans https:// ou suivie de /rest/v1 ou /auth/v1.
 */
export function normalizeUrl(input: string): string {
	const raw = input.trim().replace(/\s+/g, '')
	const page = raw.match(/supabase\.com\/dashboard\/project\/([a-z0-9]{10,40})/i)
	if (page) return `https://${page[1].toLowerCase()}.supabase.co`
	if (/^[a-z]{20}$/.test(raw)) return `https://${raw}.supabase.co`
	const url = raw.replace(/\/(rest|auth)\/v1(\/.*)?$/i, '').replace(/\/+$/, '')
	return /^[a-z0-9-]+\.supabase\.co$/i.test(url) ? `https://${url}` : url
}

/** Identifiant d'un projet Supabase (20 lettres) dont la longueur est suspecte : conseil, ou null */
export function refHint(url: string): string | null {
	const ref = url.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co$/i)?.[1]
	if (!ref || ref.length === 20) return null
	return `L’identifiant du projet (« ${ref} ») compte ${ref.length} caractères alors qu’il en fait normalement 20 : une lettre manque ou est en trop.`
}

/** Erreur évidente dans une adresse déjà nettoyée (message en clair), ou null */
export function urlProblem(url: string): string | null {
	if (!/^https?:\/\/[^/\s]+$/i.test(url)) return 'Adresse du projet invalide : elle doit ressembler à https://abcdefghijklmnopqrst.supabase.co'
	const host = url.replace(/^https?:\/\//i, '').toLowerCase()
	if (host.endsWith('.supabase.com')) return 'L’adresse du projet se termine par « .supabase.co » (sans « m » à la fin).'
	if (/^(www\.|app\.)?supabase\.(com|co)$/.test(host))
		return 'Ceci est l’adresse du site Supabase, pas celle de votre projet : elle doit ressembler à https://abcdefghijklmnopqrst.supabase.co'
	return null
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

const DEVICE_KEY = 'profitpilot-sync:device'

/** Identifiant de ce navigateur (fixe), pour reconnaître ses propres actions après une coupure */
export function deviceId(): string {
	try {
		const existing = localStorage.getItem(DEVICE_KEY)
		if (existing) return existing
		const id = randomId()
		localStorage.setItem(DEVICE_KEY, id)
		return id
	} catch {
		return 'memoire-' + randomId()
	}
}

export function randomId(): string {
	if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID()
	return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2)
}
