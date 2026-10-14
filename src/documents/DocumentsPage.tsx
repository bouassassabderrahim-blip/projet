import { useMemo, useState } from 'react'
import type { Product } from '../types'
import DocumentEditor from './DocumentEditor'
import DocumentPrint from './DocumentPrint'
import PaymentDialog from './PaymentDialog'
import ReminderPrint from './ReminderPrint'
import { downloadCsv, journal } from './csv'
import { balanceOf, isActive, isOverdue, paidAmount, sign } from './ledger'
import { addDays, emptyLine, frDate, newId, nextNumber, today } from './numbering'
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
	type Kit,
	type PartyRecord,
	type Payment,
	type StockLot,
} from './types'
import './documents.css'

interface Props {
	kind: DocKind
	documents: CommercialDocument[]
	onChange: (docs: CommercialDocument[]) => void
	products: Product[]
	lots: StockLot[]
	kits: Kit[]
	parties: PartyRecord[]
	onPartiesChange: (parties: PartyRecord[]) => void
	company: CompanyInfo
	/** Ouvre directement une pièce en modification */
	openId?: string
	onNavigate?: (kind: DocKind, openId?: string) => void
	/** Mouvement de stock : -1 sortie, +1 entrée */
	onStockMove?: (lines: DocLine[], direction: 1 | -1, supplier?: string, reference?: string) => void
}

type View =
	| { mode: 'list' }
	| { mode: 'edit'; doc: CommercialDocument }
	| { mode: 'print'; id: string }
	| { mode: 'reminder'; partyName: string }

/** Chaînes : Devis → BC → BL → Facture → Avoir ; Commande fournisseur → Réception → Facture fournisseur */
const CONVERSIONS: Record<DocKind, DocKind[]> = {
	quote: ['order', 'delivery', 'invoice'],
	order: ['delivery', 'invoice'],
	delivery: ['invoice'],
	invoice: ['credit'],
	credit: [],
	purchase: ['receipt', 'bill'],
	receipt: ['bill'],
	bill: [],
}

type Filter = DocStatus | '' | 'late' | 'open'

/** Une facture ne bouge le stock que si aucun BL ne l'a déjà fait */
function invoiceMovesStock(doc: CommercialDocument, documents: CommercialDocument[]): boolean {
	if (doc.kind !== 'invoice') return false
	const source = documents.find((d) => d.id === doc.sourceId)
	if (source?.kind === 'delivery') return false
	return true
}

