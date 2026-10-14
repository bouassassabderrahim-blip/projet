import { useState } from 'react'
import { useAccess } from '../access/context'
import DocumentPrint from './DocumentPrint'
import { loadImage, printSettingsOf } from './printSettings'
import type { CommercialDocument, CompanyInfo, LetterheadMode, PrintSettings } from './types'
import './documents.css'

interface Props {
	company: CompanyInfo
	onChange: (company: CompanyInfo) => void
}

const fields: { key: 'name' | 'address' | 'city' | 'phone' | 'email' | 'ice' | 'ifNumber' | 'rc' | 'patente' | 'cnss' | 'bank' | 'rib'; label: string; hint?: string }[] = [
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

const MODES: { mode: LetterheadMode; title: string; text: string }[] = [
	{ mode: 'generated', title: 'En-tête automatique', text: 'Logo et coordonnées tirés de la fiche ci-dessus.' },
	{ mode: 'images', title: 'Mon en-tête en image', text: 'Image de votre en-tête (et de votre pied de page) répétée sur chaque page.' },
	{ mode: 'background', title: 'Mon papier à en-tête complet', text: 'Image A4 entière (scan ou export PDF → PNG) en fond de chaque page.' },
	{ mode: 'preprinted', title: 'Papier déjà imprimé', text: 'Rien n’est imprimé en haut ni en bas : seules les marges sont réservées.' },
]

/** Facture d'exemple pour l'aperçu de la mise en page */
const SAMPLE: CommercialDocument = {
	id: 'sample',
	kind: 'invoice',
	number: 'FA-2026-0001',
	date: '2026-10-13',
	dueDate: '2026-12-12',
	party: { name: 'Clinique Exemple', address: '12, boulevard Zerktouni', city: 'Casablanca', ice: '002345678000012', ifNumber: '', rc: '', phone: '', email: '' },
	lines: [
		{ id: '1', description: 'Tige fémorale cimentée taille 3', quantity: 1, unitPriceHT: 9500, tvaRate: 7, discount: 0, lot: 'L2409', serial: 'SN-10452', expiry: '2029-05-01' },
		{ id: '2', description: 'Cotyle double mobilité 52 mm', quantity: 1, unitPriceHT: 7200, tvaRate: 7, discount: 0, lot: 'L2411' },
		{ id: '3', description: 'Ciment orthopédique 40 g', quantity: 2, unitPriceHT: 450, tvaRate: 20, discount: 10 },
	],
	status: 'validated',
	paymentMethod: 'virement',
	notes: '',
	intervention: { patient: 'M. A. Alami', patientRef: 'BE123456', surgeon: 'Dr Bennani', clinic: 'Clinique Exemple', date: '2026-10-10', coverage: 'CNSS' },
}

/** Fiche société, papier à en-tête et mise en page des pièces imprimées */
export default function CompanySettings({ company, onChange }: Props) {
	const [draft, setDraft] = useState(company)
	const [saved, setSaved] = useState(false)
	const [error, setError] = useState('')
	const access = useAccess()
	const canWrite = access.level('settings') === 'write'
	const print = printSettingsOf(draft)
	const iceInvalid = draft.ice !== '' && !/^\d{15}$/.test(draft.ice)
	const ribInvalid = draft.rib !== '' && !/^\d{24}$/.test(draft.rib.replace(/\s/g, ''))

	const set = (patch: Partial<CompanyInfo>) => {
		setDraft((d) => ({ ...d, ...patch }))
		setSaved(false)
	}
	const setPrint = (patch: Partial<PrintSettings>) => {
		setDraft((d) => ({ ...d, print: { ...printSettingsOf(d), ...patch } }))
		setSaved(false)
	}

	async function upload(file: File | undefined, apply: (dataUrl: string, ratio: number) => void, maxWidth?: number) {
		if (!file) return
		if (!file.type.startsWith('image/')) return setError('Choisissez une image (PNG ou JPEG). Un PDF doit d’abord être exporté en image.')
		try {
			const { dataUrl, ratio } = await loadImage(file, maxWidth)
			apply(dataUrl, ratio)
			setError('')
		} catch {
			setError('Image illisible.')
		}
	}

	function save() {
		try {
			onChange(draft)
			setSaved(true)
			access.log('Paramètres société modifiés', draft.name)
		} catch {
			setError('Enregistrement impossible : images trop lourdes pour le navigateur.')
		}
	}

	const number = (v: string, fallback: number) => {
		const n = Number(v.replace(',', '.'))
		return Number.isFinite(n) && n >= 0 ? n : fallback
	}

	return (
		<div>
			<div className="doc-editor-head">
				<h2>Fiche société et mise en page</h2>
				<div className="doc-editor-actions">
					<button type="button" className="btn-primary" disabled={iceInvalid || !canWrite} onClick={save}>
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
				<div className="doc-logo-row">
					<span className="doc-count">Logo (en-tête automatique) :</span>
					{draft.logo && <img className="doc-logo" src={draft.logo} alt="Logo" />}
					<input
						type="file"
						accept="image/png,image/jpeg"
						onChange={(e) => upload(e.target.files?.[0], (logo) => set({ logo }), 600)}
					/>
					{draft.logo && (
						<button type="button" onClick={() => set({ logo: undefined })}>
							Retirer
						</button>
					)}
				</div>
			</fieldset>

			<div className="doc-layout-settings">
				<fieldset className="doc-panel">
					<legend>Papier à en-tête</legend>
					<div className="doc-mode-list">
						{MODES.map((m) => (
							<label key={m.mode} className={`doc-mode ${print.mode === m.mode ? 'doc-mode-active' : ''}`}>
								<input type="radio" name="letterhead" checked={print.mode === m.mode} onChange={() => setPrint({ mode: m.mode })} />
								<span>
									<strong>{m.title}</strong>
									<small>{m.text}</small>
								</span>
							</label>
						))}
					</div>

					{print.mode === 'images' && (
						<div className="doc-grid">
							<label>
								Image de l'en-tête
								<input
									type="file"
									accept="image/png,image/jpeg"
									onChange={(e) =>
										upload(e.target.files?.[0], (headerImg, ratio) =>
											// Marge haute = hauteur de l'image à pleine largeur A4 + 5 mm
											setPrint({ headerImg, top: Math.ceil(210 * ratio) + 5 }),
										)
									}
								/>
							</label>
							<label>
								Image du pied de page
								<input
									type="file"
									accept="image/png,image/jpeg"
									onChange={(e) =>
										upload(e.target.files?.[0], (footerImg, ratio) =>
											setPrint({ footerImg, bottom: Math.ceil(210 * ratio) + 5, showLegal: false }),
										)
									}
								/>
							</label>
							{(print.headerImg || print.footerImg) && (
								<button type="button" onClick={() => setPrint({ headerImg: undefined, footerImg: undefined })}>
									Retirer les images
								</button>
							)}
						</div>
					)}

					{print.mode === 'background' && (
						<div className="doc-grid">
							<label>
								Papier à en-tête (image A4 portrait)
								<input
									type="file"
									accept="image/png,image/jpeg"
									onChange={(e) => upload(e.target.files?.[0], (backgroundImg) => setPrint({ backgroundImg, showLegal: false }))}
								/>
							</label>
							{print.backgroundImg && (
								<button type="button" onClick={() => setPrint({ backgroundImg: undefined })}>
									Retirer le fond
								</button>
							)}
						</div>
					)}

					<div className="doc-grid">
						<label>
							Marge haute (mm)
							<input className="num" type="number" min={0} max={150} value={print.top} onChange={(e) => setPrint({ top: number(e.target.value, print.top) })} />
						</label>
						<label>
							Marge basse (mm)
							<input className="num" type="number" min={0} max={120} value={print.bottom} onChange={(e) => setPrint({ bottom: number(e.target.value, print.bottom) })} />
						</label>
						<label>
							Marges gauche / droite (mm)
							<input className="num" type="number" min={5} max={40} value={print.side} onChange={(e) => setPrint({ side: number(e.target.value, print.side) })} />
						</label>
						<label>
							Couleur des titres
							<input type="color" value={print.accent} onChange={(e) => setPrint({ accent: e.target.value })} />
						</label>
						<label className="doc-check">
							<input type="checkbox" checked={print.showLegal} onChange={(e) => setPrint({ showLegal: e.target.checked })} />
							Mentions légales (ICE, IF, RC, RIB) en bas de page
						</label>
					</div>
					<p className="doc-count">
						Astuce : sur papier à en-tête, augmentez la marge haute jusqu'à ce que le titre de la pièce passe sous votre
						en-tête dans l'aperçu.
					</p>

					<label className="doc-notes">
						Conditions imprimées sous les devis
						<textarea rows={2} value={print.quoteTerms} onChange={(e) => setPrint({ quoteTerms: e.target.value })} />
					</label>
					<label className="doc-notes">
						Conditions imprimées sous les factures
						<textarea rows={2} value={print.invoiceTerms} onChange={(e) => setPrint({ invoiceTerms: e.target.value })} />
					</label>
					{error && <p className="doc-error">{error}</p>}
				</fieldset>

				<div className="doc-panel doc-preview-panel">
					<div className="doc-panel-title">Aperçu (facture d'exemple)</div>
					<div className="doc-preview">
						<div className="doc-preview-inner">
							<DocumentPrint doc={SAMPLE} company={draft} settings={print} embedded />
						</div>
					</div>
				</div>
			</div>
		</div>
	)
}
