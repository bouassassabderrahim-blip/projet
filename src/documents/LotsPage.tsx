import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { frDate, newId, today } from './numbering'
import { expiryState, type ExpiryState } from './stockMoves'
import { DOC_LABELS, type CommercialDocument, type StockLot } from './types'
import './documents.css'

interface Props {
	lots: StockLot[]
	onChange: (lots: StockLot[]) => void
	products: Product[]
	documents: CommercialDocument[]
	/** Recherche initiale (lot ou n° de série venant de la recherche globale) */
	initialQuery?: string
}

const EXPIRY_LABELS: Record<ExpiryState, string> = {
	expired: 'Périmé',
	soon: '< 90 jours',
	ok: 'OK',
	none: 'Sans date',
}

type Filter = '' | 'available' | 'expired' | 'soon'

/** Stock par lot / numéro de série, péremptions et traçabilité (rappel de lot) */
export default function LotsPage({ lots, onChange, products, documents, initialQuery = '' }: Props) {
	const [query, setQuery] = useState(initialQuery)
	const [filter, setFilter] = useState<Filter>(initialQuery ? '' : 'available')
	const [draft, setDraft] = useState({ productId: '', lot: '', serial: '', expiry: '', quantity: '1', supplier: '' })
	const [error, setError] = useState('')
	const canWrite = useAccess().level('stock') === 'write'
	const now = today()
	const productName = (id: string) => products.find((p) => p.id === id)?.name ?? '(article supprimé)'

	const rows = useMemo(() => {
		const q = query.trim().toLowerCase()
		return lots
			.filter((l) => {
				const st = expiryState(l.expiry, now)
				if (filter === 'available') return l.quantity > 0
				if (filter === 'expired') return l.quantity > 0 && st === 'expired'
				if (filter === 'soon') return l.quantity > 0 && st === 'soon'
				return true
			})
			.filter((l) => !q || [l.lot, l.serial, l.supplier, productName(l.productId)].join(' ').toLowerCase().includes(q))
			.sort((a, b) => (a.expiry || '9999').localeCompare(b.expiry || '9999'))
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [lots, query, filter, now, products])

	// Traçabilité : toutes les pièces qui citent le lot ou le n° de série recherché
	const trace = useMemo(() => {
		const q = query.trim().toLowerCase()
		if (q.length < 2) return []
		const hits: { doc: CommercialDocument; qty: number; label: string }[] = []
		for (const d of documents) {
			if (d.status === 'draft') continue
			for (const l of d.lines) {
				if ([l.lot, l.serial].some((v) => v && v.toLowerCase().includes(q)))
					hits.push({ doc: d, qty: l.quantity, label: `${l.description} · ${[l.lot, l.serial].filter(Boolean).join(' / ')}` })
			}
		}
		return hits.sort((a, b) => a.doc.date.localeCompare(b.doc.date))
	}, [documents, query])

	function add() {
		const quantity = Number(draft.quantity)
		if (!draft.productId) return setError('Choisissez un article.')
		if (!draft.lot.trim() && !draft.serial.trim()) return setError('Indiquez un n° de lot ou de série.')
		if (!Number.isFinite(quantity) || quantity <= 0) return setError('Quantité invalide.')
		onChange([
			...lots,
			{
				id: newId(),
				productId: draft.productId,
				lot: draft.lot.trim(),
				serial: draft.serial.trim(),
				expiry: draft.expiry,
				quantity,
				receivedDate: now,
				supplier: draft.supplier.trim(),
			},
		])
		setDraft({ ...draft, lot: '', serial: '', expiry: '', quantity: '1' })
		setError('')
	}

	function setQty(id: string, quantity: number) {
		onChange(lots.map((l) => (l.id === id ? { ...l, quantity: Math.max(0, quantity) } : l)))
	}

	const expired = lots.filter((l) => l.quantity > 0 && expiryState(l.expiry, now) === 'expired').length
	const soon = lots.filter((l) => l.quantity > 0 && expiryState(l.expiry, now) === 'soon').length

	return (
		<div>
			<div className="doc-stats">
				<div>
					<span>Lots en stock</span>
					<strong>{lots.filter((l) => l.quantity > 0).length}</strong>
				</div>
				<div className={expired ? 'doc-stat-late' : undefined}>
					<span>Périmés à retirer</span>
					<strong>{expired}</strong>
				</div>
				<div className={soon ? 'doc-stat-late' : undefined}>
					<span>Péremption sous 90 jours</span>
					<strong>{soon}</strong>
				</div>
			</div>

			{canWrite && <div className="doc-panel">
				<div className="doc-panel-title">Entrée manuelle d'un lot (stock initial)</div>
				<div className="doc-grid">
					<label>
						Article
						<select value={draft.productId} onChange={(e) => setDraft({ ...draft, productId: e.target.value })}>
							<option value="">—</option>
							{products.map((p) => (
								<option key={p.id} value={p.id}>
									{p.reference ? `${p.reference} · ` : ''}
									{p.name}
								</option>
							))}
						</select>
					</label>
					<label>
						N° de lot
						<input value={draft.lot} onChange={(e) => setDraft({ ...draft, lot: e.target.value })} />
					</label>
					<label>
						N° de série
						<input value={draft.serial} onChange={(e) => setDraft({ ...draft, serial: e.target.value })} />
					</label>
					<label>
						Péremption
						<input type="date" value={draft.expiry} onChange={(e) => setDraft({ ...draft, expiry: e.target.value })} />
					</label>
					<label>
						Quantité
						<input className="num" value={draft.quantity} onChange={(e) => setDraft({ ...draft, quantity: e.target.value })} />
					</label>
					<label>
						Fournisseur
						<input value={draft.supplier} onChange={(e) => setDraft({ ...draft, supplier: e.target.value })} />
					</label>
				</div>
				{error && <p className="doc-error">{error}</p>}
				<div className="doc-toolbar">
					<button type="button" className="btn-primary" onClick={add}>
						Ajouter le lot
					</button>
					<span className="doc-count">Les bons de réception validés créent les lots automatiquement.</span>
				</div>
			</div>}

			<div className="doc-toolbar">
				<input
					className="doc-search"
					placeholder="Rechercher un lot, un n° de série, un article…"
					value={query}
					onChange={(e) => setQuery(e.target.value)}
				/>
				<select value={filter} onChange={(e) => setFilter(e.target.value as Filter)}>
					<option value="available">En stock</option>
					<option value="soon">Péremption sous 90 jours</option>
					<option value="expired">Périmés</option>
					<option value="">Tous (y compris épuisés)</option>
				</select>
				<span className="doc-count">{rows.length} lot(s)</span>
			</div>

			<div className="doc-table-wrap">
				<table className="doc-table">
					<thead>
						<tr>
							<th>Article</th>
							<th>Lot</th>
							<th>N° série</th>
							<th>Péremption</th>
							<th>État</th>
							<th>Fournisseur</th>
							<th>Reçu le</th>
							<th className="num">Quantité</th>
						</tr>
					</thead>
					<tbody>
						{rows.map((l) => {
							const st = expiryState(l.expiry, now)
							return (
								<tr key={l.id} className={st === 'expired' && l.quantity > 0 ? 'doc-row-late' : undefined}>
									<td>{productName(l.productId)}</td>
									<td>{l.lot}</td>
									<td>{l.serial}</td>
									<td>{frDate(l.expiry)}</td>
									<td>
										<span className={`doc-badge doc-exp-${st}`}>{EXPIRY_LABELS[st]}</span>
									</td>
									<td>{l.supplier}</td>
									<td>{frDate(l.receivedDate)}</td>
									<td className="num">
										<input
											className="num doc-qty"
											type="number"
											min={0}
											value={l.quantity}
											readOnly={!canWrite}
											onChange={(e) => setQty(l.id, Number(e.target.value))}
										/>
									</td>
								</tr>
							)
						})}
					</tbody>
				</table>
			</div>

			{trace.length > 0 && (
				<div className="doc-panel">
					<div className="doc-panel-title">Traçabilité de « {query.trim()} » : {trace.length} mouvement(s)</div>
					<table className="doc-table">
						<thead>
							<tr>
								<th>Date</th>
								<th>Pièce</th>
								<th>N°</th>
								<th>Tiers</th>
								<th>Patient</th>
								<th>Article</th>
								<th className="num">Qté</th>
							</tr>
						</thead>
						<tbody>
							{trace.map((h, i) => (
								<tr key={`${h.doc.id}-${i}`}>
									<td>{frDate(h.doc.date)}</td>
									<td>{DOC_LABELS[h.doc.kind].title}</td>
									<td>{h.doc.number}</td>
									<td>{h.doc.party.name}</td>
									<td>{h.doc.intervention?.patient}</td>
									<td>{h.label}</td>
									<td className="num">{h.qty}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</div>
	)
}
