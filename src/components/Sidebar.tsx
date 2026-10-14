import type { PageId } from '../types'
import { PAGE_LABELS, type ModuleDef } from '../shell/navigation'

interface SidebarProps {
  module: ModuleDef
  current: PageId
  onNavigate: (page: PageId) => void
  /** Compteurs d'alertes affichés à côté des pages (factures échues, lots périmés…) */
  badges?: Partial<Record<PageId, number>>
}

/** Menu du module en cours, rubrique par rubrique */
export default function Sidebar({ module, current, onNavigate, badges }: SidebarProps) {
  return (
    <aside className="sidebar no-print">
      <div className="brand">{module.label}</div>
      <nav>
        {module.groups.map((group) => (
          <div key={group.title}>
            <div className="nav-section-title">{group.title}</div>
            {group.pages.map((id) => {
              const badge = badges?.[id]
              return (
                <button
                  key={id}
                  className={id === current ? 'nav-item active' : 'nav-item'}
                  onClick={() => onNavigate(id)}
                >
                  {PAGE_LABELS[id]}
                  {!!badge && <span className="nav-badge">{badge}</span>}
                </button>
              )
            })}
          </div>
        ))}
      </nav>
    </aside>
  )
}
