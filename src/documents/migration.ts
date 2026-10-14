// Reprise des données d'un ancien logiciel de gestion (Sage, Ciel, EBP, Excel…) :
// lecture des exports, reconnaissance des colonnes, conversion en fiches ProfitPilot
import type { Product } from '../types'
import { addDays, newId } from './numbering'
import { computeTotals, round2 } from './tva'
import type { CommercialDocument, DocKind, DocLine, PartyRecord, PartyRole, StockLot, TvaRate } from './types'

// ---------- Lecture des fichiers ----------

/** Texte d'un fichier : UTF-8, UTF-16 (Excel « Texte Unicode ») ou Windows-1252 (exports Sage, Ciel, EBP) */
export function decodeBytes(bytes: Uint8Array): string {
	if (bytes[0] === 0xff && bytes[1] === 0xfe) return new TextDecoder('utf-16le').decode(bytes.subarray(2))
	if (bytes[0] === 0xfe && bytes[1] === 0xff) return new TextDecoder('utf-16be').decode(bytes.subarray(2))
	try {
		return new TextDecoder('utf-8', { fatal: true }).decode(bytes).replace(/^\uFEFF/, '')
	} catch {
		return new TextDecoder('windows-1252').decode(bytes)
	}
}

/** Nature d'un fichier : archive ZIP (.xlsx, .ods), ancien classeur Excel (.xls) ou texte (CSV) */
export function fileKind(bytes: Uint8Array): 'zip' | 'ole' | 'text' {
	if (bytes[0] === 0x50 && bytes[1] === 0x4b) return 'zip'
	if (bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0) return 'ole'
	return 'text'
}

const DELIMITERS = ['\t', ';', ',', '|']

function countOutsideQuotes(line: string, delimiter: string): number {
	let n = 0
	let quoted = false
	for (const c of line) {
		if (c === '"') quoted = !quoted
		else if (c === delimiter && !quoted) n++
	}
	return n
}

/** Séparateur le plus régulier sur les premières lignes (tabulation pour un copier-coller depuis Excel) */
export function detectDelimiter(text: string): string {
	const lines = text
		.split(/\r\n|\n|\r/)
		.filter((l) => l.trim())
		.slice(0, 30)
	let best = ';'
	let bestScore = 0
	for (const d of DELIMITERS) {
		const counts = lines.map((l) => countOutsideQuotes(l, d)).filter((c) => c > 0)
		if (counts.length === 0) continue
		const freq = new Map<number, number>()
		for (const c of counts) freq.set(c, (freq.get(c) ?? 0) + 1)
		const [mode, times] = [...freq.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0]
		// Le plus de lignes au même nombre de colonnes, puis le plus de colonnes
		const score = times * 1000 + mode
		if (score > bestScore) {
			best = d
			bestScore = score
		}
	}
	return best
}

/** Enregistrements (cellules + n° de ligne dans le fichier) ; guillemets, guillemets doublés et retours à la ligne dans une cellule acceptés */
export function parseRows(text: string, delimiter: string): { cells: string[]; line: number }[] {
	const rows: { cells: string[]; line: number }[] = []
	let row: string[] = []
	let cell = ''
	let quoted = false
	let line = 1
	let start = 1
	for (let i = 0; i < text.length; i++) {
		const c = text[i]
		if (c === '\n' || (c === '\r' && text[i + 1] !== '\n')) line++
		if (quoted) {
			if (c !== '"') cell += c
			else if (text[i + 1] === '"') {
				cell += '"'
				i++
			} else quoted = false
		} else if (c === '"' && cell.trim() === '') {
			quoted = true
			cell = ''
		} else if (c === delimiter) {
			row.push(cell)
			cell = ''
		} else if (c === '\n' || c === '\r') {
			if (c === '\r' && text[i + 1] === '\n') {
				i++
				line++
			}
			row.push(cell)
			rows.push({ cells: row, line: start })
			row = []
			cell = ''
			start = line
		} else cell += c
	}
	if (cell !== '' || row.length) {
		row.push(cell)
		rows.push({ cells: row, line: start })
	}
	return rows
		.map((r) => ({ cells: r.cells.map((x) => x.trim()), line: r.line }))
		.filter((r) => r.cells.some((x) => x !== ''))
}

export interface Table {
	headers: string[]
	rows: string[][]
	/** N° de ligne dans le fichier de chaque ligne de données (pour les messages) */
	lines: number[]
	hasHeader: boolean
}

const looksLikeValue = (s: string) => s !== '' && (parseNumber(s) !== null || parseDate(s) !== null)

/**
 * Tableau lu dans un export. Les lignes de titre au-dessus du tableau (« Liste des clients », date d'édition…)
 * sont ignorées ; la ligne des titres de colonnes est reconnue seule (hasHeader permet de forcer le choix).
 */
export function readTable(text: string, hasHeader?: boolean): Table {
	const all = parseRows(text, detectDelimiter(text))
	const width = all.reduce((w, r) => Math.max(w, r.cells.length), 0)
	let start = all.findIndex((r, i) => i < 15 && r.cells.filter((x) => x !== '').length >= Math.max(2, Math.ceil(width * 0.5)))
	if (start < 0) start = 0
	const body = all.slice(start)
	const header = hasHeader ?? (body.length > 0 && !body[0].cells.some(looksLikeValue))
	const data = header ? body.slice(1) : body
	return {
		headers: Array.from({ length: width }, (_, i) => (header ? body[0]?.cells[i] : '') || `Colonne ${i + 1}`),
		rows: data.map((r) => Array.from({ length: width }, (_, i) => r.cells[i] ?? '')),
		lines: data.map((r) => r.line),
		hasHeader: header,
	}
}

