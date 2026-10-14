import type { PageId } from '../types'

export type ModuleId = 'home' | 'sales' | 'purchases' | 'stock' | 'finance' | 'analysis' | 'settings'

export interface ModuleDef {
	id: ModuleId
	label: string
	/** Pages du module, regroupées par rubrique dans le menu de gauche */
	groups: { title: string; pages: PageId[] }[]
}

/** Plan de l'application, découpée en modules comme un ERP */
export const MODULES: ModuleDef[] = [
	{ id: 'home', label: 'Accueil', groups: [{ title: 'Accueil', pages: ['home'] }] },
	{
		id: 'sales',
		label: 'Ventes',
		groups: [
			{ title: 'Pièces de vente', pages: ['quotes', 'orders', 'deliveries', 'invoices', 'credits'] },
			{ title: 'Suivi', pages: ['depots', 'clients'] },
		],
	},
	{
		id: 'purchases',
		label: 'Achats',
		groups: [
			{ title: "Pièces d'achat", pages: ['purchases', 'receipts', 'bills'] },
			{ title: 'Tiers', pages: ['suppliers'] },
		],
	},
	{
		id: 'stock',
		label: 'Stocks',
		groups: [
			{ title: 'Articles', pages: ['catalog', 'kits', 'import'] },
			{ title: 'Stock', pages: ['stock', 'alerts', 'movements', 'inventory'] },
			{ title: 'Traçabilité', pages: ['lots'] },
		],
	},
	{
		id: 'finance',
		label: 'Finance',
		groups: [
			{ title: 'Trésorerie', pages: ['schedule'] },
			{ title: 'Fiscalité', pages: ['vat'] },
		],
	},
	{
		id: 'analysis',
		label: 'Pilotage',
		groups: [
			{ title: 'Tableaux de bord', pages: ['dashboard', 'stats'] },
			{ title: 'Rentabilité', pages: ['products', 'breakeven', 'recommendations'] },
			{ title: 'Simulation', pages: ['simulator', 'compare', 'decision'] },
		],
	},
	{
		id: 'settings',
		label: 'Paramètres',
		groups: [
			{ title: 'Dossier', pages: ['company', 'backup'] },
			{ title: 'Administration', pages: ['users', 'audit', 'sync'] },
		],
	},
]

/** Libellés courts (menu, onglets) */
export const PAGE_LABELS: Record<PageId, string> = {
	home: 'Accueil',
	dashboard: 'Tableau de bord',
	stats: 'Statistiques ventes',
	products: 'Rentabilité produits',
	breakeven: 'Résultat & seuil',
	recommendations: 'Recommandations',
	simulator: 'Simulateur',
	compare: 'Comparaison',
	decision: 'Garder ou abandonner',
	catalog: 'Articles',
	stock: 'État du stock',
	alerts: 'Alertes stock',
	movements: 'Mouvements',
	inventory: 'Inventaire',
	lots: 'Lots & traçabilité',
	kits: 'Kits',
	import: 'Import CSV',
	quotes: 'Devis',
	orders: 'Bons de commande',
	deliveries: 'Bons de livraison',
	depots: 'Dépôts cliniques',
	invoices: 'Factures',
	credits: 'Avoirs',
	clients: 'Clients',
	purchases: 'Commandes fournisseurs',
	receipts: 'Réceptions',
	bills: 'Factures fournisseurs',
	suppliers: 'Fournisseurs',
	schedule: 'Échéancier & trésorerie',
	vat: 'Déclaration de TVA',
	company: 'Société & mise en page',
	backup: 'Sauvegarde',
	users: 'Utilisateurs & droits',
	audit: "Journal d'activité",
	sync: 'Multi-postes',
}

/** Pages réservées à l'administrateur */
export const ADMIN_PAGES: PageId[] = ['users', 'audit', 'sync']

export function moduleOf(page: PageId): ModuleDef {
	return MODULES.find((m) => m.groups.some((g) => g.pages.includes(page))) ?? MODULES[0]
}
