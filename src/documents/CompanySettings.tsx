import { useState } from 'react'
import type { CompanyInfo } from './types'

interface Props {
	company: CompanyInfo
	onChange: (company: CompanyInfo) => void
}

const fields: { key: keyof CompanyInfo; label: string; hint?: string }[] = [
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

/** Mentions légales de l'émetteur, imprimées sur les factures, BC et BL */
export default function CompanySettings({ company, onChange }: Props) {
	const [draft, setDraft] = useState(company)
	const [saved, setSaved] = useState(false)
	const iceInvalid = draft.ice !== '' && !/^\d{15}$/.test(draft.ice)

	return (
		<div className="doc-editor">
			<div className="doc-grid">
				{fields.map((f) => (
					<label key={f.key}>
						{f.label}
						{f.hint && <small> ({f.hint})</small>}
						<input
							value={draft[f.key]}
							onChange={(e) => {
								setDraft({ ...draft, [f.key]: e.target.value })
								setSaved(false)
							}}
						/>
					</label>
				))}
			</div>
			{iceInvalid && <p className="doc-error">L'ICE doit comporter exactement 15 chiffres.</p>}
			<div className="export-bar">
				<button
					type="button"
					disabled={iceInvalid}
					onClick={() => {
						onChange(draft)
						setSaved(true)
					}}
				>
					Enregistrer
				</button>
				{saved && <span>Enregistré ✓</span>}
			</div>
		</div>
	)
}
