import type { SyncStatus } from '../sync/engine'

interface Props {
	companyName: string
	sync?: SyncStatus | null
	onOpenSync?: () => void
	documentsCount: number
	productsCount: number
	lastBackup: string
}

/** Barre d'état : dossier, exercice, volumes, dernière sauvegarde */
function syncLabel(s: SyncStatus): { text: string; tone: string } {
	if (s.phase === 'offline') return { text: `Hors ligne${s.pending ? ` · ${s.pending} modification(s) en attente` : ''}`, tone: 'erp-status-warn' }
	if (s.phase === 'auth') return { text: 'Multi-postes : reconnexion nécessaire', tone: 'erp-status-error' }
	if (s.phase === 'error') return { text: 'Multi-postes : erreur de synchronisation', tone: 'erp-status-error' }
	if (s.phase === 'ok' && s.lastSync) return { text: `Synchronisé à ${new Date(s.lastSync).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}`, tone: 'erp-status-ok' }
	if (s.phase === 'idle' && s.message) return { text: s.message, tone: 'erp-status-ok' }
	return { text: 'Synchronisation…', tone: '' }
}

export default function StatusBar({ companyName, documentsCount, productsCount, lastBackup, sync, onOpenSync }: Props) {
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
			{sync ? (
				<button type="button" className={`erp-status-sync ${syncLabel(sync).tone}`} onClick={onOpenSync} title={sync.message || 'État de la synchronisation'}>
					● {syncLabel(sync).text}
				</button>
			) : null}
			<span className="erp-status-right">
				{sync ? 'Données partagées entre les postes' : 'Données enregistrées sur ce poste'} · {new Date().toLocaleDateString('fr-FR')}
			</span>
		</footer>
	)
}
