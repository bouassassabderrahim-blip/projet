import { useMemo, useState } from 'react'
import { downloadCsv } from './csv'
import { balanceOf, isActive } from './ledger'
import { addDays, daysBetween, frDate, today } from './numbering'
import { formatMAD, round2 } from './tva'
import type { CommercialDocument, DocKind } from './types'
import './documents.css'

interface Props {
	documents: CommercialDocument[]
	cash: number
	onCashChange: (cash: number) => void
	onNavigate: (kind: DocKind, openId?: string) => void
}

interface Entry {
	doc: CommercialDocument
	amount: number // + encaissement, − décaissement
	due: string
	late: number // jours de retard (0 si non échu)
}

const BUCKETS = [
	{ key: 'late', label: 'Échu' },
	{ key: 'w1', label: '7 prochains jours' },
	{ key: 'd30', label: '8 à 30 jours' },
	{ key: 'd60', label: '31 à 60 jours' },
	{ key: 'd90', label: '61 à 90 jours' },
	{ key: 'later', label: 'Au-delà de 90 jours' },
] as const

type BucketKey = (typeof BUCKETS)[number]['key']

function bucketOf(due: string, now: string): BucketKey {
	if (due < now) return 'late'
	const d = daysBetween(now, due)
	if (d <= 7) return 'w1'
	if (d <= 30) return 'd30'
	if (d <= 60) return 'd60'
	if (d <= 90) return 'd90'
	return 'later'
}

const AGES = [
	{ label: 'Non échu', test: (late: number) => late === 0 },
	{ label: '1 à 30 j', test: (late: number) => late > 0 && late <= 30 },
	{ label: '31 à 60 j', test: (late: number) => late > 30 && late <= 60 },
	{ label: '61 à 90 j', test: (late: number) => late > 60 && late <= 90 },
	{ label: '+ 90 j', test: (late: number) => late > 90 },
]

