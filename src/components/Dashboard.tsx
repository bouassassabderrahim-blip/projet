import type { PageId, Product } from '../types'
import KpiCard from './KpiCard'
import {
	computeProductMetrics,
	computeTotals,
	formatEuro,
	formatPercent,
} from '../utils/finance'
import { getStockStatus } from '../utils/stock'
import type { CommercialDocument } from '../documents/types'
import { computeTotals as computeDocTotals, formatMAD, round2 } from '../documents/tva'
import { isOverdue, today } from '../documents/numbering'

interface DashboardProps {
	products: Product[]
	/** Devis, BC, BL et factures : alimentent le bloc « Ventes » */
	documents?: CommercialDocument[]
	onNavigate?: (page: PageId) => void
}

function badgeClass(rate: number): string {
	if (rate >= 40) return 'badge badge-good'
	if (rate >= 20) return 'badge badge-medium'
	return 'badge badge-low'
}

function rateTone(rate: number): 'good' | 'medium' | 'low' {
	if (rate >= 40) return 'good'
	if (rate >= 20) return 'medium'
	return 'low'
}

/** Synthèse des ventes en dirhams : mois en cours, encours clients, retards, devis ouverts */
function salesSummary(documents: CommercialDocument[]) {
	const now = today()
	const month = now.slice(0, 7)
	let monthHT = 0
	let unpaid = 0
	let late = 0
	let lateCount = 0
	let invoiceCount = 0
	for (const d of documents) {
		if (d.kind !== 'invoice' || d.status === 'draft' || d.status === 'cancelled') continue
		invoiceCount++
		const t = computeDocTotals(d)
		if (d.date.startsWith(month)) monthHT += t.totalHT
		if (d.status !== 'paid') unpaid += t.netToPay
		if (isOverdue(d, now)) {
			late += t.netToPay
			lateCount++
		}
	}
	// Devis encore ouverts : non annulés et pas encore transformés en BC ou facture
	const converted = new Set(documents.map((d) => d.sourceId).filter(Boolean))
	const openQuotes = documents.filter(
		(d) => d.kind === 'quote' && d.status !== 'cancelled' && !converted.has(d.id) && d.dueDate >= now,
	)
	const quotesHT = openQuotes.reduce((s, d) => s + computeDocTotals(d).totalHT, 0)
	return {
		invoiceCount,
		monthHT: round2(monthHT),
		unpaid: round2(unpaid),
		late: round2(late),
		lateCount,
		openQuotes: openQuotes.length,
		quotesHT: round2(quotesHT),
	}
}

