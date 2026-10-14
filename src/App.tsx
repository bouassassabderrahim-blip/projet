import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { FixedCost, PageId, Product } from './types'
import { sampleProducts } from './data/sampleProducts'
import Sidebar from './components/Sidebar'
import BreakEven from './components/BreakEven'
import Dashboard from './components/Dashboard'
import ExportBar from './components/ExportBar'
import ImportCsv from './components/ImportCsv'
import ProductEditor from './components/ProductEditor'
import ProductProfitability from './components/ProductProfitability'
import Simulator from './components/Simulator'
import Recommendations from './components/Recommendations'
import Compare from './components/Compare'
import Decision from './components/Decision'
import StockPage from './components/StockPage'
import DocumentsPage from './documents/DocumentsPage'
import CompanySettings from './documents/CompanySettings'
import VatPage from './documents/VatPage'
import DepotPage from './documents/DepotPage'
import LotsPage from './documents/LotsPage'
import KitsPage from './documents/KitsPage'
import PartiesPage from './documents/PartiesPage'
import BackupPage from './documents/BackupPage'
import StockAlertsPage from './documents/StockAlertsPage'
import StockMovesPage from './documents/StockMovesPage'
import InventoryPage from './documents/InventoryPage'
import SchedulePage from './documents/SchedulePage'
import StatsPage from './documents/StatsPage'
import { getStockStatus } from './utils/stock'
import { isOverdue } from './documents/ledger'
import { applyMove, expiryState } from './documents/stockMoves'
import { useCashBalance, useCompany, useDocuments, useKits, useLots, useMovements, useParties } from './documents/storage'
import type { DocKind, DocLine, StockMovement } from './documents/types'
import { CURRENCIES, setCurrency } from './utils/finance'
import TopBar, { type Notification } from './shell/TopBar'
import ModuleBar from './shell/ModuleBar'
import WorkTabs from './shell/WorkTabs'
import StatusBar from './shell/StatusBar'
import GlobalSearch, { type SearchHit } from './shell/GlobalSearch'
import Launchpad from './shell/Launchpad'
import { ADMIN_PAGES, MODULES, moduleOf, type ModuleId } from './shell/navigation'
import { LAST_BACKUP_KEY, STORAGE_ERROR_EVENT } from './documents/storage'
import { AccessContext, accessFor } from './access/context'
import SyncPage from './sync/SyncPage'
import { startFromConfig, useSyncStatus } from './sync/runtime'
import { readSession, useAccessSettings, useAudit, useUsers, writeSession } from './access/storage'
import type { AuditEntry, User } from './access/types'
import LoginScreen from './access/LoginScreen'
import UsersPage from './access/UsersPage'
import AuditPage from './access/AuditPage'
import { AccessDenied, ReadOnlyArea } from './access/ReadOnly'
import { daysBetween, newId, today } from './documents/numbering'
import './theme.css'
import './documents/documents.css'
import './pro-theme.css'
import './shell/shell.css'

const STORAGE_KEY = 'profitpilot:v1'
const FIXED_KEY = 'profitpilot:fixed:v1'
const CURRENCY_KEY = 'profitpilot:currency:v1'

const titles: Record<PageId, string> = {
	home: 'Accueil',
	dashboard: 'Tableau de bord',
	catalog: 'Mes produits',
	stock: 'Gestion du stock',
	alerts: 'Alertes de stock',
	movements: 'Mouvements de stock',
	inventory: 'Inventaire physique',
	stats: 'Statistiques des ventes',
	schedule: 'Échéancier et trésorerie prévisionnelle',
	products: 'Rentabilité par produit',
	breakeven: 'Résultat & seuil de rentabilité',
	import: 'Import de fichiers CSV',
	simulator: 'Simulateur de prix et de coûts',
	recommendations: 'Recommandations',
	compare: 'Comparaison de produits',
	decision: 'Garder ou abandonner un produit',
	quotes: 'Devis clients',
	orders: 'Bons de commande clients',
	deliveries: 'Bons de livraison',
	depots: 'Dépôts cliniques',
	invoices: 'Factures clients',
	credits: 'Avoirs clients',
	clients: 'Fichier clients',
	purchases: 'Commandes fournisseurs',
	receipts: 'Bons de réception',
	bills: 'Factures fournisseurs',
	suppliers: 'Fichier fournisseurs',
	lots: 'Lots, péremptions & traçabilité',
	kits: 'Kits',
	vat: 'Déclaration de TVA',
	company: 'Société et mise en page des documents',
	backup: 'Sauvegarde des données',
	users: 'Utilisateurs et droits d’accès',
	sync: 'Multi-postes : utiliser l’ERP sur plusieurs ordinateurs',
	audit: 'Journal d’activité',
}