/** Échéancier clients / fournisseurs, trésorerie prévisionnelle et balance âgée */
export default function SchedulePage({ documents, cash, onCashChange, onNavigate }: Props) {
	const now = today()
	const [cashText, setCashText] = useState(String(cash))
	const [side, setSide] = useState<'all' | 'in' | 'out'>('all')

	const entries = useMemo<Entry[]>(() => {
		const list: Entry[] = []
		for (const d of documents) {
			if ((d.kind !== 'invoice' && d.kind !== 'bill') || !isActive(d)) continue
			const balance = balanceOf(d, documents)
			if (balance <= 0.01) continue
			const due = d.dueDate || addDays(d.date, 60)
			list.push({ doc: d, amount: d.kind === 'invoice' ? balance : -balance, due, late: due < now ? daysBetween(due, now) : 0 })
		}
		return list.sort((a, b) => a.due.localeCompare(b.due))
	}, [documents, now])

	// Trésorerie prévisionnelle : solde cumulé tranche par tranche
	const forecast = useMemo(() => {
		const rows: { key: BucketKey; label: string; inflow: number; outflow: number; balance: number }[] = []
		for (const b of BUCKETS) {
			const items = entries.filter((e) => bucketOf(e.due, now) === b.key)
			const inflow = round2(items.filter((e) => e.amount > 0).reduce((s, e) => s + e.amount, 0))
			const outflow = round2(items.filter((e) => e.amount < 0).reduce((s, e) => s - e.amount, 0))
			const previous = rows.length ? rows[rows.length - 1].balance : cash
			rows.push({ key: b.key, label: b.label, inflow, outflow, balance: round2(previous + inflow - outflow) })
		}
		return rows
	}, [entries, cash, now])

	// Balance âgée des clients
	const aged = useMemo(() => {
		const byClient = new Map<string, number[]>()
		for (const e of entries) {
			if (e.amount <= 0) continue
			const row = byClient.get(e.doc.party.name) ?? AGES.map(() => 0)
			row[AGES.findIndex((a) => a.test(e.late))] += e.amount
			byClient.set(e.doc.party.name, row)
		}
		return [...byClient.entries()]
			.map(([name, cols]) => ({ name, cols: cols.map(round2), total: round2(cols.reduce((s, v) => s + v, 0)) }))
			.sort((a, b) => b.total - a.total)
	}, [entries])

	const toCollect = round2(entries.filter((e) => e.amount > 0).reduce((s, e) => s + e.amount, 0))
	const toPay = round2(entries.filter((e) => e.amount < 0).reduce((s, e) => s - e.amount, 0))
	const shown = entries.filter((e) => side === 'all' || (side === 'in' ? e.amount > 0 : e.amount < 0))

	function saveCash(text: string) {
		setCashText(text)
		const n = Number(text.replace(/\s/g, '').replace(',', '.'))
		if (Number.isFinite(n)) onCashChange(n)
	}

	function exportCsv() {
		downloadCsv(`echeancier-${now}.csv`, [
			['Échéance', 'Sens', 'Pièce', 'Tiers', 'Montant', 'Retard (jours)'],
			...entries.map((e) => [e.due, e.amount > 0 ? 'Encaissement' : 'Décaissement', e.doc.number, e.doc.party.name, Math.abs(e.amount), String(e.late)]),
		])
	}

	return (
		<div>
			<div className="doc-stats">
				<div>
					<span>Trésorerie disponible</span>
					<input className="num doc-cash-input" value={cashText} onChange={(e) => saveCash(e.target.value)} aria-label="Trésorerie disponible" />
				</div>
				<div>
					<span>À encaisser (clients)</span>
					<strong>{formatMAD(toCollect)}</strong>
				</div>
				<div>
					<span>À payer (fournisseurs)</span>
					<strong>{formatMAD(toPay)}</strong>
				</div>
				<div className={cash + toCollect - toPay < 0 ? 'doc-stat-danger' : undefined}>
					<span>Solde prévisionnel</span>
					<strong>{formatMAD(round2(cash + toCollect - toPay))}</strong>
				</div>
			</div>

			<div className="doc-panel">
				<div className="doc-panel-title">Trésorerie prévisionnelle</div>
				<table className="doc-table">
					<thead>
						<tr>
							<th>Période</th>
							<th className="num">Encaissements</th>
							<th className="num">Décaissements</th>
							<th className="num">Solde cumulé</th>
						</tr>
					</thead>
					<tbody>
						{forecast.map((f) => (
							<tr key={f.key} className={f.balance < 0 ? 'doc-row-danger' : undefined}>
								<td>{f.label}</td>
								<td className="num">{f.inflow ? formatMAD(f.inflow) : ''}</td>
								<td className="num">{f.outflow ? formatMAD(f.outflow) : ''}</td>
								<td className="num">
									<strong>{formatMAD(f.balance)}</strong>
								</td>
							</tr>
						))}
					</tbody>
				</table>
				<p className="doc-count">
					Les montants échus sont supposés réglés immédiatement ; la trésorerie de départ se saisit en haut à gauche.
				</p>
			</div>

			{aged.length > 0 && (
				<div className="doc-panel">
					<div className="doc-panel-title">Balance âgée des clients</div>
					<table className="doc-table">
						<thead>
							<tr>
								<th>Client</th>
								{AGES.map((a) => (
									<th key={a.label} className="num">
										{a.label}
									</th>
								))}
								<th className="num">Total dû</th>
							</tr>
						</thead>
						<tbody>
							{aged.map((r) => (
								<tr key={r.name} className={r.cols[4] > 0 ? 'doc-row-danger' : r.cols.slice(1).some((v) => v > 0) ? 'doc-row-late' : undefined}>
									<td>{r.name}</td>
									{r.cols.map((v, i) => (
										<td key={i} className="num">
											{v ? formatMAD(v) : ''}
										</td>
									))}
									<td className="num">
										<strong>{formatMAD(r.total)}</strong>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}

			<div className="doc-toolbar">
				<select value={side} onChange={(e) => setSide(e.target.value as 'all' | 'in' | 'out')}>
					<option value="all">Encaissements et décaissements</option>
					<option value="in">Encaissements clients</option>
					<option value="out">Règlements fournisseurs</option>
				</select>
				<button type="button" onClick={exportCsv}>
					Exporter l'échéancier (CSV)
				</button>
				<span className="doc-count">{shown.length} échéance(s)</span>
			</div>

			{shown.length === 0 ? (
				<p className="doc-empty">Aucune échéance ouverte.</p>
			) : (
				<div className="doc-table-wrap">
					<table className="doc-table">
						<thead>
							<tr>
								<th>Échéance</th>
								<th>Sens</th>
								<th>Pièce</th>
								<th>Tiers</th>
								<th className="num">Montant</th>
								<th className="num">Retard</th>
								<th />
							</tr>
						</thead>
						<tbody>
							{shown.map((e) => (
								<tr key={e.doc.id} className={e.late ? 'doc-row-late' : undefined}>
									<td>{frDate(e.due)}</td>
									<td>
										<span className={`doc-badge ${e.amount > 0 ? 'doc-exp-ok' : 'doc-badge-validated'}`}>
											{e.amount > 0 ? 'Encaissement' : 'Décaissement'}
										</span>
									</td>
									<td>{e.doc.number}</td>
									<td>{e.doc.party.name}</td>
									<td className="num">{formatMAD(Math.abs(e.amount))}</td>
									<td className="num">{e.late ? `${e.late} j` : ''}</td>
									<td>
										<button type="button" onClick={() => onNavigate(e.doc.kind, e.doc.id)}>
											Ouvrir
										</button>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</div>
	)
}
