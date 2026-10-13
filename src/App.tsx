import { useEffect, useState } from 'react'
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
import { useCompany, useDocuments } from './documents/storage'
import type { DocKind } from './documents/types'
import { CURRENCIES, setCurrency } from './utils/finance'
import './theme.css'

const STORAGE_KEY = 'profitpilot:v1'
const FIXED_KEY = 'profitpilot:fixed:v1'
const CURRENCY_KEY = 'profitpilot:currency:v1'

const titles: Record<PageId, string> = {
	dashboard: 'Tableau de bord',
	catalog: 'Mes produits',
	stock: 'Gestion du stock',
	products: 'Rentabilité par produit',
	breakeven: 'Résultat & seuil de rentabilité',
	import: 'Import de fichiers CSV',
	simulator: 'Simulateur de prix et de coûts',
	recommendations: 'Recommandations',
	compare: 'Comparaison de produits',
	decision: 'Garder ou abandonner un produit',
	invoices: 'Factures',
	orders: 'Bons de commande',
	deliveries: 'Bons de livraison',
	company: 'Mon entreprise',
}

// Correspondance entre les pages et les types de documents commerciaux
const docPages: Partial<Record<PageId, DocKind>> = {
	invoices: 'invoice',
	orders: 'order',
	deliveries: 'delivery',
}
const pageOfKind: Record<DocKind, PageId> = {
	invoice: 'invoices',
	order: 'orders',
	delivery: 'deliveries',
}

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

	function handleEdit(next: Product[]) {
		setProducts(next)
		setIsSampleData(false)
	}

	function handleImport(imported: Product[]) {
		setProducts(imported)
		setIsSampleData(false)
		setPage('dashboard')
	}

	function handleResetSample() {
		setProducts(sampleProducts)
		setIsSampleData(true)
		setPage('dashboard')
	}

	const docKind = docPages[page]

	return (
		<div className="layout">
			<Sidebar current={page} onNavigate={setPage} />
			<main className="content">
				<p className="print-only">
					ProfitPilot · {titles[page]} · {new Date().toLocaleDateString('fr-FR')} · {currency}
					{isSampleData ? ' · données de démonstration' : ''}
				</p>
				<h1>{titles[page]}</h1>
				{/* Les documents commerciaux sont toujours en dirhams : pas de sélecteur de devise ni d'export produits */}
				{!docKind && page !== 'company' && (
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
				{page === 'dashboard' && <Dashboard products={products} />}
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
						key={docKind} // réinitialise la vue (liste) en changeant de page
						kind={docKind}
						documents={documents}
						onChange={setDocuments}
						products={products}
						company={company}
						onNavigate={(k) => setPage(pageOfKind[k])}
						// Si votre type Product a un champ de stock, décrémentez-le ici à la validation d'un BL :
						// onDelivered={(lines) => handleEdit(products.map((p) => {
						// 	const qty = lines.filter((l) => l.productId === p.id).reduce((s, l) => s + l.quantity, 0)
						// 	return qty ? { ...p, stock: p.stock - qty } : p
						// }))}
					/>
				)}
				{page === 'company' && <CompanySettings company={company} onChange={setCompany} />}
			</main>
		</div>
	)
}