// ---------- Valeurs ----------

/** Nombre au format français ou anglais : « 1 234,56 », « 1.234,56 », « 1,234.56 », « 1234.56 DH », « (12,50) » */
export function parseNumber(raw: string): number | null {
	let s = raw.trim().replace(/[\s\u00a0\u202f']/g, '')
	s = s.replace(/(mad|dhs?|dirhams?|€|eur)$/i, '').replace(/^(mad|dhs?)/i, '')
	if (!s) return null
	let negative = false
	if (/^\(.*\)$/.test(s)) {
		negative = true
		s = s.slice(1, -1)
	}
	if (s.endsWith('-')) {
		negative = !negative
		s = s.slice(0, -1)
	}
	if (s.startsWith('-')) {
		negative = !negative
		s = s.slice(1)
	} else if (s.startsWith('+')) s = s.slice(1)
	if (!/^[\d.,]+$/.test(s) || !/\d/.test(s)) return null
	const comma = s.lastIndexOf(',')
	const dot = s.lastIndexOf('.')
	if (comma >= 0 && dot >= 0) {
		// Les deux : le dernier est le séparateur décimal, l'autre celui des milliers
		const decimal = comma > dot ? ',' : '.'
		s = s
			.split(decimal === ',' ? '.' : ',')
			.join('')
			.replace(decimal, '.')
	} else if (comma >= 0) s = s.split(',').length > 2 ? s.split(',').join('') : s.replace(',', '.')
	else if (dot >= 0 && s.split('.').length > 2) s = s.split('.').join('')
	const n = Number(s)
	if (!Number.isFinite(n)) return null
	return negative ? -n : n
}

const pad2 = (n: number) => String(n).padStart(2, '0')

/** Date JJ/MM/AAAA, JJ-MM-AA, AAAA-MM-JJ, JJMMAAAA ou numéro de série Excel → AAAA-MM-JJ */
export function parseDate(raw: string): string | null {
	const s = raw.trim()
	if (!s) return null
	let y: number
	let m: number
	let d: number
	let r: RegExpMatchArray | null
	if ((r = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T].*)?$/))) [y, m, d] = [+r[1], +r[2], +r[3]]
	else if ((r = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})(?:[ T].*)?$/))) {
		;[d, m, y] = [+r[1], +r[2], +r[3]]
		if (y < 100) y += 2000
		// Format américain (MM/JJ) reconnu quand le mois est impossible
		if (m > 12 && d <= 12) [d, m] = [m, d]
	} else if ((r = s.match(/^(\d{2})(\d{2})(\d{4})$/))) [d, m, y] = [+r[1], +r[2], +r[3]]
	else if (/^\d{5}(\.\d+)?$/.test(s) && +s > 20000 && +s < 80000) {
		// Numéro de série Excel (jours depuis le 30/12/1899), heure éventuelle ignorée
		const dt = new Date(Date.UTC(1899, 11, 30) + Math.floor(+s) * 86_400_000)
		;[y, m, d] = [dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate()]
	} else return null
	if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null
	const check = new Date(Date.UTC(y, m - 1, d))
	if (check.getUTCMonth() !== m - 1) return null
	return `${y}-${pad2(m)}-${pad2(d)}`
}

const RATES: TvaRate[] = [20, 14, 10, 7, 0]

/** Taux de TVA marocain : « 20 », « 20 % », « 0,20 », « TVA 7% » */
export function parseRate(raw: string): TvaRate | null {
	const digits = raw.replace(/[^\d.,-]/g, '')
	let n = parseNumber(digits)
	if (n === null) return null
	if (n > 0 && n < 1) n *= 100
	return RATES.find((r) => Math.abs(r - n) < 0.01) ?? null
}

/** Texte comparable : minuscules, sans accents ni ponctuation (« N° Tél. » → « ntel ») */
export const norm = (s: string) =>
	s
		.normalize('NFD')
		.replace(/[̀-ͯ]/g, '')
		.toLowerCase()
		.replace(/[^a-z0-9]/g, '')

// ---------- Ce qu'on peut reprendre ----------

export type FieldType = 'text' | 'number' | 'date' | 'rate'

export interface FieldDef {
	key: string
	label: string
	type: FieldType
	hint?: string
	/** Titres de colonnes reconnus automatiquement (sous forme normalisée) */
	synonyms: string[]
}

export type Target = 'clients' | 'suppliers' | 'products' | 'lots' | 'receivables' | 'payables'

