import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react'
import type { Product } from '../types'
import { frDate } from '../documents/numbering'
import { computeTotals, formatMAD } from '../documents/tva'
import { DOC_LABELS, type CommercialDocument, type PartyRecord, type StockLot } from '../documents/types'

export type SearchHit =
	| { type: 'doc'; doc: CommercialDocument }
	| { type: 'party'; party: PartyRecord }
	| { type: 'product'; product: Product }
	| { type: 'lot'; lot: StockLot; productName: string }

interface Props {
	documents: CommercialDocument[]
	parties: PartyRecord[]
	products: Product[]
	lots: StockLot[]
	onPick: (hit: SearchHit) => void
	onClose: () => void
}

const norm = (s: string | undefined) =>
	(s ?? '')
		.toLowerCase()
		.normalize('NFD')
		.replace(/[̀-ͯ]/g, '')

/** Recherche globale (Cmd/Ctrl + K) : pièces, tiers, articles, lots et n° de série */
export default function GlobalSearch({ documents, parties, products, lots, onPick, onClose }: Props) {
	const [query, setQuery] = useState('')
	const [active, setActive] = useState(0)
	const input = useRef<HTMLInputElement>(null)

	useEffect(() => input.current?.focus(), [])

	const hits = useMemo<SearchHit[]>(() => {
		const q = norm(query.trim())
		if (q.length < 2) return []
		const has = (...values: (string | undefined)[]) => values.some((v) => norm(v).includes(q))
		const docs = documents
			.filter((d) =>
				has(d.number, d.party.name, d.supplierRef, d.intervention?.patient, d.intervention?.patientRef, ...d.lines.flatMap((l) => [l.lot, l.serial])),
			)
			.sort((a, b) => b.date.localeCompare(a.date))
			.slice(0, 8)
			.map((doc): SearchHit => ({ type: 'doc', doc }))
		const tiers = parties
			.filter((p) => has(p.name, p.ice, p.city, p.phone))
			.slice(0, 5)
			.map((party): SearchHit => ({ type: 'party', party }))
		const items = products
			.filter((p) => has(p.name, p.reference, p.category))
			.slice(0, 5)
			.map((product): SearchHit => ({ type: 'product', product }))
		const lotHits = lots
			.filter((l) => has(l.lot, l.serial))
			.slice(0, 5)
			.map((lot): SearchHit => ({ type: 'lot', lot, productName: products.find((p) => p.id === lot.productId)?.name ?? '' }))
		return [...docs, ...tiers, ...items, ...lotHits]
	}, [query, documents, parties, products, lots])

	function onKey(e: KeyboardEvent) {
		if (e.key === 'Escape') onClose()
		if (e.key === 'ArrowDown') {
			e.preventDefault()
			setActive((a) => Math.min(a + 1, hits.length - 1))
		}
		if (e.key === 'ArrowUp') {
			e.preventDefault()
			setActive((a) => Math.max(a - 1, 0))
		}
		if (e.key === 'Enter' && hits[active]) onPick(hits[active])
	}

	const describe = (h: SearchHit): [string, string, string] => {
		if (h.type === 'doc')
			return [
				DOC_LABELS[h.doc.kind].title,
				`${h.doc.number} · ${h.doc.party.name}`,
				`${frDate(h.doc.date)} · ${formatMAD(computeTotals(h.doc).netToPay)}`,
			]
		if (h.type === 'party') return [h.party.role === 'client' ? 'Client' : 'Fournisseur', h.party.name, [h.party.city, h.party.ice].filter(Boolean).join(' · ')]
		if (h.type === 'product') return ['Article', h.product.name, [h.product.reference, h.product.stock !== undefined ? `stock ${h.product.stock}` : ''].filter(Boolean).join(' · ')]
		return ['Lot', [h.lot.lot, h.lot.serial].filter(Boolean).join(' / '), `${h.productName} · ${h.lot.quantity} en stock`]
	}

	return (
		<div className="erp-search-backdrop" onClick={onClose}>
			<div className="erp-search" role="dialog" aria-modal="true" aria-label="Recherche globale" onClick={(e) => e.stopPropagation()}>
				<input
					ref={input}
					value={query}
					placeholder="Rechercher une pièce, un client, un article, un lot, un n° de série, un patient…"
					onChange={(e) => {
						setQuery(e.target.value)
						setActive(0)
					}}
					onKeyDown={onKey}
				/>
				<div className="erp-search-results">
					{query.trim().length < 2 ? (
						<p className="erp-search-hint">Tapez au moins 2 caractères · ↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer</p>
					) : hits.length === 0 ? (
						<p className="erp-search-hint">Aucun résultat.</p>
					) : (
						hits.map((h, i) => {
							const [kind, title, sub] = describe(h)
							return (
								<button
									key={i}
									type="button"
									className={`erp-search-hit ${i === active ? 'erp-search-hit-active' : ''}`}
									onMouseEnter={() => setActive(i)}
									onClick={() => onPick(h)}
								>
									<span className="erp-search-kind">{kind}</span>
									<span className="erp-search-title">{title}</span>
									<span className="erp-search-sub">{sub}</span>
								</button>
							)
						})
					)}
				</div>
			</div>
		</div>
	)
}
