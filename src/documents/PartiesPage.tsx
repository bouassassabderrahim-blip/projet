import { useMemo, useState } from 'react'
import ReminderPrint from './ReminderPrint'
import { balanceOf, isActive, isOverdue, sign } from './ledger'
import { frDate, newId, today } from './numbering'
import { computeTotals, formatMAD, round2 } from './tva'
import {
	DOC_LABELS,
	STATUS_LABELS,
	emptyParty,
	type CommercialDocument,
	type CompanyInfo,
	type PartyRecord,
	type PartyRole,
} from './types'
import './documents.css'

interface Props {
	role: PartyRole
	parties: PartyRecord[]
	onChange: (parties: PartyRecord[]) => void
	documents: CommercialDocument[]
	company: CompanyInfo
}

const fields: { key: 'name' | 'address' | 'city' | 'ice' | 'ifNumber' | 'rc' | 'phone' | 'email'; label: string }[] = [
	{ key: 'name', label: 'Raison sociale / Nom' },
	{ key: 'address', label: 'Adresse' },
	{ key: 'city', label: 'Ville' },
	{ key: 'phone', label: 'Téléphone' },
	{ key: 'email', label: 'E-mail' },
	{ key: 'ice', label: 'ICE' },
	{ key: 'ifNumber', label: 'IF' },
	{ key: 'rc', label: 'RC' },
]

const same = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase()

