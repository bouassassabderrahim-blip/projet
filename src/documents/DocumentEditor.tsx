import { useState } from 'react'
import type { Product } from '../types'
import {
	DOC_LABELS,
	PAYMENT_LABELS,
	type CommercialDocument,
	type DocLine,
	type Party,
	type PaymentMethod,
	type TvaRate,
} from './types'
import { TVA_RATES, computeTotals, formatMAD, lineHT } from './tva'
import { emptyLine } from './numbering'

interface Props {
	initial: CommercialDocument
	products: Product[]
	/** Clients déjà utilisés, pour les reprendre en un clic */
	knownParties: Party[]
	onSave: (doc: CommercialDocument) => void
	onCancel: () => void
}

const partyFields: { key: keyof Party; label: string }[] = [
	{ key: 'name', label: 'Raison sociale / Nom' },
	{ key: 'address', label: 'Adresse' },
	{ key: 'city', label: 'Ville' },
	{ key: 'ice', label: 'ICE' },
	{ key: 'ifNumber', label: 'IF' },
	{ key: 'rc', label: 'RC' },
	{ key: 'phone', label: 'Téléphone' },
	{ key: 'email', label: 'E-mail' },
]

export default function DocumentEditor({ initial, products, knownParties, onSave, onCancel }: Props) {
	const [doc, setDoc] = useState(initial)
	const [error, setError] = useState('')
	const totals = computeTotals(doc)
	const isInvoice = doc.kind === 'invoice'

	const update = (patch: Partial<CommercialDocument>) => setDoc((d) => ({ ...d, ...patch }))
	const updateParty = (key: keyof Party, value: string) =>
		setDoc((d) => ({ ...d, party: { ...d.party, [key]: value } }))
	const updateLine = (id: string, patch: Partial<DocLine>) =>
		setDoc((d) => ({ ...d, lines: d.lines.map((l) => (l.id === id ? { ...l, ...patch } : l)) }))

	function pickProduct(lineId: string, productId: string) {
		const p = products.find((x) => x.id === productId)
		if (!p) return updateLine(lineId, { productId: undefined })
		updateLine(lineId, { productId: p.id, description: p.name, unitPriceHT: p.unitPrice })
	}

	function pickParty(name: string) {
		const p = knownParties.find((x) => x.name === name)
		if (p) update({ party: { ...p } })
	}

	function submit() {
		if (!doc.party.name.trim()) return setError('Indiquez le nom du client.')
		if (isInvoice && !doc.party.ice.trim())
			return setError("L'ICE du client est obligatoire sur une facture entre professionnels.")
		if (isInvoice && doc.party.ice.trim() && !/^\d{15}$/.test(doc.party.ice.trim()))
			return setError("L'ICE doit comporter 15 chiffres.")
		const lines = doc.lines.filter((l) => l.description.trim() && l.quantity > 0)
		if (lines.length === 0) return setError('Ajoutez au moins une ligne.')
		onSave({ ...doc, lines })
	}

	const num = (v: string) => (v === '' ? 0 : Number(v))

	return (
		<div className="doc-editor">
			<h2>
				{DOC_LABELS[doc.kind].title} {doc.number}
				{doc.sourceNumber && <small> (issu de {doc.sourceNumber})</small>}
			</h2>

			<fieldset>
				<legend>Document</legend>
				<label>
					Date{' '}
					<input type="date" value={doc.date} onChange={(e) => update({ date: e.target.value })} />
				</label>
				{(isInvoice || doc.kind === 'quote') && (
					<label>
						{isInvoice ? 'Échéance' : "Valable jusqu'au"}{' '}
						<input type="date" value={doc.dueDate} onChange={(e) => update({ dueDate: e.target.value })} />
					</label>
				)}
				{isInvoice && (
					<>
						<label>
							Mode de paiement{' '}
							<select
								value={doc.paymentMethod}
								onChange={(e) => update({ paymentMethod: e.target.value as PaymentMethod })}
							>
								{Object.entries(PAYMENT_LABELS).map(([k, v]) => (
									<option key={k} value={k}>
										{v}
									</option>
								))}
							</select>
						</label>
					</>
				)}
			</fieldset>

			<fieldset>
				<legend>Client</legend>
				{knownParties.length > 0 && (
					<label>
						Client existant{' '}
						<select value="" onChange={(e) => pickParty(e.target.value)}>
							<option value="">— choisir —</option>
							{knownParties.map((p) => (
								<option key={p.name} value={p.name}>
									{p.name}
								</option>
							))}
						</select>
					</label>
				)}
				<div className="doc-grid">
					{partyFields.map((f) => (
						<label key={f.key}>
							{f.label}
							<input value={doc.party[f.key]} onChange={(e) => updateParty(f.key, e.target.value)} />
						</label>
					))}
				</div>
			</fieldset>

			<table className="doc-table">
				<thead>
					<tr>
						<th>Produit</th>
						<th>Désignation</th>
						<th>Qté</th>
						<th>P.U. HT</th>
						<th>Remise %</th>
						<th>TVA</th>
						<th>Total HT</th>
						<th />
					</tr>
				</thead>
				<tbody>
					{doc.lines.map((l) => (
						<tr key={l.id}>
							<td>
								<select value={l.productId ?? ''} onChange={(e) => pickProduct(l.id, e.target.value)}>
									<option value="">Libre</option>
									{products.map((p) => (
										<option key={p.id} value={p.id}>
											{p.name}
										</option>
									))}
								</select>
							</td>
							<td>
								<input value={l.description} onChange={(e) => updateLine(l.id, { description: e.target.value })} />
							</td>
							<td>
								<input
									type="number"
									min={0}
									step="any"
									value={l.quantity}
									onChange={(e) => updateLine(l.id, { quantity: num(e.target.value) })}
								/>
							</td>
							<td>
								<input
									type="number"
									min={0}
									step="0.01"
									value={l.unitPriceHT}
									onChange={(e) => updateLine(l.id, { unitPriceHT: num(e.target.value) })}
								/>
							</td>
							<td>
								<input
									type="number"
									min={0}
									max={100}
									value={l.discount}
									onChange={(e) => updateLine(l.id, { discount: num(e.target.value) })}
								/>
							</td>
							<td>
								<select
									value={l.tvaRate}
									onChange={(e) => updateLine(l.id, { tvaRate: Number(e.target.value) as TvaRate })}
								>
									{TVA_RATES.map((t) => (
										<option key={t.rate} value={t.rate}>
											{t.label}
										</option>
									))}
								</select>
							</td>
							<td className="num">{formatMAD(lineHT(l))}</td>
							<td>
								<button
									type="button"
									onClick={() => setDoc((d) => ({ ...d, lines: d.lines.filter((x) => x.id !== l.id) }))}
								>
									✕
								</button>
							</td>
						</tr>
					))}
				</tbody>
			</table>
			<button type="button" onClick={() => setDoc((d) => ({ ...d, lines: [...d.lines, emptyLine()] }))}>
				+ Ajouter une ligne
			</button>

			<div className="doc-totals">
				<div>Total HT : {formatMAD(totals.totalHT)}</div>
				{totals.byRate.map((r) => (
					<div key={r.rate}>
						TVA {r.rate} % sur {formatMAD(r.base)} : {formatMAD(r.tva)}
					</div>
				))}
				<div>
					<strong>Total TTC : {formatMAD(totals.totalTTC)}</strong>
				</div>
				{totals.stampDuty > 0 && (
					<>
						<div>Droit de timbre (0,25 %) : {formatMAD(totals.stampDuty)}</div>
						<div>
							<strong>Net à payer : {formatMAD(totals.netToPay)}</strong>
						</div>
					</>
				)}
			</div>

			<label className="doc-notes">
				Notes / conditions
				<textarea rows={3} value={doc.notes} onChange={(e) => update({ notes: e.target.value })} />
			</label>

			{error && <p className="doc-error">{error}</p>}
			<div className="export-bar">
				<button type="button" onClick={submit}>
					Enregistrer
				</button>
				<button type="button" onClick={onCancel}>
					Annuler
				</button>
			</div>
		</div>
	)
}
