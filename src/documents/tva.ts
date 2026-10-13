import type { CommercialDocument, DocLine, TvaRate } from './types'

export const TVA_RATES: { rate: TvaRate; label: string }[] = [
	{ rate: 20, label: '20 % (taux normal)' },
	{ rate: 14, label: '14 %' },
	{ rate: 10, label: '10 %' },
	{ rate: 7, label: '7 %' },
	{ rate: 0, label: 'Exonéré (0 %)' },
]

/** Droit de timbre sur les factures réglées en espèces : 0,25 % du TTC. Vérifiez le taux avec votre comptable. */
export const STAMP_DUTY_RATE = 0.0025

export function round2(x: number): number {
	return Math.round((x + Number.EPSILON) * 100) / 100
}

export function lineHT(line: DocLine): number {
	return round2(line.quantity * line.unitPriceHT * (1 - line.discount / 100))
}

export interface TvaBreakdown {
	rate: TvaRate
	base: number
	tva: number
}

export interface DocTotals {
	totalHT: number
	totalTVA: number
	totalTTC: number
	byRate: TvaBreakdown[]
	stampDuty: number
	netToPay: number
}

/** La TVA est calculée par taux sur la somme des bases HT, comme sur une facture marocaine classique */
export function computeTotals(doc: Pick<CommercialDocument, 'lines' | 'kind' | 'paymentMethod'>): DocTotals {
	const bases = new Map<TvaRate, number>()
	for (const line of doc.lines) {
		bases.set(line.tvaRate, (bases.get(line.tvaRate) ?? 0) + lineHT(line))
	}
	const byRate = [...bases.entries()]
		.sort((a, b) => b[0] - a[0])
		.map(([rate, base]) => ({ rate, base: round2(base), tva: round2((base * rate) / 100) }))

	const totalHT = round2(byRate.reduce((s, r) => s + r.base, 0))
	const totalTVA = round2(byRate.reduce((s, r) => s + r.tva, 0))
	const totalTTC = round2(totalHT + totalTVA)
	const stampDuty =
		doc.kind === 'invoice' && doc.paymentMethod === 'especes' ? round2(totalTTC * STAMP_DUTY_RATE) : 0

	return { totalHT, totalTVA, totalTTC, byRate, stampDuty, netToPay: round2(totalTTC + stampDuty) }
}

export function formatMAD(x: number): string {
	return (
		x.toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' DH'
	)
}

// ---------- Montant en lettres (« Arrêtée la présente facture à la somme de … ») ----------

const UNITS = [
	'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix',
	'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf',
]
const TENS = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante', 'quatre-vingt', 'quatre-vingt']

function below100(n: number): string {
	if (n < 20) return UNITS[n]
	const t = Math.floor(n / 10)
	const u = n % 10
	// 70-79 et 90-99 : soixante-dix, quatre-vingt-onze…
	if (t === 7 || t === 9) return TENS[t] + (t === 7 && u === 1 ? ' et ' : '-') + UNITS[10 + u]
	if (u === 0) return t === 8 ? 'quatre-vingts' : TENS[t]
	if (u === 1 && t !== 8) return TENS[t] + ' et un'
	return TENS[t] + '-' + UNITS[u]
}

function below1000(n: number): string {
	const h = Math.floor(n / 100)
	const r = n % 100
	let s = ''
	if (h > 0) s = h === 1 ? 'cent' : UNITS[h] + ' cent' + (r === 0 ? 's' : '')
	if (r > 0) s += (s ? ' ' : '') + below100(r)
	return s
}

export function numberToWordsFr(value: number): string {
	let n = Math.floor(Math.abs(value))
	if (n === 0) return 'zéro'
	const parts: string[] = []
	const billions = Math.floor(n / 1e9)
	n %= 1e9
	const millions = Math.floor(n / 1e6)
	n %= 1e6
	const thousands = Math.floor(n / 1000)
	const rest = n % 1000

	if (billions) parts.push(below1000(billions) + ' milliard' + (billions > 1 ? 's' : ''))
	if (millions) parts.push(below1000(millions) + ' million' + (millions > 1 ? 's' : ''))
	// « mille » est invariable et « vingts/cents » perdent leur s devant lui
	if (thousands) parts.push(thousands === 1 ? 'mille' : below1000(thousands).replace(/(vingt|cent)s$/, '$1') + ' mille')
	if (rest) parts.push(below1000(rest))
	return parts.join(' ')
}

export function amountInWordsMAD(amount: number): string {
	const cents = Math.round(round2(amount) * 100)
	const dh = Math.floor(cents / 100)
	const ct = cents % 100
	let s = numberToWordsFr(dh) + (dh > 1 ? ' dirhams' : ' dirham')
	if (ct > 0) s += ' et ' + numberToWordsFr(ct) + (ct > 1 ? ' centimes' : ' centime')
	return s.charAt(0).toUpperCase() + s.slice(1)
}
