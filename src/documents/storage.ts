import { useEffect, useState } from 'react'
import { emptyCompany, type CommercialDocument, type CompanyInfo, type Kit, type PartyRecord, type StockLot } from './types'

export const DOCS_KEY = 'profitpilot:documents:v1'
export const COMPANY_KEY = 'profitpilot:company:v1'
export const LOTS_KEY = 'profitpilot:lots:v1'
export const KITS_KEY = 'profitpilot:kits:v1'
export const PARTIES_KEY = 'profitpilot:parties:v1'
export const LAST_BACKUP_KEY = 'profitpilot:last-backup'

/** État React sauvegardé dans le localStorage, avec validation à la relecture */
export function usePersistentState<T>(key: string, fallback: () => T, isValid: (x: unknown) => x is T) {
	const [value, setValue] = useState<T>(() => {
		try {
			const raw = localStorage.getItem(key)
			if (raw) {
				const data: unknown = JSON.parse(raw)
				if (isValid(data)) return data
			}
		} catch {
			// stockage indisponible ou données corrompues
		}
		return fallback()
	})

	useEffect(() => {
		try {
			localStorage.setItem(key, JSON.stringify(value))
		} catch {
			// stockage indisponible : on continue sans sauvegarde
		}
	}, [key, value])

	return [value, setValue] as const
}

const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null

const KINDS = ['quote', 'order', 'delivery', 'invoice', 'credit', 'purchase', 'receipt', 'bill']

function isDocument(x: unknown): x is CommercialDocument {
	return (
		isObj(x) &&
		typeof x.id === 'string' &&
		KINDS.includes(x.kind as string) &&
		typeof x.number === 'string' &&
		typeof x.date === 'string' &&
		isObj(x.party) &&
		Array.isArray(x.lines)
	)
}

const listOf =
	<T,>(check: (x: unknown) => boolean) =>
	(x: unknown): x is T[] =>
		Array.isArray(x) && x.every(check)

export const isDocumentList = listOf<CommercialDocument>(isDocument)

export const isCompany = (x: unknown): x is CompanyInfo => isObj(x) && typeof x.name === 'string'

const isLotList = listOf<StockLot>(
	(x) => isObj(x) && typeof x.id === 'string' && typeof x.productId === 'string' && typeof x.quantity === 'number',
)
const isKitList = listOf<Kit>((x) => isObj(x) && typeof x.id === 'string' && Array.isArray(x.items))
const isPartyList = listOf<PartyRecord>(
	(x) => isObj(x) && typeof x.id === 'string' && typeof x.name === 'string' && (x.role === 'client' || x.role === 'supplier'),
)

export const useDocuments = () => usePersistentState<CommercialDocument[]>(DOCS_KEY, () => [], isDocumentList)
export const useCompany = () => usePersistentState<CompanyInfo>(COMPANY_KEY, emptyCompany, isCompany)
export const useLots = () => usePersistentState<StockLot[]>(LOTS_KEY, () => [], isLotList)
export const useKits = () => usePersistentState<Kit[]>(KITS_KEY, () => [], isKitList)
export const useParties = () => usePersistentState<PartyRecord[]>(PARTIES_KEY, () => [], isPartyList)

// ---------- Sauvegarde complète ----------

export interface BackupFile {
	app: 'profitpilot'
	version: 1
	createdAt: string
	data: Record<string, string>
}

/** Toutes les données de l'application (clés profitpilot:*) */
export function createBackup(): BackupFile {
	const data: Record<string, string> = {}
	for (let i = 0; i < localStorage.length; i++) {
		const key = localStorage.key(i)
		if (key && key.startsWith('profitpilot:') && key !== LAST_BACKUP_KEY) data[key] = localStorage.getItem(key) ?? ''
	}
	return { app: 'profitpilot', version: 1, createdAt: new Date().toISOString(), data }
}

export function isBackupFile(x: unknown): x is BackupFile {
	return isObj(x) && x.app === 'profitpilot' && isObj(x.data)
}

/** Remplace toutes les données par celles de la sauvegarde */
export function restoreBackup(backup: BackupFile) {
	const old: string[] = []
	for (let i = 0; i < localStorage.length; i++) {
		const key = localStorage.key(i)
		if (key && key.startsWith('profitpilot:') && key !== LAST_BACKUP_KEY) old.push(key)
	}
	for (const key of old) localStorage.removeItem(key)
	for (const [key, value] of Object.entries(backup.data)) {
		if (key.startsWith('profitpilot:') && typeof value === 'string') localStorage.setItem(key, value)
	}
}