const partyFields = (role: PartyRole): FieldDef[] => [
	{
		key: 'code',
		label: 'Code (ancien logiciel)',
		type: 'text',
		hint: 'sert à retrouver le tiers lors de la reprise des factures',
		synonyms: ['code', role === 'client' ? 'codeclient' : 'codefournisseur', 'ncompte', 'numerocompte', 'comptetiers', 'ctnum', 'codetiers', 'numtiers', 'compte', 'reference', 'ref', 'numero', 'id'],
	},
	{
		key: 'name',
		label: 'Nom / raison sociale',
		type: 'text',
		synonyms: ['raisonsociale', 'nom', 'intitule', 'ctintitule', 'denomination', 'societe', 'libelle', 'designation', 'tiers', role === 'client' ? 'client' : 'fournisseur', role === 'client' ? 'nomclient' : 'nomfournisseur', 'entreprise', 'etablissement'],
	},
	{ key: 'ice', label: 'ICE', type: 'text', synonyms: ['ice', 'nice', 'numeroice', 'identifiantcommun', 'identifiantcommundelentreprise', 'ctice'] },
	{ key: 'ifNumber', label: 'Identifiant fiscal (IF)', type: 'text', synonyms: ['if', 'nif', 'idfiscal', 'identifiantfiscal', 'numerofiscal', 'ctidentifiant'] },
	{ key: 'rc', label: 'Registre du commerce (RC)', type: 'text', synonyms: ['rc', 'nrc', 'registrecommerce', 'registreducommerce'] },
	{ key: 'address', label: 'Adresse', type: 'text', synonyms: ['adresse', 'adresse1', 'adr', 'rue', 'ctadresse', 'adressepostale'] },
	{ key: 'city', label: 'Ville', type: 'text', synonyms: ['ville', 'localite', 'commune', 'ctville'] },
	{ key: 'phone', label: 'Téléphone', type: 'text', synonyms: ['telephone', 'tel', 'tel1', 'gsm', 'portable', 'mobile', 'phone', 'fixe', 'cttelephone'] },
	{ key: 'email', label: 'E-mail', type: 'text', synonyms: ['email', 'mail', 'courriel', 'adresseemail', 'adressemail', 'ctemail'] },
	{ key: 'paymentTerms', label: 'Délai de paiement (jours)', type: 'text', synonyms: ['delai', 'delaipaiement', 'delaidepaiement', 'delaireglement', 'joursecheance', 'echeancejours', 'conditionsdepaiement'] },
	{ key: 'notes', label: 'Remarques / contact', type: 'text', synonyms: ['notes', 'note', 'remarque', 'remarques', 'commentaire', 'observation', 'contact', 'interlocuteur'] },
]

const docFields = (role: PartyRole): FieldDef[] => [
	{ key: 'number', label: 'N° de facture', type: 'text', synonyms: ['numero', 'nfacture', 'numerofacture', 'facture', 'piece', 'npiece', 'numeropiece', 'dopiece', 'ref', 'reference'] },
	{ key: 'date', label: 'Date de la facture', type: 'date', synonyms: ['date', 'datefacture', 'datepiece', 'dodate', 'datedoc'] },
	{ key: 'dueDate', label: 'Échéance', type: 'date', hint: 'sinon date + 60 jours', synonyms: ['echeance', 'dateecheance', 'datedecheance', 'datelimite', 'dateecheancereglement'] },
	{ key: 'partyCode', label: role === 'client' ? 'Code client' : 'Code fournisseur', type: 'text', synonyms: [role === 'client' ? 'codeclient' : 'codefournisseur', 'code', 'ncompte', 'comptetiers', 'ctnum', 'codetiers'] },
	{ key: 'partyName', label: role === 'client' ? 'Client' : 'Fournisseur', type: 'text', hint: 'créé s’il n’existe pas encore', synonyms: [role === 'client' ? 'client' : 'fournisseur', role === 'client' ? 'nomclient' : 'nomfournisseur', 'raisonsociale', 'nom', 'intitule', 'tiers', 'ctintitule'] },
	{ key: 'totalTTC', label: 'Montant TTC', type: 'number', synonyms: ['ttc', 'montantttc', 'totalttc', 'netapayer', 'montant', 'total', 'montanttotal'] },
	{ key: 'totalHT', label: 'Montant HT', type: 'number', hint: 'pour retrouver le taux de TVA', synonyms: ['ht', 'montantht', 'totalht'] },
	{ key: 'tvaRate', label: 'Taux de TVA', type: 'rate', synonyms: ['tauxtva', 'tva', 'taux', 'tauxdetva'] },
	{ key: 'paid', label: 'Déjà réglé', type: 'number', synonyms: ['montantregle', 'dejaregle', 'regle', 'paye', 'montantpaye', 'encaisse', 'montantencaisse', 'acompte', 'acomptes'] },
	{ key: 'remaining', label: 'Reste dû', type: 'number', synonyms: ['reste', 'restedu', 'resteapayer', 'solde', 'restant', 'du', 'montantdu', 'resteaencaisser', 'impaye'] },
]

export interface TargetDef {
	title: string
	text: string
	fields: FieldDef[]
	/** Colonnes indispensables : dans chaque groupe, au moins une doit être choisie */
	needs: string[][]
}

const docNeeds = [['number'], ['date'], ['partyName', 'partyCode'], ['totalTTC', 'remaining']]

