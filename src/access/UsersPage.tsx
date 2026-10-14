import { useState } from 'react'
import { useAccess } from './context'
import { hashPin, isValidPin, newSalt } from './crypto'
import {
	ACTIONS,
	ROLES,
	ROLE_LABELS,
	SECURED_MODULES,
	rolePermissions,
	type AccessSettings,
	type Level,
	type Permissions,
	type RoleId,
	type User,
} from './types'
import { frDate, newId } from '../documents/numbering'
import '../documents/documents.css'
import './access.css'

interface Props {
	users: User[]
	onChange: (users: User[]) => void
	settings: AccessSettings
	onSettingsChange: (settings: AccessSettings) => void
	/** Après création du premier administrateur : ouverture de sa session */
	onFirstAdmin: (user: User) => void
}

const LEVELS: { id: Level; label: string }[] = [
	{ id: 'none', label: 'Aucun' },
	{ id: 'read', label: 'Lecture' },
	{ id: 'write', label: 'Modification' },
]

interface Draft {
	id: string
	name: string
	login: string
	role: RoleId
	permissions: Permissions
	active: boolean
	pin: string
	pin2: string
	isNew: boolean
}

/** Gestion des utilisateurs et de leurs droits (réservée à l'administrateur) */
export default function UsersPage({ users, onChange, settings, onSettingsChange, onFirstAdmin }: Props) {
	const access = useAccess()
	const firstRun = users.length === 0
	const [draft, setDraft] = useState<Draft | null>(() =>
		firstRun
			? { id: newId(), name: '', login: 'admin', role: 'admin', permissions: rolePermissions('admin'), active: true, pin: '', pin2: '', isNew: true }
			: null,
	)
	const [error, setError] = useState('')

	const admins = users.filter((u) => u.role === 'admin' && u.active)

	function edit(u: User) {
		setDraft({ id: u.id, name: u.name, login: u.login, role: u.role, permissions: structuredClone(u.permissions), active: u.active, pin: '', pin2: '', isNew: false })
		setError('')
	}

	function setRole(role: RoleId) {
		if (!draft) return
		setDraft({ ...draft, role, permissions: role === 'custom' ? draft.permissions : rolePermissions(role) })
	}

	async function save() {
		if (!draft) return
		const name = draft.name.trim()
		const login = draft.login.trim().toLowerCase()
		if (!name) return setError('Indiquez le nom.')
		if (!/^[a-z0-9._-]{2,30}$/.test(login)) return setError('Identifiant : 2 à 30 caractères (lettres, chiffres, . _ -).')
		if (users.some((u) => u.id !== draft.id && u.login === login)) return setError('Cet identifiant est déjà utilisé.')
		if (draft.isNew || draft.pin) {
			if (!isValidPin(draft.pin)) return setError('Le code PIN doit comporter 4 à 8 chiffres.')
			if (draft.pin !== draft.pin2) return setError('Les deux codes PIN ne correspondent pas.')
		}
		const old = users.find((u) => u.id === draft.id)
		// On garde toujours au moins un administrateur actif
		const removesLastAdmin = old?.role === 'admin' && admins.length === 1 && (draft.role !== 'admin' || !draft.active)
		if (removesLastAdmin) return setError('Il doit rester au moins un administrateur actif.')

		const salt = draft.pin ? newSalt() : (old?.salt ?? newSalt())
		const pinHash = draft.pin ? await hashPin(draft.pin, salt) : (old?.pinHash ?? '')
		const user: User = {
			id: draft.id,
			name,
			login,
			role: draft.role,
			permissions: draft.role === 'admin' ? rolePermissions('admin') : draft.permissions,
			active: draft.active,
			salt,
			pinHash,
			createdAt: old?.createdAt ?? new Date().toISOString(),
			lastLogin: old?.lastLogin,
		}
		onChange(old ? users.map((u) => (u.id === user.id ? user : u)) : [...users, user])
		access.log(old ? 'Utilisateur modifié' : 'Utilisateur créé', `${name} (${ROLE_LABELS[user.role]})${draft.pin && old ? ', code PIN changé' : ''}`)
		setDraft(null)
		setError('')
		if (firstRun) onFirstAdmin(user)
	}

	function remove(u: User) {
		if (u.role === 'admin' && admins.length === 1) return setError('Impossible de supprimer le dernier administrateur.')
		if (u.id === access.user?.id) return setError('Vous ne pouvez pas supprimer votre propre compte.')
		if (!confirm(`Supprimer le compte de ${u.name} ?`)) return
		onChange(users.filter((x) => x.id !== u.id))
		access.log('Utilisateur supprimé', u.name)
	}

	if (draft) {
		const isAdminRole = draft.role === 'admin'
		const setModule = (m: keyof Permissions['modules'], level: Level) =>
			setDraft({ ...draft, role: 'custom', permissions: { ...draft.permissions, modules: { ...draft.permissions.modules, [m]: level } } })
		const setAction = (a: keyof Permissions['actions'], on: boolean) =>
			setDraft({ ...draft, role: 'custom', permissions: { ...draft.permissions, actions: { ...draft.permissions.actions, [a]: on } } })
		return (
			<div>
				{firstRun && (
					<p className="doc-info">
						Créez d'abord le compte <strong>administrateur</strong>. Ensuite, l'application demandera un code PIN à chaque
						ouverture et vous pourrez créer les comptes de vos employés.
					</p>
				)}
				<div className="doc-editor-head">
					<h2>{draft.isNew ? (firstRun ? 'Compte administrateur' : 'Nouvel utilisateur') : draft.name}</h2>
					<div className="doc-editor-actions">
						<button type="button" className="btn-primary" onClick={save}>
							Enregistrer
						</button>
						{!firstRun && (
							<button type="button" onClick={() => setDraft(null)}>
								Fermer
							</button>
						)}
					</div>
				</div>

				<fieldset className="doc-panel">
					<legend>Identité et connexion</legend>
					<div className="doc-grid">
						<label>
							Nom affiché
							<input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="ex. Karim Bennani" />
						</label>
						<label>
							Identifiant
							<input value={draft.login} onChange={(e) => setDraft({ ...draft, login: e.target.value })} />
						</label>
						<label>
							{draft.isNew ? 'Code PIN (4 à 8 chiffres)' : 'Nouveau code PIN (laisser vide pour garder)'}
							<input type="password" inputMode="numeric" value={draft.pin} onChange={(e) => setDraft({ ...draft, pin: e.target.value.replace(/\D/g, '').slice(0, 8) })} />
						</label>
						<label>
							Confirmer le code PIN
							<input type="password" inputMode="numeric" value={draft.pin2} onChange={(e) => setDraft({ ...draft, pin2: e.target.value.replace(/\D/g, '').slice(0, 8) })} />
						</label>
						{!firstRun && (
							<label className="doc-check">
								<input type="checkbox" checked={draft.active} onChange={(e) => setDraft({ ...draft, active: e.target.checked })} />
								Compte actif
							</label>
						)}
					</div>
				</fieldset>

				{!firstRun && (
					<fieldset className="doc-panel">
						<legend>Profil et droits</legend>
						<div className="access-roles">
							{ROLES.map((r) => (
								<label key={r.id} className={`doc-mode ${draft.role === r.id ? 'doc-mode-active' : ''}`}>
									<input type="radio" name="role" checked={draft.role === r.id} onChange={() => setRole(r.id)} />
									<span>
										<strong>{r.label}</strong>
										<small>{r.description}</small>
									</span>
								</label>
							))}
							<label className={`doc-mode ${draft.role === 'custom' ? 'doc-mode-active' : ''}`}>
								<input type="radio" name="role" checked={draft.role === 'custom'} onChange={() => setRole('custom')} />
								<span>
									<strong>Personnalisé</strong>
									<small>Réglez chaque droit ci-dessous</small>
								</span>
							</label>
						</div>

						{isAdminRole ? (
							<p className="doc-info">L'administrateur a tous les droits, gère les utilisateurs et consulte le journal d'activité.</p>
						) : (
							<div className="access-matrix">
								<table className="doc-table">
									<thead>
										<tr>
											<th>Module</th>
											{LEVELS.map((l) => (
												<th key={l.id} className="access-center">
													{l.label}
												</th>
											))}
										</tr>
									</thead>
									<tbody>
										{SECURED_MODULES.map((m) => (
											<tr key={m.id}>
												<td>{m.label}</td>
												{LEVELS.map((l) => (
													<td key={l.id} className="access-center">
														<input
															type="radio"
															name={`mod-${m.id}`}
															aria-label={`${m.label} : ${l.label}`}
															checked={draft.permissions.modules[m.id] === l.id}
															onChange={() => setModule(m.id, l.id)}
														/>
													</td>
												))}
											</tr>
										))}
									</tbody>
								</table>
								<div className="access-actions">
									<strong>Actions autorisées</strong>
									{ACTIONS.map((a) => (
										<label key={a.id} className="doc-check">
											<input type="checkbox" checked={draft.permissions.actions[a.id]} onChange={(e) => setAction(a.id, e.target.checked)} />
											<span>
												{a.label} <small>({a.hint})</small>
											</span>
										</label>
									))}
								</div>
							</div>
						)}
					</fieldset>
				)}
				{error && <p className="doc-error">{error}</p>}
			</div>
		)
	}

	return (
		<div>
			<div className="doc-toolbar">
				<button
					type="button"
					className="btn-primary"
					onClick={() =>
						setDraft({ id: newId(), name: '', login: '', role: 'sales', permissions: rolePermissions('sales'), active: true, pin: '', pin2: '', isNew: true })
					}
				>
					+ Nouvel utilisateur
				</button>
				<label>
					Verrouillage automatique après{' '}
					<select value={settings.lockMinutes} onChange={(e) => onSettingsChange({ lockMinutes: Number(e.target.value) })}>
						{[0, 5, 10, 15, 30, 60].map((m) => (
							<option key={m} value={m}>
								{m === 0 ? 'jamais' : `${m} min d'inactivité`}
							</option>
						))}
					</select>
				</label>
				<span className="doc-count">{users.length} compte(s)</span>
			</div>
			{error && <p className="doc-error">{error}</p>}

			<table className="doc-table">
				<thead>
					<tr>
						<th>Nom</th>
						<th>Identifiant</th>
						<th>Profil</th>
						{SECURED_MODULES.map((m) => (
							<th key={m.id} className="access-center">
								{m.label}
							</th>
						))}
						<th>Dernière connexion</th>
						<th>État</th>
						<th>Actions</th>
					</tr>
				</thead>
				<tbody>
					{users.map((u) => (
						<tr key={u.id}>
							<td>
								<button type="button" className="doc-link" onClick={() => edit(u)}>
									{u.name}
								</button>
								{u.id === access.user?.id && <small> (vous)</small>}
							</td>
							<td>{u.login}</td>
							<td>{ROLE_LABELS[u.role]}</td>
							{SECURED_MODULES.map((m) => {
								const level = u.role === 'admin' ? 'write' : u.permissions.modules[m.id]
								return (
									<td key={m.id} className="access-center">
										<span className={`access-level access-${level}`}>{level === 'write' ? 'M' : level === 'read' ? 'L' : '—'}</span>
									</td>
								)
							})}
							<td>{u.lastLogin ? `${frDate(u.lastLogin.slice(0, 10))} ${u.lastLogin.slice(11, 16)}` : 'jamais'}</td>
							<td>
								<span className={`doc-badge ${u.active ? 'doc-badge-paid' : 'doc-badge-cancelled'}`}>{u.active ? 'Actif' : 'Désactivé'}</span>
							</td>
							<td className="doc-actions">
								<button type="button" onClick={() => edit(u)}>
									Modifier
								</button>
								<button type="button" onClick={() => remove(u)}>
									Supprimer
								</button>
							</td>
						</tr>
					))}
				</tbody>
			</table>
			<p className="doc-count">M = modification · L = lecture seule · — = pas d'accès. Les changements de droits s'appliquent immédiatement.</p>
		</div>
	)
}
