import { useMemo, useState } from 'react'
import { downloadCsv } from '../documents/csv'
import type { AuditEntry } from './types'
import '../documents/documents.css'

interface Props {
	entries: AuditEntry[]
}

/** Journal d'activité : qui a fait quoi, et quand (réservé à l'administrateur) */
export default function AuditPage({ entries }: Props) {
	const [query, setQuery] = useState('')
	const [user, setUser] = useState('')
	const [from, setFrom] = useState('')
	const [to, setTo] = useState('')
	const users = useMemo(() => [...new Set(entries.map((e) => e.user))].sort(), [entries])

	const rows = useMemo(() => {
		const q = query.trim().toLowerCase()
		return entries
			.filter((e) => !user || e.user === user)
			.filter((e) => (!from || e.at.slice(0, 10) >= from) && (!to || e.at.slice(0, 10) <= to))
			.filter((e) => !q || `${e.action} ${e.detail}`.toLowerCase().includes(q))
			.slice()
			.reverse()
	}, [entries, query, user, from, to])

	const fmt = (iso: string) => new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })

	return (
		<div>
			<div className="doc-toolbar">
				<input className="doc-search" placeholder="Rechercher : action, n° de pièce, client…" value={query} onChange={(e) => setQuery(e.target.value)} />
				<select value={user} onChange={(e) => setUser(e.target.value)}>
					<option value="">Tous les utilisateurs</option>
					{users.map((u) => (
						<option key={u} value={u}>
							{u}
						</option>
					))}
				</select>
				<label>
					Du <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
				</label>
				<label>
					au <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
				</label>
				<button type="button" onClick={() => downloadCsv('journal-activite.csv', [['Date', 'Utilisateur', 'Action', 'Détail'], ...rows.map((e) => [fmt(e.at), e.user, e.action, e.detail])])}>
					Exporter (CSV)
				</button>
				<span className="doc-count">{rows.length} action(s)</span>
			</div>
			{rows.length === 0 ? (
				<p className="doc-empty">Aucune action enregistrée.</p>
			) : (
				<div className="doc-table-wrap">
					<table className="doc-table">
						<thead>
							<tr>
								<th>Date et heure</th>
								<th>Utilisateur</th>
								<th>Action</th>
								<th>Détail</th>
							</tr>
						</thead>
						<tbody>
							{rows.map((e) => (
								<tr key={e.id}>
									<td>{fmt(e.at)}</td>
									<td>{e.user}</td>
									<td>
										<strong>{e.action}</strong>
									</td>
									<td>{e.detail}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}
		</div>
	)
}