export const TARGETS: Record<Target, TargetDef> = {
	clients: { title: 'Clients', text: 'Fiches clients : nom, ICE, IF, RC, adresse, téléphone…', fields: partyFields('client'), needs: [['name']] },
	suppliers: { title: 'Fournisseurs', text: 'Fiches fournisseurs : mêmes informations que les clients.', fields: partyFields('supplier'), needs: [['name']] },
	products: {
		title: 'Articles et stock',
		text: 'Catalogue avec prix d’achat, prix de vente et quantité en stock.',
		fields: [
			{ key: 'reference', label: 'Référence', type: 'text', synonyms: ['reference', 'ref', 'refarticle', 'code', 'codearticle', 'arref', 'sku', 'codeproduit', 'article'] },
			{ key: 'name', label: 'Désignation', type: 'text', synonyms: ['designation', 'libelle', 'nom', 'description', 'ardesign', 'intitule', 'produit', 'nomproduit', 'nomarticle'] },
			{ key: 'category', label: 'Famille / catégorie', type: 'text', synonyms: ['famille', 'categorie', 'fafamille', 'gamme', 'type', 'typeprothese', 'rayon'] },
			{ key: 'unitCost', label: 'Prix d’achat HT', type: 'number', synonyms: ['prixdachat', 'prixachat', 'pa', 'paht', 'prixachatht', 'prixdachatht', 'cout', 'coutunitaire', 'coutdachat', 'prixderevient', 'pmp', 'cmup', 'arprixach'] },
			{ key: 'unitPrice', label: 'Prix de vente HT', type: 'number', synonyms: ['prixdevente', 'prixvente', 'pv', 'pvht', 'prixventeht', 'prixdeventeht', 'tarif', 'prixunitaire', 'pu', 'puht', 'arprixven'] },
			{ key: 'stock', label: 'Quantité en stock', type: 'number', synonyms: ['stock', 'quantite', 'qte', 'qtestock', 'stockreel', 'quantiteenstock', 'enstock', 'qtenstock', 'asqtesto', 'disponible'] },
			{ key: 'minStock', label: 'Stock minimum', type: 'number', synonyms: ['stockmini', 'stockminimum', 'stockmin', 'seuil', 'seuilalerte', 'stockdalerte', 'stockalerte', 'mini'] },
			{ key: 'supplier', label: 'Fournisseur', type: 'text', synonyms: ['fournisseur', 'fournisseurprincipal', 'nomfournisseur', 'fabricant', 'marque', 'laboratoire'] },
		],
		needs: [['name', 'reference']],
	},
	lots: {
		title: 'Lots et n° de série',
		text: 'Traçabilité des implants : lot, n° de série, péremption, quantité. Importez d’abord les articles.',
		fields: [
			{ key: 'productRef', label: 'Référence article', type: 'text', synonyms: ['reference', 'ref', 'refarticle', 'codearticle', 'arref', 'code', 'article'] },
			{ key: 'productName', label: 'Désignation article', type: 'text', hint: 'si pas de référence', synonyms: ['designation', 'libelle', 'produit', 'nomproduit', 'nomarticle', 'description'] },
			{ key: 'lot', label: 'N° de lot', type: 'text', synonyms: ['lot', 'nlot', 'numerolot', 'numerodelot', 'lsnoserie', 'batch'] },
			{ key: 'serial', label: 'N° de série', type: 'text', synonyms: ['serie', 'nserie', 'numeroserie', 'numerodeserie', 'sn', 'serial', 'noserie'] },
			{ key: 'expiry', label: 'Date de péremption', type: 'date', synonyms: ['peremption', 'dateperemption', 'datedeperemption', 'expiration', 'dateexpiration', 'dlu', 'exp', 'lsperemption'] },
			{ key: 'quantity', label: 'Quantité', type: 'number', hint: '1 par défaut pour un n° de série', synonyms: ['quantite', 'qte', 'stock', 'qtestock', 'lsqte'] },
			{ key: 'receivedDate', label: 'Date de réception', type: 'date', synonyms: ['datereception', 'reception', 'dateentree', 'entree', 'datedereception'] },
			{ key: 'supplier', label: 'Fournisseur', type: 'text', synonyms: ['fournisseur', 'fabricant', 'laboratoire'] },
		],
		needs: [['productRef', 'productName'], ['lot', 'serial']],
	},
	receivables: {
		title: 'Factures clients non réglées',
		text: 'Ce que vos clients vous doivent encore : relances, échéancier et soldes clients continuent sans rien perdre.',
		fields: docFields('client'),
		needs: docNeeds,
	},
	payables: {
		title: 'Factures fournisseurs non réglées',
		text: 'Ce que vous devez encore à vos fournisseurs, pour l’échéancier.',
		fields: docFields('supplier'),
		needs: docNeeds,
	},
}

/** Colonne (index) choisie pour chaque champ, -1 = aucune */
export type Mapping = Record<string, number>

/** Valeur lisible pour le type du champ */
function fits(type: FieldType, value: string): boolean {
	if (type === 'number') return parseNumber(value) !== null
	if (type === 'date') return parseDate(value) !== null
	if (type === 'rate') return parseRate(value) !== null
	return true
}

/**
 * Correspondance automatique titres de colonnes → champs (chaque colonne sert au plus une fois).
 * Une colonne n'est proposée pour un nombre, une date ou un taux que si son contenu en est bien un
 * (« Mode de règlement » n'est pas pris pour « Déjà réglé »).
 */
/** Titre sans les petits mots (« N° de lot » → « lot », « Qté en stock » → « qtestock ») */
const STOP_WORDS = new Set(['n', 'no', 'num', 'numero', 'de', 'du', 'des', 'd', 'la', 'le', 'les', 'l', 'en', 'par', 'a'])
const compact = (header: string) =>
	header
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '')
		.toLowerCase()
		.split(/[^a-z0-9]+/)
		.filter((w) => w && !STOP_WORDS.has(w))
		.join('')

