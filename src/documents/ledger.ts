// Règlements, soldes, avoirs et retards
import { computeTotals, round2 } from './tva'
import { today } from './numbering'
import type { CommercialDocument, Payment } from './types'

/** Règlements d'un document (reprend l'ancien champ paidDate si besoin) */
export function paymentsOf(doc: CommercialDocument): Payment[] {
	if (doc.payments) return doc.payments
	if (doc.status === 'paid' && doc.paidDate)
		return [{ id: 'legacy', date: doc.paidDate, amount: computeTotals(doc).netToPay, method: doc.paymentMethod, reference: '' }]
	return []
}

export function paidAmount(doc: CommercialDocument): number {
	return round2(paymentsOf(doc).reduce((s, p) => s + p.amount, 0))
}

/** Avoirs validés émis sur cette facture */
export function creditsFor(doc: CommercialDocument, documents: CommercialDocument[]): CommercialDocument[] {
	return documents.filter((d) => d.kind === 'credit' && d.sourceId === doc.id && d.status !== 'draft' && d.status !== 'cancelled')
}

/** Reste dû : net à payer − règlements − avoirs */
export function balanceOf(doc: CommercialDocument, documents: CommercialDocument[]): number {
	if (doc.status === 'draft' || doc.status === 'cancelled') return 0
	const credits = creditsFor(doc, documents).reduce((s, c) => s + computeTotals(c).netToPay, 0)
	return round2(computeTotals(doc).netToPay - paidAmount(doc) - credits)
}

/** Facture (client ou fournisseur) validée, non soldée, dont l'échéance est dépassée */
export function isOverdue(doc: CommercialDocument, documents: CommercialDocument[], now = today()): boolean {
	return (
		(doc.kind === 'invoice' || doc.kind === 'bill') &&
		doc.status === 'validated' &&
		!!doc.dueDate &&
		doc.dueDate < now &&
		balanceOf(doc, documents) > 0.01
	)
}

/** Les avoirs viennent en déduction du chiffre d'affaires */
export function sign(doc: CommercialDocument): 1 | -1 {
	return doc.kind === 'credit' ? -1 : 1
}

/** Document pris en compte dans les chiffres (ni brouillon ni annulé) */
export function isActive(doc: CommercialDocument): boolean {
	return doc.status !== 'draft' && doc.status !== 'cancelled'
}
