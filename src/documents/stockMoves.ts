// Mouvements de stock déclenchés par les BL, les réceptions et les retours de dépôt
import type { Product } from '../types'
import { isoDate, newId, today } from './numbering'
import type { DocLine, StockLot, StockMovement } from './types'

export interface StockState {
	products: Product[]
	lots: StockLot[]
}

export interface MoveResult extends StockState {
	/** Articles dont le stock était insuffisant (ramené à 0) */
	shortages: string[]
	/** Lignes du journal des mouvements */
	movements: StockMovement[]
	/** Quantité réellement déplacée, par ligne de pièce */
	moved: Record<string, number>
}

/**
 * direction = -1 : sortie (BL validé, réception annulée)
 * direction = +1 : entrée (réception validée, BL annulé, retour de dépôt)
 */
export function applyMove(
	state: StockState,
	lines: DocLine[],
	direction: 1 | -1,
	supplier = '',
	reference = '',
): MoveResult {
	const products = new Map(state.products.map((p) => [p.id, { ...p }]))
	const lots = state.lots.map((l) => ({ ...l }))
	const shortages: string[] = []
	const movements: StockMovement[] = []
	const moved: Record<string, number> = {}

	for (const line of lines) {
		if (!line.productId || line.quantity <= 0) continue
		const q = line.quantity * direction
		const product = products.get(line.productId)

		if (product) {
			if (product.stock === undefined) {
				// Une première réception démarre le suivi du stock
				if (direction > 0) product.stock = line.quantity
			} else {
				if (product.stock + q < 0) shortages.push(`${product.name} (stock ${product.stock}, sortie ${line.quantity})`)
				// Une sortie ne peut pas dépasser le stock : on retient ce qui est réellement sorti
				moved[line.id] = direction < 0 ? Math.min(product.stock, line.quantity) : line.quantity
				product.stock = Math.max(0, product.stock + q)
			}
		}

		// Lot : par identifiant, sinon par numéro de lot / série
		const hasTrace = !!(line.lot || line.serial)
		let lot =
			lots.find((l) => l.id === line.lotId) ??
			(hasTrace
				? lots.find(
						(l) => l.productId === line.productId && l.lot === (line.lot ?? '') && l.serial === (line.serial ?? ''),
					)
				: undefined)
		if (!lot && direction > 0 && hasTrace) {
			lot = {
				id: newId(),
				productId: line.productId,
				lot: line.lot ?? '',
				serial: line.serial ?? '',
				expiry: line.expiry ?? '',
				quantity: 0,
				receivedDate: today(),
				supplier,
			}
			lots.push(lot)
		}
		if (lot) {
			lot.quantity = Math.max(0, lot.quantity + q)
			if (direction > 0 && line.expiry && !lot.expiry) lot.expiry = line.expiry
		}

		movements.push({
			id: newId(),
			date: today(),
			productId: line.productId,
			productName: product?.name ?? line.description,
			lot: line.lot ?? '',
			serial: line.serial ?? '',
			quantity: moved[line.id] !== undefined ? moved[line.id] * direction : q,
			kind: direction > 0 ? 'in' : 'out',
			reference,
			stockAfter: product?.stock,
		})
	}

	return { products: state.products.map((p) => products.get(p.id) ?? p), lots, shortages, movements, moved }
}

export type ExpiryState = 'expired' | 'soon' | 'ok' | 'none'

/** Péremption : « soon » = dans les 90 jours */
export function expiryState(expiry: string, now = today(), soonDays = 90): ExpiryState {
	if (!expiry) return 'none'
	if (expiry < now) return 'expired'
	const limit = new Date(now + 'T00:00:00')
	limit.setDate(limit.getDate() + soonDays)
	return expiry <= isoDate(limit) ? 'soon' : 'ok'
}

/** Lots disponibles d'un produit, du plus proche de la péremption au plus lointain (FEFO) */
export function availableLots(lots: StockLot[], productId: string | undefined): StockLot[] {
	if (!productId) return []
	return lots
		.filter((l) => l.productId === productId && l.quantity > 0)
		.sort((a, b) => (a.expiry || '9999').localeCompare(b.expiry || '9999'))
}
