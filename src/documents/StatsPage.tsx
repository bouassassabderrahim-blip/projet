import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { isActive, sign } from './ledger'
import { today } from './numbering'
import { computeTotals, formatMAD, lineHT, round2 } from './tva'
import type { CommercialDocument } from './types'
import './documents.css'

interface Props {
	documents: CommercialDocument[]
	products: Product[]
}

const MONTHS = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.']
const MONTHS_LONG = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre']

const pct = (v: number) => `${v.toLocaleString('fr-FR', { maximumFractionDigits: 1 })} %`

/** Valeurs d'axe arrondies et compactes : 0 / 10 k / 20 k… */
function niceTicks(max: number): number[] {
	if (max <= 0) return [0]
	const rough = max / 4
	const pow = 10 ** Math.floor(Math.log10(rough))
	const step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= rough) ?? rough
	const ticks: number[] = []
	for (let v = 0; v <= max + step * 0.001; v += step) ticks.push(v)
	if (ticks[ticks.length - 1] < max) ticks.push(ticks[ticks.length - 1] + step)
	return ticks
}

const compact = (v: number) =>
	v >= 1e6 ? `${(v / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} M` : v >= 1000 ? `${(v / 1000).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} k` : String(v)

interface MonthPoint {
	month: number
	ht: number
	count: number
}

/** Histogramme du CA HT mensuel : une seule série, survol et focus clavier sur chaque colonne */
function MonthlyChart({ data }: { data: MonthPoint[] }) {
	const [hover, setHover] = useState<number | null>(null)
	const W = 760
	const H = 260
	const pad = { top: 22, right: 12, bottom: 28, left: 52 }
	const innerW = W - pad.left - pad.right
	const innerH = H - pad.top - pad.bottom
	const max = Math.max(...data.map((d) => d.ht), 0)
	const ticks = niceTicks(max)
	const top = ticks[ticks.length - 1] || 1
	const band = innerW / data.length
	// Le SVG s'agrandit avec la page : 16 unités ≈ 24 px sur un écran large
	const barW = Math.min(16, band * 0.5)
	const y = (v: number) => pad.top + innerH - (Math.max(v, 0) / top) * innerH
	const best = data.reduce((m, d, i) => (d.ht > data[m].ht ? i : m), 0)

	return (
		<div className="stats-chart">
			<svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Chiffre d'affaires HT par mois">
				{ticks.map((t) => (
					<g key={t}>
						<line x1={pad.left} x2={W - pad.right} y1={y(t)} y2={y(t)} className="stats-grid" />
						<text x={pad.left - 8} y={y(t)} className="stats-tick" textAnchor="end" dominantBaseline="middle">
							{compact(t)}
						</text>
					</g>
				))}
				{data.map((d, i) => {
					const cx = pad.left + band * i + band / 2
					const h = Math.max(pad.top + innerH - y(d.ht), 0)
					const r = Math.min(4, h)
					const x0 = cx - barW / 2
					const yTop = pad.top + innerH - h
					// Bout arrondi de 4 px côté valeur, angle droit sur la ligne de base
					const path = h
						? `M${x0},${pad.top + innerH} V${yTop + r} Q${x0},${yTop} ${x0 + r},${yTop} H${x0 + barW - r} Q${x0 + barW},${yTop} ${x0 + barW},${yTop + r} V${pad.top + innerH} Z`
						: ''
					return (
						<g
							key={d.month}
							tabIndex={0}
							className={`stats-bar ${hover === i ? 'stats-bar-active' : ''}`}
							onPointerEnter={() => setHover(i)}
							onPointerLeave={() => setHover(null)}
							onFocus={() => setHover(i)}
							onBlur={() => setHover(null)}
						>
							{/* Zone de survol plus large que la colonne */}
							<rect x={pad.left + band * i} y={pad.top} width={band} height={innerH} fill="transparent" />
							{path && <path d={path} className="stats-bar-fill" />}
							{i === best && d.ht > 0 && (
								<text x={cx} y={yTop - 6} textAnchor="middle" className="stats-label">
									{compact(round2(d.ht))}
								</text>
							)}
							<text x={cx} y={H - 8} textAnchor="middle" className="stats-tick">
								{MONTHS[d.month]}
							</text>
						</g>
					)
				})}
				<line x1={pad.left} x2={W - pad.right} y1={pad.top + innerH} y2={pad.top + innerH} className="stats-axis" />
			</svg>
			{hover !== null && (
				<div className="stats-tooltip" style={{ left: `${((pad.left + band * hover + band / 2) / W) * 100}%` }}>
					<strong>{formatMAD(round2(data[hover].ht))}</strong>
					<span>
						{MONTHS_LONG[data[hover].month]} · {data[hover].count} facture(s)
					</span>
				</div>
			)}
		</div>
	)
}

