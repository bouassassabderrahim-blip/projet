import { useEffect, useMemo, useState } from 'react'
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
import { getStockStatus } from './utils/stock'
import { isOverdue } from './documents/ledger'
import { applyMove, expiryState } from './documents/stockMoves'
import { useCompany, useDocuments, useKits, useLots, useParties } from './documents/storage'
import type { DocKind, DocLine } from './documents/types'
import { CURRENCIES, setCurrency } from './utils/finance'
import './theme.css'
import './documents/documents.css'
import './pro-theme.css'

const STORAGE_KEY = 'profitpilot:v1'
const FIXED_KEY = 'profitpilot:fixed:v1'
const CURRENCY_KEY = 'profitpilot:currency:v1'

const titles: Record<PageId, string> = {
	dashboard: 'Tableau de bord',
	catalog: 'Mes produits',
	stock: 'Gestion du stock',
	alerts: 'Alertes de stock',
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
	company: 'Mon entreprise',
	backup: 'Sauvegarde des données',
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
	'depots',
	'clients',
	'suppliers',
	'lots',
	'kits',
	'alerts',
	'vat',
	'company',
	'backup',
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
	const [page, setPage] = useState<PageId>('dashboard')
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
	// Bandeau d'alerte de stock masquable jusqu'au prochain chargement
	const [alertBannerHidden, setAlertBannerHidden] = useState(false)

	useEffect(() => {
		try {
			localStorage.setItem(STORAGE_KEY, JSON.stringify({ products, isSampleData }))
		} catch {
			// stockage indisponible : on continue sans sauvegarde
		}
	}, [products, isSampleData])

	useEffect(() => {
		try {
			localStorage.setItem(FIXED_KEY, JSON.stringify(fixedCosts))
		} catch {
			// stockage indisponible : on continue sans sauvegarde
		}
	}, [fixedCosts])

	function changeCurrency(code: string) {
		setCurrency(code)
		setCurrencyState(code)
		try {
			localStorage.setItem(CURRENCY_KEY, code)
		} catch {
			// stockage indisponible : on continue sans sauvegarde
		}
	}

	function navigate(next: PageId) {
		setOpenId(undefined)
		setPage(next)
	}

	function openDocument(kind: DocKind, id?: string) {
		setOpenId(id)
		setPage(pageOfKind[kind])
	}

	function handleEdit(next: Product[]) {
		setProducts(next)
		setIsSampleData(false)
	}

	// BL, réceptions et retours de dépôt : mise à jour du stock des articles et des lots
	function handleStockMove(lines: DocLine[], direction: 1 | -1, supplier?: string) {
		const result = applyMove({ products, lots }, lines, direction, supplier)
		handleEdit(result.products)
		setLots(result.lots)
		if (result.shortages.length) alert('Stock insuffisant, ramené à 0 pour :\n' + result.shortages.join('\n'))
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

	return (
		<div className="layout">
			<Sidebar current={page} onNavigate={navigate} badges={badges} />
			<main className="content">
				<p className="print-only">
					ProfitPilot · {titles[page]} · {new Date().toLocaleDateString('fr-FR')} · {currency}
					{isSampleData ? ' · données de démonstration' : ''}
				</p>
				<h1>{titles[page]}</h1>
				{stockAlerts.total > 0 && !alertBannerHidden && page !== 'alerts' && (
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
					<PartiesPage role="client" parties={parties} onChange={setParties} documents={documents} company={company} />
				)}
				{page === 'suppliers' && (
					<PartiesPage role="supplier" parties={parties} onChange={setParties} documents={documents} company={company} />
				)}
				{page === 'lots' && <LotsPage lots={lots} onChange={setLots} products={products} documents={documents} />}
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
				{page === 'kits' && <KitsPage kits={kits} onChange={setKits} products={products} />}
				{page === 'vat' && <VatPage documents={documents} />}
				{page === 'company' && <CompanySettings company={company} onChange={setCompany} />}
				{page === 'backup' && <BackupPage />}
			</main>
		</div>
	)
}
