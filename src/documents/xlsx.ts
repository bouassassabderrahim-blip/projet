// Lecture d'un classeur Excel (.xlsx) sans bibliothèque : archive ZIP + XML de la première feuille.
// Le résultat est un texte à tabulations, lu ensuite comme un copier-coller depuis Excel.

const u16 = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8)
const u32 = (b: Uint8Array, i: number) => (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0

/** Fichiers de l'archive ZIP (nom → contenu décompressé), limités à ceux demandés */
async function unzip(bytes: Uint8Array, wanted: (name: string) => boolean): Promise<Map<string, Uint8Array>> {
	// Fin du répertoire central : signature 50 4B 05 06, cherchée depuis la fin
	let end = -1
	for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65_557); i--) {
		if (u32(bytes, i) === 0x06054b50) {
			end = i
			break
		}
	}
	if (end < 0) throw new Error('Archive illisible')
	const count = u16(bytes, end + 10)
	let p = u32(bytes, end + 16)
	const out = new Map<string, Uint8Array>()
	for (let n = 0; n < count; n++) {
		if (u32(bytes, p) !== 0x02014b50) throw new Error('Archive illisible')
		const method = u16(bytes, p + 10)
		const size = u32(bytes, p + 20)
		const nameLen = u16(bytes, p + 28)
		const extraLen = u16(bytes, p + 30)
		const commentLen = u16(bytes, p + 32)
		const local = u32(bytes, p + 42)
		const name = new TextDecoder().decode(bytes.subarray(p + 46, p + 46 + nameLen))
		p += 46 + nameLen + extraLen + commentLen
		if (!wanted(name)) continue
		const start = local + 30 + u16(bytes, local + 26) + u16(bytes, local + 28)
		const data = bytes.subarray(start, start + size)
		if (method === 0) out.set(name, data)
		else if (method === 8) {
			const stream = new Blob([data as BlobPart]).stream().pipeThrough(new DecompressionStream('deflate-raw'))
			out.set(name, new Uint8Array(await new Response(stream).arrayBuffer()))
		}
	}
	return out
}

const entities: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" }
const unescapeXml = (s: string) =>
	s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e: string) =>
		e[0] === '#' ? String.fromCodePoint(e[1].toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)) : (entities[e] ?? m),
	)

/** Texte d'un élément (toutes ses balises <t>, pour le texte enrichi) */
const textOf = (xml: string) => [...xml.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map((m) => unescapeXml(m[1])).join('')

/** Colonne « AB » → 27 (base 0) */
function columnIndex(ref: string): number {
	let n = 0
	for (const c of ref.replace(/\d+$/, '')) n = n * 26 + (c.charCodeAt(0) - 64)
	return n - 1
}

/** Cellule pour un texte à tabulations (guillemets si besoin) */
const tsvCell = (s: string) => (/[\t\n\r"]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s)

/** Première feuille d'un classeur .xlsx, en texte à tabulations */
export async function xlsxToText(bytes: Uint8Array): Promise<string> {
	const files = await unzip(bytes, (n) => n === 'xl/workbook.xml' || n === 'xl/_rels/workbook.xml.rels' || n === 'xl/sharedStrings.xml' || n.startsWith('xl/worksheets/sheet'))
	const read = (name: string) => (files.has(name) ? new TextDecoder().decode(files.get(name)) : '')

	// Première feuille dans l'ordre du classeur
	let sheet = ''
	const firstSheet = read('xl/workbook.xml').match(/<sheet\b[^>]*\br:id="([^"]+)"/)
	if (firstSheet) {
		const rel = [...read('xl/_rels/workbook.xml.rels').matchAll(/<Relationship\b[^>]*>/g)].map((m) => m[0]).find((r) => r.includes(`Id="${firstSheet[1]}"`))
		const target = rel?.match(/Target="([^"]+)"/)?.[1]
		if (target) sheet = 'xl/' + target.replace(/^\/?xl\//, '').replace(/^\//, '')
	}
	if (!files.has(sheet)) sheet = [...files.keys()].filter((n) => /^xl\/worksheets\/sheet\d+\.xml$/.test(n)).sort((a, b) => a.length - b.length || a.localeCompare(b))[0] ?? ''
	if (!sheet) throw new Error('Aucune feuille dans ce classeur')

	const shared = [...read('xl/sharedStrings.xml').matchAll(/<si>([\s\S]*?)<\/si>/g)].map((m) => textOf(m[1]))
	const rows: string[][] = []
	for (const r of read(sheet).matchAll(/<row\b([^>]*)>([\s\S]*?)<\/row>/g)) {
		// Lignes vides absentes du fichier : recréées pour garder les n° de ligne d'Excel dans les messages
		const index = Number(r[1].match(/\br="(\d+)"/)?.[1] ?? rows.length + 1)
		while (rows.length < index - 1) rows.push([])
		const cells: string[] = []
		for (const c of r[2].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
			const attrs = c[1]
			const body = c[2] ?? ''
			const ref = attrs.match(/\br="([A-Z]+\d+)"/)?.[1]
			const type = attrs.match(/\bt="(\w+)"/)?.[1]
			const raw = body.match(/<v>([\s\S]*?)<\/v>/)?.[1]
			let value = ''
			if (type === 's' && raw !== undefined) value = shared[Number(raw)] ?? ''
			else if (type === 'inlineStr') value = textOf(body)
			else if (type === 'b') value = raw === '1' ? 'VRAI' : 'FAUX'
			else if (raw !== undefined) value = unescapeXml(raw)
			const col = ref ? columnIndex(ref) : cells.length
			while (cells.length < col) cells.push('')
			cells[col] = value
		}
		rows.push(cells)
	}
	return rows.map((r) => r.map(tsvCell).join('\t')).join('\n')
}
