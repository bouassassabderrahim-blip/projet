import PrintSheet from './PrintSheet'
import { CompanyFooter, CompanyHeader } from './PrintParts'
import { printSettingsOf, usesGeneratedHeader } from './printSettings'
import { DOC_LABELS, PAYMENT_LABELS, type CommercialDocument, type CompanyInfo, type PrintSettings } from './types'
import { amountInWordsMAD, computeTotals, formatMAD, lineHT } from './tva'
import { frDate } from './numbering'

interface Props {
	doc: CommercialDocument
	company: CompanyInfo
	/** Règlements et avoirs déjà imputés (factures) */
	paid?: number
	balance?: number
	/** Réglages à prévisualiser (page Paramètres) */
	settings?: PrintSettings
	/** Aperçu intégré : sans barre d'outils */
	embedded?: boolean
	onClose?: () => void
}

/** Message d'accompagnement pour l'envoi d'une pièce (e-mail, WhatsApp) */
function shareMessage(doc: CommercialDocument, company: CompanyInfo, netToPay: number, balance?: number): { subject: string; body: string } {
	const title = DOC_LABELS[doc.kind].title
	const subject = `${title} ${doc.number}${company.name ? ` – ${company.name}` : ''}`
	const lines = [
		'Bonjour,',
		'',
		`Veuillez trouver ci-joint notre ${title.toLowerCase()} n° ${doc.number} du ${frDate(doc.date)}, d'un montant de ${formatMAD(netToPay)} TTC.`,
	]
	if (doc.kind === 'invoice') {
		if (balance !== undefined && balance > 0.01 && balance < netToPay) lines.push(`Reste à régler : ${formatMAD(balance)}.`)
		if (doc.dueDate) lines.push(`Échéance : ${frDate(doc.dueDate)}.`)
		if (company.rib) lines.push(`Règlement par virement : ${company.bank} – RIB ${company.rib}.`)
	}
	if (doc.kind === 'quote' && doc.dueDate) lines.push(`Ce devis est valable jusqu'au ${frDate(doc.dueDate)}.`)
	lines.push('', 'Cordialement,', company.name)
	return { subject, body: lines.join('\n') }
}

/** Numéro marocain au format international pour WhatsApp (06… → 2126…) */
function whatsappNumber(phone: string): string {
	const digits = phone.replace(/\D/g, '')
	if (digits.startsWith('00')) return digits.slice(2)
	if (digits.startsWith('0')) return '212' + digits.slice(1)
	return digits
}

