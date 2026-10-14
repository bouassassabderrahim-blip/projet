import { useMemo, useState } from 'react'
import type { Product } from '../types'
import { downloadCsv } from './csv'
import { frDate, newId, today } from './numbering'
import { formatMAD, round2 } from './tva'
import type { StockMovement } from './types'
import './documents.css'

interface Props {
	products: Product[]
	onProductsChange: (products: Product[]) => void
	onMovements: (movements: StockMovement[]) => void
}

/** Inventaire physique : saisie des quantités comptées, écarts valorisés, mise à jour du stock */
export default function InventoryPage({ products, onProductsChange, onMovements }: Props) {
	const [counts, setCounts] = useState<Record<string, string>>({})
	const [query, setQuery] = useState('')
	const [onlyGaps, setOnlyGaps] = useState(false)
	const [message, setMessage] = useState('')

	const rows = useMemo(() => {
		const q = query.trim().toLowerCase()
		return products
			.filter((p) => !q || [p.name, p.reference, p.category].join(' ').toLowerCase().includes(q))
			.map((p) => {
				const raw = counts[p.id]
				const counted = raw === undefined || raw.trim() === '' ? undefined : Math.max(0, Math.round(Number(raw.replace(',', '.'))))
				const theoretical = p.stock ?? 0
				const gap = counted === undefined || !Number.isFinite(counted) ? undefined : counted - theoretical
				return { product: p, theoretical, counted, gap }
			})
			.filter((r) => !onlyGaps || (r.gap !== undefined && r.gap !== 0))
	}, [products, counts, query, onlyGaps])

	const changed = rows.filter((r) => r.gap !== undefined && r.gap !== 0)
	const gapValue = round2(changed.reduce((s, r) => s + (r.gap ?? 0) * r.product.unitCost, 0))
	const stockValue = round2(products.reduce((s, p) => s + (p.stock ?? 0) * p.unitCost, 0))

	function validate() {
		const entered = rows.filter((r) => r.counted !== undefined && Number.isFinite(r.counted))
		if (entered.length === 0) return setMessage('Saisissez au moins une quantité comptée.')
		if (!confirm(`Mettre à jour le stock de ${entered.length} article(s) d'après le comptage ?`)) return
		const date = today()
		const reference = `Inventaire du ${frDate(date)}`
		const byId = new Map(entered.map((r) => [r.product.id, r]))
		onProductsChange(products.map((p) => (byId.has(p.id) ? { ...p, stock: byId.get(p.id)!.counted } : p)))
		onMovements(
			entered
				.filter((r) => r.gap !== 0 || r.product.stock === undefined)
				.map((r) => ({
					id: newId(),
					date,
					productId: r.product.id,
					productName: r.product.name,
					lot: '',
					serial: '',
					quantity: r.gap ?? 0,
					kind: 'adjust' as const,
					reference,
					stockAfter: r.counted,
				})),
		)
		setCounts({})
		setMessage(`${reference} validé : ${entered.length} article(s) mis à jour, écart ${formatMAD(gapValue)}.`)
	}

	function exportSheet() {
		downloadCsv(`feuille-inventaire-${today()}.csv`, [
			['Référence', 'Article', 'Catégorie', 'Stock théorique', 'Quantité comptée', 'Écart'],
			...products.map((p) => [p.reference ?? '', p.name, p.category, String(p.stock ?? 0), '', '']),
		])
	}

	return (
		<div>
			<div className="doc-stats">
				<div>
					<span>Valeur du stock (coût d'achat)</span>
					<strong>{formatMAD(stockValue)}</strong>
				</div>
				<div>
					<span>Articles avec écart</span>
					<strong>{changed.length}</strong>
				</div>
				<div className={gapValue < 0 ? 'doc-stat-danger' : undefined}>
					<span>Valeur des écarts</span>
					<strong>{formatMAD(gapValue)}</strong>
				</div>
			</div>

			<div className="doc-toolbar">
				<input className="doc-search" placeholder="Rechercher un article…" value={query} onChange={(e) => setQuery(e.target.value)} />
				<label className="doc-check">
					<input type="checkbox" checked={onlyGaps} onChange={(e) => setOnlyGaps(e.target.checked)} /> Écarts seulement
				</label>
				<button type="button" onClick={exportSheet}>
					Feuille de comptage (CSV)
				</button>
				<button type="button" className="btn-primary" onClick={validate}>
					Valider l'inventaire
				</button>
			</div>
			{message && <p className="doc-info">{message}</p>}

			<div className="doc-table-wrap">
				<table className="doc-table">
					<thead>
						<tr>
							<th>Référence</th>
							<th>Article</th>
							<th>Catégorie</th>
							<th className="num">Stock théorique</th>
							<th className="num">Quantité comptée</th>
							<th className="num">Écart</th>
							<th className="num">Valeur de l'écart</th>
						</tr>
					</thead>
					<tbody>
						{rows.map((r) => (
							<tr key={r.product.id} className={r.gap ? (r.gap < 0 ? 'doc-row-danger' : 'doc-row-late') : undefined}>
								<td>{r.product.reference}</td>
								<td>{r.product.name}</td>
								<td>{r.product.category}</td>
								<td className="num">{r.product.stock ?? '—'}</td>
								<td className="num">
									<input
										className="num doc-qty"
										type="number"
										min={0}
										value={counts[r.product.id] ?? ''}
										onChange={(e) => setCounts({ ...counts, [r.product.id]: e.target.value })}
									/>
								</td>
								<td className="num">{r.gap === undefined ? '' : r.gap > 0 ? `+${r.gap}` : r.gap}</td>
								<td className="num">{r.gap ? formatMAD(round2(r.gap * r.product.unitCost)) : ''}</td>
							</tr>
						))}
					</tbody>
				</table>
			</div>
			<p className="doc-count">
				Les articles laissés vides ne sont pas modifiés. Chaque écart est enregistré dans les mouvements de stock.
			</p>
		</div>
	)
}
