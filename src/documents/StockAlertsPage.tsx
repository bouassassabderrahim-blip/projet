import { useMemo } from 'react'
import type { Product } from '../types'
import { getStockStatus } from '../utils/stock'
import { addDays, emptyLine, frDate, newId, nextNumber, today } from './numbering'
import { expiryState } from './stockMoves'
import { formatMAD, round2 } from './tva'
import { emptyParty, type CommercialDocument, type DocKind, type StockLot } from './types'
import './documents.css'

interface Props {
	products: Product[]
	lots: StockLot[]
	documents: CommercialDocument[]
	onChange: (docs: CommercialDocument[]) => void
	onNavigate: (kind: DocKind, openId?: string) => void
	onOpenStock: () => void
}

/** Quantités commandées aux fournisseurs (commandes validées pas encore réceptionnées) */
function onOrder(documents: CommercialDocument[]): Map<string, number> {
	const received = new Set(documents.filter((d) => d.kind === 'receipt' && d.status !== 'cancelled').map((d) => d.sourceId))
	const qty = new Map<string, number>()
	for (const d of documents) {
		if (d.kind !== 'purchase' || d.status !== 'validated' || received.has(d.id)) continue
		for (const l of d.lines) if (l.productId) qty.set(l.productId, (qty.get(l.productId) ?? 0) + l.quantity)
	}
	return qty
}

/** Quantité conseillée : remonter à 2 × le seuil d'alerte, déduction faite de ce qui est déjà commandé */
function suggestedQty(p: Product, ordered: number): number {
	const stock = p.stock ?? 0
	const target = Math.max((p.minStock ?? 0) * 2, 1)
	return Math.max(target - stock - ordered, 0)
}

