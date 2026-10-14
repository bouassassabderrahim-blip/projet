import { usePersistentState } from '../documents/storage'
import type { AccessSettings, AuditEntry, User } from './types'

export const USERS_KEY = 'profitpilot:users:v1'
export const AUDIT_KEY = 'profitpilot:audit:v1'
export const ACCESS_KEY = 'profitpilot:access:v1'
/** Session ouverte : effacée à la fermeture de l'onglet */
export const SESSION_KEY = 'profitpilot:session'

const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null

const isUserList = (x: unknown): x is User[] =>
	Array.isArray(x) &&
	x.every((u) => isObj(u) && typeof u.id === 'string' && typeof u.pinHash === 'string' && isObj(u.permissions))

const isAuditList = (x: unknown): x is AuditEntry[] =>
	Array.isArray(x) && x.every((e) => isObj(e) && typeof e.id === 'string' && typeof e.action === 'string')

const isSettings = (x: unknown): x is AccessSettings => isObj(x) && typeof x.lockMinutes === 'number'

export const useUsers = () => usePersistentState<User[]>(USERS_KEY, () => [], isUserList)
export const useAudit = () => usePersistentState<AuditEntry[]>(AUDIT_KEY, () => [], isAuditList)
export const useAccessSettings = () => usePersistentState<AccessSettings>(ACCESS_KEY, () => ({ lockMinutes: 15 }), isSettings)

export function readSession(): string | null {
	try {
		return sessionStorage.getItem(SESSION_KEY)
	} catch {
		return null
	}
}

export function writeSession(userId: string | null) {
	try {
		if (userId) sessionStorage.setItem(SESSION_KEY, userId)
		else sessionStorage.removeItem(SESSION_KEY)
	} catch {
		// stockage indisponible
	}
}
