interface Props {
	companyName: string
	documentsCount: number
	productsCount: number
	lastBackup: string
}

/** Barre d'état : dossier, exercice, volumes, dernière sauvegarde */
export default function StatusBar({ companyName, documentsCount, productsCount, lastBackup }: Props) {
	const year = new Date().getFullYear()
	return (
		<footer className="erp-status no-print">
			<span>Dossier : {companyName || '—'}</span>
			<span>Exercice {year}</span>
			<span>{documentsCount} pièce(s)</span>
			<span>{productsCount} article(s)</span>
			<span className={lastBackup ? undefined : 'erp-status-warn'}>
				Sauvegarde : {lastBackup ? new Date(lastBackup + 'T00:00:00').toLocaleDateString('fr-FR') : 'jamais'}
			</span>
			<span className="erp-status-right">Données enregistrées sur ce poste · {new Date().toLocaleDateString('fr-FR')}</span>
		</footer>
	)
}
