// Règles métier appliquées quand une pièce a changé sur deux postes à la fois
import { computeTotals } from '../documents/tva'
import type { CommercialDocument, DocStatus, Payment } from '../documents/types'

/** Une pièce avance (brouillon → validée → réglée / annulée) et ne recule jamais */
const RANK: Record<DocStatus, number> = { draft: 0, validated: 1, paid: 2, cancelled: 3 }

const isDoc = (x: unknown): x is CommercialDocument =>
	typeof x === 'object' && x !== null && typeof (x as { status?: unknown }).status === 'string'

const rank = (d: CommercialDocument) => RANK[d.status] ?? 0

/**
 * Fusion de deux versions d'une même pièce :
 * - la version la plus avancée l'emporte (une copie « brouillon » périmée n'annule jamais une validation) ;
 * - à avancement égal, la version préférée l'emporte ;
 * - les règlements des deux versions sont additionnés (deux encaissements saisis sur deux postes).
 */
export function mergeDocument(preferred: unknown, other: unknown): unknown {
	if (!isDoc(preferred) || !isDoc(other)) return preferred
	const winner = rank(other) > rank(preferred) ? other : preferred
	const payments = new Map<string, Payment>()
	for (const p of [...(preferred.payments ?? []), ...(other.payments ?? [])]) if (!payments.has(p.id)) payments.set(p.id, p)
	if (payments.size === 0) return winner
	const merged = [...payments.values()].sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id))
	// Deux acomptes saisis sur deux postes peuvent solder la facture à eux deux
	const paid = merged.reduce((sum, p) => sum + p.amount, 0)
	const settled =
		(winner.kind === 'invoice' || winner.kind === 'bill') &&
		winner.status === 'validated' &&
		paid >= computeTotals(winner).netToPay - 0.01
	return { ...winner, payments: merged, ...(settled ? { status: 'paid' as const } : {}) }
}

/** Une pièce validée ne peut pas être supprimée (seuls les brouillons le peuvent) */
export function protectDocument(record: unknown): boolean {
	return isDoc(record) && record.status !== 'draft'
}
