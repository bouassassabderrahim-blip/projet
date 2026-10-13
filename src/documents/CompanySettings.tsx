import { useState } from 'react'
import type { CompanyInfo } from './types'
import './documents.css'

interface Props {
	company: CompanyInfo
	onChange: (company: CompanyInfo) => void
}

const fields: { key: Exclude<keyof CompanyInfo, 'logo' | 'individual'>; label: string; hint?: string }[] = [
	{ key: 'name', label: 'Raison sociale' },
	{ key: 'address', label: 'Adresse' },
	{ key: 'city', label: 'Ville' },
	{ key: 'phone', label: 'Téléphone' },
	{ key: 'email', label: 'E-mail' },
	{ key: 'ice', label: 'ICE', hint: '15 chiffres' },
	{ key: 'ifNumber', label: 'Identifiant fiscal (IF)' },
	{ key: 'rc', label: 'Registre du commerce (RC)' },
	{ key: 'patente', label: 'Taxe professionnelle (Patente)' },
	{ key: 'cnss', label: 'CNSS' },
	{ key: 'bank', label: 'Banque' },
	{ key: 'rib', label: 'RIB', hint: '24 chiffres' },
]

const MAX_LOGO = 300 * 1024

/** Mentions légales de l'émetteur et logo, imprimés sur toutes les pièces */
export default function CompanySettings({ company, onChange }: Props) {
	const [draft, setDraft] = useState(company)
	const [saved, setSaved] = useState(false)
	const [error, setError] = useState('')
	const iceInvalid = draft.ice !== '' && !/^\d{15}$/.test(draft.ice)
	const ribInvalid = draft.rib !== '' && !/^\d{24}$/.test(draft.rib.replace(/\s/g, ''))

	const set = (patch: Partial<CompanyInfo>) => {
		setDraft({ ...draft, ...patch })
		setSaved(false)
	}

	function loadLogo(file: File | undefined) {
		if (!file) return
		if (!file.type.startsWith('image/')) return setError('Choisissez une image (PNG ou JPEG).')
		if (file.size > MAX_LOGO) return setError('Logo trop lourd : 300 Ko maximum.')
		const reader = new FileReader()
		reader.onload = () => {
			set({ logo: String(reader.result) })
			setError('')
		}
		reader.readAsDataURL(file)
	}

	return (
		<div>
			<div className="doc-editor-head">
				<h2>Fiche société</h2>
				<div className="doc-editor-actions">
					<button
						type="button"
						className="btn-primary"
						disabled={iceInvalid}
						onClick={() => {
							onChange(draft)
							setSaved(true)
						}}
					>
						Enregistrer
					</button>
					{saved && <span className="doc-count">Enregistré ✓</span>}
				</div>
			</div>

			<fieldset className="doc-panel">
				<legend>Identification</legend>
				<div className="doc-grid">
					{fields.map((f) => (
						<label key={f.key}>
							<span>
								{f.label}
								{f.hint && <small> ({f.hint})</small>}
							</span>
							<input value={draft[f.key]} onChange={(e) => set({ [f.key]: e.target.value })} />
						</label>
					))}
				</div>
				{iceInvalid && <p className="doc-error">L'ICE doit comporter exactement 15 chiffres.</p>}
				{ribInvalid && <p className="doc-warning">Le RIB marocain comporte normalement 24 chiffres.</p>}
			</fieldset>

			<fieldset className="doc-panel">
				<legend>Logo</legend>
				<div className="doc-logo-row">
					{draft.logo ? <img className="doc-logo" src={draft.logo} alt="Logo" /> : <span className="doc-count">Aucun logo</span>}
					<input type="file" accept="image/png,image/jpeg" onChange={(e) => loadLogo(e.target.files?.[0])} />
					{draft.logo && (
						<button type="button" onClick={() => set({ logo: undefined })}>
							Retirer
						</button>
					)}
				</div>
				{error && <p className="doc-error">{error}</p>}
			</fieldset>
		</div>
	)
}
