import { useState } from 'react'
import { useAccess } from '../access/context'
import { downloadFile } from '../documents/csv'
import { createBackup } from '../documents/storage'
import { today } from '../documents/numbering'
import { decodeInvite, encodeInvite, isValidDossier, loadConfig, normalizeUrl, refHint, saveConfig, urlProblem, type SyncConfig } from './config'
import { AuthError, OfflineError, SupabaseRemote } from './remote'
import { createEngine, currentEngine, stopEngine, useSyncStatus } from './runtime'
import { clearState } from './state'
import '../documents/documents.css'
import './sync.css'

type Step =
	| { kind: 'form' }
	| { kind: 'choose'; config: SyncConfig; remoteCount: number; localCount: number }
	| { kind: 'working'; text: string }

function localDataCount(): number {
	const count = (key: string) => {
		try {
			const v = JSON.parse(localStorage.getItem(key) ?? '[]') as unknown
			return Array.isArray(v) ? v.length : 0
		} catch {
			return 0
		}
	}
	return count('profitpilot:documents:v1') + count('profitpilot:parties:v1') + count('profitpilot:lots:v1')
}

function explain(e: unknown): string {
	if (e instanceof OfflineError)
		return 'Serveur injoignable. Causes possibles : une faute dans l’adresse du projet (copiez-la depuis Supabase plutôt que de la taper), un bloqueur de publicité qui bloque supabase.co, ou pas de connexion Internet. Utilisez le lien « Tester cette adresse » ci-dessous.'
	if (e instanceof AuthError) return `Connexion refusée : ${e.message}. Vérifiez l’e-mail, le mot de passe et la clé publique.`
	const msg = e instanceof Error ? e.message : String(e)
	if (/relation .* does not exist|Could not find the table|schema cache/i.test(msg))
		return 'La base en ligne n’est pas encore préparée : exécutez le script supabase/schema.sql (voir le guide).'
	return msg
}

