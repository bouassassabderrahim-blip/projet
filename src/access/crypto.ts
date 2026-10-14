/** Empreinte du code PIN (SHA-256 salé) : le code lui-même n'est jamais enregistré */
export async function hashPin(pin: string, salt: string): Promise<string> {
	const data = new TextEncoder().encode(`${salt}:${pin}`)
	if (globalThis.crypto?.subtle) {
		const digest = await crypto.subtle.digest('SHA-256', data)
		return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('')
	}
	// Navigateur sans crypto.subtle (page non sécurisée) : empreinte FNV-1a, moins robuste
	let h = 0x811c9dc5
	for (const byte of data) h = Math.imul(h ^ byte, 0x01000193) >>> 0
	return 'fnv-' + h.toString(16)
}

export function newSalt(): string {
	const bytes = new Uint8Array(16)
	globalThis.crypto?.getRandomValues?.(bytes)
	return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('') || Math.random().toString(36).slice(2)
}

export const isValidPin = (pin: string) => /^\d{4,8}$/.test(pin)
