// Client de la base en ligne (Supabase : authentification GoTrue + API REST PostgREST), en fetch simple

export interface RemoteRow {
	collection: string
	id: string
	data: unknown
	deleted: boolean
	updated_at?: string
	updated_by?: string | null
}

export interface Session {
	accessToken: string
	refreshToken: string
	/** Expiration du jeton d'accès (ms depuis 1970) */
	expiresAt: number
	email: string
}

/** Réseau injoignable : on réessaiera plus tard */
export class OfflineError extends Error {}
/** Connexion refusée ou expirée : il faut se reconnecter */
export class AuthError extends Error {}
/** Erreur renvoyée par le serveur */
export class RemoteError extends Error {}

const PAGE = 1000
const PUSH_CHUNK = 200
const PUSH_BYTES = 400_000

async function send(input: string, init: RequestInit): Promise<Response> {
	try {
		return await fetch(input, init)
	} catch {
		throw new OfflineError('Serveur injoignable')
	}
}

async function errorText(res: Response): Promise<string> {
	try {
		const body = (await res.json()) as Record<string, unknown>
		return String(body.error_description ?? body.msg ?? body.message ?? body.error ?? res.statusText)
	} catch {
		return res.statusText || `Erreur ${res.status}`
	}
}

interface TokenResponse {
	access_token: string
	refresh_token: string
	expires_in: number
	user?: { email?: string }
}

function toSession(t: TokenResponse, email: string): Session {
	return {
		accessToken: t.access_token,
		refreshToken: t.refresh_token,
		expiresAt: Date.now() + (t.expires_in ?? 3600) * 1000,
		email: t.user?.email ?? email,
	}
}

export class SupabaseRemote {
	private session: Session | null = null
	private refreshing: Promise<Session> | null = null
	private readonly url: string
	private readonly anonKey: string
	private readonly dossier: string
	/** Appelé quand le jeton de rafraîchissement change (à enregistrer) */
	onSession?: (s: Session) => void
	/** Dernier jeton de rafraîchissement enregistré (un autre onglet a pu le renouveler entre-temps) */
	latestRefreshToken?: () => string | undefined

	constructor(url: string, anonKey: string, dossier: string, refreshToken?: string, email = '') {
		this.url = url
		this.anonKey = anonKey
		this.dossier = dossier
		if (refreshToken) this.session = { accessToken: '', refreshToken, expiresAt: 0, email }
	}

	/** Connexion par e-mail et mot de passe */
	async signIn(email: string, password: string): Promise<Session> {
		const res = await send(`${this.url}/auth/v1/token?grant_type=password`, {
			method: 'POST',
			headers: { apikey: this.anonKey, 'Content-Type': 'application/json' },
			body: JSON.stringify({ email, password }),
		})
		if (!res.ok) throw new AuthError(await errorText(res))
		this.session = toSession((await res.json()) as TokenResponse, email)
		this.onSession?.(this.session)
		return this.session
	}

	private async refresh(): Promise<Session> {
		const current = this.session
		if (!current?.refreshToken) throw new AuthError('Session absente')
		// Supabase n'accepte qu'une fois chaque jeton : on part toujours du plus récent enregistré
		const token = this.latestRefreshToken?.() || current.refreshToken
		const call = (refresh_token: string) =>
			send(`${this.url}/auth/v1/token?grant_type=refresh_token`, {
				method: 'POST',
				headers: { apikey: this.anonKey, 'Content-Type': 'application/json' },
				body: JSON.stringify({ refresh_token }),
			})
		let res = await call(token)
		if (!res.ok && res.status < 500) {
			// Renouvelé par un autre onglet pendant l'appel : on réessaie avec le jeton enregistré par celui-ci
			const latest = this.latestRefreshToken?.()
			if (latest && latest !== token) res = await call(latest)
		}
		if (!res.ok) {
			if (res.status >= 500) throw new RemoteError(await errorText(res))
			throw new AuthError(await errorText(res))
		}
		this.session = toSession((await res.json()) as TokenResponse, current.email)
		this.onSession?.(this.session)
		return this.session
	}

