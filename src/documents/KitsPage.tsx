import { useState } from 'react'
import type { Product } from '../types'
import { newId } from './numbering'
import { formatMAD, round2 } from './tva'
import type { Kit } from './types'
import './documents.css'

interface Props {
	kits: Kit[]
	onChange: (kits: Kit[]) => void
	products: Product[]
}

/** Kits : ensembles d'articles insérés d'un coup dans un devis, un BL ou une facture (ex. kit PTH) */
export default function KitsPage({ kits, onChange, products }: Props) {
	const [editing, setEditing] = useState<Kit | null>(null)
	const [error, setError] = useState('')
	const product = (id: string) => products.find((p) => p.id === id)
	const kitPrice = (k: Kit) => round2(k.items.reduce((s, i) => s + (product(i.productId)?.unitPrice ?? 0) * i.quantity, 0))

	function save() {
		if (!editing) return
		const items = editing.items.filter((i) => i.productId && i.quantity > 0)
		if (!editing.name.trim()) return setError('Donnez un nom au kit.')
		if (items.length === 0) return setError('Ajoutez au moins un article.')
		const kit = { ...editing, name: editing.name.trim(), items }
		onChange(kits.some((k) => k.id === kit.id) ? kits.map((k) => (k.id === kit.id ? kit : k)) : [...kits, kit])
		setEditing(null)
		setError('')
	}

	if (editing) {
		const setItem = (index: number, patch: Partial<Kit['items'][number]>) =>
			setEditing({ ...editing, items: editing.items.map((it, i) => (i === index ? { ...it, ...patch } : it)) })
		return (
			<div className="doc-panel">
				<div className="doc-panel-title">Kit</div>
				<label className="doc-notes">
					Nom du kit
					<input
						value={editing.name}
						placeholder="ex. Kit PTH cimentée taille 3"
						onChange={(e) => setEditing({ ...editing, name: e.target.value })}
					/>
				</label>
				<table className="doc-table">
					<thead>
						<tr>
							<th>Article</th>
							<th className="num">Quantité</th>
							<th />
						</tr>
					</thead>
					<tbody>
						{editing.items.map((it, i) => (
							<tr key={i}>
								<td>
									<select value={it.productId} onChange={(e) => setItem(i, { productId: e.target.value })}>
										<option value="">—</option>
										{products.map((p) => (
											<option key={p.id} value={p.id}>
												{p.reference ? `${p.reference} · ` : ''}
												{p.name}
											</option>
										))}
									</select>
								</td>
								<td>
									<input
										className="num doc-qty"
										type="number"
										min={1}
										value={it.quantity}
										onChange={(e) => setItem(i, { quantity: Number(e.target.value) })}
									/>
								</td>
								<td>
									<button
										type="button"
										onClick={() => setEditing({ ...editing, items: editing.items.filter((_, j) => j !== i) })}
									>
										✕
									</button>
								</td>
							</tr>
						))}
					</tbody>
				</table>
				{error && <p className="doc-error">{error}</p>}
				<div className="doc-toolbar">
					<button
						type="button"
						onClick={() => setEditing({ ...editing, items: [...editing.items, { productId: '', quantity: 1 }] })}
					>
						+ Article
					</button>
					<button type="button" className="btn-primary" onClick={save}>
						Enregistrer le kit
					</button>
					<button type="button" onClick={() => setEditing(null)}>
						Annuler
					</button>
				</div>
			</div>
		)
	}

	return (
		<div>
			<div className="doc-toolbar">
				<button
					type="button"
					className="btn-primary"
					onClick={() => setEditing({ id: newId(), name: '', items: [{ productId: '', quantity: 1 }] })}
				>
					+ Nouveau kit
				</button>
				<span className="doc-count">Un kit s'insère en un clic dans un devis, un BL ou une facture.</span>
			</div>
			{kits.length === 0 ? (
				<p className="doc-empty">Aucun kit. Exemple : « Kit PTH » = tige fémorale + cotyle + insert + tête.</p>
			) : (
				<table className="doc-table">
					<thead>
						<tr>
							<th>Kit</th>
							<th>Composition</th>
							<th className="num">Prix de vente HT</th>
							<th>Actions</th>
						</tr>
					</thead>
					<tbody>
						{kits.map((k) => (
							<tr key={k.id}>
								<td>{k.name}</td>
								<td>
									{k.items
										.map((i) => `${i.quantity} × ${product(i.productId)?.name ?? '(article supprimé)'}`)
										.join(', ')}
								</td>
								<td className="num">{formatMAD(kitPrice(k))}</td>
								<td className="doc-actions">
									<button type="button" onClick={() => setEditing(k)}>
										Modifier
									</button>
									<button
										type="button"
										onClick={() => confirm(`Supprimer le kit « ${k.name} » ?`) && onChange(kits.filter((x) => x.id !== k.id))}
									>
										Supprimer
									</button>
								</td>
							</tr>
						))}
					</tbody>
				</table>
			)}
		</div>
	)
}