/** Fichier clients ou fournisseurs : fiche, chiffre d'affaires, encours, historique, relance */
export default function PartiesPage({ role, parties, onChange, documents, company }: Props) {
	const [query, setQuery] = useState('')
	const [editing, setEditing] = useState<PartyRecord | null>(null)
	const [reminder, setReminder] = useState<string | null>(null)
	const [error, setError] = useState('')
	const now = today()
	const isClient = role === 'client'
	const side = isClient ? 'sale' : 'purchase'

	const rows = useMemo(() => {
		const q = query.trim().toLowerCase()
		return parties
			.filter((p) => p.role === role)
			.filter((p) => !q || [p.name, p.city, p.ice, p.phone].join(' ').toLowerCase().includes(q))
			.map((p) => {
				const docs = documents.filter((d) => DOC_LABELS[d.kind].side === side && same(d.party.name, p.name))
				let revenue = 0
				let balance = 0
				let late = 0
				for (const d of docs) {
					if (!isActive(d)) continue
					if (d.kind === 'invoice' || d.kind === 'credit' || d.kind === 'bill') revenue += sign(d) * computeTotals(d).totalHT
					if (d.kind === 'invoice' || d.kind === 'bill') balance += balanceOf(d, documents)
					if (isOverdue(d, documents, now)) late += balanceOf(d, documents)
				}
				const last = docs.reduce((m, d) => (d.date > m ? d.date : m), '')
				return { party: p, docs, revenue: round2(revenue), balance: round2(balance), late: round2(late), last }
			})
			.sort((a, b) => b.revenue - a.revenue || a.party.name.localeCompare(b.party.name))
	}, [parties, documents, role, side, query, now])

	function save() {
		if (!editing) return
		if (!editing.name.trim()) return setError('Le nom est obligatoire.')
		if (editing.ice && !/^\d{15}$/.test(editing.ice.trim())) return setError("L'ICE doit comporter 15 chiffres.")
		const duplicate = parties.some((p) => p.id !== editing.id && p.role === role && same(p.name, editing.name))
		if (duplicate) return setError('Un tiers porte déjà ce nom.')
		const rec = { ...editing, name: editing.name.trim() }
		onChange(parties.some((p) => p.id === rec.id) ? parties.map((p) => (p.id === rec.id ? rec : p)) : [...parties, rec])
		setEditing(null)
		setError('')
	}

	if (reminder) {
		const invoices = documents
			.filter((d) => d.kind === 'invoice' && same(d.party.name, reminder) && isOverdue(d, documents, now))
			.map((doc) => ({ doc, balance: balanceOf(doc, documents) }))
		const party = invoices[0]?.doc.party ?? { ...emptyParty(), name: reminder }
		return <ReminderPrint company={company} party={party} invoices={invoices} onClose={() => setReminder(null)} />
	}

	if (editing) {
		const history = rows.find((r) => r.party.id === editing.id)?.docs ?? []
		return (
			<div>
				<div className="doc-editor-head">
					<h2>{editing.name || (isClient ? 'Nouveau client' : 'Nouveau fournisseur')}</h2>
					<div className="doc-editor-actions">
						<button type="button" className="btn-primary" onClick={save}>
							Enregistrer
						</button>
						<button type="button" onClick={() => setEditing(null)}>
							Fermer
						</button>
					</div>
				</div>
				<fieldset className="doc-panel">
					<legend>Coordonnées</legend>
					<div className="doc-grid">
						{fields.map((f) => (
							<label key={f.key}>
								{f.label}
								<input value={editing[f.key]} onChange={(e) => setEditing({ ...editing, [f.key]: e.target.value })} />
							</label>
						))}
						<label>
							Délai de paiement (jours)
							<input
								className="num"
								type="number"
								min={0}
								value={editing.paymentTerms ?? ''}
								onChange={(e) =>
									setEditing({ ...editing, paymentTerms: e.target.value === '' ? undefined : Number(e.target.value) })
								}
							/>
						</label>
						{isClient && (
							<label className="doc-check">
								<input
									type="checkbox"
									checked={!!editing.individual}
									onChange={(e) => setEditing({ ...editing, individual: e.target.checked })}
								/>
								Particulier (patient)
							</label>
						)}
					</div>
					<label className="doc-notes">
						Notes
						<textarea rows={3} value={editing.notes} onChange={(e) => setEditing({ ...editing, notes: e.target.value })} />
					</label>
				</fieldset>
				{error && <p className="doc-error">{error}</p>}

				{history.length > 0 && (
					<div className="doc-panel">
						<div className="doc-panel-title">Historique ({history.length} pièces)</div>
						<table className="doc-table">
							<thead>
								<tr>
									<th>Date</th>
									<th>Pièce</th>
									<th>N°</th>
									<th className="num">Total TTC</th>
									<th className="num">Reste dû</th>
									<th>État</th>
								</tr>
							</thead>
							<tbody>
								{[...history]
									.sort((a, b) => b.date.localeCompare(a.date))
									.map((d) => (
										<tr key={d.id} className={isOverdue(d, documents, now) ? 'doc-row-late' : undefined}>
											<td>{frDate(d.date)}</td>
											<td>{DOC_LABELS[d.kind].title}</td>
											<td>{d.number}</td>
											<td className="num">{formatMAD(sign(d) * computeTotals(d).netToPay)}</td>
											<td className="num">
												{(d.kind === 'invoice' || d.kind === 'bill') && isActive(d) ? formatMAD(balanceOf(d, documents)) : ''}
											</td>
											<td>{STATUS_LABELS[d.status]}</td>
										</tr>
									))}
							</tbody>
						</table>
					</div>
				)}
			</div>
		)
	}

	return (
		<div>
			<div className="doc-toolbar">
				<button
					type="button"
					className="btn-primary"
					onClick={() => setEditing({ ...emptyParty(), id: newId(), role, notes: '' })}
				>
					+ {isClient ? 'Nouveau client' : 'Nouveau fournisseur'}
				</button>
				<input
					className="doc-search"
					placeholder="Rechercher : nom, ville, ICE, téléphone…"
					value={query}
					onChange={(e) => setQuery(e.target.value)}
				/>
				<span className="doc-count">{rows.length} fiche(s)</span>
			</div>

			{rows.length === 0 ? (
				<p className="doc-empty">
					Aucune fiche. Les {isClient ? 'clients' : 'fournisseurs'} saisis sur les pièces sont ajoutés automatiquement.
				</p>
			) : (
				<div className="doc-table-wrap">
					<table className="doc-table doc-list">
						<thead>
							<tr>
								<th>Nom</th>
								<th>Ville</th>
								<th>ICE</th>
								<th>Téléphone</th>
								<th className="num">{isClient ? 'CA HT' : 'Achats HT'}</th>
								<th className="num">Encours</th>
								<th className="num">Échu</th>
								<th>Dernière pièce</th>
								<th>Actions</th>
							</tr>
						</thead>
						<tbody>
							{rows.map((r) => (
								<tr key={r.party.id} className={r.late > 0 ? 'doc-row-late' : undefined}>
									<td>
										<button type="button" className="doc-link" onClick={() => setEditing(r.party)}>
											{r.party.name}
										</button>
									</td>
									<td>{r.party.city}</td>
									<td>{r.party.ice}</td>
									<td>{r.party.phone}</td>
									<td className="num">{formatMAD(r.revenue)}</td>
									<td className="num">{formatMAD(r.balance)}</td>
									<td className="num">{r.late > 0 ? formatMAD(r.late) : ''}</td>
									<td>{frDate(r.last)}</td>
									<td className="doc-actions">
										<button type="button" onClick={() => setEditing(r.party)}>
											Fiche
										</button>
										{isClient && r.late > 0 && (
											<button type="button" onClick={() => setReminder(r.party.name)}>
												Lettre de relance
											</button>
										)}
										{r.docs.length === 0 && (
											<button
												type="button"
												onClick={() =>
													confirm(`Supprimer la fiche « ${r.party.name} » ?`) &&
													onChange(parties.filter((p) => p.id !== r.party.id))
												}
											>
												Supprimer
											</button>
										)}
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</div>
	)
}