export default function Dashboard({ products, documents = [], onNavigate }: DashboardProps) {
	if (products.length === 0) {
		return (
			<div className="card">
				<p className="muted">
					Aucun produit pour le moment. Ajoute des produits dans « Mes produits » ou importe un fichier CSV.
				</p>
			</div>
		)
	}

	const totals = computeTotals(products)
	const rows = products
		.map(computeProductMetrics)
		.sort((a, b) => b.margin - a.margin)
	const maxMargin = Math.max(...rows.map((r) => r.margin), 1)

	const best = rows[0]
	const weakest = [...rows].sort((a, b) => a.marginRate - b.marginRate)[0]
	const top3Margin = rows.slice(0, 3).reduce((sum, r) => sum + r.margin, 0)
	const top3Share = totals.margin > 0 ? (top3Margin / totals.margin) * 100 : 0

	const sales = salesSummary(documents)
	const stockAlerts = products
		.map((p) => ({ product: p, status: getStockStatus(p) }))
		.filter((x) => x.status === 'out' || x.status === 'low')
		.sort((a, b) => (a.status === b.status ? 0 : a.status === 'out' ? -1 : 1))

	return (
		<div>
			<div className="kpi-grid">
				<KpiCard
					label="Chiffre d'affaires"
					value={formatEuro(totals.revenue)}
					hint={`${products.length} produits`}
					tone="primary"
				/>
				<KpiCard label="Coûts variables" value={formatEuro(totals.totalCost)} tone="neutral" />
				<KpiCard label="Marge brute" value={formatEuro(totals.margin)} tone="good" />
				<KpiCard
					label="Taux de marge"
					value={formatPercent(totals.marginRate)}
					hint="Marge brute / chiffre d'affaires"
					tone={rateTone(totals.marginRate)}
				/>
			</div>

			{(sales.invoiceCount > 0 || sales.openQuotes > 0) && (
				<>
					<h2>Ventes</h2>
					<div className="kpi-grid">
						<KpiCard label="Facturé ce mois (HT)" value={formatMAD(sales.monthHT)} tone="primary" />
						<KpiCard
							label="Reste à encaisser"
							value={formatMAD(sales.unpaid)}
							hint={`${sales.invoiceCount} facture(s) émise(s)`}
							tone="neutral"
						/>
						<KpiCard
							label="Factures en retard"
							value={formatMAD(sales.late)}
							hint={`${sales.lateCount} facture(s) à relancer`}
							tone={sales.lateCount > 0 ? 'low' : 'good'}
						/>
						<KpiCard
							label="Devis en cours"
							value={formatMAD(sales.quotesHT)}
							hint={`${sales.openQuotes} devis à transformer`}
							tone="medium"
						/>
					</div>
				</>
			)}

			{stockAlerts.length > 0 && (
				<div className="card">
					<div className="insight-label">Alertes stock</div>
					<div className="insight-title">
						{stockAlerts.filter((x) => x.status === 'out').length} rupture(s),{' '}
						{stockAlerts.filter((x) => x.status === 'low').length} sous le seuil
					</div>
					<ul>
						{stockAlerts.slice(0, 5).map(({ product, status }) => (
							<li key={product.id}>
								<span className={status === 'out' ? 'badge badge-low' : 'badge badge-medium'}>
									{status === 'out' ? 'Rupture' : 'Seuil'}
								</span>{' '}
								{product.name} : {product.stock ?? 0} en stock
								{product.minStock ? ` (seuil ${product.minStock})` : ''}
							</li>
						))}
					</ul>
					{onNavigate && (
						<button type="button" onClick={() => onNavigate('stock')}>
							Voir le stock
						</button>
					)}
				</div>
			)}

			{rows.length >= 2 && (
				<div className="insight-grid">
					<div className="card">
						<div className="insight-label">Produit le plus rentable</div>
						<div className="insight-title">{best.product.name}</div>
						<div className="insight-text">
							{formatEuro(best.margin)} de marge brute, taux de {formatPercent(best.marginRate)}
						</div>
					</div>
					<div className="card">
						<div className="insight-label">Taux de marge le plus faible</div>
						<div className="insight-title">{weakest.product.name}</div>
						<div className="insight-text">
							{formatPercent(weakest.marginRate)} de taux de marge pour {formatEuro(weakest.revenue)} de chiffre d'affaires
						</div>
					</div>
					<div className="card">
						<div className="insight-label">Concentration</div>
						<div className="insight-title">{formatPercent(top3Share)}</div>
						<div className="insight-text">
							de la marge brute vient des {Math.min(3, rows.length)} premiers produits
						</div>
					</div>
				</div>
			)}

			<div className="card">
				<h2>Marge par produit</h2>
				<table>
					<thead>
						<tr>
							<th>Produit</th>
							<th>Catégorie</th>
							<th className="num">CA</th>
							<th className="num">Marge</th>
							<th className="num">Taux</th>
							<th>Contribution</th>
						</tr>
					</thead>
					<tbody>
						{rows.map((r) => (
							<tr key={r.product.id}>
								<td>{r.product.name}</td>
								<td>{r.product.category}</td>
								<td className="num">{formatEuro(r.revenue)}</td>
								<td className="num">{formatEuro(r.margin)}</td>
								<td className="num">
									<span className={badgeClass(r.marginRate)}>{formatPercent(r.marginRate)}</span>
								</td>
								<td>
									<div className="bar">
										<div
											className="bar-fill"
											style={{ width: `${Math.max((r.margin / maxMargin) * 100, 0)}%` }}
										/>
									</div>
								</td>
							</tr>
						))}
					</tbody>
				</table>
			</div>
		</div>
	)
}
