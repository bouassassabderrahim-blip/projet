// Client de la base en ligne (Supabase : authentification GoTrue + API REST PostgREST), en fetch simple

export interface RemoteRow {
	collection: string
	id: string
	data: unknown
	deleted: boolean
	updated_at?: string
	updated_by?: string | null
	/** Identifiant de l'envoi qui a écrit cette version */
	rev?: string | null
}

/** Ligne à envoyer : expected = date serveur de la version sur laquelle le poste s'appuie (null = nouvelle ligne) */
export interface PushRow extends RemoteRow {
	rev: string
	expected: string | null
}

export interface PushResult {
	/** Lignes écrites, avec leur nouvelle date serveur */
	accepted: { collection: string; id: string; updated_at: string }[]
	/** Lignes refusées (modifiées entre-temps sur un autre poste) : version serveur actuelle, à fusionner */
	rejected: RemoteRow[]
}

/** Résultat d'une action unique sur une pièce (validation, annulation, retour de dépôt) */
export interface Claim {
	/** Numéro définitif attribué par le serveur (validation) */
	number: number | null
	/** Action déjà faite par un autre poste : ne rien appliquer ici */
	already: boolean
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

/** Envoi interrompu : les paquets déjà écrits (partial) sont à confirmer, puis l'erreur d'origine relancée */
export class PushError extends Error {
	readonly partial: PushResult
	readonly original: Error
	constructor(original: Error, partial: PushResult) {
		super(original.message)
		this.partial = partial
		this.original = original
	}
}

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

	private async rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
		const res = await this.rest(`rpc/${name}`, { method: 'POST', body: JSON.stringify({ p_dossier: this.dossier, ...args }) })
		return (await res.json()) as T
	}

	/**
	 * Lignes modifiées depuis une date (toutes si null), par pages de 1 000 lues à la suite de la dernière ligne reçue
	 * (date, collection, id) : une ligne modifiée pendant la lecture repasse en fin de liste, aucune n'est sautée.
	 */
	async pull(since: string | null): Promise<RemoteRow[]> {
		const rows: RemoteRow[] = []
		let after: RemoteRow | null = null
		for (;;) {
			const page: RemoteRow[] = await this.rpc<RemoteRow[]>('pull_records', {
				p_since: since,
				p_after_ts: after?.updated_at ?? null,
				p_after_collection: after?.collection ?? null,
				p_after_id: after?.id ?? null,
				p_limit: PAGE,
			})
			rows.push(...page)
			if (page.length < PAGE) return rows
			after = page[page.length - 1]
		}
	}

	/**
	 * Envoi conditionnel par paquets d'au plus 200 lignes et ~400 Ko (images du papier à en-tête) :
	 * une ligne modifiée entre-temps sur un autre poste est refusée et renvoyée, jamais écrasée.
	 */
	async push(rows: PushRow[]): Promise<PushResult> {
		const result: PushResult = { accepted: [], rejected: [] }
		let chunk: string[] = []
		let size = 0
		const flush = async () => {
			if (!chunk.length) return
			const res = await this.rest('rpc/push_records', {
				method: 'POST',
				body: `{"p_dossier":${JSON.stringify(this.dossier)},"p_rows":[${chunk.join(',')}]}`,
			})
			const part = (await res.json()) as Partial<PushResult>
			result.accepted.push(...(part.accepted ?? []))
			result.rejected.push(...(part.rejected ?? []))
			chunk = []
			size = 0
		}
		try {
			for (const r of rows) {
				const json = JSON.stringify({ collection: r.collection, id: r.id, data: r.data, deleted: r.deleted, rev: r.rev, expected: r.expected })
				if (chunk.length && (chunk.length >= PUSH_CHUNK || size + json.length > PUSH_BYTES)) await flush()
				chunk.push(json)
				size += json.length
			}
			await flush()
		} catch (e) {
			if (result.accepted.length === 0 || !(e instanceof Error)) throw e
			throw new PushError(e, result)
		}
		return result
	}

	/** Parmi ces envois (dont la réponse s'est perdue), ceux qui ont bien été écrits */
	async appliedRevs(revs: string[]): Promise<Set<string>> {
		if (revs.length === 0) return new Set()
		return new Set(await this.rpc<string[]>('applied_revs', { p_revs: revs }))
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

	/**
	 * Action unique sur une pièce : un seul poste l'obtient (avec le numéro définitif pour une validation).
	 * Le même poste qui redemande après une coupure retrouve la même action et le même numéro.
	 */
	async claim(docId: string, action: string, device: string, kind: string, year: number, min: number): Promise<Claim> {
		const value = await this.rpc<{ number?: unknown; already?: unknown }>('claim_doc_action', {
			p_doc_id: docId,
			p_action: action,
			p_device: device,
			p_kind: kind,
			p_year: year,
			p_min: min,
		})
		const n = value.number === null || value.number === undefined ? null : Number(value.number)
		if (n !== null && (!Number.isInteger(n) || n < 1)) throw new RemoteError('Numéro invalide reçu du serveur')
		return { number: n, already: value.already === true }
	}
}
