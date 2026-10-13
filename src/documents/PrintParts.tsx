import type { CompanyInfo } from './types'

/** En-tête société généré (quand on n'imprime pas sur papier à en-tête) */
export function CompanyHeader({ company }: { company: CompanyInfo }) {
	return (
		<header className="doc-print-head">
			<div className="doc-print-company">
				{company.logo && <img className="doc-logo" src={company.logo} alt="" />}
				<div>
					<strong className="doc-company">{company.name || 'Votre entreprise'}</strong>
					<div>{company.address}</div>
					<div>{company.city}</div>
					<div>{[company.phone, company.email].filter(Boolean).join(' · ')}</div>
				</div>
			</div>
		</header>
	)
}

/** Mentions légales de l'émetteur, répétées en bas de chaque page */
export function CompanyFooter({ company }: { company: CompanyInfo }) {
	const ids = [
		company.ice && `ICE : ${company.ice}`,
		company.ifNumber && `IF : ${company.ifNumber}`,
		company.rc && `RC : ${company.rc}`,
		company.patente && `Patente : ${company.patente}`,
		company.cnss && `CNSS : ${company.cnss}`,
	].filter(Boolean)
	return (
		<footer className="doc-footer">
			<div>
				<strong>{company.name}</strong>
				{company.address ? ` · ${company.address}` : ''}
				{company.city ? `, ${company.city}` : ''}
				{company.phone ? ` · Tél. ${company.phone}` : ''}
			</div>
			{ids.length > 0 && <div>{ids.join(' · ')}</div>}
			{company.rib && (
				<div>
					{company.bank} · RIB : {company.rib}
				</div>
			)}
		</footer>
	)
}
