import { useMemo, useState } from 'react'
import type { Product } from '../types'
import DocumentEditor, { emptyLine } from './DocumentEditor'
import DocumentPrint from './DocumentPrint'
import { addDays, newId, nextNumber, today } from './numbering'
import { computeTotals, formatMAD, round2 } from './tva'
import {
	DOC_LABELS,
	STATUS_LABELS,
	emptyParty,
	type CommercialDocument,
	type CompanyInfo,
	type DocKind,
	type DocLine,
	type DocStatus,
	type Party,
} from './types'
import './documents.css'

interface Props {
	kind: DocKind
	documents: CommercialDocument[]
	onChange: (docs: CommercialDocument[]) => void
	products: Product[]
	company: CompanyInfo
	/** Aller vers la page d'un autre type de document (après une conversion) */
	onNavigate?: (kind: DocKind) => void
	/** Appelé quand un BL est validé : utile pour décrémenter le stock */
	onDelivered?: (lines: DocLine[]) => void
}

type View = { mode: 'list' } | { mode: 'edit'; doc: CommercialDocument } | { mode: 'print'; id: string }

/** Chaîne commerciale : BC → BL → Facture */
const CONVERSIONS: Record<DocKind, DocKind[]> = {
	order: ['delivery', 'invoice'],
	delivery: ['invoice'],
	invoice: [],
}

