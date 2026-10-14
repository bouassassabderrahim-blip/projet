import { DOC_LABELS, type CommercialDocument, type DocKind, type DocLine } from './types'

/** Derniers numéros utilisés dans l'ancien logiciel, par type et année (« invoice:2026 » → 457) */
export const NUMBERING_KEY = 'profitpilot:numbering:v1'

export type NumberingStarts = Record<string, number>

export function numberingStarts(): NumberingStarts {
	try {
		const data: unknown = JSON.parse(localStorage.getItem(NUMBERING_KEY) ?? '{}')
		if (typeof data !== 'object' || data === null) return {}
		return Object.fromEntries(Object.entries(data).filter((e): e is [string, number] => Number.isInteger(e[1]) && e[1] > 0))
	} catch {
		return {}
	}
}

/**
 * Numérotation chronologique et continue par type et par année : FA-2026-0001, BL-2026-0001…
 * Après une reprise en cours d'année, elle poursuit celle de l'ancien logiciel (dernier numéro indiqué).
 */
export function nextNumber(kind: DocKind, docs: CommercialDocument[], date: string): string {
	return nextNumberWith(kind, docs, date, numberingStarts())
}

/** Même calcul avec des numéros de départ donnés (aperçu pendant la saisie) */
export function nextNumberWith(kind: DocKind, docs: CommercialDocument[], date: string, starts: NumberingStarts): string {
	const year = date.slice(0, 4)
	const prefix = `${DOC_LABELS[kind].prefix}-${year}-`
	let max = starts[`${kind}:${year}`] ?? 0
	for (const d of docs) {
		if (d.kind !== kind || !d.number.startsWith(prefix)) continue
		const seq = Number(d.number.slice(prefix.length))
		if (Number.isFinite(seq) && seq > max) max = seq
	}
	return prefix + String(max + 1).padStart(4, '0')
}

export function newId(): string {
	return typeof crypto !== 'undefined' && 'randomUUID' in crypto
		? crypto.randomUUID()
		: Date.now().toString(36) + Math.random().toString(36).slice(2)
}

/** Date locale au format AAAA-MM-JJ (et non UTC : au Maroc, toISOString décale d'un jour entre minuit et 1 h) */
export function isoDate(d: Date): string {
	return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function today(): string {
	return isoDate(new Date())
}

export function addDays(date: string, days: number): string {
	const d = new Date(date + 'T00:00:00')
	d.setDate(d.getDate() + days)
	return isoDate(d)
}

export function daysBetween(from: string, to: string): number {
	return Math.round((new Date(to + 'T00:00:00').getTime() - new Date(from + 'T00:00:00').getTime()) / 86400000)
}

export function frDate(d: string | undefined): string {
	return d ? new Date(d + 'T00:00:00').toLocaleDateString('fr-FR') : ''
}

export function emptyLine(): DocLine {
	return { id: newId(), description: '', quantity: 1, unitPriceHT: 0, tvaRate: 20, discount: 0 }
}

/** Nouvelle pièce vierge (brouillon numéroté) */
export function newDocument(kind: DocKind, docs: CommercialDocument[]): CommercialDocument {
	const date = today()
	return {
		id: newId(),
		kind,
		number: nextNumber(kind, docs, date),
		date,
		// Facture : délai légal de paiement par défaut de 60 jours ; devis : validité de 30 jours
		dueDate: addDays(date, kind === 'quote' ? 30 : 60),
		party: { name: '', address: '', city: '', ice: '', ifNumber: '', rc: '', phone: '', email: '' },
		lines: [emptyLine()],
		status: 'draft',
		paymentMethod: 'virement',
		notes: '',
	}
}

/**
 * Numéro définitif attribué à la validation : il suit les pièces déjà validées du même type et de la
 * même année, si bien que la suppression d'un brouillon ne laisse jamais de trou dans la numérotation.
 */
export function finalNumber(doc: CommercialDocument, docs: CommercialDocument[]): string {
	return nextNumber(doc.kind, docs.filter((d) => d.status !== 'draft' && d.id !== doc.id), doc.date)
}
