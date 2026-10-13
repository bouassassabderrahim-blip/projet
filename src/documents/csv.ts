import { computeTotals } from './tva'
import { PAYMENT_LABELS, STATUS_LABELS, type CommercialDocument } from './types'

type Cell = string | number

/** CSV au format Excel français : séparateur « ; », virgule décimale, BOM UTF-8 pour les accents */
export function toCsv(rows: Cell[][]): string {
	const cell = (v: Cell) => {
		const s = typeof v === 'number' ? v.toFixed(2).replace('.', ',') : v
		return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
	}
	return '﻿' + rows.map((r) => r.map(cell).join(';')).join('\r\n')
}

export function downloadCsv(filename: string, rows: Cell[][]) {
	const url = URL.createObjectURL(new Blob([toCsv(rows)], { type: 'text/csv;charset=utf-8' }))
	const a = document.createElement('a')
	a.href = url
	a.download = filename
	a.click()
	URL.revokeObjectURL(url)
}

/** Journal des ventes pour le comptable : une ligne par facture, TVA ventilée par taux */
export function salesJournal(invoices: CommercialDocument[]): Cell[][] {
	const rates = [20, 14, 10, 7, 0] as const
	const header: Cell[] = ['N°', 'Date', 'Client', 'ICE client', 'Total HT']
	for (const r of rates) header.push(`Base ${r} %`, `TVA ${r} %`)
	header.push('Total TVA', 'Total TTC', 'Droit de timbre', 'Net à payer', 'Paiement', 'Statut', 'Payée le')

	const rows: Cell[][] = [header]
	for (const d of invoices) {
		const t = computeTotals(d)
		const row: Cell[] = [d.number, d.date, d.party.name, d.party.ice, t.totalHT]
		for (const r of rates) {
			const b = t.byRate.find((x) => x.rate === r)
			row.push(b?.base ?? 0, b?.tva ?? 0)
		}
		row.push(
			t.totalTVA,
			t.totalTTC,
			t.stampDuty,
			t.netToPay,
			PAYMENT_LABELS[d.paymentMethod],
			STATUS_LABELS[d.status],
			d.paidDate ?? '',
		)
		rows.push(row)
	}
	return rows
}
