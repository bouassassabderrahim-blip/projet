import { useMemo, useState } from 'react'
import { downloadCsv } from './csv'
import { computeTotals, formatMAD, round2 } from './tva'
import type { CommercialDocument, TvaRate } from './types'
import './documents.css'

interface Props {
	documents: CommercialDocument[]
}

/** Encaissements : régime de droit commun au Maroc. Débits : sur option, TVA due dès la facturation. */
type Regime = 'encaissement' | 'debit'
type Periodicity = 'month' | 'quarter'

const RATES: TvaRate[] = [20, 14, 10, 7]
const MONTHS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre']

interface PeriodRow {
	label: string
	ht: number
	tva: Record<number, number>
	total: number
	count: number
}

/** TVA collectée par période, à reporter sur la déclaration (la TVA déductible sur achats n'est pas suivie ici) */
export default function VatPage({ documents }: Props) {
	const years = useMemo(() => {
		const set = new Set<number>([new Date().getFullYear()])
		for (const d of documents) if (d.kind === 'invoice') set.add(Number(d.date.slice(0, 4)))
		return [...set].sort((a, b) => b - a)
	}, [documents])

	const [year, setYear] = useState(years[0])
	const [regime, setRegime] = useState<Regime>('encaissement')
	const [periodicity, setPeriodicity] = useState<Periodicity>('month')

	const rows = useMemo(() => {
		const count = periodicity === 'month' ? 12 : 4
		const result: PeriodRow[] = Array.from({ length: count }, (_, i) => ({
			label: periodicity === 'month' ? MONTHS[i] : `T${i + 1} (${MONTHS[i * 3]} – ${MONTHS[i * 3 + 2]})`,
			ht: 0,
			tva: {},
			total: 0,
			count: 0,
		}))

		for (const d of documents) {
			if (d.kind !== 'invoice' || d.status === 'draft' || d.status === 'cancelled') continue
			const ref = regime === 'encaissement' ? (d.status === 'paid' ? d.paidDate : undefined) : d.date
			if (!ref || Number(ref.slice(0, 4)) !== year) continue
			const month = Number(ref.slice(5, 7)) - 1
			const row = result[periodicity === 'month' ? month : Math.floor(month / 3)]
			const t = computeTotals(d)
			row.ht += t.totalHT
			row.count++
			for (const r of t.byRate) {
				row.tva[r.rate] = (row.tva[r.rate] ?? 0) + r.tva
				row.total += r.tva
			}
		}
		return result
	}, [documents, year, regime, periodicity])

	const totals = rows.reduce(
		(acc, r) => {
			acc.ht += r.ht
			acc.total += r.total
			for (const rate of RATES) acc.tva[rate] = (acc.tva[rate] ?? 0) + (r.tva[rate] ?? 0)
			return acc
		},
		{ ht: 0, total: 0, tva: {} as Record<number, number> },
	)

	function exportCsv() {
		const header = ['Période', 'Factures', 'CA HT', ...RATES.map((r) => `TVA ${r} %`), 'TVA collectée']
		const body = rows.map((r) => [r.label, String(r.count), round2(r.ht), ...RATES.map((x) => round2(r.tva[x] ?? 0)), round2(r.total)])
		downloadCsv(`tva-collectee-${year}-${regime}.csv`, [header, ...body])
	}

	return (
		<div>
			<div className="export-bar">
				<label>
					Année{' '}
					<select value={year} onChange={(e) => setYear(Number(e.target.value))}>
						{years.map((y) => (
							<option key={y} value={y}>
								{y}
							</option>
						))}
					</select>
				</label>
				<label>
					Régime{' '}
					<select value={regime} onChange={(e) => setRegime(e.target.value as Regime)}>
						<option value="encaissement">Encaissements (date de paiement)</option>
						<option value="debit">Débits (date de facture)</option>
					</select>
				</label>
				<label>
					Déclaration{' '}
					<select value={periodicity} onChange={(e) => setPeriodicity(e.target.value as Periodicity)}>
						<option value="month">Mensuelle</option>
						<option value="quarter">Trimestrielle</option>
					</select>
				</label>
				<button type="button" onClick={exportCsv}>
					Exporter (CSV)
				</button>
			</div>

			<div className="doc-stats">
				<div>
					<span>CA HT {year}</span>
					<strong>{formatMAD(round2(totals.ht))}</strong>
				</div>
				<div>
					<span>TVA collectée {year}</span>
					<strong>{formatMAD(round2(totals.total))}</strong>
				</div>
			</div>

			<table className="doc-table">
				<thead>
					<tr>
						<th>Période</th>
						<th className="num">Factures</th>
						<th className="num">CA HT</th>
						{RATES.map((r) => (
							<th key={r} className="num">
								TVA {r} %
							</th>
						))}
						<th className="num">TVA collectée</th>
					</tr>
				</thead>
				<tbody>
					{rows.map((r) => (
						<tr key={r.label}>
							<td>{r.label}</td>
							<td className="num">{r.count}</td>
							<td className="num">{formatMAD(round2(r.ht))}</td>
							{RATES.map((x) => (
								<td key={x} className="num">
									{formatMAD(round2(r.tva[x] ?? 0))}
								</td>
							))}
							<td className="num">
								<strong>{formatMAD(round2(r.total))}</strong>
							</td>
						</tr>
					))}
				</tbody>
				<tfoot>
					<tr>
						<th>Total</th>
						<th className="num">{rows.reduce((s, r) => s + r.count, 0)}</th>
						<th className="num">{formatMAD(round2(totals.ht))}</th>
						{RATES.map((x) => (
							<th key={x} className="num">
								{formatMAD(round2(totals.tva[x] ?? 0))}
							</th>
						))}
						<th className="num">{formatMAD(round2(totals.total))}</th>
					</tr>
				</tfoot>
			</table>

			<p className="doc-info">
				{regime === 'encaissement'
					? 'Régime des encaissements : seules les factures marquées « Payée » sont comptées, à leur date de paiement.'
					: 'Régime des débits : les factures validées sont comptées à leur date de facturation, payées ou non.'}{' '}
				Ce tableau donne la TVA collectée sur vos ventes. La TVA déductible sur vos achats n'y figure pas : faites
				valider votre déclaration par votre comptable.
			</p>
		</div>
	)
}
