import { useMemo, useState } from 'react'
import { downloadCsv } from './csv'
import { isActive, paymentsOf } from './ledger'
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
	collected: Record<number, number>
	totalCollected: number
	deductible: number
	purchasesHT: number
}

/**
 * Montants imputés à une date : au régime des encaissements, chaque règlement porte sa part
 * de HT et de TVA (prorata du montant réglé) ; au régime des débits, toute la pièce à sa date.
 */
function* imputations(d: CommercialDocument, useDocDate: boolean) {
	const t = computeTotals(d)
	if (useDocDate) {
		yield { date: d.date, ratio: 1, t }
		return
	}
	for (const p of paymentsOf(d)) yield { date: p.date, ratio: t.netToPay ? p.amount / t.netToPay : 0, t }
}

/** Tableau de préparation de la déclaration de TVA : collectée − déductible = TVA due */
export default function VatPage({ documents }: Props) {
	const years = useMemo(() => {
		const set = new Set<number>([new Date().getFullYear()])
		for (const d of documents) set.add(Number(d.date.slice(0, 4)))
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
			collected: {},
			totalCollected: 0,
			deductible: 0,
			purchasesHT: 0,
		}))
		const rowOf = (date: string) => {
			if (Number(date.slice(0, 4)) !== year) return undefined
			const month = Number(date.slice(5, 7)) - 1
			return result[periodicity === 'month' ? month : Math.floor(month / 3)]
		}

		for (const d of documents) {
			if (!isActive(d)) continue
			if (d.kind === 'invoice' || d.kind === 'credit') {
				// Débits : les avoirs viennent en déduction à leur date. Encaissements : un avoir réduit
				// simplement ce qui reste à encaisser (seul un remboursement, saisi comme règlement, compte).
				const k = d.kind === 'credit' ? -1 : 1
				for (const { date, ratio, t } of imputations(d, regime === 'debit')) {
					const row = rowOf(date)
					if (!row) continue
					row.ht += k * t.totalHT * ratio
					for (const r of t.byRate) {
						row.collected[r.rate] = (row.collected[r.rate] ?? 0) + k * r.tva * ratio
						row.totalCollected += k * r.tva * ratio
					}
				}
			}
			if (d.kind === 'bill') {
				// TVA sur achats : déductible au paiement de la facture fournisseur
				for (const { date, ratio, t } of imputations(d, false)) {
					const row = rowOf(date)
					if (!row) continue
					row.purchasesHT += t.totalHT * ratio
					row.deductible += t.totalTVA * ratio
				}
			}
		}
		return result
	}, [documents, year, regime, periodicity])

	const sum = (f: (r: PeriodRow) => number) => round2(rows.reduce((s, r) => s + f(r), 0))
	const totalCollected = sum((r) => r.totalCollected)
	const totalDeductible = sum((r) => r.deductible)

	function exportCsv() {
		const header = ['Période', 'CA HT', ...RATES.map((r) => `TVA ${r} %`), 'TVA collectée', 'Achats HT', 'TVA déductible', 'TVA due']
		const body = rows.map((r) => [
			r.label,
			round2(r.ht),
			...RATES.map((x) => round2(r.collected[x] ?? 0)),
			round2(r.totalCollected),
			round2(r.purchasesHT),
			round2(r.deductible),
			round2(r.totalCollected - r.deductible),
		])
		downloadCsv(`declaration-tva-${year}-${regime}.csv`, [header, ...body])
	}

	return (
		<div>
			<div className="doc-toolbar">
				<label>
					Exercice{' '}
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
					<strong>{formatMAD(sum((r) => r.ht))}</strong>
				</div>
				<div>
					<span>TVA collectée</span>
					<strong>{formatMAD(totalCollected)}</strong>
				</div>
				<div>
					<span>TVA déductible</span>
					<strong>{formatMAD(totalDeductible)}</strong>
				</div>
				<div className={totalCollected - totalDeductible < 0 ? undefined : 'doc-stat-late'}>
					<span>{totalCollected - totalDeductible < 0 ? 'Crédit de TVA' : 'TVA due'}</span>
					<strong>{formatMAD(Math.abs(round2(totalCollected - totalDeductible)))}</strong>
				</div>
			</div>

			<div className="doc-table-wrap">
				<table className="doc-table">
					<thead>
						<tr>
							<th>Période</th>
							<th className="num">CA HT</th>
							{RATES.map((r) => (
								<th key={r} className="num">
									TVA {r} %
								</th>
							))}
							<th className="num">Collectée</th>
							<th className="num">Achats HT</th>
							<th className="num">Déductible</th>
							<th className="num">TVA due</th>
						</tr>
					</thead>
					<tbody>
						{rows.map((r) => {
							const due = round2(r.totalCollected - r.deductible)
							return (
								<tr key={r.label}>
									<td>{r.label}</td>
									<td className="num">{formatMAD(round2(r.ht))}</td>
									{RATES.map((x) => (
										<td key={x} className="num">
											{formatMAD(round2(r.collected[x] ?? 0))}
										</td>
									))}
									<td className="num">{formatMAD(round2(r.totalCollected))}</td>
									<td className="num">{formatMAD(round2(r.purchasesHT))}</td>
									<td className="num">{formatMAD(round2(r.deductible))}</td>
									<td className={`num ${due < 0 ? 'doc-credit' : ''}`}>
										<strong>{formatMAD(due)}</strong>
									</td>
								</tr>
							)
						})}
					</tbody>
					<tfoot>
						<tr className="doc-total-row">
							<td>Total</td>
							<td className="num">{formatMAD(sum((r) => r.ht))}</td>
							{RATES.map((x) => (
								<td key={x} className="num">
									{formatMAD(sum((r) => r.collected[x] ?? 0))}
								</td>
							))}
							<td className="num">{formatMAD(totalCollected)}</td>
							<td className="num">{formatMAD(sum((r) => r.purchasesHT))}</td>
							<td className="num">{formatMAD(totalDeductible)}</td>
							<td className="num">{formatMAD(round2(totalCollected - totalDeductible))}</td>
						</tr>
					</tfoot>
				</table>
			</div>

			<p className="doc-info">
				{regime === 'encaissement'
					? 'Régime des encaissements : la TVA est comptée à chaque règlement reçu, au prorata du montant payé.'
					: 'Régime des débits : la TVA est comptée à la date de chaque facture validée, payée ou non.'}{' '}
				{regime === 'debit' && 'Les avoirs viennent en déduction à leur date. '}La TVA déductible provient des factures fournisseurs, au fur et
				à mesure de leur paiement. Ce tableau prépare votre déclaration : faites-la valider par votre comptable.
			</p>
		</div>
	)
}
