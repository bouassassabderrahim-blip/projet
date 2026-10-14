// Données synchronisées : chaque clé du stockage local devient une « collection » d'enregistrements
import { mergeDocument, protectDocument } from './merge'

export interface CollectionSpec {
	/** Nom côté serveur */
	name: string
	/** Clé du localStorage */
	key: string
	/** array : liste d'objets ayant un id ; value : une seule valeur (id « _ ») */
	kind: 'array' | 'value'
	/** Tableau rangé dans un champ d'un objet (array), ou objet privé de ce champ (value) */
	field?: string
	/** Journal : les suppressions locales (purge) ne sont jamais propagées */
	appendOnly?: boolean
	/** Nombre maximum d'éléments gardés sur ce poste (les plus récents selon sortKey) */
	maxLocal?: number
	sortKey?: string
	/**
	 * Règles métier de fusion : local = version de ce poste, remote = version serveur,
	 * base = dernière version commune (absente si ce poste n'a rien modifié : la version serveur est alors préférée)
	 */
	merge?: (local: unknown, remote: unknown, base: unknown | undefined) => { result: unknown; conflict: boolean }
	/** Enregistrement qu'une suppression venue d'ailleurs ne doit pas effacer */
	protect?: (record: unknown) => boolean
	/** Compteurs : en cas de modification sur deux postes, les variations s'additionnent (stock, quantité) */
	deltaFields?: string[]
}

export const COLLECTIONS: CollectionSpec[] = [
	{ name: 'documents', key: 'profitpilot:documents:v1', kind: 'array', merge: mergeDocument, protect: protectDocument },
	{ name: 'parties', key: 'profitpilot:parties:v1', kind: 'array' },
	{ name: 'products', key: 'profitpilot:v1', kind: 'array', field: 'products', deltaFields: ['stock'] },
	{ name: 'products-meta', key: 'profitpilot:v1', kind: 'value', field: 'products' },
	{ name: 'lots', key: 'profitpilot:lots:v1', kind: 'array', deltaFields: ['quantity'] },
	{ name: 'kits', key: 'profitpilot:kits:v1', kind: 'array' },
	{ name: 'movements', key: 'profitpilot:movements:v1', kind: 'array', appendOnly: true },
	{ name: 'fixed-costs', key: 'profitpilot:fixed:v1', kind: 'array' },
	{ name: 'users', key: 'profitpilot:users:v1', kind: 'array' },
	{ name: 'audit', key: 'profitpilot:audit:v1', kind: 'array', appendOnly: true, maxLocal: 5000, sortKey: 'at' },
	{ name: 'company', key: 'profitpilot:company:v1', kind: 'value' },
	{ name: 'access', key: 'profitpilot:access:v1', kind: 'value' },
	{ name: 'cash', key: 'profitpilot:cash:v1', kind: 'value' },
	{ name: 'currency', key: 'profitpilot:currency:v1', kind: 'value' },
	{ name: 'stock-period', key: 'profitpilot:stock-period:v1', kind: 'value' },
	{ name: 'numbering', key: 'profitpilot:numbering:v1', kind: 'value' },
]

export const VALUE_ID = '_'

/** Le navigateur refuse d'enregistrer : rien n'est marqué comme reçu, tout sera réappliqué plus tard */
export class StorageFullError extends Error {}

type Rec = Record<string, unknown> & { id: string }

const isRec = (x: unknown): x is Rec =>
	typeof x === 'object' && x !== null && typeof (x as { id?: unknown }).id === 'string'

function readRaw(key: string): string | null {
	try {
		return localStorage.getItem(key)
	} catch {
		return null
	}
}

function parse(raw: string | null): unknown {
	if (raw === null) return undefined
	try {
		return JSON.parse(raw)
	} catch {
		return undefined
	}
}

/** Enregistrements locaux d'une collection, indexés par id */
export function readLocal(spec: CollectionSpec): Map<string, unknown> {
	const raw = readRaw(spec.key)
	const out = new Map<string, unknown>()
	if (spec.kind === 'value') {
		if (raw === null) return out
		if (spec.field) {
			const obj = parse(raw)
			if (typeof obj === 'object' && obj !== null) {
				const rest = { ...(obj as Record<string, unknown>) }
				delete rest[spec.field]
				out.set(VALUE_ID, rest)
			}
		} else out.set(VALUE_ID, { raw })
		return out
	}
	const data = parse(raw)
	const list = spec.field ? (data as Record<string, unknown> | undefined)?.[spec.field] : data
	if (Array.isArray(list)) for (const item of list) if (isRec(item)) out.set(item.id, item)
	return out
}

/** Écrit une collection et prévient l'application (événement « storage » comme pour un autre onglet) */
export function writeLocal(spec: CollectionSpec, records: Map<string, unknown>, order: string[]) {
	const oldValue = readRaw(spec.key)
	let next: string | null
	if (spec.kind === 'value') {
		const v = records.get(VALUE_ID) as Record<string, unknown> | undefined
		if (spec.field) {
			const obj = (parse(oldValue) as Record<string, unknown> | undefined) ?? {}
			next = JSON.stringify({ ...(v ?? {}), [spec.field]: obj[spec.field] ?? [] })
		} else next = v && typeof v.raw === 'string' ? v.raw : null
	} else {
		// On garde l'ordre local existant, les nouveaux éléments à la fin
		let list = order.filter((id) => records.has(id)).map((id) => records.get(id))
		if (spec.maxLocal && list.length > spec.maxLocal) {
			const key = spec.sortKey ?? 'id'
			list = [...list]
				.sort((a, b) => String((a as Rec)[key]).localeCompare(String((b as Rec)[key])))
				.slice(-spec.maxLocal)
		}
		if (spec.field) {
			const obj = (parse(oldValue) as Record<string, unknown> | undefined) ?? {}
			next = JSON.stringify({ ...obj, [spec.field]: list })
		} else next = JSON.stringify(list)
	}
	if (next === oldValue) return
	try {
		if (next === null) localStorage.removeItem(spec.key)
		else localStorage.setItem(spec.key, next)
	} catch {
		throw new StorageFullError(
			'Stockage du navigateur plein : les modifications des autres postes ne peuvent plus être enregistrées ici. Libérez de la place (Paramètres › Sauvegarde) puis rechargez la page.',
		)
	}
	window.dispatchEvent(new StorageEvent('storage', { key: spec.key, oldValue, newValue: next, storageArea: localStorage }))
}

/** Ordre actuel des ids d'une collection (pour conserver l'ordre à la réécriture) */
export function localOrder(spec: CollectionSpec): string[] {
	return [...readLocal(spec).keys()]
}

export { fingerprint, stableStringify, threeWayMerge } from './json'