/** Mise en place et suivi du mode multi-postes (réservé à l'administrateur) */
export default function SyncPage() {
	const access = useAccess()
	const status = useSyncStatus()
	const [config, setConfig] = useState(loadConfig)
	const [step, setStep] = useState<Step>({ kind: 'form' })
	const [form, setForm] = useState({
		invite: '',
		url: config?.url ?? '',
		anonKey: config?.anonKey ?? '',
		dossier: config?.dossier ?? '',
		email: config?.email ?? '',
		password: '',
	})
	const [error, setError] = useState('')
	/** Adresse injoignable : lien pour la tester directement dans le navigateur */
	const [testUrl, setTestUrl] = useState('')
	/** Compte pas encore autorisé : ligne SQL exacte à exécuter dans Supabase */
	const [memberSql, setMemberSql] = useState('')
	const [sqlCopied, setSqlCopied] = useState(false)
	const [copied, setCopied] = useState(false)
	const joined = config?.joined === true

	function applyInvite(code: string) {
		const decoded = decodeInvite(code)
		setForm((f) => ({ ...f, invite: code, ...(decoded ?? {}) }))
		setError(code.trim() && !decoded ? 'Code de connexion illisible.' : '')
	}

	async function connect() {
		setError('')
		setTestUrl('')
		setMemberSql('')
		setSqlCopied(false)
		const url = normalizeUrl(form.url)
		const dossier = form.dossier.trim().toLowerCase()
		// L'adresse nettoyée est affichée telle qu'elle sera utilisée
		if (url !== form.url) setForm((f) => ({ ...f, url }))
		const problem = urlProblem(url)
		if (problem) return setError(problem)
		if (!form.anonKey.trim()) return setError('Indiquez la clé publique du projet.')
		if (!isValidDossier(dossier)) return setError('Nom de dossier : lettres minuscules, chiffres et tirets (ex. orthomed).')
		if (!form.email.trim() || !form.password) return setError('Indiquez l’e-mail et le mot de passe de ce poste.')
		setStep({ kind: 'working', text: 'Connexion…' })
		try {
			const remote = new SupabaseRemote(url, form.anonKey.trim(), dossier)
			const session = await remote.signIn(form.email.trim(), form.password)
			if (!(await remote.isMember())) {
				// E-mail tel que Supabase le connaît : aucune faute de frappe possible dans la ligne à copier
				const quote = (v: string) => `'${v.replace(/'/g, "''")}'`
				setMemberSql(`insert into public.members (dossier, email) values (${quote(dossier)}, ${quote(session.email)}) on conflict do nothing;`)
				throw new Error(`Le compte ${session.email} n’est pas encore autorisé sur le dossier « ${dossier} ». Autorisez-le avec la ligne ci-dessous.`)
			}
			const next: SyncConfig = { url, anonKey: form.anonKey.trim(), dossier, email: session.email, refreshToken: session.refreshToken, joined: false }
			saveConfig(next)
			setConfig(next)
			setStep({ kind: 'choose', config: next, remoteCount: await remote.count(), localCount: localDataCount() })
		} catch (e) {
			setStep({ kind: 'form' })
			const hint = e instanceof OfflineError ? refHint(url) : null
			setError(hint ? `Serveur injoignable. ${hint} Copiez l’adresse depuis Supabase plutôt que de la taper.` : explain(e))
			if (e instanceof OfflineError) setTestUrl(`${url}/auth/v1/health`)
		}
	}

	async function upload(c: SyncConfig) {
		setStep({ kind: 'working', text: 'Envoi des données de ce poste…' })
		try {
			const engine = createEngine(loadConfig() ?? c)
			const n = await engine.uploadAll()
			const done = { ...(loadConfig() ?? c), joined: true }
			saveConfig(done)
			setConfig(done)
			engine.start()
			access.log('Multi-postes activé', `Dossier ${c.dossier} créé en ligne (${n} enregistrements envoyés)`)
			setStep({ kind: 'form' })
		} catch (e) {
			stopEngine()
			setStep({ kind: 'form' })
			setError(explain(e))
		}
	}

	async function download(c: SyncConfig) {
		if (!confirm('Remplacer toutes les données de cet ordinateur par celles du dossier en ligne ?')) return
		setStep({ kind: 'working', text: 'Récupération du dossier en ligne…' })
		try {
			const engine = createEngine(loadConfig() ?? c)
			await engine.downloadAll()
			saveConfig({ ...(loadConfig() ?? c), joined: true })
			stopEngine()
			// Rechargement : chaque écran repart des données du dossier
			location.reload()
		} catch (e) {
			stopEngine()
			setStep({ kind: 'form' })
			setError(explain(e))
		}
	}

	async function reconnect() {
		if (!config) return
		setError('')
		try {
			const remote = new SupabaseRemote(config.url, config.anonKey, config.dossier)
			const session = await remote.signIn(config.email, form.password)
			const next = { ...config, refreshToken: session.refreshToken, email: session.email }
			saveConfig(next)
			setConfig(next)
			createEngine(next).start()
			setForm((f) => ({ ...f, password: '' }))
		} catch (e) {
			setError(explain(e))
		}
	}

	async function leave() {
		if (!config) return
		if (!confirm('Déconnecter cet ordinateur du dossier partagé ? Les données restent sur ce poste mais ne seront plus synchronisées.')) return
		access.log('Multi-postes désactivé sur ce poste', config.dossier)
		stopEngine()
		await clearState(config.dossier)
		saveConfig(null)
		setConfig(null)
		setStep({ kind: 'form' })
	}

	function backupNow() {
		downloadFile(`profitpilot-sauvegarde-${today()}.json`, JSON.stringify(createBackup(), null, 1), 'application/json')
	}

	const invite = config ? encodeInvite(config) : ''

	if (joined && config) {
		const s = status
		return (
			<div>
				<div className="doc-stats">
					<div className={s?.phase === 'ok' ? undefined : s?.phase === 'offline' ? 'doc-stat-late' : 'doc-stat-danger'}>
						<span>État</span>
						<strong>
							{s?.phase === 'ok'
								? 'Synchronisé'
								: s?.phase === 'offline'
									? 'Hors ligne'
									: s?.phase === 'auth'
										? 'Reconnexion nécessaire'
										: s?.phase === 'error'
											? 'Erreur'
											: 'En cours…'}
						</strong>
					</div>
					<div>
						<span>Dernière synchronisation</span>
						<strong>{s?.lastSync ? new Date(s.lastSync).toLocaleTimeString('fr-FR') : '—'}</strong>
					</div>
					<div className={s?.pending ? 'doc-stat-late' : undefined}>
						<span>Modifications en attente</span>
						<strong>{s?.pending ?? 0}</strong>
					</div>
					<div>
						<span>Dossier · poste</span>
						<strong className="sync-small">
							{config.dossier} · {config.email}
						</strong>
					</div>
				</div>
				{s?.message && <p className={s.phase === 'offline' ? 'doc-warning' : 'doc-error'}>{s.message}</p>}
				{!!s?.conflicts && (
					<p className="doc-info">
						{s.conflicts} enregistrement(s) modifié(s) en même temps sur un autre poste : la version de cet ordinateur a été
						conservée.
					</p>
				)}

				<div className="doc-toolbar">
					<button type="button" className="btn-primary" onClick={() => void currentEngine()?.syncNow()}>
						Synchroniser maintenant
					</button>
					<button type="button" onClick={() => void leave()}>
						Déconnecter ce poste
					</button>
				</div>

				{s?.phase === 'auth' && (
					<fieldset className="doc-panel">
						<legend>Se reconnecter</legend>
						<div className="doc-grid">
							<label>
								Mot de passe de {config.email}
								<input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
							</label>
						</div>
						<button type="button" className="btn-primary" onClick={() => void reconnect()}>
							Se reconnecter
						</button>
					</fieldset>
				)}

				<fieldset className="doc-panel">
					<legend>Ajouter un autre ordinateur</legend>
					<ol className="sync-steps">
						<li>Sur l'autre ordinateur, ouvrez l'application puis Paramètres › Multi-postes.</li>
						<li>Collez ce code de connexion, puis saisissez l'e-mail et le mot de passe du compte de ce poste.</li>
						<li>Choisissez « Récupérer le dossier sur ce poste ».</li>
					</ol>
					<div className="sync-invite">
						<code>{invite}</code>
						<button
							type="button"
							onClick={() => {
								void navigator.clipboard?.writeText(invite)
								setCopied(true)
							}}
						>
							{copied ? 'Copié ✓' : 'Copier'}
						</button>
					</div>
					<p className="doc-count">Le code ne contient ni e-mail ni mot de passe : chaque poste se connecte avec son propre compte.</p>
				</fieldset>
				{error && <p className="doc-error">{error}</p>}
			</div>
		)
	}

	return (
		<div>
			<p className="doc-info">
				Le mode multi-postes range les données dans une base en ligne (Supabase) partagée par tous vos ordinateurs. Chaque
				pièce, client ou lot est synchronisé séparément toutes les quelques secondes ; les numéros de pièces sont attribués
				par le serveur pour qu'aucun poste ne puisse donner le même. Préparez d'abord la base en suivant le guide
				docs/MULTIPOSTE.md (environ 15 minutes, une seule fois).
			</p>

			{step.kind === 'working' && <p className="doc-warning">{step.text}</p>}

			{step.kind === 'form' && (
				<fieldset className="doc-panel">
					<legend>Connecter cet ordinateur</legend>
					<label className="doc-notes">
						Code de connexion : laissez vide sur le premier ordinateur (à coller seulement sur les postes suivants)
						<input value={form.invite} placeholder="PP1-…" onChange={(e) => applyInvite(e.target.value)} />
					</label>
					<div className="doc-grid">
						<label>
							Adresse du projet Supabase
							<input value={form.url} placeholder="https://abcdefghijklmnopqrst.supabase.co" onChange={(e) => setForm({ ...form, url: e.target.value })} />
						</label>
						<label>
							Clé publique (anon / publishable)
							<input value={form.anonKey} onChange={(e) => setForm({ ...form, anonKey: e.target.value })} />
						</label>
						<label>
							Nom du dossier
							<input value={form.dossier} placeholder="orthomed" onChange={(e) => setForm({ ...form, dossier: e.target.value })} />
						</label>
						<label>
							E-mail du compte de ce poste
							<input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
						</label>
						<label>
							Mot de passe
							<input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
						</label>
					</div>
					<button type="button" className="btn-primary" onClick={() => void connect()}>
						Se connecter
					</button>
				</fieldset>
			)}

			{step.kind === 'choose' && (
				<fieldset className="doc-panel">
					<legend>Dossier « {step.config.dossier} »</legend>
					{step.remoteCount === 0 ? (
						<>
							<p>
								Le dossier en ligne est <strong>vide</strong> : cet ordinateur est le premier. Ses données ({step.localCount}{' '}
								pièces, tiers et lots, plus les articles et les paramètres) vont être envoyées.
							</p>
							<button type="button" className="btn-primary" onClick={() => void upload(step.config)}>
								Envoyer les données de ce poste
							</button>
						</>
					) : (
						<>
							<p>
								Le dossier en ligne contient déjà <strong>{step.remoteCount} enregistrements</strong>. Cet ordinateur va
								récupérer ces données.
							</p>
							{step.localCount > 0 && (
								<p className="doc-warning">
									Cet ordinateur contient aussi des données ({step.localCount} pièces, tiers et lots) : elles seront
									remplacées. Téléchargez d'abord une sauvegarde si vous voulez les garder.{' '}
									<button type="button" onClick={backupNow}>
										Télécharger une sauvegarde
									</button>
								</p>
							)}
							<button type="button" className="btn-primary" onClick={() => void download(step.config)}>
								Récupérer le dossier sur ce poste
							</button>
						</>
					)}
					<button type="button" onClick={() => setStep({ kind: 'form' })}>
						Annuler
					</button>
				</fieldset>
			)}

			{error && <p className="doc-error">{error}</p>}
			{memberSql && (
				<div className="doc-info">
					<p>
						Dans Supabase › <strong>SQL Editor</strong> › <strong>New query</strong>, collez cette ligne puis cliquez{' '}
						<strong>Run</strong>. Revenez ensuite ici et cliquez de nouveau <strong>Se connecter</strong>.
					</p>
					<div className="sync-invite">
						<code>{memberSql}</code>
						<button
							type="button"
							onClick={() => {
								void navigator.clipboard?.writeText(memberSql)
								setSqlCopied(true)
							}}
						>
							{sqlCopied ? 'Copié ✓' : 'Copier'}
						</button>
					</div>
				</div>
			)}
			{testUrl && (
				<p className="doc-info">
					<a href={testUrl} target="_blank" rel="noreferrer">
						Tester cette adresse dans un nouvel onglet
					</a>{' '}
					: si une page de texte s’affiche (même un message en anglais comme « No API key found »), l’adresse est bonne et
					c’est un bloqueur de publicité qui gêne ProfitPilot ; si le navigateur affiche « Ce site est inaccessible », l’adresse
					est fausse.
				</p>
			)}

			<fieldset className="doc-panel">
				<legend>À savoir</legend>
				<ul className="sync-steps">
					<li>Les comptes de connexion (e-mail + mot de passe) se créent dans Supabase ; les profils et droits ProfitPilot (code PIN) restent ceux de Paramètres › Utilisateurs et sont partagés entre les postes.</li>
					<li>Sans Internet, on continue à travailler : les modifications partent au retour de la connexion. Seules la validation et l'annulation des pièces, et la reprise d'un dépôt, demandent d'être en ligne (le serveur les accorde à un seul poste).</li>
					<li>Données de patients : leur hébergement est soumis à la loi 09-08 (CNDP). Choisissez une région européenne pour le projet et renseignez-vous auprès de la CNDP.</li>
				</ul>
			</fieldset>
		</div>
	)
}
