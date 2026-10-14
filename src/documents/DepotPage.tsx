import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import { addDays, daysBetween, emptyLine, frDate, newId, nextNumber, today } from './numbering'
import { formatMAD, lineHT } from './tva'
import { emptyIntervention, type CommercialDocument, type DocKind, type DocLine } from './types'
import './documents.css'

interface Props {
	documents: CommercialDocument[]
	onChange: (docs: CommercialDocument[]) => void
	onNavigate: (kind: DocKind, openId?: string) => void
	onStockMove: (lines: DocLine[], direction: 1 | -1, supplier?: string, reference?: string) => Record<string, number> | void
}

interface DepotItem {
	bl: CommercialDocument
	line: DocLine
}

/** Implants livrés en dépôt : à facturer après la pose ou à reprendre en stock */
export default function DepotPage({ documents, onChange, onNavigate, onStockMove }: Props) {
	const [selected, setSelected] = useState<string[]>([])
	const access = useAccess()
	const canWrite = access.level('sales') === 'write'
	const now = today()

	const groups = useMemo(() => {
		const byClient = new Map<string, DepotItem[]>()
		for (const bl of documents) {
			if (bl.kind !== 'delivery' || !bl.consignment || bl.status !== 'validated') continue
			for (const line of bl.lines) {
				if (line.depot !== 'depot') continue
				const list = byClient.get(bl.party.name) ?? []
				list.push({ bl, line })
				byClient.set(bl.party.name, list)
			}
		}
		return [...byClient.entries()].sort((a, b) => a[0].localeCompare(b[0]))
	}, [documents])

	const setDepot = (docs: CommercialDocument[], items: DepotItem[], state: 'posed' | 'returned') =>
		docs.map((d) =>
			items.some((i) => i.bl.id === d.id)
				? { ...d, lines: d.lines.map((l) => (items.some((i) => i.line.id === l.id) ? { ...l, depot: state } : l)) }
				: d,
		)

	function invoice(items: DepotItem[]) {
		if (items.length === 0) return
		const first = items[0].bl
		const id = newId()
		const lines: DocLine[] = items.map(({ bl, line }) => ({
			...emptyLine(),
			...line,
			id: newId(),
			depot: undefined,
			depotRef: { docId: bl.id, lineId: line.id },
		}))
		const created: CommercialDocument = {
			id,
			kind: 'invoice',
			number: nextNumber('invoice', documents, now),
			date: now,
			dueDate: addDays(now, 60),
			party: first.party,
			lines,
			status: 'draft',
			paymentMethod: 'virement',
			notes: '',
			intervention: { ...emptyIntervention(), clinic: first.party.name, date: now },
			sourceNumber: [...new Set(items.map((i) => i.bl.number))].join(', '),
		}
		onChange([...setDepot(documents, items, 'posed'), created])
		access.log('Facturation de dépôt', `${created.number} · ${first.party.name} · ${items.length} article(s)`)
		setSelected([])
		onNavigate('invoice', id)
	}

	function giveBack(item: DepotItem) {
		if (!confirm(`Reprendre « ${item.line.description} » en stock ?`)) return
		onChange(setDepot(documents, [item], 'returned'))
		access.log('Retour de dépôt', `${item.line.description} · ${item.bl.number}`)
		onStockMove([{ ...item.line, quantity: item.line.movedQty ?? item.line.quantity }], 1, '', `Retour dépôt ${item.bl.number}`)
	}

	const toggle = (id: string) => setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]))

	if (groups.length === 0)
		return (
			<p className="doc-empty">
				Aucun article en dépôt. Pour déposer du matériel chez une clinique, créez un bon de livraison et cochez « BL en
				dépôt ».
			</p>
		)

	return (
		<div>
			{groups.map(([client, items]) => {
				const chosen = items.filter((i) => selected.includes(i.line.id))
				const value = items.reduce((s, i) => s + lineHT(i.line), 0)
				return (
					<div key={client} className="doc-panel">
						<div className="doc-panel-title">
							{client} · {items.length} article(s) en dépôt · {formatMAD(value)} HT
						</div>
						<div className="doc-table-wrap">
							<table className="doc-table">
								<thead>
									<tr>
										<th />
										<th>Article</th>
										<th>Lot / N° série</th>
										<th>Péremption</th>
										<th className="num">Qté</th>
										<th>BL</th>
										<th className="num">Depuis</th>
										<th className="num">Valeur HT</th>
										<th>Actions</th>
									</tr>
								</thead>
								<tbody>
									{items.map((item) => (
										<tr key={item.line.id}>
											<td>
												<input
													disabled={!canWrite}
													type="checkbox"
													checked={selected.includes(item.line.id)}
													onChange={() => toggle(item.line.id)}
												/>
											</td>
											<td>{item.line.description}</td>
											<td>{[item.line.lot, item.line.serial].filter(Boolean).join(' / ')}</td>
											<td>{frDate(item.line.expiry)}</td>
											<td className="num">{item.line.quantity}</td>
											<td>{item.bl.number}</td>
											<td className="num">{daysBetween(item.bl.date, now)} j</td>
											<td className="num">{formatMAD(lineHT(item.line))}</td>
											<td className="doc-actions">
												{canWrite && (
													<>
														<button type="button" className="btn-primary" onClick={() => invoice([item])}>
															Posé → facturer
														</button>
														<button type="button" onClick={() => giveBack(item)}>
															Retour en stock
														</button>
													</>
												)}
											</td>
										</tr>
									))}
								</tbody>
							</table>
						</div>
						{canWrite && chosen.length > 1 && (
							<div className="doc-toolbar">
								<button type="button" className="btn-primary" onClick={() => invoice(chosen)}>
									Facturer les {chosen.length} articles sélectionnés
								</button>
							</div>
						)}
					</div>
				)
			})}
		</div>
	)
}