/** Statistiques de ventes : CA mensuel, marge, meilleurs clients et articles */
export default function StatsPage({ documents, products }: Props) {
	const years = useMemo(() => {
		const set = new Set<number>([new Date().getFullYear()])
		for (const d of documents) if (d.kind === 'invoice') set.add(Number(d.date.slice(0, 4)))
		return [...set].sort((a, b) => b - a)
	}, [documents])
	const [year, setYear] = useState(years[0])
	const [showTable, setShowTable] = useState(false)
	const showCosts = useAccess().can('costs')

	const stats = useMemo(() => {
		const cost = new Map(products.map((p) => [p.id, p.unitCost]))
		const months: MonthPoint[] = MONTHS.map((_, month) => ({ month, ht: 0, count: 0 }))
		const clients = new Map<string, { ht: number; count: number }>()
		const items = new Map<string, { name: string; qty: number; ht: number; cost: number; costKnown: boolean }>()
		const coverage = new Map<string, number>()
		let ht = 0
		let margin = 0
		let count = 0
		let previous = 0
		const thisYear = String(year)
		const lastYear = String(year - 1)
		const sameDay = today().slice(4)

		for (const d of documents) {
			// Factures reprises de l'ancien logiciel : leur chiffre d'affaires y est déjà compté
			if ((d.kind !== 'invoice' && d.kind !== 'credit') || !isActive(d) || d.legacy) continue
			const k = sign(d)
			const t = computeTotals(d)
			// Même période de l'année précédente, pour la comparaison
			if (d.date.startsWith(lastYear) && d.date.slice(4) <= sameDay) previous += k * t.totalHT
			if (!d.date.startsWith(thisYear)) continue

			const m = months[Number(d.date.slice(5, 7)) - 1]
			m.ht += k * t.totalHT
			ht += k * t.totalHT
			if (d.kind === 'invoice') {
				m.count++
				count++
			}
			const c = clients.get(d.party.name) ?? { ht: 0, count: 0 }
			c.ht += k * t.totalHT
			if (d.kind === 'invoice') c.count++
			clients.set(d.party.name, c)
			const cov = d.intervention?.coverage || 'Non renseigné'
			coverage.set(cov, (coverage.get(cov) ?? 0) + k * t.totalHT)

			for (const l of d.lines) {
				const lht = k * lineHT(l)
				const unit = l.productId ? cost.get(l.productId) : undefined
				const lcost = unit === undefined ? 0 : k * unit * l.quantity
				margin += lht - lcost
				const key = l.productId ?? `libre:${l.description}`
				const it = items.get(key) ?? { name: l.description, qty: 0, ht: 0, cost: 0, costKnown: unit !== undefined }
				it.qty += k * l.quantity
				it.ht += lht
				it.cost += lcost
				items.set(key, it)
			}
		}

		const topClients = [...clients.entries()].map(([name, v]) => ({ name, ...v })).sort((a, b) => b.ht - a.ht).slice(0, 10)
		const topItems = [...items.values()].sort((a, b) => b.ht - a.ht).slice(0, 10)
		const coverageRows = [...coverage.entries()].sort((a, b) => b[1] - a[1])
		return { months, ht, margin, count, previous, topClients, topItems, coverageRows }
	}, [documents, products, year])

	const rate = stats.ht ? (stats.margin / stats.ht) * 100 : 0
	const growth = stats.previous ? ((stats.ht - stats.previous) / Math.abs(stats.previous)) * 100 : null
	const maxClient = Math.max(...stats.topClients.map((c) => c.ht), 1)

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
				<span className="doc-count">Factures validées, avoirs déduits. Marge = prix de vente HT − coût d'achat des articles.</span>
			</div>

			<div className="doc-stats">
				<div>
					<span>Chiffre d'affaires HT</span>
					<strong>{formatMAD(round2(stats.ht))}</strong>
					{growth !== null && year === years[0] && (
						<small className={growth >= 0 ? 'doc-credit' : 'doc-error'}>
							{growth >= 0 ? '+' : ''}
							{pct(growth)} vs même période {year - 1}
						</small>
					)}
				</div>
				{showCosts && (
					<div>
						<span>Marge brute</span>
						<strong>{formatMAD(round2(stats.margin))}</strong>
					</div>
				)}
				{showCosts && (
					<div>
						<span>Taux de marge</span>
						<strong>{pct(rate)}</strong>
					</div>
				)}
				<div>
					<span>Factures · panier moyen HT</span>
					<strong>
						{stats.count} · {formatMAD(stats.count ? round2(stats.ht / stats.count) : 0)}
					</strong>
				</div>
			</div>

			<div className="doc-panel">
				<div className="doc-panel-title stats-title">
					Chiffre d'affaires HT par mois — {year}
					<button type="button" onClick={() => setShowTable(!showTable)}>
						{showTable ? 'Voir le graphique' : 'Voir le tableau'}
					</button>
				</div>
				{showTable ? (
					<table className="doc-table">
						<thead>
							<tr>
								<th>Mois</th>
								<th className="num">Factures</th>
								<th className="num">CA HT</th>
							</tr>
						</thead>
						<tbody>
							{stats.months.map((m) => (
								<tr key={m.month}>
									<td>{MONTHS_LONG[m.month]}</td>
									<td className="num">{m.count}</td>
									<td className="num">{formatMAD(round2(m.ht))}</td>
								</tr>
							))}
						</tbody>
					</table>
				) : (
					<MonthlyChart data={stats.months} />
				)}
			</div>

			<div className="stats-columns">
				<div className="doc-panel">
					<div className="doc-panel-title">Meilleurs clients</div>
					<table className="doc-table">
						<thead>
							<tr>
								<th>Client</th>
								<th className="num">Factures</th>
								<th className="num">CA HT</th>
								<th className="num">Part</th>
								<th />
							</tr>
						</thead>
						<tbody>
							{stats.topClients.map((c) => (
								<tr key={c.name}>
									<td>{c.name}</td>
									<td className="num">{c.count}</td>
									<td className="num">{formatMAD(round2(c.ht))}</td>
									<td className="num">{stats.ht ? pct((c.ht / stats.ht) * 100) : ''}</td>
									<td className="stats-bar-cell">
										<div className="stats-inline-bar" style={{ width: `${Math.max((c.ht / maxClient) * 100, 0)}%` }} />
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>

				<div className="doc-panel">
					<div className="doc-panel-title">CA par prise en charge</div>
					<table className="doc-table">
						<thead>
							<tr>
								<th>Prise en charge</th>
								<th className="num">CA HT</th>
								<th className="num">Part</th>
							</tr>
						</thead>
						<tbody>
							{stats.coverageRows.map(([cov, v]) => (
								<tr key={cov}>
									<td>{cov}</td>
									<td className="num">{formatMAD(round2(v))}</td>
									<td className="num">{stats.ht ? pct((v / stats.ht) * 100) : ''}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			</div>

			<div className="doc-panel">
				<div className="doc-panel-title">Articles les plus vendus</div>
				<table className="doc-table">
					<thead>
						<tr>
							<th>Article</th>
							<th className="num">Quantité</th>
							<th className="num">CA HT</th>
							{showCosts && <th className="num">Marge</th>}
							{showCosts && <th className="num">Taux de marge</th>}
						</tr>
					</thead>
					<tbody>
						{stats.topItems.map((it) => (
							<tr key={it.name}>
								<td>{it.name}</td>
								<td className="num">{it.qty}</td>
								<td className="num">{formatMAD(round2(it.ht))}</td>
								{showCosts && <td className="num">{it.costKnown ? formatMAD(round2(it.ht - it.cost)) : '—'}</td>}
								{showCosts && <td className="num">{it.costKnown && it.ht ? pct(((it.ht - it.cost) / it.ht) * 100) : '—'}</td>}
							</tr>
						))}
					</tbody>
				</table>
				<p className="doc-count">« — » : ligne saisie librement, sans article du catalogue, donc sans coût d'achat connu.</p>
			</div>
		</div>
	)
}
