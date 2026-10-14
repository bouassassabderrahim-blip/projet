// Comparaison et fusion d'enregistrements JSON (sans dépendance : utilisable partout)

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

export const same = (a: unknown, b: unknown) => stableStringify(a) === stableStringify(b)

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
		else if (same(r, b)) v = l
		// Compteur avant l'égalité : deux sorties de 1 sur deux postes (10 → 9 ici, 10 → 9 ailleurs) donnent 8, pas 9
		else if (deltaFields.includes(key) && typeof b === 'number' && typeof l === 'number' && typeof r === 'number') v = r + (l - b)
		else if (same(l, r)) v = l
		else {
			v = l
			conflict = true
		}
		if (v !== undefined) out[key] = v
	}
	return { result: out, conflict }
}
