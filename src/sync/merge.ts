// Règles métier appliquées quand une pièce a changé sur deux postes à la fois
import { computeTotals } from '../documents/tva'
import type { CommercialDocument, DocStatus, Payment } from '../documents/types'
import { threeWayMerge } from './json'

/** Une pièce avance (brouillon → validée → réglée / annulée) et ne recule jamais */
const RANK: Record<DocStatus, number> = { draft: 0, validated: 1, paid: 2, cancelled: 3 }

const isDoc = (x: unknown): x is CommercialDocument =>
	typeof x === 'object' && x !== null && typeof (x as { status?: unknown }).status === 'string'

const rank = (d: CommercialDocument) => RANK[d.status] ?? 0

/**
 * Fusion de deux versions d'une même pièce :
 * - la version la plus avancée l'emporte entière (une copie « brouillon » périmée ne modifie jamais une pièce validée) ;
 * - à avancement égal : sans modification sur ce poste (base absente) la version serveur est reprise,
 *   sinon fusion champ par champ à partir de la dernière version commune ;
 * - les règlements des deux versions sont additionnés (deux encaissements saisis sur deux postes).
 */
export function mergeDocument(local: unknown, remote: unknown, base: unknown | undefined): { result: unknown; conflict: boolean } {
	if (!isDoc(local) || !isDoc(remote)) return { result: base === undefined ? remote : local, conflict: base !== undefined }
	let winner: CommercialDocument
	let conflict = false
	if (rank(local) !== rank(remote)) {
		winner = rank(local) > rank(remote) ? local : remote
		conflict = base !== undefined
	} else if (base === undefined) winner = remote
	else {
		const merged = threeWayMerge(base, local, remote)
		winner = merged.result as CommercialDocument
		conflict = merged.conflict
	}
	const payments = new Map<string, Payment>()
	for (const p of [...(local.payments ?? []), ...(remote.payments ?? [])]) if (!payments.has(p.id)) payments.set(p.id, p)
	if (payments.size === 0) return { result: winner, conflict }
	const all = [...payments.values()].sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id))
	// Deux acomptes saisis sur deux postes peuvent solder la facture à eux deux
	const paid = all.reduce((sum, p) => sum + p.amount, 0)
	const settled =
		(winner.kind === 'invoice' || winner.kind === 'bill') &&
		winner.status === 'validated' &&
		paid >= computeTotals(winner).netToPay - 0.01
	return { result: { ...winner, payments: all, ...(settled ? { status: 'paid' as const } : {}) }, conflict }
}

/** Une pièce validée ne peut pas être supprimée (seuls les brouillons le peuvent) */
export function protectDocument(record: unknown): boolean {
	return isDoc(record) && record.status !== 'draft'
}