	private async accessToken(force = false): Promise<string> {
		if (!this.session) throw new AuthError('Non connecté')
		if (force || this.session.expiresAt - 60_000 < Date.now()) {
			// Un seul rafraîchissement à la fois
			this.refreshing ??= this.refresh().finally(() => {
				this.refreshing = null
			})
			await this.refreshing
		}
		return this.session.accessToken
	}

	private async rest(path: string, init: RequestInit & { headers?: Record<string, string> } = {}): Promise<Response> {
		const call = async (force: boolean) =>
			send(`${this.url}/rest/v1/${path}`, {
				...init,
				headers: {
					apikey: this.anonKey,
					Authorization: `Bearer ${await this.accessToken(force)}`,
					'Content-Type': 'application/json',
					...init.headers,
				},
			})
		let res = await call(false)
		// Jeton expiré entre-temps : un nouvel essai après rafraîchissement
		if (res.status === 401) res = await call(true)
		if (res.status === 401 || res.status === 403) throw new AuthError(await errorText(res))
		if (!res.ok) throw new RemoteError(await errorText(res))
		return res
	}

	private filter(): string {
		return `dossier=eq.${encodeURIComponent(this.dossier)}`
	}

	/** Lignes modifiées depuis une date (toutes si null), par pages de 1 000 */
	async pull(since: string | null): Promise<RemoteRow[]> {
		const rows: RemoteRow[] = []
		for (let offset = 0; ; offset += PAGE) {
			const params = [
				'select=collection,id,data,deleted,updated_at,updated_by',
				this.filter(),
				since ? `updated_at=gte.${encodeURIComponent(since)}` : '',
				'order=updated_at.asc,collection.asc,id.asc',
				`limit=${PAGE}`,
				`offset=${offset}`,
			].filter(Boolean)
			const res = await this.rest(`records?${params.join('&')}`)
			const page = (await res.json()) as RemoteRow[]
			rows.push(...page)
			if (page.length < PAGE) return rows
		}
	}

	/** Envoi (insertion ou mise à jour) par paquets d'au plus 200 lignes et ~400 Ko (images du papier à en-tête) */
	async push(rows: RemoteRow[]): Promise<void> {
		let chunk: string[] = []
		let size = 0
		const flush = async () => {
			if (!chunk.length) return
			await this.rest('records', {
				method: 'POST',
				headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
				body: '[' + chunk.join(',') + ']',
			})
			chunk = []
			size = 0
		}
		for (const r of rows) {
			const json = JSON.stringify({ dossier: this.dossier, collection: r.collection, id: r.id, data: r.data, deleted: r.deleted })
			if (chunk.length && (chunk.length >= PUSH_CHUNK || size + json.length > PUSH_BYTES)) await flush()
			chunk.push(json)
			size += json.length
		}
		await flush()
	}

	/** Le compte connecté figure-t-il dans la liste des membres du dossier ? */
	async isMember(): Promise<boolean> {
		const res = await this.rest(`members?select=dossier&${this.filter()}`)
		return ((await res.json()) as unknown[]).length > 0
	}

	/** Nombre d'enregistrements du dossier en ligne */
	async count(): Promise<number> {
		const res = await this.rest(`records?select=id&${this.filter()}&deleted=is.false`, {
			headers: { Prefer: 'count=exact', Range: '0-0' },
		})
		const range = res.headers.get('Content-Range') ?? ''
		const total = Number(range.split('/')[1])
		return Number.isFinite(total) ? total : (await res.json()).length
	}

	/** Prochain numéro de pièce, attribué par le serveur (aucun doublon entre postes) */
	async nextNumber(kind: string, year: number, min: number): Promise<number> {
		const res = await this.rest('rpc/next_number', {
			method: 'POST',
			body: JSON.stringify({ p_dossier: this.dossier, p_kind: kind, p_year: year, p_min: min }),
		})
		const value = (await res.json()) as unknown
		const n = Number(value)
		if (!Number.isInteger(n) || n < 1) throw new RemoteError('Numéro invalide reçu du serveur')
		return n
	}
}
