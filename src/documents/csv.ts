import { balanceOf, paidAmount, sign } from './ledger'
import { computeTotals, round2 } from './tva'
import { DOC_LABELS, PAYMENT_LABELS, STATUS_LABELS, type CommercialDocument } from './types'

type Cell = string | number

/** CSV au format Excel français : séparateur « ; », virgule décimale, BOM UTF-8 pour les accents */
export function toCsv(rows: Cell[][]): string {
	const cell = (v: Cell) => {
		const s = typeof v === 'number' ? v.toFixed(2).replace('.', ',') : v
		return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
	}
	return '﻿' + rows.map((r) => r.map(cell).join(';')).join('\r\n')
}

export function downloadFile(filename: string, content: string, type: string) {
	const url = URL.createObjectURL(new Blob([content], { type }))
	const a = document.createElement('a')
	a.href = url
	a.download = filename
	a.click()
	URL.revokeObjectURL(url)
}

export function downloadCsv(filename: string, rows: Cell[][]) {
	downloadFile(filename, toCsv(rows), 'text/csv;charset=utf-8')
}

/**
 * Journal pour le comptable : une ligne par pièce, TVA ventilée par taux.
 * Les avoirs sont en négatif.
 */
export function journal(docs: CommercialDocument[], all: CommercialDocument[]): Cell[][] {
	const rates = [20, 14, 10, 7, 0] as const
	const header: Cell[] = ['Type', 'N°', 'Réf. fournisseur', 'Date', 'Tiers', 'ICE', 'Total HT']
	for (const r of rates) header.push(`Base ${r} %`, `TVA ${r} %`)
	header.push('Total TVA', 'Total TTC', 'Droit de timbre', 'Net', 'Réglé', 'Reste dû', 'Paiement', 'Statut', 'Pièce d\'origine')

	const rows: Cell[][] = [header]
	for (const d of docs) {
		const t = computeTotals(d)
		const k = sign(d)
		const row: Cell[] = [DOC_LABELS[d.kind].title, d.number, d.supplierRef ?? '', d.date, d.party.name, d.party.ice, k * t.totalHT]
		for (const r of rates) {
			const b = t.byRate.find((x) => x.rate === r)
			row.push(k * (b?.base ?? 0), k * (b?.tva ?? 0))
		}
		row.push(
			k * t.totalTVA,
			k * t.totalTTC,
			k * t.stampDuty,
			k * t.netToPay,
			paidAmount(d),
			d.kind === 'credit' ? 0 : round2(balanceOf(d, all)),
			PAYMENT_LABELS[d.paymentMethod],
			STATUS_LABELS[d.status],
			d.sourceNumber ?? '',
		)
		rows.push(row)
	}
	return rows
}
