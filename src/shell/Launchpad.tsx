import { useMemo } from 'react'
import type { PageId, Product } from '../types'
import { getStockStatus } from '../utils/stock'
import { balanceOf, isActive, isOverdue, sign } from '../documents/ledger'
import { frDate, today } from '../documents/numbering'
import { expiryState } from '../documents/stockMoves'
import { computeTotals, formatMAD, round2 } from '../documents/tva'
import { DOC_LABELS, STATUS_LABELS, type CommercialDocument, type DocKind, type StockLot } from '../documents/types'
import Icon from './icons'
import { useAccess } from '../access/context'
import type { ModuleId } from './navigation'

interface Props {
	companyName: string
	documents: CommercialDocument[]
	products: Product[]
	lots: StockLot[]
	cash: number
	onNavigate: (page: PageId) => void
	onOpenDocument: (kind: DocKind, id?: string) => void
	onCreate: (kind: DocKind) => void
}

interface Tile {
	module: ModuleId
	title: string
	value: string
	sub: string
	page: PageId
	tone?: 'danger' | 'warning' | 'good'
}

const compactMAD = (v: number) =>
	Math.abs(v) >= 1e6
		? `${(v / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 2 })} M DH`
		: Math.abs(v) >= 1e4
			? `${(v / 1e3).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} k DH`
			: formatMAD(v)