/** Alertes de stock : ruptures, articles sous le seuil, lots périmés, et réapprovisionnement */
export default function StockAlertsPage({ products, lots, documents, onChange, onNavigate, onOpenStock }: Props) {
	const now = today()
	const ordered = useMemo(() => onOrder(documents), [documents])

	const alerts = useMemo(
		() =>
			products
				.map((p) => ({ product: p, status: getStockStatus(p), ordered: ordered.get(p.id) ?? 0 }))
				.filter((a) => a.status === 'out' || a.status === 'low')
				.map((a) => ({ ...a, suggested: suggestedQty(a.product, a.ordered) }))
				.sort((a, b) => (a.status === b.status ? a.product.name.localeCompare(b.product.name) : a.status === 'out' ? -1 : 1)),
		[products, ordered],
	)

	const lotAlerts = useMemo(
		() =>
			lots
				.filter((l) => l.quantity > 0)
				.map((l) => ({ lot: l, state: expiryState(l.expiry, now) }))
				.filter((x) => x.state === 'expired' || x.state === 'soon')
				.sort((a, b) => a.lot.expiry.localeCompare(b.lot.expiry)),
		[lots, now],
	)

	const unset = products.filter((p) => getStockStatus(p) === 'unset').length
	const out = alerts.filter((a) => a.status === 'out').length
	const low = alerts.length - out
	const expired = lotAlerts.filter((x) => x.state === 'expired').length

	// Réapprovisionnement regroupé par fournisseur
	const bySupplier = useMemo(() => {
		const groups = new Map<string, typeof alerts>()
		for (const a of alerts) {
			if (a.suggested <= 0) continue
			const key = a.product.supplier?.trim() || 'Fournisseur non renseigné'
			groups.set(key, [...(groups.get(key) ?? []), a])
		}
		return [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]))
	}, [alerts])

	function createPurchase(supplier: string, items: typeof alerts) {
		const id = newId()
		const known = supplier !== 'Fournisseur non renseigné'
		const order: CommercialDocument = {
			id,
			kind: 'purchase',
			number: nextNumber('purchase', documents, now),
			date: now,
			dueDate: addDays(now, 60),
			party: { ...emptyParty(), name: known ? supplier : '' },
			lines: items.map((a) => ({
				...emptyLine(),
				productId: a.product.id,
				description: a.product.name,
				quantity: a.suggested,
				unitPriceHT: a.product.unitCost,
			})),
			status: 'draft',
			paymentMethod: 'virement',
			notes: 'Réapprovisionnement (alertes de stock)',
		}
		onChange([...documents, order])
		onNavigate('purchase', id)
	}

	const name = (id: string) => products.find((p) => p.id === id)?.name ?? '(article supprimé)'

	return (
		<div>
			<div className="doc-stats">
				<div className={out ? 'doc-stat-danger' : undefined}>
					<span>Ruptures</span>
					<strong>{out}</strong>
				</div>
				<div className={low ? 'doc-stat-late' : undefined}>
					<span>Sous le seuil d'alerte</span>
					<strong>{low}</strong>
				</div>
				<div className={expired ? 'doc-stat-danger' : lotAlerts.length ? 'doc-stat-late' : undefined}>
					<span>Lots périmés / sous 90 jours</span>
					<strong>
						{expired} / {lotAlerts.length - expired}
					</strong>
				</div>
				<div>
					<span>Articles sans stock renseigné</span>
					<strong>{unset}</strong>
				</div>
			</div>

			{alerts.length === 0 && lotAlerts.length === 0 && (
				<p className="doc-info">Aucune alerte : tous les articles suivis sont au-dessus de leur seuil.</p>
			)}
			{unset > 0 && (
				<p className="doc-warning">
					{unset} article(s) n'ont ni stock ni seuil d'alerte : ils ne peuvent pas déclencher d'alerte.{' '}
					<button type="button" onClick={onOpenStock}>
						Renseigner le stock
					</button>
				</p>
			)}

			{alerts.length > 0 && (
				<div className="doc-panel">
					<div className="doc-panel-title">Articles à surveiller</div>
					<div className="doc-table-wrap">
						<table className="doc-table">
							<thead>
								<tr>
									<th>État</th>
									<th>Référence</th>
									<th>Article</th>
									<th>Fournisseur</th>
									<th className="num">Stock</th>
									<th className="num">Seuil</th>
									<th className="num">En commande</th>
									<th className="num">À commander</th>
									<th className="num">Coût estimé HT</th>
								</tr>
							</thead>
							<tbody>
								{alerts.map((a) => (
									<tr key={a.product.id} className={a.status === 'out' ? 'doc-row-danger' : 'doc-row-late'}>
										<td>
											<span className={`doc-badge ${a.status === 'out' ? 'doc-exp-expired' : 'doc-exp-soon'}`}>
												{a.status === 'out' ? 'Rupture' : 'Sous le seuil'}
											</span>
										</td>
										<td>{a.product.reference}</td>
										<td>{a.product.name}</td>
										<td>{a.product.supplier}</td>
										<td className="num">{a.product.stock ?? 0}</td>
										<td className="num">{a.product.minStock ?? 0}</td>
										<td className="num">{a.ordered || ''}</td>
										<td className="num">
											<strong>{a.suggested || '—'}</strong>
										</td>
										<td className="num">{a.suggested ? formatMAD(round2(a.suggested * a.product.unitCost)) : ''}</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
					<p className="doc-count">
						Quantité conseillée : de quoi remonter à deux fois le seuil d'alerte, moins ce qui est déjà commandé.
					</p>
				</div>
			)}

			{bySupplier.length > 0 && (
				<div className="doc-panel">
					<div className="doc-panel-title">Réapprovisionnement par fournisseur</div>
					<table className="doc-table">
						<thead>
							<tr>
								<th>Fournisseur</th>
								<th>Articles</th>
								<th className="num">Montant estimé HT</th>
								<th />
							</tr>
						</thead>
						<tbody>
							{bySupplier.map(([supplier, items]) => (
								<tr key={supplier}>
									<td>{supplier}</td>
									<td>{items.map((a) => `${a.suggested} × ${a.product.name}`).join(', ')}</td>
									<td className="num">
										{formatMAD(round2(items.reduce((s, a) => s + a.suggested * a.product.unitCost, 0)))}
									</td>
									<td>
										<button type="button" className="btn-primary" onClick={() => createPurchase(supplier, items)}>
											Créer la commande fournisseur
										</button>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}

			{lotAlerts.length > 0 && (
				<div className="doc-panel">
					<div className="doc-panel-title">Péremptions</div>
					<table className="doc-table">
						<thead>
							<tr>
								<th>État</th>
								<th>Article</th>
								<th>Lot</th>
								<th>N° série</th>
								<th>Péremption</th>
								<th className="num">Quantité</th>
							</tr>
						</thead>
						<tbody>
							{lotAlerts.map(({ lot, state }) => (
								<tr key={lot.id} className={state === 'expired' ? 'doc-row-danger' : 'doc-row-late'}>
									<td>
										<span className={`doc-badge doc-exp-${state}`}>{state === 'expired' ? 'Périmé' : '< 90 jours'}</span>
									</td>
									<td>{name(lot.productId)}</td>
									<td>{lot.lot}</td>
									<td>{lot.serial}</td>
									<td>{frDate(lot.expiry)}</td>
									<td className="num">{lot.quantity}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</div>
	)
}
