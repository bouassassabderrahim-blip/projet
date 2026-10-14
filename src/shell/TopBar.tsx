import { useState } from 'react'
import Icon from './icons'
import type { PageId } from '../types'
import type { DocKind } from '../documents/types'

export interface Notification {
	id: string
	text: string
	severity: 'danger' | 'warning' | 'info'
	page: PageId
}

interface Props {
	companyName: string
	notifications: Notification[]
	onSearch: () => void
	onNavigate: (page: PageId) => void
	onCreate: (kind: DocKind) => void
}

const CREATE: { kind: DocKind; label: string }[] = [
	{ kind: 'quote', label: 'Devis' },
	{ kind: 'order', label: 'Bon de commande' },
	{ kind: 'delivery', label: 'Bon de livraison' },
	{ kind: 'invoice', label: 'Facture' },
	{ kind: 'credit', label: 'Avoir' },
	{ kind: 'purchase', label: 'Commande fournisseur' },
	{ kind: 'receipt', label: 'Bon de réception' },
	{ kind: 'bill', label: 'Facture fournisseur' },
]

const isMac = typeof navigator !== 'undefined' && /Mac/.test(navigator.platform)

/** Barre supérieure : dossier, recherche globale, création rapide, notifications */
export default function TopBar({ companyName, notifications, onSearch, onNavigate, onCreate }: Props) {
	const [menu, setMenu] = useState<'create' | 'notif' | null>(null)
	const toggle = (m: 'create' | 'notif') => setMenu((cur) => (cur === m ? null : m))
	const danger = notifications.filter((n) => n.severity === 'danger').length

	return (
		<header className="erp-topbar no-print">
			<button type="button" className="erp-brand" onClick={() => onNavigate('home')}>
				<span className="erp-logo">PP</span>
				<span>
					ProfitPilot <small>ERP</small>
				</span>
			</button>
			<span className="erp-dossier" title="Dossier ouvert">
				{companyName || 'Dossier sans nom'}
			</span>

			<button type="button" className="erp-search-trigger" onClick={onSearch}>
				<Icon name="search" />
				<span>Rechercher…</span>
				<kbd>{isMac ? '⌘' : 'Ctrl'} K</kbd>
			</button>

			<div className="erp-top-actions">
				<div className="erp-menu-wrap">
					<button type="button" className="erp-create" onClick={() => toggle('create')} aria-expanded={menu === 'create'}>
						<Icon name="plus" /> Créer
					</button>
					{menu === 'create' && (
						<div className="erp-menu" onMouseLeave={() => setMenu(null)}>
							{CREATE.map((c, i) => (
								<button
									key={c.kind}
									type="button"
									className={i === 5 ? 'erp-menu-sep' : undefined}
									onClick={() => {
										setMenu(null)
										onCreate(c.kind)
									}}
								>
									{c.label}
								</button>
							))}
						</div>
					)}
				</div>

				<div className="erp-menu-wrap">
					<button
						type="button"
						className="erp-icon-btn"
						title="Notifications"
						onClick={() => toggle('notif')}
						aria-expanded={menu === 'notif'}
					>
						<Icon name="bell" size={18} />
						{notifications.length > 0 && (
							<span className={`erp-notif-count ${danger ? 'erp-notif-danger' : ''}`}>{notifications.length}</span>
						)}
					</button>
					{menu === 'notif' && (
						<div className="erp-menu erp-notif-menu" onMouseLeave={() => setMenu(null)}>
							<div className="erp-menu-title">Notifications</div>
							{notifications.length === 0 ? (
								<p className="erp-menu-empty">Rien à signaler.</p>
							) : (
								notifications.map((n) => (
									<button
										key={n.id}
										type="button"
										className={`erp-notif erp-notif-${n.severity}`}
										onClick={() => {
											setMenu(null)
											onNavigate(n.page)
										}}
									>
										{n.text}
									</button>
								))
							)}
						</div>
					)}
				</div>

				<button type="button" className="erp-icon-btn" title="Paramètres" onClick={() => onNavigate('company')}>
					<Icon name="settings" size={18} />
				</button>
			</div>
		</header>
	)
}
