import Icon from './icons'
import { MODULES, type ModuleId } from './navigation'
import type { PageId } from '../types'

interface Props {
	current: ModuleId
	onOpen: (page: PageId) => void
	/** Alertes par module (pastille) */
	badges: Partial<Record<ModuleId, number>>
}

/** Ruban des modules : Accueil, Ventes, Achats, Stocks, Finance, Pilotage, Paramètres */
export default function ModuleBar({ current, onOpen, badges }: Props) {
	return (
		<nav className="erp-modules no-print" aria-label="Modules">
			{MODULES.map((m, i) => (
				<button
					key={m.id}
					type="button"
					className={`erp-module ${m.id === current ? 'erp-module-active' : ''}`}
					title={`${m.label} (Alt+${i + 1})`}
					onClick={() => onOpen(m.groups[0].pages[0])}
				>
					<Icon name={m.id} />
					{m.label}
					{!!badges[m.id] && <span className="nav-badge">{badges[m.id]}</span>}
				</button>
			))}
		</nav>
	)
}