/** Accueil façon « launchpad » : une tuile par indicateur clé, cliquable vers l'écran concerné */
export default function Launchpad({ companyName, documents, products, lots, cash, onNavigate, onOpenDocument, onCreate }: Props) {
	const now = today()
	const month = now.slice(0, 7)
	const access = useAccess()
	const showCosts = access.can('costs')

	const tiles = useMemo<Tile[]>(() => {
		let monthHT = 0
		let monthMargin = 0
		let receivable = 0
		let late = 0
		let lateCount = 0
		let payable = 0
		let quotesHT = 0
		let quotes = 0
		const converted = new Set(documents.map((d) => d.sourceId).filter(Boolean))
		const received = new Set(documents.filter((d) => d.kind === 'receipt' && d.status !== 'cancelled').map((d) => d.sourceId))
		let pendingPurchases = 0
		// TVA du mois, estimée sur les dates de facture (collectée − déductible)
		let monthVat = 0
		let depot = 0
		const cost = new Map(products.map((p) => [p.id, p.unitCost]))

		for (const d of documents) {
			if (!isActive(d)) continue
			if ((d.kind === 'invoice' || d.kind === 'credit') && d.date.startsWith(month)) {
				const t = computeTotals(d)
				monthHT += sign(d) * t.totalHT
				for (const l of d.lines) {
					const c = l.productId ? (cost.get(l.productId) ?? 0) : 0
					monthMargin += sign(d) * (l.quantity * l.unitPriceHT * (1 - l.discount / 100) - c * l.quantity)
				}
			}
			if (d.date.startsWith(month) && (d.kind === 'invoice' || d.kind === 'credit' || d.kind === 'bill'))
				monthVat += (d.kind === 'bill' ? -1 : sign(d)) * computeTotals(d).totalTVA
			if (d.kind === 'invoice') receivable += balanceOf(d, documents)
			if (d.kind === 'bill') payable += balanceOf(d, documents)
			if (d.kind === 'invoice' && isOverdue(d, documents, now)) {
				late += balanceOf(d, documents)
				lateCount++
			}
			if (d.kind === 'quote' && d.status === 'validated' && !converted.has(d.id) && d.dueDate >= now) {
				quotes++
				quotesHT += computeTotals(d).totalHT
			}
			if (d.kind === 'purchase' && d.status === 'validated' && !received.has(d.id)) pendingPurchases++
			if (d.kind === 'delivery' && d.consignment && d.status === 'validated') depot += d.lines.filter((l) => l.depot === 'depot').length
		}
		const out = products.filter((p) => getStockStatus(p) === 'out').length
		const low = products.filter((p) => getStockStatus(p) === 'low').length
		const expiring = lots.filter((l) => l.quantity > 0 && ['expired', 'soon'].includes(expiryState(l.expiry, now))).length
		const stockValue = products.reduce((s, p) => s + (p.stock ?? 0) * p.unitCost, 0)
		const forecast = cash + receivable - payable

		return [
			{ module: 'sales', title: 'CA du mois (HT)', value: compactMAD(round2(monthHT)), sub: !monthHT ? 'aucune facture ce mois' : showCosts ? `marge ${Math.round((monthMargin / monthHT) * 100)} %` : 'net des avoirs', page: 'stats' },
			{ module: 'sales', title: 'Devis en cours', value: String(quotes), sub: compactMAD(round2(quotesHT)) + ' HT à transformer', page: 'quotes' },
			{ module: 'sales', title: 'Factures échues', value: String(lateCount), sub: compactMAD(round2(late)) + ' à relancer', page: 'invoices', tone: lateCount ? 'danger' : 'good' },
			{ module: 'sales', title: 'Implants en dépôt', value: String(depot), sub: 'chez les cliniques', page: 'depots' },
			{ module: 'purchases', title: 'Commandes à recevoir', value: String(pendingPurchases), sub: 'commandes fournisseurs validées', page: 'purchases' },
			{ module: 'purchases', title: 'Fournisseurs à payer', value: compactMAD(round2(payable)), sub: 'factures fournisseurs ouvertes', page: 'bills' },
			{ module: 'stock', title: 'Ruptures / sous le seuil', value: `${out} / ${low}`, sub: 'articles à réapprovisionner', page: 'alerts', tone: out ? 'danger' : low ? 'warning' : 'good' },
			{ module: 'stock', title: 'Péremptions', value: String(expiring), sub: 'lots périmés ou < 90 jours', page: 'lots', tone: expiring ? 'warning' : 'good' },
			{ module: 'stock', title: 'Valeur du stock', value: compactMAD(round2(stockValue)), sub: "au coût d'achat", page: 'inventory' },
			{ module: 'finance', title: 'À encaisser', value: compactMAD(round2(receivable)), sub: 'créances clients', page: 'schedule' },
			{ module: 'finance', title: 'Solde prévisionnel', value: compactMAD(round2(forecast)), sub: 'trésorerie + créances − dettes', page: 'schedule', tone: forecast < 0 ? 'danger' : undefined },
			{ module: 'finance', title: 'TVA du mois (estimation)', value: compactMAD(round2(monthVat)), sub: monthVat < 0 ? 'crédit de TVA' : 'collectée − déductible', page: 'vat' },
		]
	}, [documents, products, lots, cash, month, now, showCosts])

	const visibleTiles = tiles.filter((t) => access.level(t.module) !== 'none' && (showCosts || t.title !== 'Valeur du stock'))
	const sideOk = (d: CommercialDocument) => access.level(DOC_LABELS[d.kind].side === 'sale' ? 'sales' : 'purchases') !== 'none'
	const canCreate = (side: 'sales' | 'purchases') => access.level(side) === 'write'

	const recent = useMemo(
		() => [...documents].filter(sideOk).sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number)).slice(0, 8),
		// eslint-disable-next-line react-hooks/exhaustive-deps
		[documents, access],
	)

	const groups: { module: ModuleId; label: string }[] = [
		{ module: 'sales', label: 'Ventes' },
		{ module: 'purchases', label: 'Achats' },
		{ module: 'stock', label: 'Stocks' },
		{ module: 'finance', label: 'Finance' },
	]
	const hour = new Date().getHours()

	return (
		<div className="erp-home">
			<div className="erp-home-head">
				<div>
					<h2>
						{hour < 18 ? 'Bonjour' : 'Bonsoir'}
						{access.user ? ` ${access.user.name}` : ''}
					</h2>
					<p>
						{companyName || 'Votre dossier'} · {new Date().toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
					</p>
				</div>
				<div className="erp-quick">
					{canCreate('sales') && (
						<>
							<button type="button" className="btn-primary" onClick={() => onCreate('quote')}>
								+ Devis
							</button>
							<button type="button" onClick={() => onCreate('invoice')}>
								+ Facture
							</button>
							<button type="button" onClick={() => onCreate('delivery')}>
								+ BL
							</button>
						</>
					)}
					{canCreate('purchases') && (
						<button type="button" onClick={() => onCreate('purchase')}>
							+ Commande fournisseur
						</button>
					)}
				</div>
			</div>

			{groups.filter((g) => visibleTiles.some((t) => t.module === g.module)).map((g) => (
				<section key={g.module} className="erp-tile-group">
					<h3>
						<Icon name={g.module} /> {g.label}
					</h3>
					<div className="erp-tiles">
						{visibleTiles
							.filter((t) => t.module === g.module)
							.map((t) => (
								<button key={t.title} type="button" className={`erp-tile ${t.tone ? `erp-tile-${t.tone}` : ''}`} onClick={() => onNavigate(t.page)}>
									<span className="erp-tile-title">{t.title}</span>
									<span className="erp-tile-value">{t.value}</span>
									<span className="erp-tile-sub">{t.sub}</span>
								</button>
							))}
					</div>
				</section>
			))}

			<section className="erp-tile-group">
				<h3>Dernières pièces</h3>
				{recent.length === 0 ? (
					<p className="doc-empty">Aucune pièce pour l'instant : commencez par créer un devis ou une facture.</p>
				) : (
					<table className="doc-table">
						<thead>
							<tr>
								<th>Pièce</th>
								<th>N°</th>
								<th>Date</th>
								<th>Tiers</th>
								<th className="num">Montant TTC</th>
								<th>État</th>
							</tr>
						</thead>
						<tbody>
							{recent.map((d) => (
								<tr key={d.id}>
									<td>{DOC_LABELS[d.kind].title}</td>
									<td>
										<button type="button" className="doc-link" onClick={() => onOpenDocument(d.kind, d.id)}>
											{d.number}
										</button>
									</td>
									<td>{frDate(d.date)}</td>
									<td>{d.party.name}</td>
									<td className="num">{formatMAD(computeTotals(d).netToPay)}</td>
									<td>
										<span className={`doc-badge doc-badge-${d.status}`}>{STATUS_LABELS[d.status]}</span>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				)}
			</section>
		</div>
	)
}
