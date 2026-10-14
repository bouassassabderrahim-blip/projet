import { createContext, useContext } from 'react'
import type { ModuleId } from '../shell/navigation'
import type { Action, Level, User } from './types'

export interface Access {
	/** Utilisateur connecté (null tant qu'aucun compte n'a été créé) */
	user: User | null
	isAdmin: boolean
	level: (module: ModuleId) => Level
	can: (action: Action) => boolean
	/** Trace une action dans le journal d'activité */
	log: (action: string, detail: string) => void
}

/** Sans compte utilisateur, tout est permis (première installation) */
export const FULL_ACCESS: Access = {
	user: null,
	isAdmin: true,
	level: () => 'write',
	can: () => true,
	log: () => {},
}

export const AccessContext = createContext<Access>(FULL_ACCESS)

export const useAccess = () => useContext(AccessContext)

/** Droits de l'utilisateur sur un module */
export function accessFor(user: User | null, log: Access['log']): Access {
	if (!user) return { ...FULL_ACCESS, log }
	const isAdmin = user.role === 'admin'
	return {
		user,
		isAdmin,
		level: (module) => (module === 'home' || isAdmin ? 'write' : user.permissions.modules[module]),
		can: (action) => isAdmin || user.permissions.actions[action],
		log,
	}
}