// Correspondance entre les pages et les types de pièces commerciales
const docPages: Partial<Record<PageId, DocKind>> = {
	quotes: 'quote',
	orders: 'order',
	deliveries: 'delivery',
	invoices: 'invoice',
	credits: 'credit',
	purchases: 'purchase',
	receipts: 'receipt',
	bills: 'bill',
}
const pageOfKind: Record<DocKind, PageId> = {
	quote: 'quotes',
	order: 'orders',
	delivery: 'deliveries',
	invoice: 'invoices',
	credit: 'credits',
	purchase: 'purchases',
	receipt: 'receipts',
	bill: 'bills',
}

// Écrans de gestion commerciale : montants en dirhams, sans sélecteur de devise ni export produits
const commercialPages = new Set<PageId>([
	...Object.keys(docPages),
	'home',
	'depots',
	'clients',
	'suppliers',
	'lots',
	'kits',
	'alerts',
	'movements',
	'inventory',
	'stats',
	'schedule',
	'vat',
	'company',
	'backup',
	'users',
	'audit',
	'sync',
] as PageId[])

function isProduct(x: unknown): x is Product {
	if (typeof x !== 'object' || x === null) return false
	const p = x as Record<string, unknown>
	return (
		typeof p.id === 'string' &&
		typeof p.name === 'string' &&
		typeof p.category === 'string' &&
		typeof p.unitPrice === 'number' &&
		typeof p.unitCost === 'number' &&
		typeof p.unitsSold === 'number'
	)
}

function isFixedCost(x: unknown): x is FixedCost {
	if (typeof x !== 'object' || x === null) return false
	const f = x as Record<string, unknown>
	return typeof f.id === 'string' && typeof f.label === 'string' && typeof f.amount === 'number'
}

function loadSaved(): { products: Product[]; isSampleData: boolean } | null {
	try {
		const raw = localStorage.getItem(STORAGE_KEY)
		if (!raw) return null
		const data: unknown = JSON.parse(raw)
		if (typeof data !== 'object' || data === null) return null
		const { products, isSampleData } = data as { products?: unknown; isSampleData?: unknown }
		if (!Array.isArray(products) || !products.every(isProduct)) return null
		return { products, isSampleData: isSampleData === true }
	} catch {
		return null
	}
}

function loadFixedCosts(): FixedCost[] {
	try {
		const raw = localStorage.getItem(FIXED_KEY)
		if (!raw) return []
		const data: unknown = JSON.parse(raw)
		if (!Array.isArray(data) || !data.every(isFixedCost)) return []
		return data
	} catch {
		return []
	}
}

function loadCurrency(): string {
	try {
		const code = localStorage.getItem(CURRENCY_KEY)
		if (code && CURRENCIES.some((c) => c.code === code)) return code
	} catch {
		// stockage indisponible
	}
	return 'EUR'
}

