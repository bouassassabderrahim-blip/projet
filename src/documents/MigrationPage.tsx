import { useMemo, useState, type Dispatch, type SetStateAction } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { downloadFile } from './csv'
import {
	TARGETS,
	apply,
	autoMap,
	buildPlan,
	cleanValue,
	decodeBytes,
	fileKind,
	isRequired,
	missingFields,
	readTable,
	revert,
	undoInfo,
	type Mapping,
	type RowStatus,
	type Target,
	type UndoInfo,
} from './migration'
import { NUMBERING_KEY, nextNumberWith, today, type NumberingStarts } from './numbering'
import { LAST_BACKUP_KEY, createBackup, usePersistentState } from './storage'
import { DOC_LABELS, type CommercialDocument, type DocKind, type PartyRecord, type StockLot, type TvaRate } from './types'
import { xlsxToText } from './xlsx'
import './documents.css'

interface Props {
	parties: PartyRecord[]
	onParties: Dispatch<SetStateAction<PartyRecord[]>>
	products: Product[]
	isSampleData: boolean
	/** Mise à jour des articles (les articles de démonstration cessent de l'être) */
	onProducts: (update: (prev: Product[]) => Product[]) => void
	/** Remet les articles de démonstration (annulation d'un import qui les avait remplacés) */
	onRestoreSample: () => void
	lots: StockLot[]
	onLots: Dispatch<SetStateAction<StockLot[]>>
	documents: CommercialDocument[]
	onDocuments: Dispatch<SetStateAction<CommercialDocument[]>>
}

/** Dernier import, pour pouvoir l'annuler (gardé sur ce poste uniquement) */
const UNDO_KEY = 'profitpilot-migration:undo'
const ORDER: Target[] = ['clients', 'suppliers', 'products', 'lots', 'receivables', 'payables']
const STATUS: Record<RowStatus, { label: string; badge: string }> = {
	create: { label: 'À créer', badge: 'doc-badge-paid' },
	update: { label: 'À compléter', badge: 'doc-badge-validated' },
	skip: { label: 'Ignorée', badge: '' },
	error: { label: 'Erreur', badge: 'doc-badge-error' },
}
/** Pièces dont la numérotation peut poursuivre celle de l'ancien logiciel */
const NUMBERED: DocKind[] = ['invoice', 'credit', 'quote', 'order', 'delivery', 'purchase', 'receipt']
const RATES: TvaRate[] = [20, 14, 10, 7, 0]
const PREVIEW_MAX = 300

const isStarts = (x: unknown): x is NumberingStarts => typeof x === 'object' && x !== null && !Array.isArray(x)

function loadUndo(): UndoInfo | null {
	try {
		const raw = localStorage.getItem(UNDO_KEY)
		return raw ? (JSON.parse(raw) as UndoInfo) : null
	} catch {
		return null
	}
}

