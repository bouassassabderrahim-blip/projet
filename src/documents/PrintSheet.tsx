import type { CSSProperties, ReactNode } from 'react'
import { printSettingsOf } from './printSettings'
import type { CompanyInfo, PrintSettings } from './types'

interface Props {
	company: CompanyInfo
	/** Réglages à appliquer (aperçu en direct depuis les paramètres) */
	settings?: PrintSettings
	/** Pied de page (mentions légales) quand le papier n'en a pas */
	footer?: ReactNode
	children: ReactNode
}

/**
 * Feuille A4 : place le papier à en-tête (image d'en-tête, de pied de page ou fond complet)
 * et réserve les marges. À l'impression, l'en-tête et le pied de page se répètent sur chaque page
 * (éléments fixes) et les marges sont réservées par l'en-tête et le pied d'un tableau englobant,
 * que le navigateur répète lui aussi sur chaque page.
 */
export default function PrintSheet({ company, settings, footer, children }: Props) {
	const s = settings ?? printSettingsOf(company)
	const style = {
		'--doc-accent': s.accent,
		'--sheet-top': `${s.top}mm`,
		'--sheet-bottom': `${s.bottom}mm`,
		'--sheet-side': `${s.side}mm`,
	} as CSSProperties

	return (
		<div className={`doc-sheet doc-sheet-${s.mode}`} style={style}>
			{/* Page imprimée bord à bord : les marges sont gérées par la feuille */}
			<style>{'@page { size: A4; margin: 0; }'}</style>
			{s.mode === 'background' && s.backgroundImg && <img className="sheet-bg" src={s.backgroundImg} alt="" />}
			{s.mode === 'images' && s.headerImg && <img className="sheet-header" src={s.headerImg} alt="" />}
			{s.mode === 'images' && s.footerImg && <img className="sheet-footer" src={s.footerImg} alt="" />}
			{s.mode === 'preprinted' && <div className="sheet-preprinted no-print">Zone réservée au papier pré-imprimé</div>}

			<table className="sheet-frame">
				<thead>
					<tr>
						<td>
							<div className="sheet-space-top" />
						</td>
					</tr>
				</thead>
				<tfoot>
					<tr>
						<td>
							<div className="sheet-space-bottom">{footer}</div>
						</td>
					</tr>
				</tfoot>
				<tbody>
					<tr>
						<td className="sheet-body">{children}</td>
					</tr>
				</tbody>
			</table>
		</div>
	)
}