export default function App() {
	const [initial] = useState(loadSaved)
	const [page, setPage] = useState<PageId>('home')
	// Onglets de travail : écrans ouverts récemment
	const [tabs, setTabs] = useState<PageId[]>(['home'])
	const [searchOpen, setSearchOpen] = useState(false)
	const [lotQuery, setLotQuery] = useState('')
	const [partyId, setPartyId] = useState<string | undefined>()
	// Pièce à ouvrir directement en arrivant sur une page (après une conversion ou une facturation de dépôt)
	const [openId, setOpenId] = useState<string | undefined>()
	const [products, setProducts] = useState<Product[]>(initial?.products ?? sampleProducts)
	const [isSampleData, setIsSampleData] = useState(initial?.isSampleData ?? true)
	const [fixedCosts, setFixedCosts] = useState<FixedCost[]>(loadFixedCosts)
	// La devise est appliquée une seule fois au chargement, puis à chaque changement (plus d'effet de bord pendant le rendu)
	const [currency, setCurrencyState] = useState(() => {
		const code = loadCurrency()
		setCurrency(code)
		return code
	})
	const [documents, setDocuments] = useDocuments()
	const [company, setCompany] = useCompany()
	const [lots, setLots] = useLots()
	const [kits, setKits] = useKits()
	const [parties, setParties] = useParties()
	const [movements, setMovements] = useMovements()
	const [cash, setCash] = useCashBalance()
	// Bandeau d'alerte de stock masquable jusqu'au prochain chargement
	const [alertBannerHidden, setAlertBannerHidden] = useState(false)

	// ---------- Utilisateurs, session et journal d'activité ----------
	const [users, setUsers] = useUsers()
	const [audit, setAudit] = useAudit()
	const [accessSettings, setAccessSettings] = useAccessSettings()
	const [sessionId, setSessionId] = useState(readSession)
	const [locked, setLocked] = useState(false)
	const currentUser = users.find((u) => u.id === sessionId && u.active) ?? null
	const needsLogin = users.length > 0 && (!currentUser || locked)

	const log = useCallback(
		(action: string, detail: string, who?: string) => {
			const entry: AuditEntry = { id: newId(), at: new Date().toISOString(), user: who ?? currentUser?.name ?? 'Administrateur (installation)', action, detail }
			// On garde les 5 000 dernières actions
			setAudit((a) => [...a, entry].slice(-5000))
		},
		[currentUser, setAudit],
	)
	const access = useMemo(() => accessFor(currentUser, log), [currentUser, log])

	function login(user: User) {
		const at = new Date().toISOString()
		setUsers((list) => list.map((u) => (u.id === user.id ? { ...u, lastLogin: at } : u)))
		writeSession(user.id)
		setSessionId(user.id)
		log(locked && user.id === sessionId ? 'Session déverrouillée' : 'Connexion', user.name, user.name)
		// Changement d'utilisateur : on repart de l'accueil (pas à la création du premier compte)
		if (sessionId && user.id !== sessionId) {
			setPage('home')
			setTabs(['home'])
		}
		setLocked(false)
	}

	function logout() {
		log('Déconnexion', currentUser?.name ?? '')
		writeSession(null)
		setSessionId(null)
		setLocked(false)
		setPage('home')
		setTabs(['home'])
	}

	// Verrouillage automatique après inactivité
	useEffect(() => {
		if (!currentUser || locked || !accessSettings.lockMinutes) return
		let timer = window.setTimeout(() => setLocked(true), accessSettings.lockMinutes * 60_000)
		const reset = () => {
			window.clearTimeout(timer)
			timer = window.setTimeout(() => setLocked(true), accessSettings.lockMinutes * 60_000)
		}
		const events = ['mousemove', 'keydown', 'click', 'scroll', 'touchstart']
		for (const e of events) window.addEventListener(e, reset, { passive: true })
		return () => {
			window.clearTimeout(timer)
			for (const e of events) window.removeEventListener(e, reset)
		}
	}, [currentUser, locked, accessSettings.lockMinutes])

	useEffect(() => {
		try {
			const raw = JSON.stringify({ products, isSampleData })
			if (localStorage.getItem(STORAGE_KEY) !== raw) localStorage.setItem(STORAGE_KEY, raw)
		} catch {
			window.dispatchEvent(new CustomEvent(STORAGE_ERROR_EVENT, { detail: STORAGE_KEY }))
		}
	}, [products, isSampleData])

	// Stockage plein : on prévient au lieu de perdre les saisies en silence
	const [storageFull, setStorageFull] = useState(false)
	useEffect(() => {
		const onError = () => setStorageFull(true)
		// Articles modifiés dans un autre onglet : on reprend leur version
		const onStorage = (e: StorageEvent) => {
			if (e.key !== STORAGE_KEY || !e.newValue) return
			const saved = loadSaved()
			if (saved) {
				setProducts(saved.products)
				setIsSampleData(saved.isSampleData)
			}
		}
		window.addEventListener(STORAGE_ERROR_EVENT, onError)
		window.addEventListener('storage', onStorage)
		return () => {
			window.removeEventListener(STORAGE_ERROR_EVENT, onError)
			window.removeEventListener('storage', onStorage)
		}
	}, [])

	useEffect(() => {
		try {
			const raw = JSON.stringify(fixedCosts)
			if (localStorage.getItem(FIXED_KEY) !== raw) localStorage.setItem(FIXED_KEY, raw)
		} catch {
			window.dispatchEvent(new CustomEvent(STORAGE_ERROR_EVENT, { detail: FIXED_KEY }))
		}
	}, [fixedCosts])

	// Charges fixes et devise modifiées sur un autre poste ou un autre onglet
	useEffect(() => {
		const onStorage = (e: StorageEvent) => {
			if (e.key === FIXED_KEY) setFixedCosts(loadFixedCosts())
			if (e.key === CURRENCY_KEY) {
				const code = loadCurrency()
				setCurrency(code)
				setCurrencyState(code)
			}
		}
		window.addEventListener('storage', onStorage)
		return () => window.removeEventListener('storage', onStorage)
	}, [])

	// Mode multi-postes : reprise de la synchronisation au lancement
	useEffect(() => {
		startFromConfig()
	}, [])
	const syncStatus = useSyncStatus()

	function changeCurrency(code: string) {
		setCurrency(code)
		setCurrencyState(code)
		try {
			localStorage.setItem(CURRENCY_KEY, code)
		} catch {
			// stockage indisponible : on continue sans sauvegarde
		}
	}

	function show(next: PageId) {
		setPage(next)
		setTabs((t) => (t.includes(next) ? t : [...t, next].slice(-8)))
	}

	function navigate(next: PageId) {
		setOpenId(undefined)
		setPartyId(undefined)
		setLotQuery('')
		show(next)
	}

	function openDocument(kind: DocKind, id?: string) {
		setOpenId(id)
		show(pageOfKind[kind])
	}

	function closeTab(t: PageId) {
		const rest = tabs.filter((x) => x !== t)
		const next = rest.length ? rest : (['home'] as PageId[])
		setTabs(next)
		if (t === page) navigate(next[next.length - 1])
	}

	function pickSearch(hit: SearchHit) {
		setSearchOpen(false)
		if (hit.type === 'doc') return openDocument(hit.doc.kind, hit.doc.id)
		if (hit.type === 'party') {
			navigate(hit.party.role === 'client' ? 'clients' : 'suppliers')
			return setPartyId(hit.party.id)
		}
		if (hit.type === 'product') return navigate('catalog')
		navigate('lots')
		setLotQuery(hit.lot.serial || hit.lot.lot)
	}

	// Raccourcis clavier : Cmd/Ctrl+K recherche, Alt+1…7 modules
	useEffect(() => {
		function onKey(e: KeyboardEvent) {
			if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
				e.preventDefault()
				setSearchOpen((o) => !o)
			}
			if (e.altKey && /^[1-7]$/.test(e.key)) {
				e.preventDefault()
				const m = MODULES[Number(e.key) - 1]
				setOpenId(undefined)
				setPage(m.groups[0].pages[0])
				setTabs((t) => (t.includes(m.groups[0].pages[0]) ? t : [...t, m.groups[0].pages[0]].slice(-8)))
			}
		}
		window.addEventListener('keydown', onKey)
		return () => window.removeEventListener('keydown', onKey)
	}, [])

	function handleEdit(next: Product[]) {
		setProducts(next)
		setIsSampleData(false)
	}

	// BL, réceptions et retours de dépôt : mise à jour du stock des articles et des lots
	// Dernières valeurs connues : un mouvement de stock peut suivre une attente réseau (validation multi-postes)
	const latest = useRef({ products, lots })
	useEffect(() => {
		latest.current = { products, lots }
	}, [products, lots])

	function handleStockMove(lines: DocLine[], direction: 1 | -1, supplier?: string, reference?: string): Record<string, number> {
		const result = applyMove(latest.current, lines, direction, supplier, reference)
		latest.current = { products: result.products, lots: result.lots }
		handleEdit(result.products)
		setLots(result.lots)
		addMovements(result.movements)
		if (result.shortages.length) alert('Stock insuffisant, ramené à 0 pour :\n' + result.shortages.join('\n'))
		return result.moved
	}

	function addMovements(added: StockMovement[]) {
		if (added.length) setMovements((m) => [...m, ...added])
	}

	function handleImport(imported: Product[]) {
		setProducts(imported)
		setIsSampleData(false)
		navigate('dashboard')
	}

	function handleResetSample() {
		setProducts(sampleProducts)
		setIsSampleData(true)
		navigate('dashboard')
	}

	const docKind = docPages[page]
	const stockAlerts = useMemo(() => {
		let out = 0
		let low = 0
		for (const p of products) {
			const status = getStockStatus(p)
			if (status === 'out') out++
			if (status === 'low') low++
		}
		const expired = lots.filter((l) => l.quantity > 0 && expiryState(l.expiry) === 'expired').length
		return { out, low, expired, total: out + low + expired }
	}, [products, lots])

	const badges = useMemo(() => {
		const overdue = (kind: DocKind) => documents.filter((d) => d.kind === kind && isOverdue(d, documents)).length
		return {
			alerts: stockAlerts.total,
			invoices: overdue('invoice'),
			bills: overdue('bill'),
			lots: lots.filter((l) => l.quantity > 0 && ['expired', 'soon'].includes(expiryState(l.expiry))).length,
			depots: documents.reduce(
				(n, d) => n + (d.consignment && d.status === 'validated' ? d.lines.filter((l) => l.depot === 'depot').length : 0),
				0,
			),
		}
	}, [documents, lots, stockAlerts])

	const lastBackup = (() => {
		try {
			return localStorage.getItem(LAST_BACKUP_KEY) ?? ''
		} catch {
			return ''
		}
	})()

	const notifications = useMemo<Notification[]>(() => {
		const list: Notification[] = []
		if (badges.invoices) list.push({ id: 'inv', severity: 'danger', page: 'invoices', text: `${badges.invoices} facture(s) client échue(s) à relancer` })
		if (badges.bills) list.push({ id: 'bill', severity: 'warning', page: 'bills', text: `${badges.bills} facture(s) fournisseur échue(s)` })
		if (stockAlerts.out) list.push({ id: 'out', severity: 'danger', page: 'alerts', text: `${stockAlerts.out} article(s) en rupture de stock` })
		if (stockAlerts.low) list.push({ id: 'low', severity: 'warning', page: 'alerts', text: `${stockAlerts.low} article(s) sous le seuil d'alerte` })
		if (stockAlerts.expired) list.push({ id: 'exp', severity: 'danger', page: 'lots', text: `${stockAlerts.expired} lot(s) périmé(s) à retirer` })
		if (badges.depots) list.push({ id: 'dep', severity: 'info', page: 'depots', text: `${badges.depots} implant(s) en dépôt chez les cliniques` })
		if (!lastBackup || daysBetween(lastBackup, today()) > 7)
			list.push({ id: 'bak', severity: 'warning', page: 'backup', text: lastBackup ? 'Dernière sauvegarde il y a plus de 7 jours' : 'Aucune sauvegarde effectuée' })
		// Chacun ne voit que les alertes des modules qui lui sont ouverts
		return list.filter((n) => access.level(moduleOf(n.page).id) !== 'none')
	}, [badges, stockAlerts, lastBackup, access])

	const currentModule = moduleOf(page)
	const pageLevel = access.level(currentModule.id)
	const pageAllowed = pageLevel !== 'none' && (access.isAdmin || !ADMIN_PAGES.includes(page))
	// Pages d'origine sans gestion des droits : en lecture seule, on désactive leurs champs
	const lockFields = ['catalog', 'stock', 'import', 'breakeven'].includes(page)

	// Recherche limitée à ce que l'utilisateur a le droit de voir
	const searchable = {
		documents: documents.filter((d) => access.level(d.kind === 'purchase' || d.kind === 'receipt' || d.kind === 'bill' ? 'purchases' : 'sales') !== 'none'),
		parties: parties.filter((p) => access.level(p.role === 'client' ? 'sales' : 'purchases') !== 'none'),
		products: access.level('stock') !== 'none' ? products : [],
		lots: access.level('stock') !== 'none' ? lots : [],
	}

	if (needsLogin)
		return (
			<LoginScreen
				users={users}
				companyName={company.name}
				logo={company.logo}
				lockedUser={locked && currentUser ? currentUser : undefined}
				onLogin={login}
			/>
		)

	const moduleBadges: Partial<Record<ModuleId, number>> = {
		sales: badges.invoices,
		purchases: badges.bills,
		stock: stockAlerts.total,
	}

	return (
		<AccessContext.Provider value={access}>
		<div className="layout erp">
			<TopBar
				companyName={company.name}
				notifications={notifications}
				onSearch={() => setSearchOpen(true)}
				onNavigate={navigate}
				onCreate={(kind) => openDocument(kind, 'new')}
				onLock={() => {
					log('Session verrouillée', currentUser?.name ?? '')
					setLocked(true)
				}}
				onLogout={logout}
			/>
			<ModuleBar current={currentModule.id} onOpen={navigate} badges={moduleBadges} />
			<div className="erp-body">
			{currentModule.id !== 'home' && (
				<Sidebar module={currentModule} current={page} onNavigate={navigate} badges={badges} />
			)}
			<main className="content">
				<WorkTabs tabs={tabs} current={page} onOpen={navigate} onClose={closeTab} />
				<div className="erp-breadcrumb no-print">
					<button type="button" onClick={() => navigate('home')}>
						Accueil
					</button>
					{currentModule.id !== 'home' && (
						<>
							<span>›</span>
							<button type="button" onClick={() => navigate(currentModule.groups[0].pages[0])}>
								{currentModule.label}
							</button>
						</>
					)}
					{page !== 'home' && (
						<>
							<span>›</span>
							<strong>{titles[page]}</strong>
						</>
					)}
				</div>
				<p className="print-only">
					ProfitPilot · {titles[page]} · {new Date().toLocaleDateString('fr-FR')} · {currency}
					{isSampleData ? ' · données de démonstration' : ''}
				</p>
				{storageFull && (
					<div className="stock-alert-banner no-print">
						<span>
							<strong>Espace de stockage plein :</strong> vos dernières modifications n'ont pas pu être enregistrées.
							Téléchargez une sauvegarde tout de suite, puis allégez les images (logo, papier à en-tête) ou le
							journal d'activité.
						</span>
						<button type="button" onClick={() => navigate('backup')}>
							Sauvegarde
						</button>
					</div>
				)}
				{page !== 'home' && <h1>{titles[page]}</h1>}
				{stockAlerts.total > 0 && !alertBannerHidden && page !== 'alerts' && page !== 'home' && access.level('stock') !== 'none' && (
					<div className="stock-alert-banner no-print">
						<span>
							<strong>Alerte stock :</strong>{' '}
							{[
								stockAlerts.out && `${stockAlerts.out} rupture(s)`,
								stockAlerts.low && `${stockAlerts.low} article(s) sous le seuil`,
								stockAlerts.expired && `${stockAlerts.expired} lot(s) périmé(s)`,
							]
								.filter(Boolean)
								.join(' · ')}
						</span>
						<button type="button" onClick={() => navigate('alerts')}>
							Voir les alertes
						</button>
						<button type="button" className="stock-alert-close" title="Masquer" onClick={() => setAlertBannerHidden(true)}>
							✕
						</button>
					</div>
				)}
				{!pageAllowed && <AccessDenied />}
				{pageAllowed && (
				<ReadOnlyArea readOnly={pageLevel === 'read'} lock={lockFields}>
				{!commercialPages.has(page) && (
					<>
						<div className="export-bar" style={{ alignItems: 'center' }}>
							<label style={{ fontSize: 14 }}>
								Devise :{' '}
								<select value={currency} onChange={(e) => changeCurrency(e.target.value)}>
									{CURRENCIES.map((c) => (
										<option key={c.code} value={c.code}>
											{c.label}
										</option>
									))}
								</select>
							</label>
						</div>
						<ExportBar products={products} />
					</>
				)}
				{page === 'home' && (
					<Launchpad
						companyName={company.name}
						documents={documents}
						products={products}
						lots={lots}
						cash={cash}
						onNavigate={navigate}
						onOpenDocument={openDocument}
						onCreate={(kind) => openDocument(kind, 'new')}
					/>
				)}
				{page === 'dashboard' && (
					<Dashboard products={products} documents={documents} lots={lots} onNavigate={navigate} />
				)}
				{page === 'catalog' && (
					<ProductEditor
						products={products}
						isSampleData={isSampleData}
						onChange={handleEdit}
						onResetSample={handleResetSample}
					/>
				)}
				{page === 'stock' && <StockPage products={products} onChange={handleEdit} />}
				{page === 'products' && <ProductProfitability products={products} />}
				{page === 'breakeven' && (
					<BreakEven products={products} fixedCosts={fixedCosts} onChange={setFixedCosts} />
				)}
				{page === 'import' && (
					<ImportCsv
						currentCount={products.length}
						isSampleData={isSampleData}
						onImport={handleImport}
						onResetSample={handleResetSample}
					/>
				)}
				{page === 'simulator' && <Simulator products={products} />}
				{page === 'recommendations' && <Recommendations products={products} />}
				{page === 'compare' && <Compare products={products} />}
				{page === 'decision' && <Decision products={products} />}
				{docKind && (
					<DocumentsPage
						key={docKind + (openId ?? '')} // réinitialise la vue en changeant de page
						kind={docKind}
						documents={documents}
						onChange={setDocuments}
						products={products}
						lots={lots}
						kits={kits}
						parties={parties}
						onPartiesChange={setParties}
						company={company}
						openId={openId}
						onNavigate={openDocument}
						onStockMove={handleStockMove}
					/>
				)}
				{page === 'depots' && (
					<DepotPage
						documents={documents}
						onChange={setDocuments}
						onNavigate={openDocument}
						onStockMove={handleStockMove}
					/>
				)}
				{page === 'clients' && (
					<PartiesPage key={partyId} role="client" parties={parties} onChange={setParties} documents={documents} company={company} openId={partyId} />
				)}
				{page === 'suppliers' && (
					<PartiesPage key={partyId} role="supplier" parties={parties} onChange={setParties} documents={documents} company={company} openId={partyId} />
				)}
				{page === 'lots' && (
					<LotsPage key={lotQuery} lots={lots} onChange={setLots} products={products} documents={documents} initialQuery={lotQuery} />
				)}
				{page === 'alerts' && (
					<StockAlertsPage
						products={products}
						lots={lots}
						documents={documents}
						onChange={setDocuments}
						onNavigate={openDocument}
						onOpenStock={() => navigate('stock')}
					/>
				)}
				{page === 'movements' && <StockMovesPage movements={movements} products={products} />}
				{page === 'inventory' && (
					<InventoryPage products={products} onProductsChange={handleEdit} onMovements={addMovements} />
				)}
				{page === 'stats' && <StatsPage documents={documents} products={products} />}
				{page === 'schedule' && (
					<SchedulePage documents={documents} cash={cash} onCashChange={setCash} onNavigate={openDocument} />
				)}
				{page === 'kits' && <KitsPage kits={kits} onChange={setKits} products={products} />}
				{page === 'vat' && <VatPage documents={documents} />}
				{page === 'company' && <CompanySettings company={company} onChange={setCompany} />}
				{page === 'backup' && <BackupPage />}
				{page === 'users' && (
					<UsersPage
						users={users}
						onChange={setUsers}
						settings={accessSettings}
						onSettingsChange={setAccessSettings}
						onFirstAdmin={login}
					/>
				)}
				{page === 'audit' && <AuditPage entries={audit} />}
				{page === 'sync' && <SyncPage />}
				</ReadOnlyArea>
				)}
			</main>
			</div>
			<StatusBar
				companyName={company.name}
				documentsCount={documents.length}
				productsCount={products.length}
				lastBackup={lastBackup}
				sync={syncStatus}
				onOpenSync={() => navigate('sync')}
			/>
			{searchOpen && (
				<GlobalSearch
					documents={searchable.documents}
					parties={searchable.parties}
					products={searchable.products}
					lots={searchable.lots}
					onPick={pickSearch}
					onClose={() => setSearchOpen(false)}
				/>
			)}
		</div>
		</AccessContext.Provider>
	)
}
