import { useEffect, useState } from 'react'
import { emptyCompany, type CommercialDocument, type CompanyInfo } from './types'

export const DOCS_KEY = 'profitpilot:documents:v1'
export const COMPANY_KEY = 'profitpilot:company:v1'

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

function isDocument(x: unknown): x is CommercialDocument {
	if (typeof x !== 'object' || x === null) return false
	const d = x as Record<string, unknown>
	return (
		typeof d.id === 'string' &&
		(d.kind === 'invoice' || d.kind === 'order' || d.kind === 'delivery') &&
		typeof d.number === 'string' &&
		typeof d.date === 'string' &&
		typeof d.party === 'object' &&
		d.party !== null &&
		Array.isArray(d.lines)
	)
}

export const isDocumentList = (x: unknown): x is CommercialDocument[] =>
	Array.isArray(x) && x.every(isDocument)

export const isCompany = (x: unknown): x is CompanyInfo =>
	typeof x === 'object' && x !== null && typeof (x as Record<string, unknown>).name === 'string'

export function useDocuments() {
	return usePersistentState<CommercialDocument[]>(DOCS_KEY, () => [], isDocumentList)
}

export function useCompany() {
	return usePersistentState<CompanyInfo>(COMPANY_KEY, emptyCompany, isCompany)
}
