import type { ModuleId } from './navigation'

const PATHS: Record<ModuleId | 'search' | 'bell' | 'plus' | 'close', string> = {
	home: 'M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z',
	sales: 'M4 4h16v16H4z M8 9h8 M8 13h8 M8 17h5',
	purchases: 'M3 6h3l2.5 10h10L21 9H7.2 M10 20a1 1 0 1 0 0-2 1 1 0 0 0 0 2z M18 20a1 1 0 1 0 0-2 1 1 0 0 0 0 2z',
	stock: 'M12 3l8 4.5v9L12 21l-8-4.5v-9z M4 7.5l8 4.5 8-4.5 M12 12v9',
	finance: 'M4 19h16 M6 16V10 M10 16V6 M14 16v-4 M18 16V8',
	analysis: 'M4 20V4 M4 20h16 M7 15l4-4 3 3 5-6',
	settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M19.4 13a7.6 7.6 0 0 0 0-2l2-1.6-2-3.4-2.4 1a7.4 7.4 0 0 0-1.7-1L15 3.5h-4l-.3 2.5a7.4 7.4 0 0 0-1.7 1l-2.4-1-2 3.4 2 1.6a7.6 7.6 0 0 0 0 2l-2 1.6 2 3.4 2.4-1a7.4 7.4 0 0 0 1.7 1l.3 2.5h4l.3-2.5a7.4 7.4 0 0 0 1.7-1l2.4 1 2-3.4z',
	search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z M21 21l-5-5',
	bell: 'M6 16V11a6 6 0 1 1 12 0v5l2 2H4z M10 21h4',
	plus: 'M12 5v14 M5 12h14',
	close: 'M6 6l12 12 M18 6L6 18',
}

/** Icônes au trait, dessinées en SVG (aucune dépendance) */
export default function Icon({ name, size = 16 }: { name: keyof typeof PATHS; size?: number }) {
	return (
		<svg
			width={size}
			height={size}
			viewBox="0 0 24 24"
			fill="none"
			stroke="currentColor"
			strokeWidth={1.8}
			strokeLinecap="round"
			strokeLinejoin="round"
			aria-hidden="true"
		>
			<path d={PATHS[name]} />
		</svg>
	)
}
