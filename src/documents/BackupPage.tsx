import { useState } from 'react'
import { downloadFile } from './csv'
import { LAST_BACKUP_KEY, createBackup, isBackupFile, restoreBackup } from './storage'
import { daysBetween, frDate, today } from './numbering'
import './documents.css'

function readLastBackup(): string {
	try {
		return localStorage.getItem(LAST_BACKUP_KEY) ?? ''
	} catch {
		return ''
	}
}

/** Sauvegarde et restauration de toutes les données (produits, pièces, lots, tiers, paramètres) */
export default function BackupPage() {
	const [last, setLast] = useState(readLastBackup)
	const [message, setMessage] = useState('')
	const [error, setError] = useState('')
	const age = last ? daysBetween(last, today()) : null

	function exportAll() {
		const backup = createBackup()
		downloadFile(`profitpilot-sauvegarde-${today()}.json`, JSON.stringify(backup, null, 1), 'application/json')
		try {
			localStorage.setItem(LAST_BACKUP_KEY, today())
		} catch {
			// stockage indisponible
		}
		setLast(today())
		setMessage(`Sauvegarde téléchargée (${Object.keys(backup.data).length} jeux de données).`)
	}

	function importAll(file: File | undefined) {
		if (!file) return
		const reader = new FileReader()
		reader.onload = () => {
			try {
				const data: unknown = JSON.parse(String(reader.result))
				if (!isBackupFile(data)) return setError("Ce fichier n'est pas une sauvegarde ProfitPilot.")
				const date = frDate(data.createdAt.slice(0, 10))
				if (!confirm(`Remplacer TOUTES les données actuelles par la sauvegarde du ${date} ?`)) return
				restoreBackup(data)
				location.reload()
			} catch {
				setError('Fichier illisible.')
			}
		}
		reader.readAsText(file)
	}

	return (
		<div>
			<div className={age === null || age > 7 ? 'doc-warning' : 'doc-info'}>
				{last
					? `Dernière sauvegarde : ${frDate(last)}${age ? ` (il y a ${age} jour${age > 1 ? 's' : ''})` : " (aujourd'hui)"}.`
					: 'Aucune sauvegarde effectuée.'}{' '}
				Vos données sont enregistrées uniquement dans ce navigateur : vider le cache ou changer d'ordinateur les fait
				perdre. Sauvegardez au moins une fois par semaine et gardez le fichier en lieu sûr (clé USB, Google Drive…).
			</div>

			<fieldset className="doc-panel">
				<legend>Sauvegarder</legend>
				<p>Télécharge un fichier contenant les produits, le stock, les lots, les pièces, les tiers et les paramètres.</p>
				<button type="button" className="btn-primary" onClick={exportAll}>
					Télécharger une sauvegarde complète
				</button>
			</fieldset>

			<fieldset className="doc-panel">
				<legend>Restaurer</legend>
				<p>Remplace toutes les données de ce navigateur par celles d'un fichier de sauvegarde.</p>
				<input type="file" accept="application/json,.json" onChange={(e) => importAll(e.target.files?.[0])} />
			</fieldset>

			{message && <p className="doc-info">{message}</p>}
			{error && <p className="doc-error">{error}</p>}
		</div>
	)
}
