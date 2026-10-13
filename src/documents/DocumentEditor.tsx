import { useState } from 'react'
import type { Product } from '../types'
import {
	COVERAGES,
	DOC_LABELS,
	PAYMENT_LABELS,
	emptyIntervention,
	type CommercialDocument,
	type Coverage,
	type DocLine,
	type Intervention,
	type Kit,
	type Party,
	type PartyRecord,
	type PaymentMethod,
	type StockLot,
	type TvaRate,
} from './types'
import { TVA_RATES, computeTotals, formatMAD, lineHT } from './tva'
import { addDays, emptyLine, frDate, newId } from './numbering'
import { availableLots } from './stockMoves'

interface Props {
	initial: CommercialDocument
	products: Product[]
	lots: StockLot[]
	kits: Kit[]
	/** Fiches tiers du bon rôle (clients pour les ventes, fournisseurs pour les achats) */
	parties: PartyRecord[]
	onSave: (doc: CommercialDocument) => void
	onCancel: () => void
}

const partyFields: { key: Exclude<keyof Party, 'individual'>; label: string }[] = [
	{ key: 'name', label: 'Raison sociale / Nom' },
	{ key: 'address', label: 'Adresse' },
	{ key: 'city', label: 'Ville' },
	{ key: 'ice', label: 'ICE' },
	{ key: 'ifNumber', label: 'IF' },
	{ key: 'rc', label: 'RC' },
	{ key: 'phone', label: 'Téléphone' },
	{ key: 'email', label: 'E-mail' },
]

const interventionFields: { key: Exclude<keyof Intervention, 'coverage' | 'date'>; label: string }[] = [
	{ key: 'patient', label: 'Patient' },
	{ key: 'patientRef', label: 'N° dossier / CIN' },
	{ key: 'surgeon', label: 'Chirurgien' },
	{ key: 'clinic', label: 'Clinique / hôpital' },
]