export function autoMap(table: Table, fields: FieldDef[]): Mapping {
	const normalized = table.headers.map(norm)
	const short = table.headers.map(compact)
	const sample = table.rows.slice(0, 50)
	const readable = (type: FieldType, col: number) => {
		const values = sample.map((r) => cleanValue(r[col] ?? '')).filter(Boolean)
		return values.length === 0 || values.filter((x) => fits(type, x)).length >= values.length * 0.8
	}
	const candidates: { field: string; col: number; score: number }[] = []
	fields.forEach((f, fi) => {
		normalized.forEach((h, col) => {
			if (!h) return
			let score = 0
			f.synonyms.forEach((syn, si) => {
				// Égalité exacte (titre complet, puis sans les petits mots), sinon titre qui contient le mot
				// (mots courts : égalité exacte seulement)
				const s = h === syn ? 100 - si : short[col] === syn ? 90 - si : syn.length >= 4 && h.includes(syn) ? 50 - si : 0
				score = Math.max(score, s)
			})
			// À égalité, le champ le plus haut dans la liste l'emporte
			if (score > 0 && readable(f.type, col)) candidates.push({ field: f.key, col, score: score * 100 - fi })
		})
	})
	const mapping: Mapping = Object.fromEntries(fields.map((f) => [f.key, -1]))
	const used = new Set<number>()
	for (const c of candidates.sort((a, b) => b.score - a.score)) {
		if (mapping[c.field] !== -1 || used.has(c.col)) continue
		mapping[c.field] = c.col
		used.add(c.col)
	}
	return mapping
}

/** Colonnes indispensables pas encore choisies (libellés « A ou B ») */
export function missingFields(target: Target, mapping: Mapping): string[] {
	const def = TARGETS[target]
	const label = (key: string) => def.fields.find((f) => f.key === key)?.label ?? key
	return def.needs.filter((group) => group.every((k) => (mapping[k] ?? -1) < 0)).map((group) => group.map(label).join(' ou '))
}

/** Champ indispensable à lui seul (affiché avec une étoile) */
export const isRequired = (target: Target, key: string) => TARGETS[target].needs.some((g) => g.length === 1 && g[0] === key)

/** Cellule vide ou équivalente (« - », « N/A ») */
export const cleanValue = (x: string) => {
	const t = x.trim()
	return /^([-–—.]|n\/?a|néant|neant|null)$/i.test(t) ? '' : t
}

// ---------- Conversion ----------

export type RowStatus = 'create' | 'update' | 'skip' | 'error'

export interface RowResult {
	/** N° de ligne dans le fichier */
	line: number
	status: RowStatus
	label: string
	message?: string
}

export interface ImportContext {
	parties: PartyRecord[]
	products: Product[]
	/** Articles de démonstration : remplacés par l'import au lieu d'être complétés */
	isSampleData: boolean
	lots: StockLot[]
	documents: CommercialDocument[]
	today: string
	/** Taux de TVA des factures reprises quand l'export ne le donne pas */
	defaultRate: TvaRate
	user: string
}

export interface Pair<T> {
	before: T
	after: T
}

export interface ImportPlan {
	target: Target
	rows: RowResult[]
	parties: { create: PartyRecord[]; update: Pair<PartyRecord>[] }
	products: { create: Product[]; update: Pair<Product>[]; replaceSample: boolean }
	lots: { create: StockLot[]; update: Pair<StockLot>[] }
	documents: CommercialDocument[]
}

const emptyPlan = (target: Target): ImportPlan => ({
	target,
	rows: [],
	parties: { create: [], update: [] },
	products: { create: [], update: [], replaceSample: false },
	lots: { create: [], update: [] },
	documents: [],
})

type Values = Record<string, string>

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)
const digits = (s: string) => s.replace(/\D/g, '')

/** Prépare l'import (rien n'est encore enregistré) : fiches à créer, à compléter, lignes ignorées ou en erreur */
export function buildPlan(target: Target, table: Table, mapping: Mapping, ctx: ImportContext): ImportPlan {
	const plan = emptyPlan(target)
	const fields = TARGETS[target].fields
	table.rows.forEach((row, i) => {
		const line = table.lines[i] ?? i + 1
		const v: Values = {}
		for (const f of fields) v[f.key] = mapping[f.key] >= 0 ? cleanValue(row[mapping[f.key]] ?? '') : ''
		const first = Object.values(v).find(Boolean)
		// Ligne sans rien d'utile, ou ligne de total en bas d'export : ignorée
		if (!first) return
		if (/^(total|sous-total|totaux|cumul)\b/i.test(first)) {
			plan.rows.push({ line, status: 'skip', label: first, message: 'Ligne de total' })
			return
		}
		const typeError = fields
			.filter((f) => v[f.key] !== '')
			.map((f) =>
				(f.type === 'number' && parseNumber(v[f.key]) === null) ||
				(f.type === 'date' && parseDate(v[f.key]) === null) ||
				(f.type === 'rate' && parseRate(v[f.key]) === null)
					? `${f.label} illisible : « ${v[f.key]} »`
					: '',
			)
			.find(Boolean)
		const result =
			typeError ? { status: 'error' as const, label: first, message: typeError } : convert(target, v, plan, ctx)
		plan.rows.push({ line, ...result })
	})
	return plan
}

type Outcome = Omit<RowResult, 'line'>

