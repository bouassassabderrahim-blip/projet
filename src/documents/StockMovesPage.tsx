import { useMemo, useState } from 'react'
import type { Product } from '../types'
import { downloadCsv } from './csv'
import { frDate } from './numbering'
import type { MovementKind, StockMovement } from './types'
import './documents.css'

interface Props {
	movements: StockMovement[]
	products: Product[]
}

const KIND_LABELS: Record<MovementKind, string> = { in: 'Entrée', out: 'Sortie', adjust: 'Inventaire' }

/** Journal des mouvements de stock : réceptions, livraisons, retours, inventaires */
export default function StockMovesPage({ movements, products }: Props) {
	const [productId, setProductId] = useState('')
	const [kind, setKind] = useState<MovementKind | ''>('')
	const [from, setFrom] = useState('')
	const [to, setTo] = useState('')
	const [query, setQuery] = useState('')

	const rows = useMemo(() => {
		const q = query.trim().toLowerCase()
		return movements
			.filter((m) => !productId || m.productId === productId)
			.filter((m) => !kind || m.kind === kind)
			.filter((m) => (!from || m.date >= from) && (!to || m.date <= to))
			.filter((m) => !q || [m.productName, m.lot, m.serial, m.reference].join(' ').toLowerCase().includes(q))
			.slice()
			.reverse()
	}, [movements, productId, kind, from, to, query])

	const inQty = rows.filter((m) => m.quantity > 0).reduce((s, m) => s + m.quantity, 0)
	const outQty = rows.filter((m) => m.quantity < 0).reduce((s, m) => s - m.quantity, 0)

	function exportCsv() {
		downloadCsv('mouvements-stock.csv', [
			['Date', 'Type', 'Article', 'Lot', 'N° série', 'Quantité', 'Stock après', 'Pièce / motif'],
			...rows.map((m) => [m.date, KIND_LABELS[m.kind], m.productName, m.lot, m.serial, String(m.quantity), m.stockAfter === undefined ? '' : String(m.stockAfter), m.reference]),
		])
	}

	return (
		<div>
			<div className="doc-stats">
				<div>
					<span>Mouvements affichés</span>
					<strong>{rows.length}</strong>
				</div>
				<div>
					<span>Quantités entrées</span>
					<strong>+{inQty}</strong>
				</div>
				<div>
					<span>Quantités sorties</span>
					<strong>−{outQty}</strong>
				</div>
			</div>

			<div className="doc-toolbar">
				<input className="doc-search" placeholder="Rechercher : article, lot, n° de série, pièce…" value={query} onChange={(e) => setQuery(e.target.value)} />
				<select value={productId} onChange={(e) => setProductId(e.target.value)}>
					<option value="">Tous les articles</option>
					{products.map((p) => (
						<option key={p.id} value={p.id}>
							{p.name}
						</option>
					))}
				</select>
				<select value={kind} onChange={(e) => setKind(e.target.value as MovementKind | '')}>
					<option value="">Tous les types</option>
					<option value="in">Entrées</option>
					<option value="out">Sorties</option>
					<option value="adjust">Inventaires</option>
				</select>
				<label>
					Du <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
				</label>
				<label>
					au <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
				</label>
				<button type="button" onClick={exportCsv}>
					Exporter (CSV)
				</button>
			</div>

			{rows.length === 0 ? (
				<p className="doc-empty">
					Aucun mouvement. Les réceptions, les BL, les factures sans BL, les retours de dépôt et les inventaires
					validés s'enregistrent ici automatiquement.
				</p>
			) : (
				<div className="doc-table-wrap">
					<table className="doc-table">
						<thead>
							<tr>
								<th>Date</th>
								<th>Type</th>
								<th>Article</th>
								<th>Lot / N° série</th>
								<th className="num">Quantité</th>
								<th className="num">Stock après</th>
								<th>Pièce / motif</th>
							</tr>
						</thead>
						<tbody>
							{rows.map((m) => (
								<tr key={m.id}>
									<td>{frDate(m.date)}</td>
									<td>
										<span className={`doc-badge ${m.kind === 'in' ? 'doc-exp-ok' : m.kind === 'out' ? 'doc-badge-validated' : 'doc-badge-depot'}`}>
											{KIND_LABELS[m.kind]}
										</span>
									</td>
									<td>{m.productName}</td>
									<td>{[m.lot, m.serial].filter(Boolean).join(' / ')}</td>
									<td className={`num ${m.quantity > 0 ? 'doc-credit' : ''}`}>
										<strong>{m.quantity > 0 ? `+${m.quantity}` : m.quantity}</strong>
									</td>
									<td className="num">{m.stockAfter ?? ''}</td>
									<td>{m.reference}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</div>
	)
}