/** Pièce commerciale au format A4, compatible avec votre papier à en-tête */
export default function DocumentPrint({ doc, company, paid = 0, balance, settings, embedded, onClose }: Props) {
	const s = settings ?? printSettingsOf(company)
	const totals = computeTotals(doc)
	const info = DOC_LABELS[doc.kind]
	// BL et bons de réception servent à la logistique : pas de prix
	const showPrices = doc.kind !== 'delivery' && doc.kind !== 'receipt'
	const showTrace = doc.lines.some((l) => l.lot || l.serial || l.expiry)
	const iv = doc.intervention
	const partyLabel = info.side === 'purchase' ? 'Fournisseur' : doc.kind === 'delivery' ? 'Livré à' : 'Client'
	const terms = doc.kind === 'quote' ? s.quoteTerms : doc.kind === 'invoice' ? s.invoiceTerms : ''
	const signatures =
		doc.kind === 'quote' || doc.kind === 'order' || doc.kind === 'delivery' || doc.kind === 'receipt' || doc.kind === 'purchase'

	const refs: [string, string][] = [
		['Date', frDate(doc.date)],
		...((doc.kind === 'invoice' || doc.kind === 'bill') && doc.dueDate ? [['Échéance', frDate(doc.dueDate)] as [string, string]] : []),
		...(doc.kind === 'quote' && doc.dueDate ? [['Valable jusqu’au', frDate(doc.dueDate)] as [string, string]] : []),
		...(doc.supplierRef ? [['Réf. fournisseur', doc.supplierRef] as [string, string]] : []),
		...(doc.sourceNumber ? [[doc.kind === 'credit' ? 'Sur facture' : 'Référence', doc.sourceNumber] as [string, string]] : []),
		...(doc.kind === 'invoice' || doc.kind === 'credit' || doc.kind === 'bill'
			? [['Règlement', PAYMENT_LABELS[doc.paymentMethod]] as [string, string]]
			: []),
	]

	return (
		<div>
			{!embedded && (
				<div className="doc-toolbar no-print">
					<button type="button" className="btn-primary" onClick={() => window.print()}>
						Imprimer / PDF
					</button>
					<button
						type="button"
						title="Ouvre votre messagerie : joignez le PDF enregistré avec « Imprimer / PDF »"
						onClick={() => {
							const m = shareMessage(doc, company, totals.netToPay, balance)
							location.href = `mailto:${encodeURIComponent(doc.party.email)}?subject=${encodeURIComponent(m.subject)}&body=${encodeURIComponent(m.body)}`
						}}
					>
						Envoyer par e-mail
					</button>
					<button
						type="button"
						title={doc.party.phone ? 'Ouvre WhatsApp avec le message prêt à envoyer' : 'Ajoutez le téléphone du client sur la pièce'}
						disabled={!doc.party.phone}
						onClick={() => {
							const m = shareMessage(doc, company, totals.netToPay, balance)
							window.open(`https://wa.me/${whatsappNumber(doc.party.phone)}?text=${encodeURIComponent(m.body)}`, '_blank', 'noopener')
						}}
					>
						WhatsApp
					</button>
					{onClose && (
						<button type="button" onClick={onClose}>
							Retour à la liste
						</button>
					)}
					<span className="doc-count">Mise en page et papier à en-tête : Paramètres › Mon entreprise</span>
				</div>
			)}

			<div className="doc-print">
				<PrintSheet company={company} settings={s} footer={s.showLegal ? <CompanyFooter company={company} /> : null}>
					{usesGeneratedHeader(s) && <CompanyHeader company={company} />}

					<div className="doc-title-block">
						<h2>
							{info.printTitle}
							{doc.consignment ? ' (DÉPÔT)' : ''}
						</h2>
						<div className="doc-title-number">N° {doc.number}</div>
					</div>

					<div className="doc-print-boxes">
						<section className="doc-box">
							<table className="doc-ref-table">
								<tbody>
									{refs.map(([k, v]) => (
										<tr key={k}>
											<th>{k}</th>
											<td>{v}</td>
										</tr>
									))}
								</tbody>
							</table>
						</section>
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

					{iv && (
						<section className="doc-box doc-intervention">
							<strong>Intervention</strong>
							<div className="doc-intervention-grid">
								{iv.patient && <span>Patient : {iv.patient}</span>}
								{iv.patientRef && <span>Dossier / CIN : {iv.patientRef}</span>}
								{iv.surgeon && <span>Chirurgien : {iv.surgeon}</span>}
								{iv.clinic && <span>Établissement : {iv.clinic}</span>}
								{iv.date && <span>Date : {frDate(iv.date)}</span>}
								{iv.coverage && <span>Prise en charge : {iv.coverage}</span>}
							</div>
						</section>
					)}

					<table className="doc-table doc-print-lines">
						<thead>
							<tr>
								<th className="doc-col-index">#</th>
								<th>Désignation</th>
								{showTrace && <th>Lot / N° série</th>}
								{showTrace && <th>Péremption</th>}
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
							{doc.lines.map((l, i) => (
								<tr key={l.id}>
									<td className="doc-col-index">{i + 1}</td>
									<td>{l.description}</td>
									{showTrace && <td>{[l.lot, l.serial].filter(Boolean).join(' / ')}</td>}
									{showTrace && <td>{frDate(l.expiry)}</td>}
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
										<th>Taux TVA</th>
										<th className="num">Base HT</th>
										<th className="num">Montant TVA</th>
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
									{totals.stampDuty > 0 && (
										<tr>
											<td>Droit de timbre 0,25 %</td>
											<td className="num">{formatMAD(totals.stampDuty)}</td>
										</tr>
									)}
									<tr className="doc-grand-total">
										<td>{totals.stampDuty > 0 ? 'Net à payer' : 'Total TTC'}</td>
										<td className="num">{formatMAD(totals.netToPay)}</td>
									</tr>
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

					{(doc.kind === 'invoice' || doc.kind === 'credit' || doc.kind === 'quote') && (
						<p className="doc-amount-words">
							{doc.kind === 'invoice'
								? 'Arrêtée la présente facture'
								: doc.kind === 'credit'
									? 'Arrêté le présent avoir'
									: 'Arrêté le présent devis'}{' '}
							à la somme de : <strong>{amountInWordsMAD(totals.netToPay)}</strong> TTC.
						</p>
					)}

					{(terms || doc.notes) && (
						<div className="doc-terms">
							{doc.notes && <p className="doc-notes-print">{doc.notes}</p>}
							{terms && <p className="doc-terms-text">{terms}</p>}
						</div>
					)}

					{signatures && (
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
										: 'Bon pour accord : date, cachet et signature du client'}
							</div>
						</div>
					)}
				</PrintSheet>
			</div>
		</div>
	)
}