function convert(target: Target, v: Values, plan: ImportPlan, ctx: ImportContext): Outcome {
	switch (target) {
		case 'clients':
			return convertParty('client', v, plan, ctx)
		case 'suppliers':
			return convertParty('supplier', v, plan, ctx)
		case 'products':
			return convertProduct(v, plan, ctx)
		case 'lots':
			return convertLot(v, plan, ctx)
		case 'receivables':
			return convertDoc('invoice', v, plan, ctx)
		case 'payables':
			return convertDoc('bill', v, plan, ctx)
	}
}

/** Fiche déjà connue : même code, même ICE (15 chiffres) ou même nom */
function findParty(role: PartyRole, list: PartyRecord[], code: string, ice: string, name: string): PartyRecord | undefined {
	const n = norm(name)
	return (
		(code ? list.find((p) => p.role === role && p.code && norm(p.code) === norm(code)) : undefined) ??
		(ice.length === 15 ? list.find((p) => p.role === role && digits(p.ice) === ice) : undefined) ??
		(n ? list.find((p) => p.role === role && norm(p.name) === n) : undefined)
	)
}

/** Toutes les fiches tiers connues à ce stade de l'import (existantes, modifiées, créées) */
function currentParties(plan: ImportPlan, ctx: ImportContext): PartyRecord[] {
	const updated = new Map(plan.parties.update.map((u) => [u.after.id, u.after]))
	return [...ctx.parties.map((p) => updated.get(p.id) ?? p), ...plan.parties.create]
}

function replaceIn<T extends { id: string }>(list: T[], item: T) {
	const i = list.findIndex((x) => x.id === item.id)
	if (i >= 0) list[i] = item
}

function convertParty(role: PartyRole, v: Values, plan: ImportPlan, ctx: ImportContext): Outcome {
	const name = v.name
	if (!name) return { status: 'error', label: v.code, message: 'Nom manquant' }
	// Excel enregistre souvent l'ICE comme un nombre et perd les zéros du début (002345… → 2345…)
	const raw = digits(v.ice)
	const ice = raw.length === 13 || raw.length === 14 ? raw.padStart(15, '0') : raw
	const warning =
		ice !== raw
			? 'ICE complété par des zéros au début (perdus par Excel) : à vérifier'
			: ice && ice.length !== 15
				? `ICE à vérifier (${ice.length} chiffres au lieu de 15)`
				: undefined
	const terms = v.paymentTerms ? Number.parseInt(digits(v.paymentTerms), 10) || undefined : undefined
	const imported: Partial<PartyRecord> = {
		name,
		...(v.code && { code: v.code }),
		...(v.ice && { ice: ice || v.ice }),
		...(v.ifNumber && { ifNumber: v.ifNumber }),
		...(v.rc && { rc: v.rc }),
		...(v.address && { address: v.address }),
		...(v.city && { city: v.city }),
		...(v.phone && { phone: v.phone }),
		...(v.email && { email: v.email }),
		...(terms !== undefined && { paymentTerms: terms }),
	}
	const existing = findParty(role, currentParties(plan, ctx), v.code, ice, name)
	if (!existing) {
		plan.parties.create.push({
			id: newId(),
			role,
			address: '',
			city: '',
			ice: '',
			ifNumber: '',
			rc: '',
			phone: '',
			email: '',
			notes: v.notes,
			...imported,
			name,
		})
		return { status: 'create', label: name, message: warning }
	}
	// Fiche existante : complétée, jamais vidée (une case vide dans l'export ne l'efface pas)
	const notes = v.notes && !existing.notes.includes(v.notes) ? [existing.notes, v.notes].filter(Boolean).join('\n') : existing.notes
	const after: PartyRecord = { ...existing, ...imported, name: existing.name, notes }
	if (same(after, existing)) return { status: 'skip', label: name, message: 'Déjà à jour' }
	recordUpdate(plan.parties, existing, after)
	return { status: 'update', label: name, message: warning ?? 'Fiche existante complétée' }
}

/** Mémorise une modification ; une fiche créée par ce même import est modifiée sur place */
function recordUpdate<T extends { id: string }>(bucket: { create: T[]; update: Pair<T>[] }, existing: T, after: T) {
	if (bucket.create.some((x) => x.id === existing.id)) return replaceIn(bucket.create, after)
	const prev = bucket.update.find((u) => u.after.id === existing.id)
	if (prev) prev.after = after
	else bucket.update.push({ before: existing, after })
}

function currentProducts(plan: ImportPlan, ctx: ImportContext): Product[] {
	const updated = new Map(plan.products.update.map((u) => [u.after.id, u.after]))
	const base = ctx.isSampleData ? [] : ctx.products
	return [...base.map((p) => updated.get(p.id) ?? p), ...plan.products.create]
}

function findProduct(list: Product[], ref: string, name: string): Product | undefined {
	return (ref ? list.find((p) => p.reference && norm(p.reference) === norm(ref)) : undefined) ?? (name ? list.find((p) => norm(p.name) === norm(name)) : undefined)
}

