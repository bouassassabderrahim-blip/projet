// Types de la gestion commerciale : ventes, achats, stock par lot, tiers

/**
 * Ventes : quote = devis, order = bon de commande, delivery = bon de livraison (BL),
 * invoice = facture, credit = avoir.
 * Achats : purchase = commande fournisseur, receipt = bon de réception, bill = facture fournisseur.
 */
export type DocKind = 'quote' | 'order' | 'delivery' | 'invoice' | 'credit' | 'purchase' | 'receipt' | 'bill'

/** Taux de TVA en vigueur au Maroc (CGI, art. 98 à 100) */
export type TvaRate = 0 | 7 | 10 | 14 | 20

export type DocStatus = 'draft' | 'validated' | 'paid' | 'cancelled'

export type PaymentMethod = 'virement' | 'cheque' | 'especes' | 'effet' | 'carte'

export type Coverage = 'CNSS' | 'CNOPS' | 'AMO' | 'Mutuelle' | 'Privé'

/** Client ou fournisseur */
export interface Party {
	name: string
	address: string
	city: string
	ice: string // Identifiant Commun de l'Entreprise (15 chiffres)
	ifNumber: string // Identifiant fiscal
	rc: string // Registre du commerce
	phone: string
	email: string
	/** Particulier (patient) : l'ICE n'est pas exigé sur la facture */
	individual?: boolean
}

export type PartyRole = 'client' | 'supplier'

/** Fiche tiers enregistrée (clients et fournisseurs) */
export interface PartyRecord extends Party {
	id: string
	role: PartyRole
	notes: string
	/** Délai de paiement accordé, en jours */
	paymentTerms?: number
}

/**
 * Mise en page des pièces imprimées :
 * - generated : en-tête et pied de page générés à partir de la fiche société
 * - images : votre en-tête et votre pied de page (images) en haut et en bas de chaque page
 * - background : votre papier à en-tête complet (image A4) en fond de chaque page
 * - preprinted : impression sur papier déjà imprimé, on réserve seulement les marges
 */
export type LetterheadMode = 'generated' | 'images' | 'background' | 'preprinted'

export interface PrintSettings {
	mode: LetterheadMode
	headerImg?: string
	footerImg?: string
	backgroundImg?: string
	/** Marges en millimètres (haut et bas : place réservée à l'en-tête et au pied de page) */
	top: number
	bottom: number
	side: number
	/** Mentions légales (ICE, IF, RC…) en bas de page */
	showLegal: boolean
	/** Couleur des titres et bandeaux */
	accent: string
	/** Conditions imprimées par défaut sous les devis et les factures */
	quoteTerms: string
	invoiceTerms: string
}

export const defaultPrintSettings = (): PrintSettings => ({
	mode: 'generated',
	top: 15,
	bottom: 15,
	side: 15,
	showLegal: true,
	accent: '#1f4e79',
	quoteTerms: 'Devis valable 30 jours. Délai de livraison : selon disponibilité. Paiement : 60 jours à réception de facture.',
	invoiceTerms: 'Paiement à 60 jours à réception de facture. Tout retard de paiement donne lieu à des pénalités conformément à la loi 69-21.',
})

/** Informations de votre entreprise, imprimées sur chaque document */
export interface CompanyInfo extends Party {
	patente: string
	cnss: string
	bank: string
	rib: string
	/** Logo en data URL (PNG/JPEG) */
	logo?: string
	print?: PrintSettings
}

/** Suivi d'un implant laissé en dépôt chez une clinique */
export type DepotState = 'depot' | 'posed' | 'returned'

export interface DocLine {
	id: string
	productId?: string
	description: string
	quantity: number
	unitPriceHT: number
	tvaRate: TvaRate
	discount: number // remise en %
	/** Traçabilité */
	lotId?: string
	lot?: string
	serial?: string
	expiry?: string // AAAA-MM-JJ
	/** Lignes de BL en dépôt */
	depot?: DepotState
	/** Ligne de BL dépôt facturée par cette ligne (pour la remettre en dépôt si la facture est supprimée) */
	depotRef?: { docId: string; lineId: string }
}

export interface Payment {
	id: string
	date: string
	amount: number
	method: PaymentMethod
	reference: string
}

/** Intervention chirurgicale liée à une facture ou un BL */
export interface Intervention {
	patient: string
	patientRef: string // n° de dossier, CIN ou immatriculation
	surgeon: string
	clinic: string
	date: string
	coverage: Coverage | ''
}