export default function DocumentsPage({
	kind,
	documents,
	onChange,
	products,
	lots,
	kits,
	parties,
	onPartiesChange,
	company,
	openId,
	onNavigate,
	onStockMove,
}: Props) {
	const [view, setView] = useState<View>(() => {
		const doc = openId ? documents.find((d) => d.id === openId) : undefined
		if (!doc) return { mode: 'list' }
		// Une pièce validée s'ouvre en consultation, un brouillon en modification
		return doc.status === 'draft' ? { mode: 'edit', doc } : { mode: 'print', id: doc.id }
	})
	const [search, setSearch] = useState('')
	const [filter, setFilter] = useState<Filter>('')
	const [paying, setPaying] = useState<CommercialDocument | null>(null)
	const [message, setMessage] = useState<{ text: string; kind?: DocKind; id?: string } | null>(null)
	const info = DOC_LABELS[kind]
	const isPurchase = info.side === 'purchase'
	const role = isPurchase ? 'supplier' : 'client'
	const now = today()

	const list = useMemo(() => {
		const q = search.trim().toLowerCase()
		return documents
			.filter((d) => d.kind === kind)
			.filter((d) => {
				if (filter === 'late') return isOverdue(d, documents, now)
				if (filter === 'open') return isActive(d) && balanceOf(d, documents) > 0.01
				return !filter || d.status === filter
			})
			.filter(
				(d) =>
					!q ||
					[d.number, d.party.name, d.supplierRef, d.intervention?.patient, ...d.lines.map((l) => `${l.lot ?? ''} ${l.serial ?? ''}`)]
						.join(' ')
						.toLowerCase()
						.includes(q),
			)
			.sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number))
	}, [documents, kind, search, filter, now])

	const roleParties = useMemo(() => parties.filter((p) => p.role === role).sort((a, b) => a.name.localeCompare(b.name)), [parties, role])

	const stats = useMemo(() => {
		if (kind !== 'invoice' && kind !== 'bill') return null
		let ht = 0
		let tva = 0
		let open = 0
		let late = 0
		let lateCount = 0
		for (const d of documents) {
			if (!isActive(d)) continue
			const same = kind === 'invoice' ? d.kind === 'invoice' || d.kind === 'credit' : d.kind === 'bill'
			if (!same) continue
			const t = computeTotals(d)
			ht += sign(d) * t.totalHT
			tva += sign(d) * t.totalTVA
			if (d.kind !== 'credit') open += balanceOf(d, documents)
			if (isOverdue(d, documents, now)) {
				late += balanceOf(d, documents)
				lateCount++
			}
		}
		return { ht: round2(ht), tva: round2(tva), open: round2(open), late: round2(late), lateCount }
	}, [documents, kind, now])

	function createDoc(): CommercialDocument {
		return {
			id: newId(),
			kind,
			number: nextNumber(kind, documents, now),
			date: now,
			// Facture : délai légal de paiement par défaut de 60 jours ; devis : validité de 30 jours
			dueDate: addDays(now, kind === 'quote' ? 30 : 60),
			party: emptyParty(),
			lines: [emptyLine()],
			status: 'draft',
			paymentMethod: 'virement',
			notes: '',
		}
	}

	/** Ajoute le tiers au fichier clients / fournisseurs s'il n'y est pas encore */
	function rememberParty(doc: CommercialDocument) {
		const name = doc.party.name.trim().toLowerCase()
		if (!name || parties.some((p) => p.role === role && p.name.trim().toLowerCase() === name)) return
		onPartiesChange([...parties, { ...doc.party, id: newId(), role, notes: '' }])
	}

	function save(doc: CommercialDocument) {
		const exists = documents.some((d) => d.id === doc.id)
		onChange(exists ? documents.map((d) => (d.id === doc.id ? doc : d)) : [...documents, doc])
		rememberParty(doc)
		setView({ mode: 'list' })
	}

	function setStatus(doc: CommercialDocument, status: DocStatus) {
		let next = documents.map((d) => (d.id === doc.id ? { ...d, status } : d))
		const supplier = doc.party.name

		if (status === 'validated') {
			if (doc.kind === 'delivery') {
				onStockMove?.(doc.lines, -1, '', doc.number)
				// BL en dépôt : chaque ligne reste à facturer à la pose
				if (doc.consignment)
					next = next.map((d) =>
						d.id === doc.id ? { ...d, lines: d.lines.map((l) => ({ ...l, depot: l.depot ?? 'depot' })) } : d,
					)
			}
			if (doc.kind === 'receipt') onStockMove?.(doc.lines, 1, supplier, doc.number)
			if (invoiceMovesStock(doc, documents)) onStockMove?.(doc.lines.filter((l) => !l.depotRef), -1, '', doc.number)
		}

		if (status === 'cancelled' && doc.status !== 'draft') {
			if (doc.kind === 'delivery') onStockMove?.(doc.lines.filter((l) => l.depot !== 'returned'), 1, '', `Annulation ${doc.number}`)
			if (doc.kind === 'receipt') onStockMove?.(doc.lines, -1, '', `Annulation ${doc.number}`)
		}
		onChange(next)
	}

	function addPayment(doc: CommercialDocument, payment: Payment) {
		const balance = balanceOf(doc, documents) - payment.amount
		onChange(
			documents.map((d) =>
				d.id === doc.id
					? { ...d, payments: [...(d.payments ?? []), payment], status: balance <= 0.01 ? 'paid' : d.status }
					: d,
			),
		)
		setPaying(null)
	}

	function remove(doc: CommercialDocument) {
		if (!confirm(`Supprimer ${doc.number} ?`)) return
		// Facture issue d'un dépôt : les implants redeviennent « en dépôt »
		const refs = doc.lines.map((l) => l.depotRef).filter((r): r is { docId: string; lineId: string } => !!r)
		onChange(
			documents
				.filter((d) => d.id !== doc.id)
				.map((d) =>
					refs.some((r) => r.docId === d.id)
						? {
								...d,
								lines: d.lines.map((l) => (refs.some((r) => r.lineId === l.id) ? { ...l, depot: 'depot' as const } : l)),
							}
						: d,
				),
		)
	}

	function copyLines(lines: DocLine[]): DocLine[] {
		return lines.map((l) => ({ ...l, id: newId(), depot: undefined, depotRef: undefined }))
	}

	function duplicate(doc: CommercialDocument) {
		setView({
			mode: 'edit',
			doc: {
				...doc,
				id: newId(),
				number: nextNumber(kind, documents, now),
				date: now,
				dueDate: addDays(now, kind === 'quote' ? 30 : 60),
				status: 'draft',
				payments: undefined,
				paidDate: undefined,
				sourceId: undefined,
				sourceNumber: undefined,
				lines: copyLines(doc.lines),
			},
		})
	}

	function convert(doc: CommercialDocument, to: DocKind) {
		const created: CommercialDocument = {
			...doc,
			id: newId(),
			kind: to,
			number: nextNumber(to, documents, now),
			date: now,
			dueDate: addDays(now, to === 'quote' ? 30 : 60),
			status: 'draft',
			payments: undefined,
			paidDate: undefined,
			consignment: undefined,
			supplierRef: to === 'bill' ? '' : undefined,
			sourceId: doc.id,
			sourceNumber: doc.number,
			lines: copyLines(doc.lines),
		}
		onChange([...documents, created])
		const label = DOC_LABELS[to]
		setMessage({ text: `${label.title} ${created.number} créé(e) en brouillon à partir de ${doc.number}.`, kind: to, id: created.id })
	}

	function exportJournal() {
		const kinds: DocKind[] = isPurchase ? ['bill'] : ['invoice', 'credit']
		const docs = documents.filter((d) => kinds.includes(d.kind) && d.status !== 'draft').sort((a, b) => a.date.localeCompare(b.date) || a.number.localeCompare(b.number))
		downloadCsv(`journal-${isPurchase ? 'achats' : 'ventes'}-${now}.csv`, journal(docs, documents))
	}

	if (view.mode === 'edit') {
		return (
			<DocumentEditor
				initial={view.doc}
				products={products}
				lots={lots}
				kits={kits}
				parties={roleParties}
				onSave={save}
				onCancel={() => setView({ mode: 'list' })}
			/>
		)
	}

	if (view.mode === 'print') {
		const doc = documents.find((d) => d.id === view.id)
		if (doc)
			return (
				<DocumentPrint
					doc={doc}
					company={company}
					paid={paidAmount(doc)}
					balance={balanceOf(doc, documents)}
					onClose={() => setView({ mode: 'list' })}
				/>
			)
	}

	if (view.mode === 'reminder') {
		const invoices = documents
			.filter((d) => d.party.name === view.partyName && isOverdue(d, documents, now) && d.kind === 'invoice')
			.map((doc) => ({ doc, balance: balanceOf(doc, documents) }))
		const party = invoices[0]?.doc.party ?? { ...emptyParty(), name: view.partyName }
		return <ReminderPrint company={company} party={party} invoices={invoices} onClose={() => setView({ mode: 'list' })} />
	}

	const showMoney = kind !== 'delivery' && kind !== 'receipt'
	const hasBalance = kind === 'invoice' || kind === 'bill'

	return (
		<div>
			{!company.name && !isPurchase && (
				<p className="doc-warning">
					Renseignez d'abord la fiche de votre entreprise (ICE, IF, RC…) dans Paramètres › Mon entreprise : ces
					mentions sont obligatoires sur les factures.
				</p>
			)}

			{stats && (
				<div className="doc-stats">
					<div>
						<span>{isPurchase ? 'Achats HT' : "Chiffre d'affaires HT (net d'avoirs)"}</span>
						<strong>{formatMAD(stats.ht)}</strong>
					</div>
					<div>
						<span>{isPurchase ? 'TVA déductible' : 'TVA collectée'}</span>
						<strong>{formatMAD(stats.tva)}</strong>
					</div>
					<div>
						<span>{isPurchase ? 'Reste à payer' : 'Reste à encaisser'}</span>
						<strong>{formatMAD(stats.open)}</strong>
					</div>
					<div className={stats.lateCount ? 'doc-stat-late' : undefined}>
						<span>Échu ({stats.lateCount})</span>
						<strong>{formatMAD(stats.late)}</strong>
					</div>
				</div>
			)}

			{message && (
				<p className="doc-info">
					{message.text}{' '}
					{onNavigate && message.kind && (
						<button type="button" onClick={() => onNavigate(message.kind!, message.id)}>
							Ouvrir
						</button>
					)}
				</p>
			)}

			<div className="doc-toolbar">
				<button type="button" className="btn-primary" onClick={() => setView({ mode: 'edit', doc: createDoc() })}>
					+ {info.newLabel}
				</button>
				<input
					className="doc-search"
					placeholder="Rechercher : n°, tiers, patient, lot, n° de série…"
					value={search}
					onChange={(e) => setSearch(e.target.value)}
				/>
				<select value={filter} onChange={(e) => setFilter(e.target.value as Filter)}>
					<option value="">Tous les états</option>
					{Object.entries(STATUS_LABELS).map(([k, v]) => (
						<option key={k} value={k}>
							{v}
						</option>
					))}
					{hasBalance && <option value="open">Non soldées</option>}
					{hasBalance && <option value="late">Échues</option>}
				</select>
				{(kind === 'invoice' || kind === 'credit' || kind === 'bill') && (
					<button type="button" onClick={exportJournal}>
						Exporter le journal {isPurchase ? 'des achats' : 'des ventes'} (CSV)
					</button>
				)}
				<span className="doc-count">{list.length} pièce(s)</span>
			</div>

			{list.length === 0 ? (
				<p className="doc-empty">Aucune pièce pour le moment.</p>
			) : (
				<div className="doc-table-wrap">
					<table className="doc-table doc-list">
						<thead>
							<tr>
								<th>N°</th>
								<th>Date</th>
								<th>{isPurchase ? 'Fournisseur' : 'Client'}</th>
								{kind === 'bill' && <th>Réf. fournisseur</th>}
								{!isPurchase && <th>Patient</th>}
								{showMoney && <th className="num">Total TTC</th>}
								{hasBalance && <th className="num">Reste dû</th>}
								{hasBalance && <th>Échéance</th>}
								<th>État</th>
								<th>Actions</th>
							</tr>
						</thead>
						<tbody>
							{list.map((d) => {
								const t = computeTotals(d)
								const balance = balanceOf(d, documents)
								const late = isOverdue(d, documents, now)
								const settledByCredit = d.kind === 'invoice' && d.status === 'validated' && balance <= 0.01
								const depotLeft = d.consignment ? d.lines.filter((l) => l.depot === 'depot').length : 0
								return (
									<tr key={d.id} className={late ? 'doc-row-late' : undefined}>
										<td>
											<button type="button" className="doc-link" onClick={() => setView(d.status === 'draft' ? { mode: 'edit', doc: d } : { mode: 'print', id: d.id })}>
												{d.number}
											</button>
										</td>
										<td>{frDate(d.date)}</td>
										<td>{d.party.name}</td>
										{kind === 'bill' && <td>{d.supplierRef}</td>}
										{!isPurchase && <td>{d.intervention?.patient}</td>}
										{showMoney && <td className="num">{formatMAD(t.netToPay)}</td>}
										{hasBalance && <td className="num">{isActive(d) ? formatMAD(balance) : ''}</td>}
										{hasBalance && <td>{frDate(d.dueDate)}</td>}
										<td>
											<span className={`doc-badge doc-badge-${settledByCredit ? 'paid' : d.status}`}>
												{settledByCredit ? 'Soldée' : d.kind === 'invoice' && d.status === 'paid' ? 'Payée' : STATUS_LABELS[d.status]}
											</span>
											{late && <span className="doc-badge doc-badge-late">Échue</span>}
											{d.consignment && (
												<span className="doc-badge doc-badge-depot">
													Dépôt{depotLeft ? ` · ${depotLeft} chez le client` : ''}
												</span>
											)}
										</td>
										<td className="doc-actions">
											<button type="button" onClick={() => setView({ mode: 'print', id: d.id })}>
												Imprimer
											</button>
											{d.status === 'draft' && (
												<>
													<button type="button" onClick={() => setView({ mode: 'edit', doc: d })}>
														Modifier
													</button>
													<button type="button" className="btn-primary" onClick={() => setStatus(d, 'validated')}>
														Valider
													</button>
													<button type="button" onClick={() => remove(d)}>
														Supprimer
													</button>
												</>
											)}
											{hasBalance && d.status === 'validated' && balance > 0.01 && (
												<button type="button" onClick={() => setPaying(d)}>
													{isPurchase ? 'Régler' : 'Encaisser'}
												</button>
											)}
											{late && d.kind === 'invoice' && (
												<button type="button" onClick={() => setView({ mode: 'reminder', partyName: d.party.name })}>
													Relance
												</button>
											)}
											{/* Une facture validée ne s'annule pas : on émet un avoir */}
											{d.status === 'validated' && d.kind !== 'invoice' && (
												<button
													type="button"
													onClick={() => confirm(`Annuler ${d.number} ?`) && setStatus(d, 'cancelled')}
												>
													Annuler
												</button>
											)}
											{d.status !== 'cancelled' &&
												d.status !== 'draft' &&
												CONVERSIONS[d.kind]
													.filter((to) => !(d.consignment && to === 'invoice'))
													.map((to) => (
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
				</div>
			)}

			{paying && (
				<PaymentDialog
					doc={paying}
					balance={balanceOf(paying, documents)}
					onSave={(p) => addPayment(paying, p)}
					onClose={() => setPaying(null)}
				/>
			)}
		</div>
	)
}