export default function DocumentsPage({
	kind,
	documents,
	onChange,
	products,
	company,
	onNavigate,
	onDelivered,
}: Props) {
	const [view, setView] = useState<View>({ mode: 'list' })
	const [search, setSearch] = useState('')
	const [statusFilter, setStatusFilter] = useState<DocStatus | ''>('')
	const [message, setMessage] = useState<{ text: string; kind: DocKind } | null>(null)
	const labels = DOC_LABELS[kind]

	const list = useMemo(() => {
		const q = search.trim().toLowerCase()
		return documents
			.filter((d) => d.kind === kind)
			.filter((d) => !statusFilter || d.status === statusFilter)
			.filter((d) => !q || d.number.toLowerCase().includes(q) || d.party.name.toLowerCase().includes(q))
			.sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number))
	}, [documents, kind, search, statusFilter])

	const knownParties = useMemo(() => {
		const byName = new Map<string, Party>()
		for (const d of documents) if (d.party.name) byName.set(d.party.name, d.party)
		return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
	}, [documents])

	// Indicateurs pour les factures (hors annulées)
	const stats = useMemo(() => {
		if (kind !== 'invoice') return null
		let ht = 0
		let tva = 0
		let unpaid = 0
		for (const d of documents) {
			if (d.kind !== 'invoice' || d.status === 'cancelled' || d.status === 'draft') continue
			const t = computeTotals(d)
			ht += t.totalHT
			tva += t.totalTVA
			if (d.status !== 'paid') unpaid += t.netToPay
		}
		return { ht: round2(ht), tva: round2(tva), unpaid: round2(unpaid) }
	}, [documents, kind])

	function createDoc(): CommercialDocument {
		const date = today()
		return {
			id: newId(),
			kind,
			number: nextNumber(kind, documents, date),
			date,
			dueDate: addDays(date, 60), // délai légal par défaut au Maroc : 60 jours
			party: emptyParty(),
			lines: [emptyLine()],
			status: 'draft',
			paymentMethod: 'virement',
			notes: '',
		}
	}

	function save(doc: CommercialDocument) {
		const exists = documents.some((d) => d.id === doc.id)
		onChange(exists ? documents.map((d) => (d.id === doc.id ? doc : d)) : [...documents, doc])
		setView({ mode: 'list' })
	}

	function setStatus(doc: CommercialDocument, status: DocStatus) {
		onChange(documents.map((d) => (d.id === doc.id ? { ...d, status } : d)))
		if (status === 'validated' && doc.kind === 'delivery') onDelivered?.(doc.lines)
	}

	function remove(doc: CommercialDocument) {
		if (!confirm(`Supprimer ${doc.number} ?`)) return
		onChange(documents.filter((d) => d.id !== doc.id))
	}

	function duplicate(doc: CommercialDocument) {
		const date = today()
		setView({
			mode: 'edit',
			doc: {
				...doc,
				id: newId(),
				number: nextNumber(kind, documents, date),
				date,
				dueDate: addDays(date, 60),
				status: 'draft',
				sourceId: undefined,
				sourceNumber: undefined,
				lines: doc.lines.map((l) => ({ ...l, id: newId() })),
			},
		})
	}

	function convert(doc: CommercialDocument, to: DocKind) {
		const date = today()
		const created: CommercialDocument = {
			...doc,
			id: newId(),
			kind: to,
			number: nextNumber(to, documents, date),
			date,
			dueDate: addDays(date, 60),
			status: 'draft',
			sourceId: doc.id,
			sourceNumber: doc.number,
			lines: doc.lines.map((l) => ({ ...l, id: newId() })),
		}
		onChange([...documents, created])
		setMessage({ text: `${DOC_LABELS[to].title} ${created.number} créé(e) en brouillon à partir de ${doc.number}.`, kind: to })
	}

	if (view.mode === 'edit') {
		return (
			<DocumentEditor
				initial={view.doc}
				products={products}
				knownParties={knownParties}
				onSave={save}
				onCancel={() => setView({ mode: 'list' })}
			/>
		)
	}

	if (view.mode === 'print') {
		const doc = documents.find((d) => d.id === view.id)
		if (doc) return <DocumentPrint doc={doc} company={company} onClose={() => setView({ mode: 'list' })} />
	}

	return (
		<div>
			{!company.name && (
				<p className="doc-warning">
					Renseignez d'abord les informations de votre entreprise (ICE, IF, RC…) : elles sont obligatoires sur
					les factures.
				</p>
			)}

			{stats && (
				<div className="doc-stats">
					<div>
						<span>Chiffre d'affaires HT</span>
						<strong>{formatMAD(stats.ht)}</strong>
					</div>
					<div>
						<span>TVA collectée</span>
						<strong>{formatMAD(stats.tva)}</strong>
					</div>
					<div>
						<span>Reste à encaisser</span>
						<strong>{formatMAD(stats.unpaid)}</strong>
					</div>
				</div>
			)}

			{message && (
				<p className="doc-info">
					{message.text}{' '}
					{onNavigate && (
						<button type="button" onClick={() => onNavigate(message.kind)}>
							Voir
						</button>
					)}
				</p>
			)}

			<div className="export-bar">
				<button type="button" onClick={() => setView({ mode: 'edit', doc: createDoc() })}>
					+ Nouveau {labels.title.toLowerCase()}
				</button>
				<input placeholder="Rechercher (n°, client)" value={search} onChange={(e) => setSearch(e.target.value)} />
				<select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value as DocStatus | '')}>
					<option value="">Tous les statuts</option>
					{Object.entries(STATUS_LABELS).map(([k, v]) => (
						<option key={k} value={k}>
							{v}
						</option>
					))}
				</select>
			</div>

			{list.length === 0 ? (
				<p>Aucun document pour le moment.</p>
			) : (
				<table className="doc-table">
					<thead>
						<tr>
							<th>N°</th>
							<th>Date</th>
							<th>Client</th>
							<th className="num">Total TTC</th>
							<th>Statut</th>
							<th>Actions</th>
						</tr>
					</thead>
					<tbody>
						{list.map((d) => {
							const t = computeTotals(d)
							return (
								<tr key={d.id}>
									<td>{d.number}</td>
									<td>{new Date(d.date + 'T00:00:00').toLocaleDateString('fr-FR')}</td>
									<td>{d.party.name}</td>
									<td className="num">{formatMAD(t.netToPay)}</td>
									<td>
										<span className={`doc-badge doc-badge-${d.status}`}>{STATUS_LABELS[d.status]}</span>
									</td>
									<td className="doc-actions">
										<button type="button" onClick={() => setView({ mode: 'print', id: d.id })}>
											Voir / imprimer
										</button>
										{d.status === 'draft' && (
											<>
												<button type="button" onClick={() => setView({ mode: 'edit', doc: d })}>
													Modifier
												</button>
												<button type="button" onClick={() => setStatus(d, 'validated')}>
													Valider
												</button>
												<button type="button" onClick={() => remove(d)}>
													Supprimer
												</button>
											</>
										)}
										{d.kind === 'invoice' && d.status === 'validated' && (
											<button type="button" onClick={() => setStatus(d, 'paid')}>
												Marquer payée
											</button>
										)}
										{d.status === 'validated' && (
											<button type="button" onClick={() => setStatus(d, 'cancelled')}>
												Annuler
											</button>
										)}
										{d.status !== 'cancelled' &&
											CONVERSIONS[d.kind].map((to) => (
												<button key={to} type="button" onClick={() => convert(d, to)}>
													→ {DOC_LABELS[to].title}
												</button>
											))}
										<button type="button" onClick={() => duplicate(d)}>
											Dupliquer
										</button>
									</td>
								</tr>
							)
						})}
					</tbody>
				</table>
			)}
		</div>
	)
}
