import { DOC_LABELS, PAYMENT_LABELS, type CommercialDocument, type CompanyInfo } from './types'
import { amountInWordsMAD, computeTotals, formatMAD, lineHT } from './tva'

interface Props {
	doc: CommercialDocument
	company: CompanyInfo
	onClose: () => void
}

const frDate = (d: string) => (d ? new Date(d + 'T00:00:00').toLocaleDateString('fr-FR') : '')

/** Aperçu imprimable (Ctrl+P ou bouton « Imprimer / PDF ») */
export default function DocumentPrint({ doc, company, onClose }: Props) {
	const totals = computeTotals(doc)
	// Le BL sert à la livraison : on n'y imprime pas les prix
	const showPrices = doc.kind !== 'delivery'
	const label = DOC_LABELS[doc.kind].title

	return (
		<div>
			<div className="export-bar no-print">
				<button type="button" onClick={() => window.print()}>
					Imprimer / PDF
				</button>
				<button type="button" onClick={onClose}>
					Retour
				</button>
			</div>

			<div className="doc-print">
				<header className="doc-print-head">
					<div>
						<strong className="doc-company">{company.name || 'Votre entreprise'}</strong>
						<div>{company.address}</div>
						<div>{company.city}</div>
						<div>{[company.phone, company.email].filter(Boolean).join(' · ')}</div>
					</div>
					<div className="doc-print-title">
						<h2>{label.toUpperCase()}</h2>
						<div>N° {doc.number}</div>
						<div>Date : {frDate(doc.date)}</div>
						{doc.kind === 'invoice' && doc.dueDate && <div>Échéance : {frDate(doc.dueDate)}</div>}
						{doc.sourceNumber && <div>Réf. : {doc.sourceNumber}</div>}
					</div>
				</header>

				<section className="doc-party">
					<strong>{doc.kind === 'delivery' ? 'Livré à' : 'Client'}</strong>
					<div>{doc.party.name}</div>
					<div>{doc.party.address}</div>
					<div>{doc.party.city}</div>
					{doc.party.ice && <div>ICE : {doc.party.ice}</div>}
					{doc.party.ifNumber && <div>IF : {doc.party.ifNumber}</div>}
					{doc.party.rc && <div>RC : {doc.party.rc}</div>}
				</section>

				<table className="doc-table">
					<thead>
						<tr>
							<th>Désignation</th>
							<th className="num">Qté</th>
							{showPrices && (
								<>
									<th className="num">P.U. HT</th>
									<th className="num">Remise</th>
									<th className="num">TVA</th>
									<th className="num">Total HT</th>
								</>
							)}
						</tr>
					</thead>
					<tbody>
						{doc.lines.map((l) => (
							<tr key={l.id}>
								<td>{l.description}</td>
								<td className="num">{l.quantity}</td>
								{showPrices && (
									<>
										<td className="num">{formatMAD(l.unitPriceHT)}</td>
										<td className="num">{l.discount ? `${l.discount} %` : ''}</td>
										<td className="num">{l.tvaRate} %</td>
										<td className="num">{formatMAD(lineHT(l))}</td>
									</>
								)}
							</tr>
						))}
					</tbody>
				</table>

				{showPrices && (
					<table className="doc-table doc-totals-table">
						<tbody>
							<tr>
								<td>Total HT</td>
								<td className="num">{formatMAD(totals.totalHT)}</td>
							</tr>
							{totals.byRate.map((r) => (
								<tr key={r.rate}>
									<td>
										TVA {r.rate} % (base {formatMAD(r.base)})
									</td>
									<td className="num">{formatMAD(r.tva)}</td>
								</tr>
							))}
							<tr>
								<th>Total TTC</th>
								<th className="num">{formatMAD(totals.totalTTC)}</th>
							</tr>
							{totals.stampDuty > 0 && (
								<>
									<tr>
										<td>Droit de timbre 0,25 %</td>
										<td className="num">{formatMAD(totals.stampDuty)}</td>
									</tr>
									<tr>
										<th>Net à payer</th>
										<th className="num">{formatMAD(totals.netToPay)}</th>
									</tr>
								</>
							)}
						</tbody>
					</table>
				)}

				{doc.kind === 'invoice' && (
					<p>
						Arrêtée la présente facture à la somme de : <strong>{amountInWordsMAD(totals.netToPay)}</strong>{' '}
						TTC.
						<br />
						Mode de paiement : {PAYMENT_LABELS[doc.paymentMethod]}
					</p>
				)}

				{doc.notes && <p className="doc-notes-print">{doc.notes}</p>}

				{doc.kind !== 'invoice' && (
					<div className="doc-signatures">
						<div>{doc.kind === 'delivery' ? 'Signature du livreur' : 'Cachet et signature du fournisseur'}</div>
						<div>{doc.kind === 'delivery' ? 'Reçu conforme : cachet et signature du client' : 'Bon pour accord : cachet et signature du client'}</div>
					</div>
				)}

				<footer className="doc-footer">
					{[
						company.name,
						company.ice && `ICE : ${company.ice}`,
						company.ifNumber && `IF : ${company.ifNumber}`,
						company.rc && `RC : ${company.rc}`,
						company.patente && `Patente : ${company.patente}`,
						company.cnss && `CNSS : ${company.cnss}`,
					]
						.filter(Boolean)
						.join(' · ')}
					{company.rib && (
						<div>
							{company.bank} · RIB : {company.rib}
						</div>
					)}
				</footer>
			</div>
		</div>
	)
}
