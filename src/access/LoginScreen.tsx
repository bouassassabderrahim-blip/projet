import { useState, type FormEvent } from 'react'
import { hashPin } from './crypto'
import { ROLE_LABELS, type User } from './types'
import './access.css'

interface Props {
	users: User[]
	companyName: string
	logo?: string
	/** Écran de verrouillage : l'utilisateur est déjà choisi */
	lockedUser?: User
	onLogin: (user: User) => void
}

const MAX_TRIES = 5
const COOLDOWN_MS = 30_000

/** Connexion par utilisateur et code PIN */
export default function LoginScreen({ users, companyName, logo, lockedUser, onLogin }: Props) {
	const active = users.filter((u) => u.active)
	const [selected, setSelected] = useState<User | null>(lockedUser ?? (active.length === 1 ? active[0] : null))
	const [pin, setPin] = useState('')
	const [error, setError] = useState('')
	const [tries, setTries] = useState(0)
	const [blockedUntil, setBlockedUntil] = useState(0)

	async function submit(e: FormEvent) {
		e.preventDefault()
		if (!selected) return
		if (Date.now() < blockedUntil) return setError('Trop de tentatives : patientez 30 secondes.')
		const hash = await hashPin(pin, selected.salt)
		if (hash === selected.pinHash) return onLogin(selected)
		const n = tries + 1
		setTries(n)
		setPin('')
		if (n >= MAX_TRIES) {
			setBlockedUntil(Date.now() + COOLDOWN_MS)
			setTries(0)
			setError('Code incorrect. Trop de tentatives : patientez 30 secondes.')
		} else setError(`Code incorrect (${MAX_TRIES - n} essai(s) restant(s)).`)
	}

	return (
		<div className="login-screen">
			<div className="login-card">
				<div className="login-head">
					{logo ? <img src={logo} alt="" className="login-logo" /> : <span className="erp-logo">PP</span>}
					<div>
						<strong>ProfitPilot ERP</strong>
						<span>{companyName || 'Gestion commerciale'}</span>
					</div>
				</div>

				{!selected ? (
					<>
						<p className="login-title">Qui êtes-vous ?</p>
						<div className="login-users">
							{active.map((u) => (
								<button key={u.id} type="button" className="login-user" onClick={() => setSelected(u)}>
									<span className="login-avatar">{u.name.slice(0, 1).toUpperCase()}</span>
									<span>
										<strong>{u.name}</strong>
										<small>{ROLE_LABELS[u.role]}</small>
									</span>
								</button>
							))}
						</div>
					</>
				) : (
					<form onSubmit={submit}>
						<p className="login-title">{lockedUser ? 'Session verrouillée' : 'Saisissez votre code'}</p>
						<div className="login-user login-user-selected">
							<span className="login-avatar">{selected.name.slice(0, 1).toUpperCase()}</span>
							<span>
								<strong>{selected.name}</strong>
								<small>{ROLE_LABELS[selected.role]}</small>
							</span>
						</div>
						<input
							className="login-pin"
							type="password"
							inputMode="numeric"
							autoComplete="current-password"
							placeholder="Code PIN"
							value={pin}
							autoFocus
							onChange={(e) => {
								setPin(e.target.value.replace(/\D/g, '').slice(0, 8))
								setError('')
							}}
						/>
						{error && <p className="login-error">{error}</p>}
						<button type="submit" className="login-submit" disabled={pin.length < 4}>
							{lockedUser ? 'Déverrouiller' : 'Se connecter'}
						</button>
						{!lockedUser && active.length > 1 && (
							<button type="button" className="login-back" onClick={() => setSelected(null)}>
								← Changer d'utilisateur
							</button>
						)}
						{lockedUser && (
							<button type="button" className="login-back" onClick={() => setSelected(null)}>
								Se connecter avec un autre compte
							</button>
						)}
					</form>
				)}
				<p className="login-foot">Le code PIN est demandé à chaque ouverture et après une période d'inactivité.</p>
			</div>
		</div>
	)
}
