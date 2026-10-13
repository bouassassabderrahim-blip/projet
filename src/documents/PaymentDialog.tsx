import { useState } from 'react'
import { newId, today } from './numbering'
import { formatMAD, round2 } from './tva'
import { PAYMENT_LABELS, type CommercialDocument, type Payment, type PaymentMethod } from './types'

interface Props {
	doc: CommercialDocument
	balance: number
	onSave: (payment: Payment) => void
	onClose: () => void
}

/** Saisie d'un règlement (total ou partiel) */
export default function PaymentDialog({ doc, balance, onSave, onClose }: Props) {
	const [date, setDate] = useState(today())
	const [amount, setAmount] = useState(String(balance))
	const [method, setMethod] = useState<PaymentMethod>(doc.paymentMethod)
	const [reference, setReference] = useState('')
	const [error, setError] = useState('')
	const isPurchase = doc.kind === 'bill'

	function submit() {
		const value = round2(Number(amount.replace(',', '.')))
		if (!Number.isFinite(value) || value <= 0) return setError('Montant invalide.')
		if (value > balance + 0.01) return setError(`Le montant dépasse le reste dû (${formatMAD(balance)}).`)
		if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return setError('Date invalide.')
		onSave({ id: newId(), date, amount: value, method, reference: reference.trim() })
	}

	return (
		<div className="doc-modal-backdrop" onClick={onClose}>
			<div className="doc-modal" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
				<div className="doc-modal-title">
					{isPurchase ? 'Règlement fournisseur' : 'Encaissement'} · {doc.number}
				</div>
				<div className="doc-modal-body">
					<p>
						{doc.party.name} · reste dû : <strong>{formatMAD(balance)}</strong>
					</p>
					<div className="doc-grid">
						<label>
							Date
							<input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
						</label>
						<label>
							Montant (DH)
							<input className="num" value={amount} onChange={(e) => setAmount(e.target.value)} autoFocus />
						</label>
						<label>
							Mode
							<select value={method} onChange={(e) => setMethod(e.target.value as PaymentMethod)}>
								{Object.entries(PAYMENT_LABELS).map(([k, v]) => (
									<option key={k} value={k}>
										{v}
									</option>
								))}
							</select>
						</label>
						<label>
							Référence (n° chèque, virement…)
							<input value={reference} onChange={(e) => setReference(e.target.value)} />
						</label>
					</div>
					{error && <p className="doc-error">{error}</p>}
				</div>
				<div className="doc-modal-actions">
					<button type="button" className="btn-primary" onClick={submit}>
						Enregistrer le règlement
					</button>
					<button type="button" onClick={onClose}>
						Annuler
					</button>
				</div>
			</div>
		</div>
	)
}
