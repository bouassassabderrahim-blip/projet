// Types des documents commerciaux : facture, bon de commande, bon de livraison

/** quote = devis, order = bon de commande, delivery = bon de livraison (BL), invoice = facture */
export type DocKind = 'quote' | 'order' | 'delivery' | 'invoice'

/** Taux de TVA en vigueur au Maroc (CGI, art. 98 à 100) */
export type TvaRate = 0 | 7 | 10 | 14 | 20

export type DocStatus = 'draft' | 'validated' | 'paid' | 'cancelled'

export type PaymentMethod = 'virement' | 'cheque' | 'especes' | 'effet' | 'carte'

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
}

/** Informations de votre entreprise, imprimées sur chaque document */
export interface CompanyInfo extends Party {
	patente: string
	cnss: string
	bank: string
	rib: string
}

export interface DocLine {
	id: string
	productId?: string
	description: string
	quantity: number
	unitPriceHT: number
	tvaRate: TvaRate
	discount: number // remise en %
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
	/** Date d'encaissement, renseignée quand la facture passe en « Payée » */
	paidDate?: string
	/** Document d'origine (ex. le BC ayant donné ce BL) */
	sourceId?: string
	sourceNumber?: string
}

export const DOC_LABELS: Record<DocKind, { title: string; plural: string; prefix: string; newLabel: string }> = {
	quote: { title: 'Devis', plural: 'Devis', prefix: 'DV', newLabel: 'Nouveau devis' },
	order: { title: 'Bon de commande', plural: 'Bons de commande', prefix: 'BC', newLabel: 'Nouveau bon de commande' },
	delivery: { title: 'Bon de livraison', plural: 'Bons de livraison', prefix: 'BL', newLabel: 'Nouveau bon de livraison' },
	invoice: { title: 'Facture', plural: 'Factures', prefix: 'FA', newLabel: 'Nouvelle facture' },
}

export const STATUS_LABELS: Record<DocStatus, string> = {
	draft: 'Brouillon',
	validated: 'Validé',
	paid: 'Payée',
	cancelled: 'Annulé',
}

export const PAYMENT_LABELS: Record<PaymentMethod, string> = {
	virement: 'Virement bancaire',
	cheque: 'Chèque',
	especes: 'Espèces',
	effet: 'Effet de commerce (LCN)',
	carte: 'Carte bancaire',
}

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