/** Reprise des données d'un ancien logiciel : fichier (CSV, Excel) ou copier-coller, colonnes, aperçu, import */
export default function MigrationPage(props: Props) {
	const access = useAccess()
	const [target, setTarget] = useState<Target | null>(null)
	const [text, setText] = useState('')
	const [source, setSource] = useState('')
	const [hasHeader, setHasHeader] = useState<boolean | undefined>(undefined)
	/** Colonnes choisies à la main (le reste vient de la reconnaissance automatique) */
	const [overrides, setOverrides] = useState<Mapping>({})
	const [defaultRate, setDefaultRate] = useState<TvaRate>(20)
	const [onlyProblems, setOnlyProblems] = useState(false)
	const [error, setError] = useState('')
	const [done, setDone] = useState('')
	const [undo, setUndo] = useState<UndoInfo | null>(loadUndo)
	const [starts, setStarts] = usePersistentState<NumberingStarts>(NUMBERING_KEY, () => ({}), isStarts)
	const now = today()
	const year = now.slice(0, 4)

	const table = useMemo(() => (text.trim() ? readTable(text, hasHeader) : null), [text, hasHeader])
	const mapping = useMemo<Mapping>(
		() => (table && target ? { ...autoMap(table, TARGETS[target].fields), ...overrides } : {}),
		[table, target, overrides],
	)
	const missing = target && table ? missingFields(target, mapping) : []
	const plan = useMemo(
		() =>
			table && target && missing.length === 0
				? buildPlan(target, table, mapping, {
						parties: props.parties,
						products: props.products,
						isSampleData: props.isSampleData,
						lots: props.lots,
						documents: props.documents,
						today: now,
						defaultRate,
						user: access.user?.name ?? '',
					})
				: null,
		// missing est dérivé de table, target et mapping
		// eslint-disable-next-line react-hooks/exhaustive-deps
		[table, target, mapping, props.parties, props.products, props.isSampleData, props.lots, props.documents, now, defaultRate, access.user],
	)
	const count = (s: RowStatus) => plan?.rows.filter((r) => r.status === s).length ?? 0
	const toImport = count('create') + count('update')

	function reset() {
		setOverrides({})
		setOnlyProblems(false)
		setError('')
		setDone('')
	}

	function chooseTarget(t: Target) {
		setTarget(t)
		reset()
	}

	function loadText(content: string, name: string) {
		reset()
		setHasHeader(undefined)
		setText(content)
		setSource(name)
	}

	async function readFile(file: File | undefined) {
		if (!file) return
		const bytes = new Uint8Array(await file.arrayBuffer())
		const kind = fileKind(bytes)
		if (kind === 'ole')
			return setError(
				'Ancien format Excel (.xls) : ouvrez le fichier dans Excel, puis Fichier › Enregistrer sous › « Classeur Excel (.xlsx) ». Vous pouvez aussi copier les cellules et les coller dans la zone de droite.',
			)
		try {
			loadText(kind === 'zip' ? await xlsxToText(bytes) : decodeBytes(bytes), file.name)
		} catch {
			setError(
				'Fichier illisible. Dans Excel ou LibreOffice, enregistrez-le en « Classeur Excel (.xlsx) » ou en CSV, ou copiez les cellules et collez-les dans la zone de droite.',
			)
		}
	}

	function backupFirst() {
		downloadFile(`profitpilot-sauvegarde-${now}.json`, JSON.stringify(createBackup(), null, 1), 'application/json')
		try {
			localStorage.setItem(LAST_BACKUP_KEY, now)
		} catch {
			// stockage indisponible
		}
	}

	function runImport() {
		if (!plan || !target || toImport === 0) return
		const replace = plan.products.replaceSample && (plan.products.create.length > 0 || plan.products.update.length > 0)
		const question = [
			`Importer ${toImport} ligne(s) (${TARGETS[target].title.toLowerCase()}) dans ProfitPilot ?`,
			replace ? 'Les articles de démonstration seront remplacés par vos articles.' : '',
			count('error') ? `${count('error')} ligne(s) en erreur ne seront pas importées.` : '',
		]
			.filter(Boolean)
			.join('\n\n')
		if (!confirm(question)) return
		if (plan.parties.create.length || plan.parties.update.length) props.onParties((prev) => apply(prev, plan.parties))
		if (plan.products.create.length || plan.products.update.length)
			props.onProducts((prev) => apply(plan.products.replaceSample ? [] : prev, plan.products))
		if (plan.lots.create.length || plan.lots.update.length) props.onLots((prev) => apply(prev, plan.lots))
		if (plan.documents.length) props.onDocuments((prev) => [...prev, ...plan.documents])
		const info = undoInfo(plan, new Date().toISOString())
		let undoSaved = true
		try {
			localStorage.setItem(UNDO_KEY, JSON.stringify(info))
		} catch {
			undoSaved = false
			try {
				localStorage.removeItem(UNDO_KEY)
			} catch {
				// stockage indisponible
			}
		}
		setUndo(undoSaved ? info : null)
		const created = plan.parties.create.length + plan.products.create.length + plan.lots.create.length + plan.documents.length
		const updated = plan.parties.update.length + plan.products.update.length + plan.lots.update.length
		access.log('Reprise de données', `${TARGETS[target].title} (${source}) : ${created} créé(s), ${updated} complété(s)`)
		setText('')
		setSource('')
		setOverrides({})
		setDone(
			`Import terminé : ${created} fiche(s) ou facture(s) créée(s), ${updated} complétée(s).` +
				(undoSaved ? '' : ' (Annulation impossible : stockage du navigateur plein. Gardez la sauvegarde téléchargée.)'),
		)
	}

	function runUndo() {
		if (!undo) return
		if (
			!confirm(
				`Annuler l'import du ${new Date(undo.at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })} (${TARGETS[undo.target].title.toLowerCase()}) ?\n\nCe qu'il a créé sera supprimé, même si vous l'avez modifié depuis, et les fiches qu'il a complétées reprendront leur version d'avant.`,
			)
		)
			return
		props.onParties((prev) => revert(prev, undo.created.parties, undo.updated.parties))
		if (undo.replacedSample && revert(props.products, undo.created.products, undo.updated.products).length === 0) props.onRestoreSample()
		else if (undo.created.products.length || undo.updated.products.length)
			props.onProducts((prev) => revert(prev, undo.created.products, undo.updated.products))
		props.onLots((prev) => revert(prev, undo.created.lots, undo.updated.lots))
		const docs = new Set(undo.created.documents)
		if (docs.size) props.onDocuments((prev) => prev.filter((d) => !docs.has(d.id)))
		try {
			localStorage.removeItem(UNDO_KEY)
		} catch {
			// stockage indisponible
		}
		access.log('Reprise de données annulée', TARGETS[undo.target].title)
		setUndo(null)
		setDone('Le dernier import a été annulé.')
	}

	const example = (col: number) => table?.rows.map((r) => cleanValue(r[col] ?? '')).find(Boolean) ?? ''
	const shown = plan ? plan.rows.filter((r) => !onlyProblems || r.status === 'error' || r.status === 'skip') : []
	const validated = props.documents.filter((d) => d.status !== 'draft')

	return (
		<div>
			<div className="doc-info">
				Reprenez les données de votre ancien logiciel (Sage, Ciel, EBP, Excel…) sans les ressaisir : exportez chaque liste
				depuis l'ancien logiciel (Excel ou CSV), choisissez-la ici, vérifiez l'aperçu puis importez. Rien n'est enregistré
				avant de cliquer sur « Importer », et le dernier import peut être annulé. Suivez de préférence l'ordre ci-dessous :
				les factures retrouvent ainsi leurs clients, et les lots leurs articles.
			</div>

			<fieldset className="doc-panel">
				<legend>1. Que voulez-vous reprendre ?</legend>
				<div className="doc-mode-list mig-targets">
					{ORDER.map((t, i) => (
						<button key={t} type="button" className={`doc-mode ${target === t ? 'doc-mode-active' : ''}`} onClick={() => chooseTarget(t)}>
							<span>
								<strong>
									<span className="mig-step">{i + 1}</span>
									{TARGETS[t].title}
								</strong>
								<small>{TARGETS[t].text}</small>
							</span>
						</button>
					))}
				</div>
			</fieldset>

			{target && (
				<fieldset className="doc-panel">
					<legend>2. Le fichier exporté de l'ancien logiciel</legend>
					<div className="mig-source">
						<label>
							Fichier Excel (.xlsx) ou CSV
							<input
								type="file"
								accept=".xlsx,.csv,.txt,.tsv,.xls"
								onChange={(e) => {
									const file = e.target.files?.[0]
									// Le même fichier pourra être choisi de nouveau (par exemple après correction dans Excel)
									e.target.value = ''
									void readFile(file)
								}}
							/>
							{source && <small className="doc-count">Lu : {source}</small>}
						</label>
						<label>
							ou collez ici les cellules copiées dans Excel (sélectionnez le tableau avec ses titres, Cmd+C, puis Cmd+V ici)
							<textarea
								value={source === 'copier-coller' ? text : ''}
								placeholder={'Code\tNom\tVille\nCL0001\tClinique Atlas\tCasablanca'}
								onChange={(e) => loadText(e.target.value, 'copier-coller')}
							/>
						</label>
					</div>
					{error && <p className="doc-error">{error}</p>}
				</fieldset>
			)}

			{target && table && (
				<fieldset className="doc-panel">
					<legend>3. Les colonnes ({table.rows.length} ligne(s) lue(s))</legend>
					<label className="doc-check">
						<input
							type="checkbox"
							checked={table.hasHeader}
							onChange={(e) => {
								setHasHeader(e.target.checked)
								setOverrides({})
							}}
						/>
						La première ligne contient les titres des colonnes
					</label>
					<p className="doc-count">
						ProfitPilot a reconnu les colonnes d'après leurs titres : vérifiez et corrigez si besoin. Les champs marqués * sont
						indispensables ; « Aucune » si l'information n'existe pas dans votre fichier.
					</p>
					<div className="doc-table-wrap">
						<table className="doc-table mig-map">
							<thead>
								<tr>
									<th>Information ProfitPilot</th>
									<th>Colonne de votre fichier</th>
									<th>Exemple lu</th>
								</tr>
							</thead>
							<tbody>
								{TARGETS[target].fields.map((f) => (
									<tr key={f.key}>
										<td>
											{f.label}
											{isRequired(target, f.key) && ' *'}
											{f.hint && <small className="doc-count"> ({f.hint})</small>}
										</td>
										<td>
											<select
												value={mapping[f.key] ?? -1}
												onChange={(e) => setOverrides((o) => ({ ...o, [f.key]: Number(e.target.value) }))}
											>
												<option value={-1}>— Aucune —</option>
												{table.headers.map((h, i) => (
													<option key={i} value={i}>
														{h}
													</option>
												))}
											</select>
										</td>
										<td className="mig-example">{(mapping[f.key] ?? -1) >= 0 ? example(mapping[f.key]) : ''}</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
					{(target === 'receivables' || target === 'payables') && (
						<label className="mig-rate">
							Taux de TVA des factures quand le fichier ne le donne pas (ni taux, ni montant HT){' '}
							<select value={defaultRate} onChange={(e) => setDefaultRate(Number(e.target.value) as TvaRate)}>
								{RATES.map((r) => (
									<option key={r} value={r}>
										{r} %
									</option>
								))}
							</select>
						</label>
					)}
					{missing.length > 0 && <p className="doc-warning">Choisissez une colonne pour : {missing.join(' ; ')}.</p>}
				</fieldset>
			)}

			{target && plan && (
				<fieldset className="doc-panel">
					<legend>4. Aperçu avant import</legend>
					<div className="doc-stats">
						{(Object.keys(STATUS) as RowStatus[]).map((s) => (
							<div key={s}>
								<span>{STATUS[s].label}</span>
								<strong>{count(s)}</strong>
							</div>
						))}
					</div>
					{plan.products.replaceSample && toImport > 0 && (
						<p className="doc-warning">Les articles de démonstration seront remplacés par vos articles.</p>
					)}
					{target === 'receivables' || target === 'payables' ? (
						<p className="doc-count">
							Chaque facture est reprise avec son reste à payer, son échéance et son client. Elle est marquée « Reprise » :
							elle n'entre ni dans le chiffre d'affaires, ni dans le journal comptable, ni dans la TVA déjà déclarée par
							l'ancien logiciel ; seuls les règlements saisis désormais dans ProfitPilot comptent pour la TVA.
						</p>
					) : null}
					<label className="doc-check">
						<input type="checkbox" checked={onlyProblems} onChange={(e) => setOnlyProblems(e.target.checked)} />
						Afficher seulement les lignes ignorées ou en erreur
					</label>
					<div className="doc-table-wrap">
						<table className="doc-table">
							<thead>
								<tr>
									<th className="num">Ligne</th>
									<th>Élément</th>
									<th>Résultat</th>
									<th>Détail</th>
								</tr>
							</thead>
							<tbody>
								{shown.slice(0, PREVIEW_MAX).map((r) => (
									<tr key={r.line}>
										<td className="num">{r.line}</td>
										<td>{r.label}</td>
										<td>
											<span className={`doc-badge ${STATUS[r.status].badge}`}>{STATUS[r.status].label}</span>
										</td>
										<td>{r.message}</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
					{shown.length > PREVIEW_MAX && <p className="doc-count">… et {shown.length - PREVIEW_MAX} autre(s) ligne(s).</p>}
					<div className="doc-editor-actions">
						<button type="button" onClick={backupFirst}>
							Télécharger une sauvegarde d'abord
						</button>
						<button type="button" className="btn-primary" disabled={toImport === 0} onClick={runImport}>
							Importer {toImport} ligne(s)
						</button>
					</div>
				</fieldset>
			)}

			{done && <p className="doc-info">{done}</p>}

			{undo && (
				<fieldset className="doc-panel">
					<legend>Dernier import</legend>
					<p>
						{TARGETS[undo.target].title}, le {new Date(undo.at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}.
					</p>
					<button type="button" onClick={runUndo}>
						Annuler cet import
					</button>
				</fieldset>
			)}

			<fieldset className="doc-panel">
				<legend>Numérotation : poursuivre celle de l'ancien logiciel</legend>
				<p className="doc-count">
					La numérotation des factures doit rester continue sur l'année. Si vous changez de logiciel en cours d'année, indiquez
					le dernier numéro utilisé en {year} dans l'ancien logiciel : ProfitPilot continuera à la suite. (Les factures reprises
					au format {DOC_LABELS.invoice.prefix}-{year}-0000 sont prises en compte automatiquement.)
				</p>
				<div className="mig-numbering">
					{NUMBERED.map((kind) => {
						const key = `${kind}:${year}`
						return (
							<label key={kind}>
								{DOC_LABELS[kind].title} : dernier n° utilisé
								<input
									className="num"
									type="number"
									min={0}
									value={starts[key] ?? ''}
									placeholder="0"
									disabled={!access.isAdmin}
									onChange={(e) => {
										const n = Math.max(0, Math.floor(Number(e.target.value) || 0))
										setStarts((s) => {
											const next = { ...s }
											if (n > 0) next[key] = n
											else delete next[key]
											return next
										})
									}}
								/>
								<small className="doc-count">Prochain : {nextNumberWith(kind, validated, now, starts)}</small>
							</label>
						)
					})}
				</div>
			</fieldset>
		</div>
	)
}
