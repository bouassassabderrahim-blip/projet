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
	/** Fusion de deux versions modifiées en parallèle (préférée, autre) */
	merge?: (preferred: unknown, other: unknown) => unknown
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
]

export const VALUE_ID = '_'

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
	if (next === null) localStorage.removeItem(spec.key)
	else localStorage.setItem(spec.key, next)
	window.dispatchEvent(new StorageEvent('storage', { key: spec.key, oldValue, newValue: next, storageArea: localStorage }))
}

/** Ordre actuel des ids d'une collection (pour conserver l'ordre à la réécriture) */
export function localOrder(spec: CollectionSpec): string[] {
	return [...readLocal(spec).keys()]
}

/** JSON à clés triées : deux objets égaux donnent toujours le même texte (le serveur réordonne les clés) */
export function stableStringify(value: unknown): string {
	if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null'
	if (Array.isArray(value)) return '[' + value.map((v) => (v === undefined ? 'null' : stableStringify(v))).join(',') + ']'
	const obj = value as Record<string, unknown>
	const keys = Object.keys(obj)
		.filter((k) => obj[k] !== undefined)
		.sort()
	return '{' + keys.map((k) => JSON.stringify(k) + ':' + stableStringify(obj[k])).join(',') + '}'
}

/** Empreinte courte d'un enregistrement (FNV-1a 32 bits + longueur) */
export function fingerprint(value: unknown): string {
	const s = stableStringify(value)
	let h = 0x811c9dc5
	for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 0x01000193) >>> 0
	return h.toString(36) + '.' + s.length.toString(36)
}

const same = (a: unknown, b: unknown) => stableStringify(a) === stableStringify(b)

/**
 * Fusion à trois versions, champ par champ : base = dernière version serveur connue,
 * local = version de ce poste, remote = nouvelle version serveur.
 * - champ changé d'un seul côté : ce changement est gardé ;
 * - compteur changé des deux côtés : les deux variations s'additionnent (10 → 8 ici, 10 → 7 ailleurs : 5) ;
 * - autre champ changé des deux côtés : la version de ce poste l'emporte (conflit compté).
 */
export function threeWayMerge(
	base: unknown,
	local: unknown,
	remote: unknown,
	deltaFields: string[] = [],
): { result: unknown; conflict: boolean } {
	const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null && !Array.isArray(x)
	if (!isObj(base) || !isObj(local) || !isObj(remote)) return { result: local, conflict: true }
	const out: Record<string, unknown> = {}
	let conflict = false
	for (const key of new Set([...Object.keys(base), ...Object.keys(local), ...Object.keys(remote)])) {
		const b = base[key]
		const l = local[key]
		const r = remote[key]
		let v: unknown
		if (same(l, b)) v = r
		else if (same(r, b) || same(l, r)) v = l
		else if (deltaFields.includes(key) && typeof b === 'number' && typeof l === 'number' && typeof r === 'number') v = r + (l - b)
		else {
			v = l
			conflict = true
		}
		if (v !== undefined) out[key] = v
	}
	return { result: out, conflict }
}
