import { DOC_LABELS, PAYMENT_LABELS, type CommercialDocument, type CompanyInfo } from './types'
import { amountInWordsMAD, computeTotals, formatMAD, lineHT } from './tva'
import { frDate } from './numbering'

interface Props {
	doc: CommercialDocument
	company: CompanyInfo
	/** Règlements et avoirs déjà imputés (factures) */
	paid?: number
	balance?: number
	onClose: () => void
}

export function CompanyHeader({ company }: { company: CompanyInfo }) {
	return (
		<div className="doc-print-company">
			{company.logo && <img className="doc-logo" src={company.logo} alt="" />}
			<div>
				<strong className="doc-company">{company.name || 'Votre entreprise'}</strong>
				<div>{company.address}</div>
				<div>{company.city}</div>
				<div>{[company.phone, company.email].filter(Boolean).join(' · ')}</div>
			</div>
		</div>
	)
}

export function CompanyFooter({ company }: { company: CompanyInfo }) {
	return (
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
	)
}

/** Aperçu imprimable (bouton « Imprimer / PDF ») */
export default function DocumentPrint({ doc, company, paid = 0, balance, onClose }: Props) {
	const totals = computeTotals(doc)
	const info = DOC_LABELS[doc.kind]
	// BL et bons de réception servent à la logistique : pas de prix
	const showPrices = doc.kind !== 'delivery' && doc.kind !== 'receipt'
	const showTrace = doc.lines.some((l) => l.lot || l.serial || l.expiry)
	const iv = doc.intervention
	const partyLabel =
		info.side === 'purchase' ? 'Fournisseur' : doc.kind === 'delivery' ? 'Livré à' : 'Client'

	return (
		<div>
			<div className="doc-toolbar no-print">
				<button type="button" className="btn-primary" onClick={() => window.print()}>
					Imprimer / PDF
				</button>
				<button type="button" onClick={onClose}>
					Retour à la liste
				</button>
			</div>

			<div className="doc-print">
				<header className="doc-print-head">
					<CompanyHeader company={company} />
					<div className="doc-print-title">
						<h2>
							{info.printTitle}
							{doc.consignment ? ' (DÉPÔT)' : ''}
						</h2>
						<table className="doc-ref-table">
							<tbody>
								<tr>
									<th>N°</th>
									<td>{doc.number}</td>
								</tr>
								<tr>
									<th>Date</th>
									<td>{frDate(doc.date)}</td>
								</tr>
								{(doc.kind === 'invoice' || doc.kind === 'bill') && doc.dueDate && (
									<tr>
										<th>Échéance</th>
										<td>{frDate(doc.dueDate)}</td>
									</tr>
								)}
								{doc.kind === 'quote' && doc.dueDate && (
									<tr>
										<th>Validité</th>
										<td>{frDate(doc.dueDate)}</td>
									</tr>
								)}
								{doc.supplierRef && (
									<tr>
										<th>Réf. fournisseur</th>
										<td>{doc.supplierRef}</td>
									</tr>
								)}
								{doc.sourceNumber && (
									<tr>
										<th>{doc.kind === 'credit' ? 'Sur facture' : 'Votre réf.'}</th>
										<td>{doc.sourceNumber}</td>
									</tr>
								)}
							</tbody>
						</table>
					</div>
				</header>

				<div className="doc-print-boxes">
					{iv ? (
						<section className="doc-box">
							<strong>Intervention</strong>
							{iv.patient && <div>Patient : {iv.patient}</div>}
							{iv.patientRef && <div>Dossier / CIN : {iv.patientRef}</div>}
							{iv.surgeon && <div>Chirurgien : {iv.surgeon}</div>}
							{iv.clinic && <div>Établissement : {iv.clinic}</div>}
							{iv.date && <div>Date : {frDate(iv.date)}</div>}
							{iv.coverage && <div>Prise en charge : {iv.coverage}</div>}
						</section>
					) : (
						<span />
					)}
					<section className="doc-box doc-party">
						<strong>{partyLabel}</strong>
						<div className="doc-party-name">{doc.party.name}</div>
						<div>{doc.party.address}</div>
						<div>{doc.party.city}</div>
						{doc.party.ice && <div>ICE : {doc.party.ice}</div>}
						{doc.party.ifNumber && <div>IF : {doc.party.ifNumber}</div>}
						{doc.party.rc && <div>RC : {doc.party.rc}</div>}
					</section>
				</div>

				<table className="doc-table doc-print-lines">
					<thead>
						<tr>
							<th>Désignation</th>
							{showTrace && (
								<>
									<th>Lot / N° série</th>
									<th>Péremption</th>
								</>
							)}
							<th className="num">Qté</th>
							{showPrices && (
								<>
									<th className="num">P.U. HT</th>
									<th className="num">Rem.</th>
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
								{showTrace && (
									<>
										<td>{[l.lot, l.serial].filter(Boolean).join(' / ')}</td>
										<td>{frDate(l.expiry)}</td>
									</>
								)}
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
					<div className="doc-print-bottom">
						<table className="doc-table doc-vat-table">
							<thead>
								<tr>
									<th>Taux</th>
									<th className="num">Base HT</th>
									<th className="num">TVA</th>
								</tr>
							</thead>
							<tbody>
								{totals.byRate.map((r) => (
									<tr key={r.rate}>
										<td>{r.rate} %</td>
										<td className="num">{formatMAD(r.base)}</td>
										<td className="num">{formatMAD(r.tva)}</td>
									</tr>
								))}
							</tbody>
						</table>
						<table className="doc-table doc-totals-box">
							<tbody>
								<tr>
									<td>Total HT</td>
									<td className="num">{formatMAD(totals.totalHT)}</td>
								</tr>
								<tr>
									<td>Total TVA</td>
									<td className="num">{formatMAD(totals.totalTVA)}</td>
								</tr>
								<tr className="doc-total-row">
									<td>Total TTC</td>
									<td className="num">{formatMAD(totals.totalTTC)}</td>
								</tr>
								{totals.stampDuty > 0 && (
									<>
										<tr>
											<td>Droit de timbre 0,25 %</td>
											<td className="num">{formatMAD(totals.stampDuty)}</td>
										</tr>
										<tr className="doc-total-row">
											<td>Net à payer</td>
											<td className="num">{formatMAD(totals.netToPay)}</td>
										</tr>
									</>
								)}
								{doc.kind === 'invoice' && paid > 0 && balance !== undefined && (
									<>
										<tr>
											<td>Déjà réglé / avoirs</td>
											<td className="num">{formatMAD(totals.netToPay - balance)}</td>
										</tr>
										<tr className="doc-total-row">
											<td>Reste dû</td>
											<td className="num">{formatMAD(balance)}</td>
										</tr>
									</>
								)}
							</tbody>
						</table>
					</div>
				)}

				{(doc.kind === 'invoice' || doc.kind === 'credit') && (
					<p>
						{doc.kind === 'invoice' ? 'Arrêtée la présente facture' : 'Arrêté le présent avoir'} à la somme de :{' '}
						<strong>{amountInWordsMAD(totals.netToPay)}</strong> TTC.
						<br />
						Mode de règlement : {PAYMENT_LABELS[doc.paymentMethod]}
					</p>
				)}

				{doc.notes && <p className="doc-notes-print">{doc.notes}</p>}

				{(doc.kind === 'quote' || doc.kind === 'order' || doc.kind === 'delivery' || doc.kind === 'receipt' || doc.kind === 'purchase') && (
					<div className="doc-signatures">
						<div>
							{doc.kind === 'delivery'
								? 'Signature du livreur'
								: doc.kind === 'receipt'
									? 'Réceptionné par'
									: "Cachet et signature de l'entreprise"}
						</div>
						<div>
							{doc.kind === 'delivery'
								? 'Reçu conforme : cachet et signature du client'
								: doc.kind === 'receipt'
									? 'Contrôle qualité / conformité'
									: 'Bon pour accord : cachet et signature'}
						</div>
					</div>
				)}

				<CompanyFooter company={company} />
			</div>
		</div>
	)
}
