import PrintSheet from './PrintSheet'
import { CompanyFooter, CompanyHeader } from './PrintParts'
import { printSettingsOf, usesGeneratedHeader } from './printSettings'
import { daysBetween, frDate, today } from './numbering'
import { computeTotals, formatMAD, round2 } from './tva'
import type { CommercialDocument, CompanyInfo, Party } from './types'

interface Props {
	company: CompanyInfo
	party: Party
	invoices: { doc: CommercialDocument; balance: number }[]
	onClose: () => void
}

/** Lettre de relance des factures échues d'un client */
export default function ReminderPrint({ company, party, invoices, onClose }: Props) {
	const now = today()
	const settings = printSettingsOf(company)
	const total = round2(invoices.reduce((s, i) => s + i.balance, 0))

	return (
		<div>
			<div className="doc-toolbar no-print">
				<button type="button" className="btn-primary" onClick={() => window.print()}>
					Imprimer / PDF
				</button>
				<button type="button" onClick={onClose}>
					Retour
				</button>
			</div>

			<div className="doc-print">
				<PrintSheet company={company} footer={settings.showLegal ? <CompanyFooter company={company} /> : null}>
				{usesGeneratedHeader(settings) && <CompanyHeader company={company} />}
				<section className="doc-box doc-party doc-reminder-party">
					<div className="doc-party-name">{party.name}</div>
					<div>{party.address}</div>
					<div>{party.city}</div>
				</section>

				<p style={{ textAlign: 'right' }}>
					{company.city ? `${company.city}, le ` : 'Le '}
					{frDate(now)}
				</p>
				<p>
					<strong>Objet : relance pour factures échues</strong>
				</p>
				<p>Madame, Monsieur,</p>
				<p>
					Sauf erreur de notre part, les factures ci-dessous restent impayées à ce jour, alors que leur échéance
					est dépassée :
				</p>

				<table className="doc-table doc-print-lines">
					<thead>
						<tr>
							<th>Facture</th>
							<th>Date</th>
							<th>Échéance</th>
							<th className="num">Retard</th>
							<th className="num">Montant TTC</th>
							<th className="num">Reste dû</th>
						</tr>
					</thead>
					<tbody>
						{invoices.map(({ doc, balance }) => (
							<tr key={doc.id}>
								<td>{doc.number}</td>
								<td>{frDate(doc.date)}</td>
								<td>{frDate(doc.dueDate)}</td>
								<td className="num">{daysBetween(doc.dueDate, now)} j</td>
								<td className="num">{formatMAD(computeTotals(doc).netToPay)}</td>
								<td className="num">{formatMAD(balance)}</td>
							</tr>
						))}
					</tbody>
					<tfoot>
						<tr className="doc-total-row">
							<td colSpan={5}>Total restant dû</td>
							<td className="num">{formatMAD(total)}</td>
						</tr>
					</tfoot>
				</table>

				<p>
					Nous vous remercions de bien vouloir procéder à leur règlement dans les meilleurs délais
					{company.rib ? `, de préférence par virement sur notre compte ${company.bank} (RIB ${company.rib})` : ''}. Si
					votre paiement a été effectué entre-temps, merci de ne pas tenir compte de ce courrier.
				</p>
				<p>Veuillez agréer, Madame, Monsieur, nos salutations distinguées.</p>
				<p style={{ marginTop: 48 }}>
					<strong>{company.name}</strong>
					<br />
					Service comptabilité
				</p>

				</PrintSheet>
			</div>
		</div>
	)
}