function convertProduct(v: Values, plan: ImportPlan, ctx: ImportContext): Outcome {
	const name = v.name || v.reference
	if (!name) return { status: 'error', label: '', message: 'Désignation manquante' }
	const num = (s: string) => (s ? parseNumber(s) : null)
	const [unitCost, unitPrice, stock, minStock] = [num(v.unitCost), num(v.unitPrice), num(v.stock), num(v.minStock)]
	if ([unitCost, unitPrice, minStock].some((n) => n !== null && n < 0)) return { status: 'error', label: name, message: 'Prix ou seuil négatif' }
	plan.products.replaceSample = ctx.isSampleData
	const existing = findProduct(currentProducts(plan, ctx), v.reference, v.name)
	const imported: Partial<Product> = {
		...(v.reference && { reference: v.reference }),
		...(v.category && { category: v.category }),
		...(unitCost !== null && { unitCost: round2(unitCost) }),
		...(unitPrice !== null && { unitPrice: round2(unitPrice) }),
		...(stock !== null && { stock }),
		...(minStock !== null && { minStock }),
		...(v.supplier && { supplier: v.supplier }),
	}
	const warning = stock !== null && stock < 0 ? 'Stock négatif dans l’ancien logiciel : à vérifier' : undefined
	if (!existing) {
		plan.products.create.push({
			id: newId(),
			name,
			category: 'Non classé',
			unitCost: 0,
			unitPrice: 0,
			unitsSold: 0,
			stock: 0,
			...imported,
		} as Product)
		return { status: 'create', label: name, message: warning }
	}
	const after = { ...existing, ...imported, ...(v.name && { name: v.name }) } as Product
	if (same(after, existing)) return { status: 'skip', label: name, message: 'Déjà à jour' }
	recordUpdate(plan.products, existing, after)
	return { status: 'update', label: name, message: warning ?? 'Article existant mis à jour' }
}

function convertLot(v: Values, plan: ImportPlan, ctx: ImportContext): Outcome {
	const label = [v.productRef || v.productName, v.lot, v.serial].filter(Boolean).join(' · ')
	if (!v.lot && !v.serial) return { status: 'error', label, message: 'Ni n° de lot ni n° de série' }
	const product = findProduct(ctx.isSampleData ? [] : ctx.products, v.productRef, v.productName)
	if (!product) return { status: 'error', label, message: 'Article introuvable : importez d’abord les articles (même référence ou même désignation)' }
	const quantity = v.quantity ? parseNumber(v.quantity) : v.serial ? 1 : null
	if (quantity === null || quantity < 0) return { status: 'error', label, message: 'Quantité manquante' }
	const expiry = v.expiry ? (parseDate(v.expiry) ?? '') : ''
	const updated = new Map(plan.lots.update.map((u) => [u.after.id, u.after]))
	const all = [...ctx.lots.map((l) => updated.get(l.id) ?? l), ...plan.lots.create]
	const existing = all.find((l) => l.productId === product.id && norm(l.lot) === norm(v.lot) && norm(l.serial) === norm(v.serial))
	if (!existing) {
		plan.lots.create.push({
			id: newId(),
			productId: product.id,
			lot: v.lot,
			serial: v.serial,
			expiry,
			quantity,
			receivedDate: v.receivedDate ? (parseDate(v.receivedDate) ?? ctx.today) : ctx.today,
			supplier: v.supplier || product.supplier || '',
		})
		return { status: 'create', label }
	}
	const after: StockLot = { ...existing, quantity, ...(expiry && { expiry }), ...(v.supplier && { supplier: v.supplier }) }
	if (same(after, existing)) return { status: 'skip', label, message: 'Déjà à jour' }
	recordUpdate(plan.lots, existing, after)
	return { status: 'update', label, message: 'Lot existant mis à jour' }
}

/**
 * Une ligne à un seul taux dont le TTC tombe exactement sur le montant de l'ancien logiciel
 * (sinon une ligne d'arrondi de quelques centimes, sans TVA)
 */
function linesFor(ttc: number, rate: TvaRate, label: string, kind: DocKind): DocLine[] {
	const base = round2(ttc / (1 + rate / 100))
	for (const delta of [0, 0.01, -0.01, 0.02, -0.02]) {
		const line: DocLine = { id: newId(), description: label, quantity: 1, unitPriceHT: round2(base + delta), tvaRate: rate, discount: 0 }
		if (computeTotals({ lines: [line], kind, paymentMethod: 'virement' }).totalTTC === ttc) return [line]
	}
	const line: DocLine = { id: newId(), description: label, quantity: 1, unitPriceHT: base, tvaRate: rate, discount: 0 }
	const gap = round2(ttc - computeTotals({ lines: [line], kind, paymentMethod: 'virement' }).totalTTC)
	return [line, { id: newId(), description: 'Arrondi de reprise', quantity: 1, unitPriceHT: gap, tvaRate: 0, discount: 0 }]
}

