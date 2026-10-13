import { DOC_LABELS, type CommercialDocument, type DocKind, type DocLine } from './types'

/** Numérotation chronologique et continue par type et par année : FA-2026-0001, BL-2026-0001… */
export function nextNumber(kind: DocKind, docs: CommercialDocument[], date: string): string {
	const year = date.slice(0, 4)
	const prefix = `${DOC_LABELS[kind].prefix}-${year}-`
	let max = 0
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

export function today(): string {
	return new Date().toISOString().slice(0, 10)
}

export function addDays(date: string, days: number): string {
	const d = new Date(date + 'T00:00:00')
	d.setDate(d.getDate() + days)
	return d.toISOString().slice(0, 10)
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
