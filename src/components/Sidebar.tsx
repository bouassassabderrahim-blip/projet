import type { PageId } from '../types'

interface SidebarProps {
  current: PageId
  onNavigate: (page: PageId) => void
  /** Compteurs d'alertes affichés à côté des pages (factures échues, lots périmés…) */
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
    title: 'Articles & stock',
    items: [
      { id: 'catalog', label: 'Mes produits' },
      { id: 'stock', label: 'Stock' },
      { id: 'lots', label: 'Lots & traçabilité' },
      { id: 'kits', label: 'Kits' },
      { id: 'import', label: 'Import CSV' },
    ],
  },
  {
    title: 'Ventes',
    items: [
      { id: 'quotes', label: 'Devis' },
      { id: 'orders', label: 'Bons de commande' },
      { id: 'deliveries', label: 'Bons de livraison' },
      { id: 'depots', label: 'Dépôts cliniques' },
      { id: 'invoices', label: 'Factures' },
      { id: 'credits', label: 'Avoirs' },
      { id: 'clients', label: 'Clients' },
    ],
  },
  {
    title: 'Achats',
    items: [
      { id: 'purchases', label: 'Commandes fournisseurs' },
      { id: 'receipts', label: 'Réceptions' },
      { id: 'bills', label: 'Factures fournisseurs' },
      { id: 'suppliers', label: 'Fournisseurs' },
    ],
  },
  {
    title: 'Analyse & fiscalité',
    items: [
      { id: 'vat', label: 'Déclaration de TVA' },
      { id: 'simulator', label: 'Simulateur' },
      { id: 'compare', label: 'Comparaison' },
      { id: 'decision', label: 'Garder ou abandonner' },
    ],
  },
  {
    title: 'Paramètres',
    items: [
      { id: 'company', label: 'Mon entreprise' },
      { id: 'backup', label: 'Sauvegarde' },
    ],
  },
]

export default function Sidebar({ current, onNavigate, badges }: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="brand">
        ProfitPilot
        <small>Gestion commerciale</small>
      </div>
      <nav>
        {sections.map((section) => (
          <div key={section.title}>
            <div className="nav-section-title">{section.title}</div>
            {section.items.map((item) => {
              const badge = badges?.[item.id]
              return (
                <button
                  key={item.id}
                  className={item.id === current ? 'nav-item active' : 'nav-item'}
                  onClick={() => onNavigate(item.id)}
                >
                  {item.label}
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