function convertDoc(kind: 'invoice' | 'bill', v: Values, plan: ImportPlan, ctx: ImportContext): Outcome {
	const role: PartyRole = kind === 'invoice' ? 'client' : 'supplier'
	const number = v.number
	const label = [number, v.partyName || v.partyCode].filter(Boolean).join(' · ')
	const date = parseDate(v.date)
	if (!number || !date) return { status: 'error', label, message: 'N° ou date de facture manquant' }
	if (!v.partyName && !v.partyCode) return { status: 'error', label, message: role === 'client' ? 'Client manquant' : 'Fournisseur manquant' }

	// Montants : TTC, déjà réglé, reste dû (deux des trois suffisent)
	const ttcIn = v.totalTTC ? parseNumber(v.totalTTC) : null
	const paidIn = v.paid ? parseNumber(v.paid) : null
	const restIn = v.remaining ? parseNumber(v.remaining) : null
	const ttc = round2(ttcIn ?? (restIn !== null ? restIn + (paidIn ?? 0) : NaN))
	if (!Number.isFinite(ttc)) return { status: 'error', label, message: 'Montant TTC (ou reste dû) manquant' }
	if (ttc < 0) return { status: 'skip', label, message: 'Montant négatif (avoir) : à saisir à la main si besoin' }
	const paid = round2(paidIn ?? (restIn !== null && ttcIn !== null ? ttcIn - restIn : 0))
	if (paid < 0 || paid > ttc + 0.01) return { status: 'error', label, message: 'Montant réglé incohérent avec le TTC' }
	if (ttc - paid <= 0.01) return { status: 'skip', label, message: 'Déjà réglée : rien à reprendre' }

	// Taux de TVA : donné, déduit du HT, sinon taux par défaut
	let rate: TvaRate = ctx.defaultRate
	let warning: string | undefined
	const rateIn = v.tvaRate ? parseRate(v.tvaRate) : null
	const htIn = v.totalHT ? parseNumber(v.totalHT) : null
	if (rateIn !== null) rate = rateIn
	else if (htIn !== null && htIn > 0) {
		const found = RATES.find((r) => Math.abs(htIn * (1 + r / 100) - ttc) <= Math.max(0.05, ttc * 0.001))
		if (found !== undefined) rate = found
		else warning = `Taux de TVA non reconnu d’après le HT : ${ctx.defaultRate} % appliqué`
	}

	// Tiers : retrouvé par code ou par nom, sinon créé (après le contrôle de doublon)
	const known = findParty(role, currentParties(plan, ctx), v.partyCode, '', v.partyName)
	const partyName = known?.name ?? v.partyName

	// Déjà reprise : même numéro (et même fournisseur pour une facture d'achat)
	const duplicate = [...ctx.documents, ...plan.documents].find(
		(d) => d.kind === kind && norm(d.number) === norm(number) && (kind === 'invoice' || (!!partyName && norm(d.party.name) === norm(partyName))),
	)
	if (duplicate) return { status: 'skip', label, message: 'Déjà présente dans ProfitPilot' }
	if (!known && !v.partyName) return { status: 'error', label, message: `Code ${v.partyCode} inconnu : importez d’abord les ${role === 'client' ? 'clients' : 'fournisseurs'}` }

	let party = known
	let created = false
	if (!party) {
		party = { id: newId(), role, name: v.partyName, ...(v.partyCode && { code: v.partyCode }), address: '', city: '', ice: '', ifNumber: '', rc: '', phone: '', email: '', notes: '' }
		plan.parties.create.push(party)
		created = true
	}
	const { name, address, city, ice, ifNumber, rc, phone, email, individual } = party
	const description = `Solde repris de l’ancien logiciel : facture ${number} du ${date.split('-').reverse().join('/')}`
	plan.documents.push({
		id: newId(),
		kind,
		number,
		date,
		dueDate: (v.dueDate && parseDate(v.dueDate)) || addDays(date, party.paymentTerms ?? 60),
		party: { name, address, city, ice, ifNumber, rc, phone, email, ...(individual && { individual }) },
		lines: linesFor(ttc, rate, description, kind),
		status: 'validated',
		paymentMethod: 'virement',
		notes: `Reprise de l’ancien logiciel le ${ctx.today.split('-').reverse().join('/')}.`,
		...(paid > 0 && {
			payments: [{ id: newId(), date: ctx.today, amount: paid, method: 'virement', reference: 'Déjà réglé dans l’ancien logiciel', legacy: true }],
		}),
		...(kind === 'bill' && { supplierRef: number }),
		createdBy: ctx.user,
		validatedBy: ctx.user,
		legacy: true,
	})
	const extra = created ? `${role === 'client' ? 'Client' : 'Fournisseur'} « ${v.partyName} » créé` : undefined
	return { status: 'create', label, message: [warning, extra].filter(Boolean).join(' · ') || undefined }
}

// ---------- Annulation du dernier import ----------

export interface UndoInfo {
	at: string
	target: Target
	created: { parties: string[]; products: string[]; lots: string[]; documents: string[] }
	updated: { parties: PartyRecord[]; products: Product[]; lots: StockLot[] }
	/** Articles de démonstration remplacés par l'import */
	replacedSample: boolean
}

export function undoInfo(plan: ImportPlan, at: string): UndoInfo {
	return {
		at,
		target: plan.target,
		created: {
			parties: plan.parties.create.map((p) => p.id),
			products: plan.products.create.map((p) => p.id),
			lots: plan.lots.create.map((l) => l.id),
			documents: plan.documents.map((d) => d.id),
		},
		updated: {
			parties: plan.parties.update.map((u) => u.before),
			products: plan.products.update.map((u) => u.before),
			lots: plan.lots.update.map((u) => u.before),
		},
		replacedSample: plan.products.replaceSample,
	}
}

/** Liste après annulation : éléments créés retirés, éléments modifiés remis dans leur version d'avant */
export function revert<T extends { id: string }>(list: T[], created: string[], previous: T[]): T[] {
	const removed = new Set(created)
	const before = new Map(previous.map((x) => [x.id, x]))
	return list.filter((x) => !removed.has(x.id)).map((x) => before.get(x.id) ?? x)
}

/** Liste après import : modifications appliquées, créations ajoutées */
export function apply<T extends { id: string }>(list: T[], bucket: { create: T[]; update: Pair<T>[] }): T[] {
	const after = new Map(bucket.update.map((u) => [u.after.id, u.after]))
	return [...list.map((x) => after.get(x.id) ?? x), ...bucket.create]
}