export default function DocumentEditor({ initial, products, lots, kits, parties, onSave, onCancel }: Props) {
	const [doc, setDoc] = useState(initial)
	const [error, setError] = useState('')
	const totals = computeTotals(doc)
	const info = DOC_LABELS[doc.kind]
	const isPurchase = info.side === 'purchase'
	const isInvoice = doc.kind === 'invoice'
	const hasDueDate = doc.kind === 'invoice' || doc.kind === 'bill' || doc.kind === 'quote'
	const hasPayment = doc.kind === 'invoice' || doc.kind === 'bill' || doc.kind === 'credit'
	const hasIntervention = doc.kind === 'invoice' || doc.kind === 'delivery' || doc.kind === 'quote' || doc.kind === 'credit'
	// Sorties de stock : on propose les lots disponibles
	const picksLots = doc.kind === 'delivery' || doc.kind === 'invoice' || doc.kind === 'credit'

	const update = (patch: Partial<CommercialDocument>) => setDoc((d) => ({ ...d, ...patch }))
	const updateParty = (patch: Partial<Party>) => setDoc((d) => ({ ...d, party: { ...d.party, ...patch } }))
	const updateLine = (id: string, patch: Partial<DocLine>) =>
		setDoc((d) => ({ ...d, lines: d.lines.map((l) => (l.id === id ? { ...l, ...patch } : l)) }))
	const updateIntervention = (patch: Partial<Intervention>) =>
		setDoc((d) => ({ ...d, intervention: { ...(d.intervention ?? emptyIntervention()), ...patch } }))

	const priceOf = (p: Product) => (isPurchase ? p.unitCost : p.unitPrice)

	function pickProduct(lineId: string, productId: string) {
		const p = products.find((x) => x.id === productId)
		if (!p) return updateLine(lineId, { productId: undefined, lotId: undefined })
		updateLine(lineId, { productId: p.id, description: p.name, unitPriceHT: priceOf(p), lotId: undefined })
	}

	function pickLot(lineId: string, lotId: string) {
		const lot = lots.find((l) => l.id === lotId)
		if (!lot) return updateLine(lineId, { lotId: undefined })
		updateLine(lineId, { lotId: lot.id, lot: lot.lot, serial: lot.serial, expiry: lot.expiry })
	}

	function pickParty(id: string) {
		const p = parties.find((x) => x.id === id)
		if (!p) return
		const { name, address, city, ice, ifNumber, rc, phone, email, individual } = p
		const patch: Partial<CommercialDocument> = { party: { name, address, city, ice, ifNumber, rc, phone, email, individual } }
		// Échéance selon le délai de paiement de la fiche
		if ((doc.kind === 'invoice' || doc.kind === 'bill') && p.paymentTerms !== undefined)
			patch.dueDate = addDays(doc.date, p.paymentTerms)
		update(patch)
	}

	function insertKit(kitId: string) {
		const kit = kits.find((k) => k.id === kitId)
		if (!kit) return
		const added: DocLine[] = []
		for (const item of kit.items) {
			const p = products.find((x) => x.id === item.productId)
			if (!p) continue
			added.push({ ...emptyLine(), id: newId(), productId: p.id, description: p.name, unitPriceHT: priceOf(p), quantity: item.quantity })
		}
		// On remplace la ligne vide de départ si elle n'a pas été remplie
		setDoc((d) => ({ ...d, lines: [...d.lines.filter((l) => l.description.trim()), ...added] }))
	}

	function submit() {
		const name = doc.party.name.trim()
		if (!name) return setError(isPurchase ? 'Indiquez le fournisseur.' : 'Indiquez le client.')
		const ice = doc.party.ice.trim()
		if (ice && !/^\d{15}$/.test(ice)) return setError("L'ICE doit comporter 15 chiffres.")
		if (isInvoice && !doc.party.individual && !ice)
			return setError("L'ICE du client est obligatoire sur une facture à un professionnel. Cochez « Particulier » pour un patient.")
		if (doc.kind === 'bill' && !doc.supplierRef?.trim()) return setError('Indiquez le numéro de la facture du fournisseur.')
		const lines = doc.lines.filter((l) => l.description.trim() && l.quantity > 0)
		if (lines.length === 0) return setError('Ajoutez au moins une ligne.')
		const intervention = doc.intervention && Object.values(doc.intervention).some((v) => v) ? doc.intervention : undefined
		onSave({ ...doc, lines, intervention, party: { ...doc.party, name } })
	}

	const num = (v: string) => (v === '' ? 0 : Number(v))

	return (
		<div className="doc-editor">
			<div className="doc-editor-head">
				<h2>
					{info.title} {doc.number}
					{doc.sourceNumber && <small> (issu de {doc.sourceNumber})</small>}
				</h2>
				<div className="doc-editor-actions">
					<button type="button" className="btn-primary" onClick={submit}>
						Enregistrer
					</button>
					<button type="button" onClick={onCancel}>
						Fermer
					</button>
				</div>
			</div>

			<div className="doc-panels">
				<fieldset>
					<legend>Pièce</legend>
					<div className="doc-grid">
						<label>
							Date
							<input type="date" value={doc.date} onChange={(e) => update({ date: e.target.value })} />
						</label>
						{hasDueDate && (
							<label>
								{doc.kind === 'quote' ? "Valable jusqu'au" : 'Échéance'}
								<input type="date" value={doc.dueDate} onChange={(e) => update({ dueDate: e.target.value })} />
							</label>
						)}
						{hasPayment && (
							<label>
								Mode de règlement
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
						)}
						{doc.kind === 'bill' && (
							<label>
								N° facture fournisseur
								<input value={doc.supplierRef ?? ''} onChange={(e) => update({ supplierRef: e.target.value })} />
							</label>
						)}
						{doc.kind === 'delivery' && (
							<label className="doc-check">
								<input
									type="checkbox"
									checked={!!doc.consignment}
									onChange={(e) => update({ consignment: e.target.checked })}
								/>
								BL en dépôt (facturé à la pose)
							</label>
						)}
					</div>
				</fieldset>

				<fieldset>
					<legend>{isPurchase ? 'Fournisseur' : 'Client'}</legend>
					{parties.length > 0 && (
						<label>
							{isPurchase ? 'Fournisseur enregistré' : 'Client enregistré'}
							<select value="" onChange={(e) => pickParty(e.target.value)}>
								<option value="">— choisir dans le fichier —</option>
								{parties.map((p) => (
									<option key={p.id} value={p.id}>
										{p.name}
										{p.city ? ` (${p.city})` : ''}
									</option>
								))}
							</select>
						</label>
					)}
					<div className="doc-grid">
						{partyFields.map((f) => (
							<label key={f.key}>
								{f.label}
								<input value={doc.party[f.key]} onChange={(e) => updateParty({ [f.key]: e.target.value })} />
							</label>
						))}
						{!isPurchase && (
							<label className="doc-check">
								<input
									type="checkbox"
									checked={!!doc.party.individual}
									onChange={(e) => updateParty({ individual: e.target.checked })}
								/>
								Particulier (patient, sans ICE)
							</label>
						)}
					</div>
				</fieldset>

				{hasIntervention && (
					<fieldset>
						<legend>Intervention / patient</legend>
						<div className="doc-grid">
							{interventionFields.map((f) => (
								<label key={f.key}>
									{f.label}
									<input
										value={doc.intervention?.[f.key] ?? ''}
										onChange={(e) => updateIntervention({ [f.key]: e.target.value })}
									/>
								</label>
							))}
							<label>
								Date d'intervention
								<input
									type="date"
									value={doc.intervention?.date ?? ''}
									onChange={(e) => updateIntervention({ date: e.target.value })}
								/>
							</label>
							<label>
								Prise en charge
								<select
									value={doc.intervention?.coverage ?? ''}
									onChange={(e) => updateIntervention({ coverage: e.target.value as Coverage | '' })}
								>
									<option value="">—</option>
									{COVERAGES.map((c) => (
										<option key={c} value={c}>
											{c}
										</option>
									))}
								</select>
							</label>
						</div>
					</fieldset>
				)}
			</div>

			<div className="doc-toolbar">
				<button type="button" onClick={() => setDoc((d) => ({ ...d, lines: [...d.lines, emptyLine()] }))}>
					+ Ligne
				</button>
				{kits.length > 0 && (
					<select value="" onChange={(e) => insertKit(e.target.value)}>
						<option value="">Insérer un kit…</option>
						{kits.map((k) => (
							<option key={k.id} value={k.id}>
								{k.name}
							</option>
						))}
					</select>
				)}
			</div>

			<div className="doc-table-wrap">
				<table className="doc-table doc-lines">
					<thead>
						<tr>
							<th>Article</th>
							<th>Désignation</th>
							<th>Lot / N° de série</th>
							<th>Péremption</th>
							<th className="num">Qté</th>
							<th className="num">P.U. HT</th>
							<th className="num">Rem. %</th>
							<th>TVA</th>
							<th className="num">Total HT</th>
							<th />
						</tr>
					</thead>
					<tbody>
						{doc.lines.map((l) => {
							const choices = picksLots ? availableLots(lots, l.productId) : []
							return (
								<tr key={l.id}>
									<td>
										<select value={l.productId ?? ''} onChange={(e) => pickProduct(l.id, e.target.value)}>
											<option value="">Libre</option>
											{products.map((p) => (
												<option key={p.id} value={p.id}>
													{p.reference ? `${p.reference} · ` : ''}
													{p.name}
												</option>
											))}
										</select>
									</td>
									<td>
										<input
											value={l.description}
											onChange={(e) => updateLine(l.id, { description: e.target.value })}
										/>
									</td>
									<td className="doc-lot-cell">
										{choices.length > 0 && (
											<select value={l.lotId ?? ''} onChange={(e) => pickLot(l.id, e.target.value)}>
												<option value="">Lot en stock…</option>
												{choices.map((c) => (
													<option key={c.id} value={c.id}>
														{[c.lot, c.serial].filter(Boolean).join(' / ')} · {c.quantity} dispo
														{c.expiry ? ` · exp. ${frDate(c.expiry)}` : ''}
													</option>
												))}
											</select>
										)}
										<div className="doc-lot-inputs">
											<input
												placeholder="Lot"
												value={l.lot ?? ''}
												onChange={(e) => updateLine(l.id, { lot: e.target.value, lotId: undefined })}
											/>
											<input
												placeholder="N° série"
												value={l.serial ?? ''}
												onChange={(e) => updateLine(l.id, { serial: e.target.value, lotId: undefined })}
											/>
										</div>
									</td>
									<td>
										<input
											type="date"
											value={l.expiry ?? ''}
											onChange={(e) => updateLine(l.id, { expiry: e.target.value })}
										/>
									</td>
									<td>
										<input
											className="num"
											type="number"
											min={0}
											step="any"
											value={l.quantity}
											onChange={(e) => updateLine(l.id, { quantity: num(e.target.value) })}
										/>
									</td>
									<td>
										<input
											className="num"
											type="number"
											min={0}
											step="0.01"
											value={l.unitPriceHT}
											onChange={(e) => updateLine(l.id, { unitPriceHT: num(e.target.value) })}
										/>
									</td>
									<td>
										<input
											className="num"
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
											title="Supprimer la ligne"
											onClick={() => setDoc((d) => ({ ...d, lines: d.lines.filter((x) => x.id !== l.id) }))}
										>
											✕
										</button>
									</td>
								</tr>
							)
						})}
					</tbody>
				</table>
			</div>

			<div className="doc-bottom">
				<label className="doc-notes">
					Notes / conditions
					<textarea rows={4} value={doc.notes} onChange={(e) => update({ notes: e.target.value })} />
				</label>
				<table className="doc-table doc-totals-box">
					<tbody>
						<tr>
							<td>Total HT</td>
							<td className="num">{formatMAD(totals.totalHT)}</td>
						</tr>
						{totals.byRate.map((r) => (
							<tr key={r.rate}>
								<td>
									TVA {r.rate} % sur {formatMAD(r.base)}
								</td>
								<td className="num">{formatMAD(r.tva)}</td>
							</tr>
						))}
						<tr className="doc-total-row">
							<td>Total TTC</td>
							<td className="num">{formatMAD(totals.totalTTC)}</td>
						</tr>
						{totals.stampDuty > 0 && (
							<>
								<tr>
									<td>Droit de timbre (0,25 %)</td>
									<td className="num">{formatMAD(totals.stampDuty)}</td>
								</tr>
								<tr className="doc-total-row">
									<td>Net à payer</td>
									<td className="num">{formatMAD(totals.netToPay)}</td>
								</tr>
							</>
						)}
					</tbody>
				</table>
			</div>

			{error && <p className="doc-error">{error}</p>}
		</div>
	)
}
