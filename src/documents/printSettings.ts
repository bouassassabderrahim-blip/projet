import { defaultPrintSettings, type CompanyInfo, type PrintSettings } from './types'

export function printSettingsOf(company: CompanyInfo): PrintSettings {
	return { ...defaultPrintSettings(), ...company.print }
}

/** Le contenu imprime-t-il son propre en-tête société ? (non si le papier à en-tête le fait déjà) */
export function usesGeneratedHeader(settings: PrintSettings): boolean {
	return settings.mode === 'generated' || (settings.mode === 'images' && !settings.headerImg)
}

/** Réduit une image (en-tête, fond de page) pour ne pas saturer le stockage du navigateur */
export function loadImage(file: File, maxWidth = 1654): Promise<{ dataUrl: string; ratio: number }> {
	return new Promise((resolve, reject) => {
		const reader = new FileReader()
		reader.onerror = () => reject(new Error('Fichier illisible'))
		reader.onload = () => {
			const img = new Image()
			img.onerror = () => reject(new Error('Image illisible'))
			img.onload = () => {
				const scale = Math.min(1, maxWidth / img.naturalWidth)
				const canvas = document.createElement('canvas')
				canvas.width = Math.round(img.naturalWidth * scale)
				canvas.height = Math.round(img.naturalHeight * scale)
				const ctx = canvas.getContext('2d')
				if (!ctx) return reject(new Error('Navigateur incompatible'))
				ctx.fillStyle = '#fff'
				ctx.fillRect(0, 0, canvas.width, canvas.height)
				ctx.drawImage(img, 0, 0, canvas.width, canvas.height)
				resolve({ dataUrl: canvas.toDataURL('image/jpeg', 0.85), ratio: img.naturalHeight / img.naturalWidth })
			}
			img.src = String(reader.result)
		}
		reader.readAsDataURL(file)
	})
}
