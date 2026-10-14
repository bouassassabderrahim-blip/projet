import type { ReactNode } from 'react'

/** Écran en lecture seule : bandeau d'information et champs désactivés si demandé */
export function ReadOnlyArea({ readOnly, lock, children }: { readOnly: boolean; lock: boolean; children: ReactNode }) {
	if (!readOnly) return <>{children}</>
	return (
		<>
			<p className="access-readonly-banner no-print">Lecture seule : vos droits ne permettent pas de modifier cet écran.</p>
			{lock ? (
				<fieldset disabled className="access-readonly">
					{children}
				</fieldset>
			) : (
				children
			)}
		</>
	)
}

export function AccessDenied() {
	return (
		<div className="access-denied">
			<strong>Accès non autorisé</strong>
			Vos droits ne permettent pas d'ouvrir cet écran. Demandez à l'administrateur de modifier votre profil.
		</div>
	)
}
