import type { ModuleId } from '../shell/navigation'

/** Niveau d'accès à un module */
export type Level = 'none' | 'read' | 'write'

/** Modules soumis à droits (l'accueil est toujours visible) */
export type SecuredModule = Exclude<ModuleId, 'home'>

export const SECURED_MODULES: { id: SecuredModule; label: string }[] = [
	{ id: 'sales', label: 'Ventes' },
	{ id: 'purchases', label: 'Achats' },
	{ id: 'stock', label: 'Stocks' },
	{ id: 'finance', label: 'Finance' },
	{ id: 'analysis', label: 'Pilotage' },
	{ id: 'settings', label: 'Paramètres' },
]

export type Action = 'validate' | 'payments' | 'delete' | 'costs'

export const ACTIONS: { id: Action; label: string; hint: string }[] = [
	{ id: 'validate', label: 'Valider les pièces', hint: 'devis, BL, factures, réceptions…' },
	{ id: 'payments', label: 'Saisir les règlements', hint: 'encaissements clients et paiements fournisseurs' },
	{ id: 'delete', label: 'Supprimer des brouillons', hint: 'et annuler des pièces validées' },
	{ id: 'costs', label: 'Voir les coûts et les marges', hint: "prix d'achat, marges, valeur du stock" },
]

export interface Permissions {
	modules: Record<SecuredModule, Level>
	actions: Record<Action, boolean>
}

export type RoleId = 'admin' | 'sales' | 'warehouse' | 'accountant' | 'viewer' | 'custom'

export interface User {
	id: string
	name: string
	login: string
	role: RoleId
	pinHash: string
	salt: string
	active: boolean
	permissions: Permissions
	createdAt: string
	lastLogin?: string
}

export interface AuditEntry {
	id: string
	at: string // date ISO
	user: string
	action: string
	detail: string
}

export interface AccessSettings {
	/** Verrouillage automatique après inactivité (minutes, 0 = jamais) */
	lockMinutes: number
}

const all = (level: Level): Record<SecuredModule, Level> => ({
	sales: level,
	purchases: level,
	stock: level,
	finance: level,
	analysis: level,
	settings: level,
})

/** Profils types, modifiables ensuite utilisateur par utilisateur */
export const ROLES: { id: RoleId; label: string; description: string; permissions: Permissions }[] = [
	{
		id: 'admin',
		label: 'Administrateur',
		description: 'Accès complet, gestion des utilisateurs et du journal',
		permissions: { modules: all('write'), actions: { validate: true, payments: true, delete: true, costs: true } },
	},
	{
		id: 'sales',
		label: 'Commercial',
		description: 'Devis, commandes, BL et factures ; consulte le stock',
		permissions: {
			modules: { ...all('none'), sales: 'write', stock: 'read' },
			actions: { validate: true, payments: false, delete: true, costs: false },
		},
	},
	{
		id: 'warehouse',
		label: 'Magasinier',
		description: 'Stock, lots, réceptions, BL et dépôts',
		permissions: {
			modules: { ...all('none'), sales: 'read', purchases: 'write', stock: 'write' },
			actions: { validate: true, payments: false, delete: false, costs: false },
		},
	},
	{
		id: 'accountant',
		label: 'Comptable',
		description: 'Factures, règlements, achats, trésorerie et TVA',
		permissions: {
			modules: { ...all('read'), sales: 'write', purchases: 'write', finance: 'write', settings: 'none' },
			actions: { validate: true, payments: true, delete: false, costs: true },
		},
	},
	{
		id: 'viewer',
		label: 'Consultation',
		description: 'Voit tout, ne modifie rien',
		permissions: { modules: { ...all('read'), settings: 'none' }, actions: { validate: false, payments: false, delete: false, costs: false } },
	},
]

export const ROLE_LABELS: Record<RoleId, string> = {
	admin: 'Administrateur',
	sales: 'Commercial',
	warehouse: 'Magasinier',
	accountant: 'Comptable',
	viewer: 'Consultation',
	custom: 'Personnalisé',
}

export const rolePermissions = (role: RoleId): Permissions =>
	structuredClone((ROLES.find((r) => r.id === role) ?? ROLES[ROLES.length - 1]).permissions)