export interface CommercialDocument {
	id: string
	kind: DocKind
	number: string // ex. FA-2026-0001
	date: string // AAAA-MM-JJ
	dueDate: string // échéance (factures) ou fin de validité (devis)
	party: Party
	lines: DocLine[]
	status: DocStatus
	paymentMethod: PaymentMethod
	notes: string
	/** Règlements reçus (ventes) ou effectués (achats) */
	payments?: Payment[]
	/** Ancien format : date d'encaissement unique */
	paidDate?: string
	/** BL en dépôt : le matériel reste chez le client jusqu'à la pose */
	consignment?: boolean
	intervention?: Intervention
	/** Numéro de la facture chez le fournisseur */
	supplierRef?: string
	/** Traçabilité : utilisateur qui a créé et validé la pièce */
	createdBy?: string
	validatedBy?: string
	/** Document d'origine (ex. le BC ayant donné ce BL) */
	sourceId?: string
	sourceNumber?: string
}

/** Lot (ou numéro de série) en stock, avec sa date de péremption */
export interface StockLot {
	id: string
	productId: string
	lot: string
	serial: string
	expiry: string
	quantity: number
	receivedDate: string
	supplier: string
}

/** Mouvement de stock (journal) : quantité signée, + entrée / − sortie */
export type MovementKind = 'in' | 'out' | 'adjust'

export interface StockMovement {
	id: string
	date: string
	productId: string
	productName: string
	lot: string
	serial: string
	quantity: number
	kind: MovementKind
	/** Pièce ou motif : « BL-2026-0003 », « Inventaire du 14/10/2026 »… */
	reference: string
	/** Stock de l'article après le mouvement */
	stockAfter?: number
}

export interface Kit {
	id: string
	name: string
	items: { productId: string; quantity: number }[]
}

export type DocSide = 'sale' | 'purchase'

export const DOC_LABELS: Record<
	DocKind,
	{ title: string; plural: string; prefix: string; newLabel: string; side: DocSide; printTitle: string }
> = {
	quote: { title: 'Devis', plural: 'Devis', prefix: 'DV', newLabel: 'Nouveau devis', side: 'sale', printTitle: 'DEVIS' },
	order: {
		title: 'Bon de commande',
		plural: 'Bons de commande',
		prefix: 'BC',
		newLabel: 'Nouveau bon de commande',
		side: 'sale',
		printTitle: 'BON DE COMMANDE',
	},
	delivery: {
		title: 'Bon de livraison',
		plural: 'Bons de livraison',
		prefix: 'BL',
		newLabel: 'Nouveau bon de livraison',
		side: 'sale',
		printTitle: 'BON DE LIVRAISON',
	},
	invoice: { title: 'Facture', plural: 'Factures', prefix: 'FA', newLabel: 'Nouvelle facture', side: 'sale', printTitle: 'FACTURE' },
	credit: { title: 'Avoir', plural: 'Avoirs', prefix: 'AV', newLabel: 'Nouvel avoir', side: 'sale', printTitle: 'AVOIR' },
	purchase: {
		title: 'Commande fournisseur',
		plural: 'Commandes fournisseurs',
		prefix: 'CF',
		newLabel: 'Nouvelle commande fournisseur',
		side: 'purchase',
		printTitle: 'BON DE COMMANDE FOURNISSEUR',
	},
	receipt: {
		title: 'Bon de réception',
		plural: 'Bons de réception',
		prefix: 'BR',
		newLabel: 'Nouveau bon de réception',
		side: 'purchase',
		printTitle: 'BON DE RÉCEPTION',
	},
	bill: {
		title: 'Facture fournisseur',
		plural: 'Factures fournisseurs',
		prefix: 'FF',
		newLabel: 'Nouvelle facture fournisseur',
		side: 'purchase',
		printTitle: 'FACTURE FOURNISSEUR',
	},
}

export const ALL_KINDS = Object.keys(DOC_LABELS) as DocKind[]

export const STATUS_LABELS: Record<DocStatus, string> = {
	draft: 'Brouillon',
	validated: 'Validé',
	paid: 'Réglé',
	cancelled: 'Annulé',
}

export const PAYMENT_LABELS: Record<PaymentMethod, string> = {
	virement: 'Virement bancaire',
	cheque: 'Chèque',
	especes: 'Espèces',
	effet: 'Effet de commerce (LCN)',
	carte: 'Carte bancaire',
}

export const COVERAGES: Coverage[] = ['CNSS', 'CNOPS', 'AMO', 'Mutuelle', 'Privé']

export const emptyParty = (): Party => ({
	name: '',
	address: '',
	city: '',
	ice: '',
	ifNumber: '',
	rc: '',
	phone: '',
	email: '',
})

export const emptyCompany = (): CompanyInfo => ({
	...emptyParty(),
	patente: '',
	cnss: '',
	bank: '',
	rib: '',
})

export const emptyIntervention = (): Intervention => ({
	patient: '',
	patientRef: '',
	surgeon: '',
	clinic: '',
	date: '',
	coverage: '',
})
