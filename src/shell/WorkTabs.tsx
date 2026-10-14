import Icon from './icons'
import { PAGE_LABELS } from './navigation'
import type { PageId } from '../types'

interface Props {
	tabs: PageId[]
	current: PageId
	onOpen: (page: PageId) => void
	onClose: (page: PageId) => void
}

/** Onglets des écrans ouverts, pour passer de l'un à l'autre sans repasser par le menu */
export default function WorkTabs({ tabs, current, onOpen, onClose }: Props) {
	if (tabs.length <= 1) return null
	return (
		<div className="erp-tabs no-print" role="tablist">
			{tabs.map((t) => (
				<div key={t} className={`erp-tab ${t === current ? 'erp-tab-active' : ''}`} role="tab" aria-selected={t === current}>
					<button type="button" className="erp-tab-label" onClick={() => onOpen(t)}>
						{PAGE_LABELS[t]}
					</button>
					<button type="button" className="erp-tab-close" title="Fermer l'onglet" onClick={() => onClose(t)}>
						<Icon name="close" size={12} />
					</button>
				</div>
			))}
		</div>
	)
}
