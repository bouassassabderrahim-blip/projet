import type { PageId } from '../types'

interface SidebarProps {
  current: PageId
  onNavigate: (page: PageId) => void
  /** Petit compteur affiché à côté d'une page (ex. factures en retard) */
  badges?: Partial<Record<PageId, number>>
}

const sections: { title: string; items: { id: PageId; label: string }[] }[] = [
  {
    title: 'Pilotage',
    items: [
      { id: 'dashboard', label: 'Tableau de bord' },
      { id: 'products', label: 'Rentabilité produits' },
      { id: 'breakeven', label: 'Résultat & seuil' },
      { id: 'recommendations', label: 'Recommandations' },
    ],
  },
  {
    title: 'Produits & stock',
    items: [
      { id: 'catalog', label: 'Mes produits' },
      { id: 'stock', label: 'Stock' },
      { id: 'import', label: 'Import CSV' },
      { id: 'simulator', label: 'Simulateur' },
      { id: 'compare', label: 'Comparaison' },
      { id: 'decision', label: 'Garder ou abandonner' },
    ],
  },
  {
    title: 'Ventes',
    items: [
      { id: 'quotes', label: 'Devis' },
      { id: 'orders', label: 'Bons de commande' },
      { id: 'deliveries', label: 'Bons de livraison' },
      { id: 'invoices', label: 'Factures' },
      { id: 'vat', label: 'Déclaration TVA' },
    ],
  },
  {
    title: 'Paramètres',
    items: [{ id: 'company', label: 'Mon entreprise' }],
  },
]

export default function Sidebar({ current, onNavigate, badges }: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="brand">ProfitPilot</div>
      <nav>
        {sections.map((section) => (
          <div key={section.title}>
            <div
              style={{
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: 1,
                textTransform: 'uppercase',
                opacity: 0.6,
                margin: '16px 0 4px',
              }}
            >
              {section.title}
            </div>
            {section.items.map((item) => {
              const badge = badges?.[item.id]
              return (
                <button
                  key={item.id}
                  className={item.id === current ? 'nav-item active' : 'nav-item'}
                  onClick={() => onNavigate(item.id)}
                >
                  {item.label}
                  {!!badge && (
                    <span
                      title="Factures en retard"
                      style={{
                        marginLeft: 8,
                        padding: '0 7px',
                        borderRadius: 999,
                        fontSize: 12,
                        background: '#f59e0b',
                        color: '#111827',
                      }}
                    >
                      {badge}
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        ))}
      </nav>
    </aside>
  )
}
