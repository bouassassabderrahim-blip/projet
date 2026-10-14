#!/usr/bin/env bash
# ProfitPilot : gestion commerciale complète (ventes, achats, lots, dépôts, TVA, thème pro)
# À lancer à la racine du projet (dossier contenant src/)
set -e
[ -f src/types.ts ] || { echo "Erreur : lancez ce script dans le dossier du projet (src/types.ts introuvable)"; exit 1; }
mkdir -p src/documents src/components src/shell src/access src/sync supabase docs
for f in src/App.tsx src/components/Sidebar.tsx src/components/Dashboard.tsx src/types.ts; do [ -f "$f" ] && cp "$f" "$f.bak"; done; true

















cat > src/documents/BackupPage.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { useAccess } from '../access/context'
import { loadConfig } from '../sync/config'
import { downloadFile } from './csv'
import { LAST_BACKUP_KEY, STORAGE_LIMIT, createBackup, isBackupFile, restoreBackup, storageUsage } from './storage'
import { daysBetween, frDate, today } from './numbering'
import './documents.css'

function readLastBackup(): string {
  try {
    return localStorage.getItem(LAST_BACKUP_KEY) ?? ''
  } catch {
    return ''
  }
}

/** Sauvegarde et restauration de toutes les données (produits, pièces, lots, tiers, paramètres) */
export default function BackupPage() {
  const [last, setLast] = useState(readLastBackup)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const access = useAccess()
  const age = last ? daysBetween(last, today()) : null
  const used = storageUsage()
  const usedPct = Math.min(100, Math.round((used / STORAGE_LIMIT) * 100))
  const multi = loadConfig()?.joined === true

  function exportAll() {
    const backup = createBackup()
    downloadFile(`profitpilot-sauvegarde-${today()}.json`, JSON.stringify(backup, null, 1), 'application/json')
    try {
      localStorage.setItem(LAST_BACKUP_KEY, today())
    } catch {
      // stockage indisponible
    }
    setLast(today())
    access.log('Sauvegarde téléchargée', `${Object.keys(backup.data).length} jeux de données`)
    setMessage(`Sauvegarde téléchargée (${Object.keys(backup.data).length} jeux de données).`)
  }

  function importAll(file: File | undefined) {
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => {
      try {
        const data: unknown = JSON.parse(String(reader.result))
        if (!isBackupFile(data)) return setError("Ce fichier n'est pas une sauvegarde ProfitPilot.")
        if (loadConfig()?.joined) return setError('Restauration impossible en mode multi-postes : déconnectez d’abord ce poste.')
        const date = frDate(data.createdAt.slice(0, 10))
        if (!confirm(`Remplacer TOUTES les données actuelles par la sauvegarde du ${date} ?`)) return
        restoreBackup(data)
        location.reload()
      } catch {
        setError('Fichier illisible.')
      }
    }
    reader.readAsText(file)
  }

  return (
    <div>
      <div className={age === null || age > 7 ? 'doc-warning' : 'doc-info'}>
        {last
          ? `Dernière sauvegarde : ${frDate(last)}${age ? ` (il y a ${age} jour${age > 1 ? 's' : ''})` : " (aujourd'hui)"}.`
          : 'Aucune sauvegarde effectuée.'}{' '}
        Vos données sont enregistrées uniquement dans ce navigateur : vider le cache ou changer d'ordinateur les fait
        perdre. Sauvegardez au moins une fois par semaine et gardez le fichier en lieu sûr (clé USB, Google Drive…).
      </div>

      <fieldset className="doc-panel">
        <legend>Espace utilisé</legend>
        <div className="storage-gauge" role="meter" aria-valuenow={usedPct} aria-valuemin={0} aria-valuemax={100} aria-label="Espace de stockage utilisé">
          <div className={`storage-gauge-fill ${usedPct >= 80 ? 'storage-gauge-high' : ''}`} style={{ width: `${usedPct}%` }} />
        </div>
        <p className="doc-count">
          {(used / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 2 })} Mo utilisés sur environ 5 Mo ({usedPct} %).
          {usedPct >= 80 && ' Attention : au-delà de la limite, les saisies ne sont plus enregistrées.'}
        </p>
      </fieldset>

      <fieldset className="doc-panel">
        <legend>Sauvegarder</legend>
        <p>Télécharge un fichier contenant les produits, le stock, les lots, les pièces, les tiers et les paramètres.</p>
        <button type="button" className="btn-primary" onClick={exportAll}>
          Télécharger une sauvegarde complète
        </button>
      </fieldset>

      <fieldset className="doc-panel">
        <legend>Restaurer</legend>
        <p>Remplace toutes les données de ce navigateur par celles d'un fichier de sauvegarde.</p>
        {!access.isAdmin ? (
          <p className="doc-warning">Seul un administrateur peut restaurer une sauvegarde.</p>
        ) : multi ? (
          // Restaurer ici renverrait d'anciennes versions mêlées aux nouvelles vers tous les postes
          <p className="doc-warning">
            Ce poste partage ses données avec d'autres ordinateurs (multi-postes) : la restauration est désactivée pour ne pas
            mélanger d'anciennes données avec celles des autres postes. Pour revenir à une sauvegarde, déconnectez d'abord
            ce poste (Paramètres › Administration › Multi-postes), restaurez, puis créez un nouveau dossier en ligne.
          </p>
        ) : (
          <input type="file" accept="application/json,.json" onChange={(e) => importAll(e.target.files?.[0])} />
        )}
      </fieldset>

      {message && <p className="doc-info">{message}</p>}
      {error && <p className="doc-error">{error}</p>}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/BackupPage.tsx"

cat > src/documents/CompanySettings.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { useAccess } from '../access/context'
import DocumentPrint from './DocumentPrint'
import { loadImage, printSettingsOf } from './printSettings'
import type { CommercialDocument, CompanyInfo, LetterheadMode, PrintSettings } from './types'
import './documents.css'

interface Props {
  company: CompanyInfo
  onChange: (company: CompanyInfo) => void
}

const fields: { key: 'name' | 'address' | 'city' | 'phone' | 'email' | 'ice' | 'ifNumber' | 'rc' | 'patente' | 'cnss' | 'bank' | 'rib'; label: string; hint?: string }[] = [
  { key: 'name', label: 'Raison sociale' },
  { key: 'address', label: 'Adresse' },
  { key: 'city', label: 'Ville' },
  { key: 'phone', label: 'Téléphone' },
  { key: 'email', label: 'E-mail' },
  { key: 'ice', label: 'ICE', hint: '15 chiffres' },
  { key: 'ifNumber', label: 'Identifiant fiscal (IF)' },
  { key: 'rc', label: 'Registre du commerce (RC)' },
  { key: 'patente', label: 'Taxe professionnelle (Patente)' },
  { key: 'cnss', label: 'CNSS' },
  { key: 'bank', label: 'Banque' },
  { key: 'rib', label: 'RIB', hint: '24 chiffres' },
]

const MODES: { mode: LetterheadMode; title: string; text: string }[] = [
  { mode: 'generated', title: 'En-tête automatique', text: 'Logo et coordonnées tirés de la fiche ci-dessus.' },
  { mode: 'images', title: 'Mon en-tête en image', text: 'Image de votre en-tête (et de votre pied de page) répétée sur chaque page.' },
  { mode: 'background', title: 'Mon papier à en-tête complet', text: 'Image A4 entière (scan ou export PDF → PNG) en fond de chaque page.' },
  { mode: 'preprinted', title: 'Papier déjà imprimé', text: 'Rien n’est imprimé en haut ni en bas : seules les marges sont réservées.' },
]

/** Facture d'exemple pour l'aperçu de la mise en page */
const SAMPLE: CommercialDocument = {
  id: 'sample',
  kind: 'invoice',
  number: 'FA-2026-0001',
  date: '2026-10-13',
  dueDate: '2026-12-12',
  party: { name: 'Clinique Exemple', address: '12, boulevard Zerktouni', city: 'Casablanca', ice: '002345678000012', ifNumber: '', rc: '', phone: '', email: '' },
  lines: [
    { id: '1', description: 'Tige fémorale cimentée taille 3', quantity: 1, unitPriceHT: 9500, tvaRate: 7, discount: 0, lot: 'L2409', serial: 'SN-10452', expiry: '2029-05-01' },
    { id: '2', description: 'Cotyle double mobilité 52 mm', quantity: 1, unitPriceHT: 7200, tvaRate: 7, discount: 0, lot: 'L2411' },
    { id: '3', description: 'Ciment orthopédique 40 g', quantity: 2, unitPriceHT: 450, tvaRate: 20, discount: 10 },
  ],
  status: 'validated',
  paymentMethod: 'virement',
  notes: '',
  intervention: { patient: 'M. A. Alami', patientRef: 'BE123456', surgeon: 'Dr Bennani', clinic: 'Clinique Exemple', date: '2026-10-10', coverage: 'CNSS' },
}

/** Fiche société, papier à en-tête et mise en page des pièces imprimées */
export default function CompanySettings({ company, onChange }: Props) {
  const [draft, setDraft] = useState(company)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState('')
  const access = useAccess()
  const canWrite = access.level('settings') === 'write'
  const print = printSettingsOf(draft)
  const iceInvalid = draft.ice !== '' && !/^\d{15}$/.test(draft.ice)
  const ribInvalid = draft.rib !== '' && !/^\d{24}$/.test(draft.rib.replace(/\s/g, ''))

  const set = (patch: Partial<CompanyInfo>) => {
    setDraft((d) => ({ ...d, ...patch }))
    setSaved(false)
  }
  const setPrint = (patch: Partial<PrintSettings>) => {
    setDraft((d) => ({ ...d, print: { ...printSettingsOf(d), ...patch } }))
    setSaved(false)
  }

  async function upload(file: File | undefined, apply: (dataUrl: string, ratio: number) => void, maxWidth?: number) {
    if (!file) return
    if (!file.type.startsWith('image/')) return setError('Choisissez une image (PNG ou JPEG). Un PDF doit d’abord être exporté en image.')
    try {
      const { dataUrl, ratio } = await loadImage(file, maxWidth)
      apply(dataUrl, ratio)
      setError('')
    } catch {
      setError('Image illisible.')
    }
  }

  function save() {
    try {
      onChange(draft)
      setSaved(true)
      access.log('Paramètres société modifiés', draft.name)
    } catch {
      setError('Enregistrement impossible : images trop lourdes pour le navigateur.')
    }
  }

  const number = (v: string, fallback: number) => {
    const n = Number(v.replace(',', '.'))
    return Number.isFinite(n) && n >= 0 ? n : fallback
  }

  return (
    <div>
      <div className="doc-editor-head">
        <h2>Fiche société et mise en page</h2>
        <div className="doc-editor-actions">
          <button type="button" className="btn-primary" disabled={iceInvalid || !canWrite} onClick={save}>
            Enregistrer
          </button>
          {saved && <span className="doc-count">Enregistré ✓</span>}
        </div>
      </div>

      <fieldset className="doc-panel">
        <legend>Identification</legend>
        <div className="doc-grid">
          {fields.map((f) => (
            <label key={f.key}>
              <span>
                {f.label}
                {f.hint && <small> ({f.hint})</small>}
              </span>
              <input value={draft[f.key]} onChange={(e) => set({ [f.key]: e.target.value })} />
            </label>
          ))}
        </div>
        {iceInvalid && <p className="doc-error">L'ICE doit comporter exactement 15 chiffres.</p>}
        {ribInvalid && <p className="doc-warning">Le RIB marocain comporte normalement 24 chiffres.</p>}
        <div className="doc-logo-row">
          <span className="doc-count">Logo (en-tête automatique) :</span>
          {draft.logo && <img className="doc-logo" src={draft.logo} alt="Logo" />}
          <input
            type="file"
            accept="image/png,image/jpeg"
            onChange={(e) => upload(e.target.files?.[0], (logo) => set({ logo }), 600)}
          />
          {draft.logo && (
            <button type="button" onClick={() => set({ logo: undefined })}>
              Retirer
            </button>
          )}
        </div>
      </fieldset>

      <div className="doc-layout-settings">
        <fieldset className="doc-panel">
          <legend>Papier à en-tête</legend>
          <div className="doc-mode-list">
            {MODES.map((m) => (
              <label key={m.mode} className={`doc-mode ${print.mode === m.mode ? 'doc-mode-active' : ''}`}>
                <input type="radio" name="letterhead" checked={print.mode === m.mode} onChange={() => setPrint({ mode: m.mode })} />
                <span>
                  <strong>{m.title}</strong>
                  <small>{m.text}</small>
                </span>
              </label>
            ))}
          </div>

          {print.mode === 'images' && (
            <div className="doc-grid">
              <label>
                Image de l'en-tête
                <input
                  type="file"
                  accept="image/png,image/jpeg"
                  onChange={(e) =>
                    upload(e.target.files?.[0], (headerImg, ratio) =>
                      // Marge haute = hauteur de l'image à pleine largeur A4 + 5 mm
                      setPrint({ headerImg, top: Math.ceil(210 * ratio) + 5 }),
                    )
                  }
                />
              </label>
              <label>
                Image du pied de page
                <input
                  type="file"
                  accept="image/png,image/jpeg"
                  onChange={(e) =>
                    upload(e.target.files?.[0], (footerImg, ratio) =>
                      setPrint({ footerImg, bottom: Math.ceil(210 * ratio) + 5, showLegal: false }),
                    )
                  }
                />
              </label>
              {(print.headerImg || print.footerImg) && (
                <button type="button" onClick={() => setPrint({ headerImg: undefined, footerImg: undefined })}>
                  Retirer les images
                </button>
              )}
            </div>
          )}

          {print.mode === 'background' && (
            <div className="doc-grid">
              <label>
                Papier à en-tête (image A4 portrait)
                <input
                  type="file"
                  accept="image/png,image/jpeg"
                  onChange={(e) => upload(e.target.files?.[0], (backgroundImg) => setPrint({ backgroundImg, showLegal: false }))}
                />
              </label>
              {print.backgroundImg && (
                <button type="button" onClick={() => setPrint({ backgroundImg: undefined })}>
                  Retirer le fond
                </button>
              )}
            </div>
          )}

          <div className="doc-grid">
            <label>
              Marge haute (mm)
              <input className="num" type="number" min={0} max={150} value={print.top} onChange={(e) => setPrint({ top: number(e.target.value, print.top) })} />
            </label>
            <label>
              Marge basse (mm)
              <input className="num" type="number" min={0} max={120} value={print.bottom} onChange={(e) => setPrint({ bottom: number(e.target.value, print.bottom) })} />
            </label>
            <label>
              Marges gauche / droite (mm)
              <input className="num" type="number" min={5} max={40} value={print.side} onChange={(e) => setPrint({ side: number(e.target.value, print.side) })} />
            </label>
            <label>
              Couleur des titres
              <input type="color" value={print.accent} onChange={(e) => setPrint({ accent: e.target.value })} />
            </label>
            <label className="doc-check">
              <input type="checkbox" checked={print.showLegal} onChange={(e) => setPrint({ showLegal: e.target.checked })} />
              Mentions légales (ICE, IF, RC, RIB) en bas de page
            </label>
          </div>
          <p className="doc-count">
            Astuce : sur papier à en-tête, augmentez la marge haute jusqu'à ce que le titre de la pièce passe sous votre
            en-tête dans l'aperçu.
          </p>

          <label className="doc-notes">
            Conditions imprimées sous les devis
            <textarea rows={2} value={print.quoteTerms} onChange={(e) => setPrint({ quoteTerms: e.target.value })} />
          </label>
          <label className="doc-notes">
            Conditions imprimées sous les factures
            <textarea rows={2} value={print.invoiceTerms} onChange={(e) => setPrint({ invoiceTerms: e.target.value })} />
          </label>
          {error && <p className="doc-error">{error}</p>}
        </fieldset>

        <div className="doc-panel doc-preview-panel">
          <div className="doc-panel-title">Aperçu (facture d'exemple)</div>
          <div className="doc-preview">
            <div className="doc-preview-inner">
              <DocumentPrint doc={SAMPLE} company={draft} settings={print} embedded />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/CompanySettings.tsx"

cat > src/documents/DepotPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState, type Dispatch, type SetStateAction } from 'react'
import { runDocAction } from '../sync/runtime'
import { useAccess } from '../access/context'
import { addDays, daysBetween, emptyLine, frDate, newId, nextNumber, today } from './numbering'
import { formatMAD, lineHT } from './tva'
import { emptyIntervention, type CommercialDocument, type DocKind, type DocLine } from './types'
import './documents.css'

interface Props {
  documents: CommercialDocument[]
  onChange: Dispatch<SetStateAction<CommercialDocument[]>>
  onNavigate: (kind: DocKind, openId?: string) => void
  onStockMove: (lines: DocLine[], direction: 1 | -1, supplier?: string, reference?: string) => Record<string, number> | void
}

interface DepotItem {
  bl: CommercialDocument
  line: DocLine
}

/** Implants livrés en dépôt : à facturer après la pose ou à reprendre en stock */
export default function DepotPage({ documents, onChange, onNavigate, onStockMove }: Props) {
  const [selected, setSelected] = useState<string[]>([])
  const access = useAccess()
  const canWrite = access.level('sales') === 'write'
  const now = today()

  const groups = useMemo(() => {
    const byClient = new Map<string, DepotItem[]>()
    for (const bl of documents) {
      if (bl.kind !== 'delivery' || !bl.consignment || bl.status !== 'validated') continue
      for (const line of bl.lines) {
        if (line.depot !== 'depot') continue
        const list = byClient.get(bl.party.name) ?? []
        list.push({ bl, line })
        byClient.set(bl.party.name, list)
      }
    }
    return [...byClient.entries()].sort((a, b) => a[0].localeCompare(b[0]))
  }, [documents])

  const setDepot = (docs: CommercialDocument[], items: DepotItem[], state: 'posed' | 'returned') =>
    docs.map((d) =>
      items.some((i) => i.bl.id === d.id)
        ? { ...d, lines: d.lines.map((l) => (items.some((i) => i.line.id === l.id) ? { ...l, depot: state } : l)) }
        : d,
    )

  function invoice(items: DepotItem[]) {
    if (items.length === 0) return
    const first = items[0].bl
    const id = newId()
    const lines: DocLine[] = items.map(({ bl, line }) => ({
      ...emptyLine(),
      ...line,
      id: newId(),
      depot: undefined,
      depotRef: { docId: bl.id, lineId: line.id },
    }))
    const created: CommercialDocument = {
      id,
      kind: 'invoice',
      number: nextNumber('invoice', documents, now),
      date: now,
      dueDate: addDays(now, 60),
      party: first.party,
      lines,
      status: 'draft',
      paymentMethod: 'virement',
      notes: '',
      intervention: { ...emptyIntervention(), clinic: first.party.name, date: now },
      sourceNumber: [...new Set(items.map((i) => i.bl.number))].join(', '),
    }
    onChange([...setDepot(documents, items, 'posed'), created])
    access.log('Facturation de dépôt', `${created.number} · ${first.party.name} · ${items.length} article(s)`)
    setSelected([])
    onNavigate('invoice', id)
  }

  async function giveBack(item: DepotItem) {
    if (!confirm(`Reprendre « ${item.line.description} » en stock ?`)) return
    try {
      // Multi-postes : un seul poste peut reprendre cet article (pas de double entrée en stock)
      const outcome = await runDocAction({ docId: item.bl.id, action: `return:${item.line.id}`, kind: 'delivery', year: 0, min: 0 }, () => {
        onChange((prev) => setDepot(prev, [item], 'returned'))
        access.log('Retour de dépôt', `${item.line.description} · ${item.bl.number}`)
        onStockMove([{ ...item.line, quantity: item.line.movedQty ?? item.line.quantity }], 1, '', `Retour dépôt ${item.bl.number}`)
      })
      if (outcome === 'already') alert('Cet article vient d’être repris en stock sur un autre poste.')
    } catch {
      alert('Reprise impossible pour le moment : en mode multi-postes, le serveur doit la confirmer. Vérifiez la connexion Internet puis réessayez.')
    }
  }

  const toggle = (id: string) => setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]))

  if (groups.length === 0)
    return (
      <p className="doc-empty">
        Aucun article en dépôt. Pour déposer du matériel chez une clinique, créez un bon de livraison et cochez « BL en
        dépôt ».
      </p>
    )

  return (
    <div>
      {groups.map(([client, items]) => {
        const chosen = items.filter((i) => selected.includes(i.line.id))
        const value = items.reduce((s, i) => s + lineHT(i.line), 0)
        return (
          <div key={client} className="doc-panel">
            <div className="doc-panel-title">
              {client} · {items.length} article(s) en dépôt · {formatMAD(value)} HT
            </div>
            <div className="doc-table-wrap">
              <table className="doc-table">
                <thead>
                  <tr>
                    <th />
                    <th>Article</th>
                    <th>Lot / N° série</th>
                    <th>Péremption</th>
                    <th className="num">Qté</th>
                    <th>BL</th>
                    <th className="num">Depuis</th>
                    <th className="num">Valeur HT</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {items.map((item) => (
                    <tr key={item.line.id}>
                      <td>
                        <input
                          disabled={!canWrite}
                          type="checkbox"
                          checked={selected.includes(item.line.id)}
                          onChange={() => toggle(item.line.id)}
                        />
                      </td>
                      <td>{item.line.description}</td>
                      <td>{[item.line.lot, item.line.serial].filter(Boolean).join(' / ')}</td>
                      <td>{frDate(item.line.expiry)}</td>
                      <td className="num">{item.line.quantity}</td>
                      <td>{item.bl.number}</td>
                      <td className="num">{daysBetween(item.bl.date, now)} j</td>
                      <td className="num">{formatMAD(lineHT(item.line))}</td>
                      <td className="doc-actions">
                        {canWrite && (
                          <>
                            <button type="button" className="btn-primary" onClick={() => invoice([item])}>
                              Posé → facturer
                            </button>
                            <button type="button" onClick={() => void giveBack(item)}>
                              Retour en stock
                            </button>
                          </>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {canWrite && chosen.length > 1 && (
              <div className="doc-toolbar">
                <button type="button" className="btn-primary" onClick={() => invoice(chosen)}>
                  Facturer les {chosen.length} articles sélectionnés
                </button>
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DepotPage.tsx"

cat > src/documents/DocumentEditor.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import type { Product } from '../types'
import {
  COVERAGES,
  DOC_LABELS,
  PAYMENT_LABELS,
  emptyIntervention,
  type CommercialDocument,
  type Coverage,
  type DocLine,
  type Intervention,
  type Kit,
  type Party,
  type PartyRecord,
  type PaymentMethod,
  type StockLot,
  type TvaRate,
} from './types'
import { TVA_RATES, computeTotals, formatMAD, lineHT } from './tva'
import { addDays, emptyLine, frDate, newId } from './numbering'
import { availableLots } from './stockMoves'

interface Props {
  initial: CommercialDocument
  products: Product[]
  lots: StockLot[]
  kits: Kit[]
  /** Fiches tiers du bon rôle (clients pour les ventes, fournisseurs pour les achats) */
  parties: PartyRecord[]
  onSave: (doc: CommercialDocument) => void
  onCancel: () => void
}

const partyFields: { key: Exclude<keyof Party, 'individual'>; label: string }[] = [
  { key: 'name', label: 'Raison sociale / Nom' },
  { key: 'address', label: 'Adresse' },
  { key: 'city', label: 'Ville' },
  { key: 'ice', label: 'ICE' },
  { key: 'ifNumber', label: 'IF' },
  { key: 'rc', label: 'RC' },
  { key: 'phone', label: 'Téléphone' },
  { key: 'email', label: 'E-mail' },
]

const interventionFields: { key: Exclude<keyof Intervention, 'coverage' | 'date'>; label: string }[] = [
  { key: 'patient', label: 'Patient' },
  { key: 'patientRef', label: 'N° dossier / CIN' },
  { key: 'surgeon', label: 'Chirurgien' },
  { key: 'clinic', label: 'Clinique / hôpital' },
]

export default function DocumentEditor({ initial, products, lots, kits, parties, onSave, onCancel }: Props) {
  const [doc, setDoc] = useState(initial)
  const [error, setError] = useState('')
  const totals = computeTotals(doc)
  const info = DOC_LABELS[doc.kind]
  const isPurchase = info.side === 'purchase'
  const isInvoice = doc.kind === 'invoice'
  const hasDueDate = doc.kind === 'invoice' || doc.kind === 'bill' || doc.kind === 'quote'
  const hasPayment = doc.kind === 'invoice' || doc.kind === 'bill' || doc.kind === 'credit'
  const hasIntervention = doc.kind === 'invoice' || doc.kind === 'delivery' || doc.kind === 'quote' || doc.kind === 'credit'
  // Sorties de stock : on propose les lots disponibles
  const picksLots = doc.kind === 'delivery' || doc.kind === 'invoice' || doc.kind === 'credit'

  const update = (patch: Partial<CommercialDocument>) => setDoc((d) => ({ ...d, ...patch }))
  const updateParty = (patch: Partial<Party>) => setDoc((d) => ({ ...d, party: { ...d.party, ...patch } }))
  const updateLine = (id: string, patch: Partial<DocLine>) =>
    setDoc((d) => ({ ...d, lines: d.lines.map((l) => (l.id === id ? { ...l, ...patch } : l)) }))
  const updateIntervention = (patch: Partial<Intervention>) =>
    setDoc((d) => ({ ...d, intervention: { ...(d.intervention ?? emptyIntervention()), ...patch } }))

  const priceOf = (p: Product) => (isPurchase ? p.unitCost : p.unitPrice)

  function pickProduct(lineId: string, productId: string) {
    const p = products.find((x) => x.id === productId)
    if (!p) return updateLine(lineId, { productId: undefined, lotId: undefined })
    updateLine(lineId, { productId: p.id, description: p.name, unitPriceHT: priceOf(p), lotId: undefined })
  }

  function pickLot(lineId: string, lotId: string) {
    const lot = lots.find((l) => l.id === lotId)
    if (!lot) return updateLine(lineId, { lotId: undefined })
    updateLine(lineId, { lotId: lot.id, lot: lot.lot, serial: lot.serial, expiry: lot.expiry })
  }

  function pickParty(id: string) {
    const p = parties.find((x) => x.id === id)
    if (!p) return
    const { name, address, city, ice, ifNumber, rc, phone, email, individual } = p
    const patch: Partial<CommercialDocument> = { party: { name, address, city, ice, ifNumber, rc, phone, email, individual } }
    // Échéance selon le délai de paiement de la fiche
    if ((doc.kind === 'invoice' || doc.kind === 'bill') && p.paymentTerms !== undefined)
      patch.dueDate = addDays(doc.date, p.paymentTerms)
    update(patch)
  }

  function insertKit(kitId: string) {
    const kit = kits.find((k) => k.id === kitId)
    if (!kit) return
    const added: DocLine[] = []
    for (const item of kit.items) {
      const p = products.find((x) => x.id === item.productId)
      if (!p) continue
      added.push({ ...emptyLine(), id: newId(), productId: p.id, description: p.name, unitPriceHT: priceOf(p), quantity: item.quantity })
    }
    // On remplace la ligne vide de départ si elle n'a pas été remplie
    setDoc((d) => ({ ...d, lines: [...d.lines.filter((l) => l.description.trim()), ...added] }))
  }

  function submit() {
    const name = doc.party.name.trim()
    if (!name) return setError(isPurchase ? 'Indiquez le fournisseur.' : 'Indiquez le client.')
    const ice = doc.party.ice.trim()
    if (ice && !/^\d{15}$/.test(ice)) return setError("L'ICE doit comporter 15 chiffres.")
    if (isInvoice && !doc.party.individual && !ice)
      return setError("L'ICE du client est obligatoire sur une facture à un professionnel. Cochez « Particulier » pour un patient.")
    if (doc.kind === 'bill' && !doc.supplierRef?.trim()) return setError('Indiquez le numéro de la facture du fournisseur.')
    const lines = doc.lines.filter((l) => l.description.trim() && l.quantity > 0)
    if (lines.length === 0) return setError('Ajoutez au moins une ligne.')
    const intervention = doc.intervention && Object.values(doc.intervention).some((v) => v) ? doc.intervention : undefined
    onSave({ ...doc, lines, intervention, party: { ...doc.party, name } })
  }

  const num = (v: string) => (v === '' ? 0 : Number(v))

  return (
    <div className="doc-editor">
      <div className="doc-editor-head">
        <h2>
          {info.title} {doc.number}
          {doc.sourceNumber && <small> (issu de {doc.sourceNumber})</small>}
        </h2>
        <div className="doc-editor-actions">
          <button type="button" className="btn-primary" onClick={submit}>
            Enregistrer
          </button>
          <button type="button" onClick={onCancel}>
            Fermer
          </button>
        </div>
      </div>

      <div className="doc-panels">
        <fieldset>
          <legend>Pièce</legend>
          <div className="doc-grid">
            <label>
              Date
              <input type="date" value={doc.date} onChange={(e) => update({ date: e.target.value })} />
            </label>
            {hasDueDate && (
              <label>
                {doc.kind === 'quote' ? "Valable jusqu'au" : 'Échéance'}
                <input type="date" value={doc.dueDate} onChange={(e) => update({ dueDate: e.target.value })} />
              </label>
            )}
            {hasPayment && (
              <label>
                Mode de règlement
                <select
                  value={doc.paymentMethod}
                  onChange={(e) => update({ paymentMethod: e.target.value as PaymentMethod })}
                >
                  {Object.entries(PAYMENT_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {doc.kind === 'bill' && (
              <label>
                N° facture fournisseur
                <input value={doc.supplierRef ?? ''} onChange={(e) => update({ supplierRef: e.target.value })} />
              </label>
            )}
            {doc.kind === 'delivery' && (
              <label className="doc-check">
                <input
                  type="checkbox"
                  checked={!!doc.consignment}
                  onChange={(e) => update({ consignment: e.target.checked })}
                />
                BL en dépôt (facturé à la pose)
              </label>
            )}
          </div>
        </fieldset>

        <fieldset>
          <legend>{isPurchase ? 'Fournisseur' : 'Client'}</legend>
          {parties.length > 0 && (
            <label>
              {isPurchase ? 'Fournisseur enregistré' : 'Client enregistré'}
              <select value="" onChange={(e) => pickParty(e.target.value)}>
                <option value="">— choisir dans le fichier —</option>
                {parties.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                    {p.city ? ` (${p.city})` : ''}
                  </option>
                ))}
              </select>
            </label>
          )}
          <div className="doc-grid">
            {partyFields.map((f) => (
              <label key={f.key}>
                {f.label}
                <input value={doc.party[f.key]} onChange={(e) => updateParty({ [f.key]: e.target.value })} />
              </label>
            ))}
            {!isPurchase && (
              <label className="doc-check">
                <input
                  type="checkbox"
                  checked={!!doc.party.individual}
                  onChange={(e) => updateParty({ individual: e.target.checked })}
                />
                Particulier (patient, sans ICE)
              </label>
            )}
          </div>
        </fieldset>

        {hasIntervention && (
          <fieldset>
            <legend>Intervention / patient</legend>
            <div className="doc-grid">
              {interventionFields.map((f) => (
                <label key={f.key}>
                  {f.label}
                  <input
                    value={doc.intervention?.[f.key] ?? ''}
                    onChange={(e) => updateIntervention({ [f.key]: e.target.value })}
                  />
                </label>
              ))}
              <label>
                Date d'intervention
                <input
                  type="date"
                  value={doc.intervention?.date ?? ''}
                  onChange={(e) => updateIntervention({ date: e.target.value })}
                />
              </label>
              <label>
                Prise en charge
                <select
                  value={doc.intervention?.coverage ?? ''}
                  onChange={(e) => updateIntervention({ coverage: e.target.value as Coverage | '' })}
                >
                  <option value="">—</option>
                  {COVERAGES.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
              </label>
            </div>
          </fieldset>
        )}
      </div>

      <div className="doc-toolbar">
        <button type="button" onClick={() => setDoc((d) => ({ ...d, lines: [...d.lines, emptyLine()] }))}>
          + Ligne
        </button>
        {kits.length > 0 && (
          <select value="" onChange={(e) => insertKit(e.target.value)}>
            <option value="">Insérer un kit…</option>
            {kits.map((k) => (
              <option key={k.id} value={k.id}>
                {k.name}
              </option>
            ))}
          </select>
        )}
      </div>

      <div className="doc-table-wrap">
        <table className="doc-table doc-lines">
          <thead>
            <tr>
              <th>Article</th>
              <th>Désignation</th>
              <th>Lot / N° de série</th>
              <th>Péremption</th>
              <th className="num">Qté</th>
              <th className="num">P.U. HT</th>
              <th className="num">Rem. %</th>
              <th>TVA</th>
              <th className="num">Total HT</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {doc.lines.map((l) => {
              const choices = picksLots ? availableLots(lots, l.productId) : []
              return (
                <tr key={l.id}>
                  <td>
                    <select value={l.productId ?? ''} onChange={(e) => pickProduct(l.id, e.target.value)}>
                      <option value="">Libre</option>
                      {products.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.reference ? `${p.reference} · ` : ''}
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </td>
                  <td>
                    <input
                      value={l.description}
                      onChange={(e) => updateLine(l.id, { description: e.target.value })}
                    />
                  </td>
                  <td className="doc-lot-cell">
                    {choices.length > 0 && (
                      <select value={l.lotId ?? ''} onChange={(e) => pickLot(l.id, e.target.value)}>
                        <option value="">Lot en stock…</option>
                        {choices.map((c) => (
                          <option key={c.id} value={c.id}>
                            {[c.lot, c.serial].filter(Boolean).join(' / ')} · {c.quantity} dispo
                            {c.expiry ? ` · exp. ${frDate(c.expiry)}` : ''}
                          </option>
                        ))}
                      </select>
                    )}
                    <div className="doc-lot-inputs">
                      <input
                        placeholder="Lot"
                        value={l.lot ?? ''}
                        onChange={(e) => updateLine(l.id, { lot: e.target.value, lotId: undefined })}
                      />
                      <input
                        placeholder="N° série"
                        value={l.serial ?? ''}
                        onChange={(e) => updateLine(l.id, { serial: e.target.value, lotId: undefined })}
                      />
                    </div>
                  </td>
                  <td>
                    <input
                      type="date"
                      value={l.expiry ?? ''}
                      onChange={(e) => updateLine(l.id, { expiry: e.target.value })}
                    />
                  </td>
                  <td>
                    <input
                      className="num"
                      type="number"
                      min={0}
                      step="any"
                      value={l.quantity}
                      onChange={(e) => updateLine(l.id, { quantity: num(e.target.value) })}
                    />
                  </td>
                  <td>
                    <input
                      className="num"
                      type="number"
                      min={0}
                      step="0.01"
                      value={l.unitPriceHT}
                      onChange={(e) => updateLine(l.id, { unitPriceHT: num(e.target.value) })}
                    />
                  </td>
                  <td>
                    <input
                      className="num"
                      type="number"
                      min={0}
                      max={100}
                      value={l.discount}
                      onChange={(e) => updateLine(l.id, { discount: num(e.target.value) })}
                    />
                  </td>
                  <td>
                    <select
                      value={l.tvaRate}
                      onChange={(e) => updateLine(l.id, { tvaRate: Number(e.target.value) as TvaRate })}
                    >
                      {TVA_RATES.map((t) => (
                        <option key={t.rate} value={t.rate}>
                          {t.label}
                        </option>
                      ))}
                    </select>
                  </td>
                  <td className="num">{formatMAD(lineHT(l))}</td>
                  <td>
                    <button
                      type="button"
                      title="Supprimer la ligne"
                      onClick={() => setDoc((d) => ({ ...d, lines: d.lines.filter((x) => x.id !== l.id) }))}
                    >
                      ✕
                    </button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      <div className="doc-bottom">
        <label className="doc-notes">
          Notes / conditions
          <textarea rows={4} value={doc.notes} onChange={(e) => update({ notes: e.target.value })} />
        </label>
        <table className="doc-table doc-totals-box">
          <tbody>
            <tr>
              <td>Total HT</td>
              <td className="num">{formatMAD(totals.totalHT)}</td>
            </tr>
            {totals.byRate.map((r) => (
              <tr key={r.rate}>
                <td>
                  TVA {r.rate} % sur {formatMAD(r.base)}
                </td>
                <td className="num">{formatMAD(r.tva)}</td>
              </tr>
            ))}
            <tr className="doc-total-row">
              <td>Total TTC</td>
              <td className="num">{formatMAD(totals.totalTTC)}</td>
            </tr>
            {totals.stampDuty > 0 && (
              <>
                <tr>
                  <td>Droit de timbre (0,25 %)</td>
                  <td className="num">{formatMAD(totals.stampDuty)}</td>
                </tr>
                <tr className="doc-total-row">
                  <td>Net à payer</td>
                  <td className="num">{formatMAD(totals.netToPay)}</td>
                </tr>
              </>
            )}
          </tbody>
        </table>
      </div>

      {error && <p className="doc-error">{error}</p>}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DocumentEditor.tsx"

cat > src/documents/DocumentPrint.tsx <<'FIN_DU_FICHIER'
import PrintSheet from './PrintSheet'
import { CompanyFooter, CompanyHeader } from './PrintParts'
import { printSettingsOf, usesGeneratedHeader } from './printSettings'
import { DOC_LABELS, PAYMENT_LABELS, type CommercialDocument, type CompanyInfo, type PrintSettings } from './types'
import { amountInWordsMAD, computeTotals, formatMAD, lineHT } from './tva'
import { frDate } from './numbering'

interface Props {
  doc: CommercialDocument
  company: CompanyInfo
  /** Règlements et avoirs déjà imputés (factures) */
  paid?: number
  balance?: number
  /** Réglages à prévisualiser (page Paramètres) */
  settings?: PrintSettings
  /** Aperçu intégré : sans barre d'outils */
  embedded?: boolean
  onClose?: () => void
}

/** Message d'accompagnement pour l'envoi d'une pièce (e-mail, WhatsApp) */
function shareMessage(doc: CommercialDocument, company: CompanyInfo, netToPay: number, balance?: number): { subject: string; body: string } {
  const title = DOC_LABELS[doc.kind].title
  const subject = `${title} ${doc.number}${company.name ? ` – ${company.name}` : ''}`
  const lines = [
    'Bonjour,',
    '',
    `Veuillez trouver ci-joint notre ${title.toLowerCase()} n° ${doc.number} du ${frDate(doc.date)}, d'un montant de ${formatMAD(netToPay)} TTC.`,
  ]
  if (doc.kind === 'invoice') {
    if (balance !== undefined && balance > 0.01 && balance < netToPay) lines.push(`Reste à régler : ${formatMAD(balance)}.`)
    if (doc.dueDate) lines.push(`Échéance : ${frDate(doc.dueDate)}.`)
    if (company.rib) lines.push(`Règlement par virement : ${company.bank} – RIB ${company.rib}.`)
  }
  if (doc.kind === 'quote' && doc.dueDate) lines.push(`Ce devis est valable jusqu'au ${frDate(doc.dueDate)}.`)
  lines.push('', 'Cordialement,', company.name)
  return { subject, body: lines.join('\n') }
}

/** Numéro marocain au format international pour WhatsApp (06… → 2126…) */
function whatsappNumber(phone: string): string {
  const digits = phone.replace(/\D/g, '')
  if (digits.startsWith('00')) return digits.slice(2)
  if (digits.startsWith('0')) return '212' + digits.slice(1)
  return digits
}

/** Pièce commerciale au format A4, compatible avec votre papier à en-tête */
export default function DocumentPrint({ doc, company, paid = 0, balance, settings, embedded, onClose }: Props) {
  const s = settings ?? printSettingsOf(company)
  const totals = computeTotals(doc)
  const info = DOC_LABELS[doc.kind]
  // BL et bons de réception servent à la logistique : pas de prix
  const showPrices = doc.kind !== 'delivery' && doc.kind !== 'receipt'
  const showTrace = doc.lines.some((l) => l.lot || l.serial || l.expiry)
  const iv = doc.intervention
  const partyLabel = info.side === 'purchase' ? 'Fournisseur' : doc.kind === 'delivery' ? 'Livré à' : 'Client'
  const terms = doc.kind === 'quote' ? s.quoteTerms : doc.kind === 'invoice' ? s.invoiceTerms : ''
  const signatures =
    doc.kind === 'quote' || doc.kind === 'order' || doc.kind === 'delivery' || doc.kind === 'receipt' || doc.kind === 'purchase'

  const refs: [string, string][] = [
    ['Date', frDate(doc.date)],
    ...((doc.kind === 'invoice' || doc.kind === 'bill') && doc.dueDate ? [['Échéance', frDate(doc.dueDate)] as [string, string]] : []),
    ...(doc.kind === 'quote' && doc.dueDate ? [['Valable jusqu’au', frDate(doc.dueDate)] as [string, string]] : []),
    ...(doc.supplierRef ? [['Réf. fournisseur', doc.supplierRef] as [string, string]] : []),
    ...(doc.sourceNumber ? [[doc.kind === 'credit' ? 'Sur facture' : 'Référence', doc.sourceNumber] as [string, string]] : []),
    ...(doc.kind === 'invoice' || doc.kind === 'credit' || doc.kind === 'bill'
      ? [['Règlement', PAYMENT_LABELS[doc.paymentMethod]] as [string, string]]
      : []),
  ]

  return (
    <div>
      {!embedded && (
        <div className="doc-toolbar no-print">
          <button type="button" className="btn-primary" onClick={() => window.print()}>
            Imprimer / PDF
          </button>
          <button
            type="button"
            title="Ouvre votre messagerie : joignez le PDF enregistré avec « Imprimer / PDF »"
            onClick={() => {
              const m = shareMessage(doc, company, totals.netToPay, balance)
              location.href = `mailto:${encodeURIComponent(doc.party.email)}?subject=${encodeURIComponent(m.subject)}&body=${encodeURIComponent(m.body)}`
            }}
          >
            Envoyer par e-mail
          </button>
          <button
            type="button"
            title={doc.party.phone ? 'Ouvre WhatsApp avec le message prêt à envoyer' : 'Ajoutez le téléphone du client sur la pièce'}
            disabled={!doc.party.phone}
            onClick={() => {
              const m = shareMessage(doc, company, totals.netToPay, balance)
              window.open(`https://wa.me/${whatsappNumber(doc.party.phone)}?text=${encodeURIComponent(m.body)}`, '_blank', 'noopener')
            }}
          >
            WhatsApp
          </button>
          {onClose && (
            <button type="button" onClick={onClose}>
              Retour à la liste
            </button>
          )}
          <span className="doc-count">Mise en page et papier à en-tête : Paramètres › Mon entreprise</span>
        </div>
      )}

      <div className="doc-print">
        <PrintSheet company={company} settings={s} footer={s.showLegal ? <CompanyFooter company={company} /> : null}>
          {usesGeneratedHeader(s) && <CompanyHeader company={company} />}

          <div className="doc-title-block">
            <h2>
              {info.printTitle}
              {doc.consignment ? ' (DÉPÔT)' : ''}
            </h2>
            <div className="doc-title-number">N° {doc.number}</div>
          </div>

          <div className="doc-print-boxes">
            <section className="doc-box">
              <table className="doc-ref-table">
                <tbody>
                  {refs.map(([k, v]) => (
                    <tr key={k}>
                      <th>{k}</th>
                      <td>{v}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </section>
            <section className="doc-box doc-party">
              <strong>{partyLabel}</strong>
              <div className="doc-party-name">{doc.party.name}</div>
              <div>{doc.party.address}</div>
              <div>{doc.party.city}</div>
              {doc.party.ice && <div>ICE : {doc.party.ice}</div>}
              {doc.party.ifNumber && <div>IF : {doc.party.ifNumber}</div>}
              {doc.party.rc && <div>RC : {doc.party.rc}</div>}
            </section>
          </div>

          {iv && (
            <section className="doc-box doc-intervention">
              <strong>Intervention</strong>
              <div className="doc-intervention-grid">
                {iv.patient && <span>Patient : {iv.patient}</span>}
                {iv.patientRef && <span>Dossier / CIN : {iv.patientRef}</span>}
                {iv.surgeon && <span>Chirurgien : {iv.surgeon}</span>}
                {iv.clinic && <span>Établissement : {iv.clinic}</span>}
                {iv.date && <span>Date : {frDate(iv.date)}</span>}
                {iv.coverage && <span>Prise en charge : {iv.coverage}</span>}
              </div>
            </section>
          )}

          <table className="doc-table doc-print-lines">
            <thead>
              <tr>
                <th className="doc-col-index">#</th>
                <th>Désignation</th>
                {showTrace && <th>Lot / N° série</th>}
                {showTrace && <th>Péremption</th>}
                <th className="num">Qté</th>
                {showPrices && (
                  <>
                    <th className="num">P.U. HT</th>
                    <th className="num">Rem.</th>
                    <th className="num">TVA</th>
                    <th className="num">Total HT</th>
                  </>
                )}
              </tr>
            </thead>
            <tbody>
              {doc.lines.map((l, i) => (
                <tr key={l.id}>
                  <td className="doc-col-index">{i + 1}</td>
                  <td>{l.description}</td>
                  {showTrace && <td>{[l.lot, l.serial].filter(Boolean).join(' / ')}</td>}
                  {showTrace && <td>{frDate(l.expiry)}</td>}
                  <td className="num">{l.quantity}</td>
                  {showPrices && (
                    <>
                      <td className="num">{formatMAD(l.unitPriceHT)}</td>
                      <td className="num">{l.discount ? `${l.discount} %` : ''}</td>
                      <td className="num">{l.tvaRate} %</td>
                      <td className="num">{formatMAD(lineHT(l))}</td>
                    </>
                  )}
                </tr>
              ))}
            </tbody>
          </table>

          {showPrices && (
            <div className="doc-print-bottom">
              <table className="doc-table doc-vat-table">
                <thead>
                  <tr>
                    <th>Taux TVA</th>
                    <th className="num">Base HT</th>
                    <th className="num">Montant TVA</th>
                  </tr>
                </thead>
                <tbody>
                  {totals.byRate.map((r) => (
                    <tr key={r.rate}>
                      <td>{r.rate} %</td>
                      <td className="num">{formatMAD(r.base)}</td>
                      <td className="num">{formatMAD(r.tva)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <table className="doc-table doc-totals-box">
                <tbody>
                  <tr>
                    <td>Total HT</td>
                    <td className="num">{formatMAD(totals.totalHT)}</td>
                  </tr>
                  <tr>
                    <td>Total TVA</td>
                    <td className="num">{formatMAD(totals.totalTVA)}</td>
                  </tr>
                  {totals.stampDuty > 0 && (
                    <tr>
                      <td>Droit de timbre 0,25 %</td>
                      <td className="num">{formatMAD(totals.stampDuty)}</td>
                    </tr>
                  )}
                  <tr className="doc-grand-total">
                    <td>{totals.stampDuty > 0 ? 'Net à payer' : 'Total TTC'}</td>
                    <td className="num">{formatMAD(totals.netToPay)}</td>
                  </tr>
                  {doc.kind === 'invoice' && paid > 0 && balance !== undefined && (
                    <>
                      <tr>
                        <td>Déjà réglé / avoirs</td>
                        <td className="num">{formatMAD(totals.netToPay - balance)}</td>
                      </tr>
                      <tr className="doc-total-row">
                        <td>Reste dû</td>
                        <td className="num">{formatMAD(balance)}</td>
                      </tr>
                    </>
                  )}
                </tbody>
              </table>
            </div>
          )}

          {(doc.kind === 'invoice' || doc.kind === 'credit' || doc.kind === 'quote') && (
            <p className="doc-amount-words">
              {doc.kind === 'invoice'
                ? 'Arrêtée la présente facture'
                : doc.kind === 'credit'
                  ? 'Arrêté le présent avoir'
                  : 'Arrêté le présent devis'}{' '}
              à la somme de : <strong>{amountInWordsMAD(totals.netToPay)}</strong> TTC.
            </p>
          )}

          {(terms || doc.notes) && (
            <div className="doc-terms">
              {doc.notes && <p className="doc-notes-print">{doc.notes}</p>}
              {terms && <p className="doc-terms-text">{terms}</p>}
            </div>
          )}

          {signatures && (
            <div className="doc-signatures">
              <div>
                {doc.kind === 'delivery'
                  ? 'Signature du livreur'
                  : doc.kind === 'receipt'
                    ? 'Réceptionné par'
                    : "Cachet et signature de l'entreprise"}
              </div>
              <div>
                {doc.kind === 'delivery'
                  ? 'Reçu conforme : cachet et signature du client'
                  : doc.kind === 'receipt'
                    ? 'Contrôle qualité / conformité'
                    : 'Bon pour accord : date, cachet et signature du client'}
              </div>
            </div>
          )}
        </PrintSheet>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DocumentPrint.tsx"

cat > src/documents/DocumentsPage.tsx <<'FIN_DU_FICHIER'
import { useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react'
import { isSyncActive, runDocAction } from '../sync/runtime'
import type { Product } from '../types'
import { useAccess } from '../access/context'
import DocumentEditor from './DocumentEditor'
import DocumentPrint from './DocumentPrint'
import PaymentDialog from './PaymentDialog'
import ReminderPrint from './ReminderPrint'
import { downloadCsv, journal } from './csv'
import { readDocuments } from './storage'
import { balanceOf, isActive, isOverdue, paidAmount, sign } from './ledger'
import { addDays, finalNumber, frDate, newDocument, newId, nextNumber, today } from './numbering'
import { computeTotals, formatMAD, round2 } from './tva'
import {
  DOC_LABELS,
  STATUS_LABELS,
  emptyParty,
  type CommercialDocument,
  type CompanyInfo,
  type DocKind,
  type DocLine,
  type DocStatus,
  type Kit,
  type PartyRecord,
  type Payment,
  type StockLot,
} from './types'
import './documents.css'

interface Props {
  kind: DocKind
  documents: CommercialDocument[]
  /** Accepte une mise à jour fonctionnelle (appliquée à la liste la plus récente, même après une attente réseau) */
  onChange: Dispatch<SetStateAction<CommercialDocument[]>>
  products: Product[]
  lots: StockLot[]
  kits: Kit[]
  parties: PartyRecord[]
  onPartiesChange: (parties: PartyRecord[]) => void
  company: CompanyInfo
  /** Ouvre directement une pièce en modification */
  openId?: string
  onNavigate?: (kind: DocKind, openId?: string) => void
  /** Mouvement de stock : -1 sortie, +1 entrée */
  /** Renvoie la quantité réellement déplacée par ligne */
  onStockMove?: (lines: DocLine[], direction: 1 | -1, supplier?: string, reference?: string) => Record<string, number> | void
}

type View =
  | { mode: 'list' }
  | { mode: 'edit'; doc: CommercialDocument }
  | { mode: 'print'; id: string }
  | { mode: 'reminder'; partyName: string }

/** Chaînes : Devis → BC → BL → Facture → Avoir ; Commande fournisseur → Réception → Facture fournisseur */
const CONVERSIONS: Record<DocKind, DocKind[]> = {
  quote: ['order', 'delivery', 'invoice'],
  order: ['delivery', 'invoice'],
  delivery: ['invoice'],
  invoice: ['credit'],
  credit: [],
  purchase: ['receipt', 'bill'],
  receipt: ['bill'],
  bill: [],
}

type Filter = DocStatus | '' | 'late' | 'open'

/** Une facture ne bouge le stock que si aucun BL ne l'a déjà fait */
function invoiceMovesStock(doc: CommercialDocument, documents: CommercialDocument[]): boolean {
  if (doc.kind !== 'invoice') return false
  const source = documents.find((d) => d.id === doc.sourceId)
  if (source?.kind === 'delivery') return false
  return true
}

export default function DocumentsPage({
  kind,
  documents,
  onChange,
  products,
  lots,
  kits,
  parties,
  onPartiesChange,
  company,
  openId,
  onNavigate,
  onStockMove,
}: Props) {
  const [view, setView] = useState<View>(() => {
    // « new » : création directe depuis le bouton Créer ou l'accueil
    if (openId === 'new') return { mode: 'edit', doc: newDocument(kind, documents) }
    const doc = openId ? documents.find((d) => d.id === openId) : undefined
    if (!doc) return { mode: 'list' }
    // Une pièce validée s'ouvre en consultation, un brouillon en modification
    return doc.status === 'draft' ? { mode: 'edit', doc } : { mode: 'print', id: doc.id }
  })
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<Filter>('')
  const [paying, setPaying] = useState<CommercialDocument | null>(null)
  const [message, setMessage] = useState<{ text: string; kind?: DocKind; id?: string } | null>(null)
  const info = DOC_LABELS[kind]
  // Droits de l'utilisateur sur le module Ventes ou Achats
  const access = useAccess()
  const canWrite = access.level(info.side === 'sale' ? 'sales' : 'purchases') === 'write'
  const canValidate = canWrite && access.can('validate')
  const canDelete = canWrite && access.can('delete')
  const canPay = access.can('payments')
  const stamp = () => ({ by: access.user?.name ?? '' })
  const isPurchase = info.side === 'purchase'
  const role = isPurchase ? 'supplier' : 'client'
  const now = today()

  const list = useMemo(() => {
    const q = search.trim().toLowerCase()
    return documents
      .filter((d) => d.kind === kind)
      .filter((d) => {
        if (filter === 'late') return isOverdue(d, documents, now)
        if (filter === 'open') return isActive(d) && balanceOf(d, documents) > 0.01
        return !filter || d.status === filter
      })
      .filter(
        (d) =>
          !q ||
          [d.number, d.party.name, d.supplierRef, d.intervention?.patient, ...d.lines.map((l) => `${l.lot ?? ''} ${l.serial ?? ''}`)]
            .join(' ')
            .toLowerCase()
            .includes(q),
      )
      .sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number))
  }, [documents, kind, search, filter, now])

  const roleParties = useMemo(() => parties.filter((p) => p.role === role).sort((a, b) => a.name.localeCompare(b.name)), [parties, role])

  const stats = useMemo(() => {
    if (kind !== 'invoice' && kind !== 'bill') return null
    let ht = 0
    let tva = 0
    let open = 0
    let late = 0
    let lateCount = 0
    for (const d of documents) {
      if (!isActive(d)) continue
      const same = kind === 'invoice' ? d.kind === 'invoice' || d.kind === 'credit' : d.kind === 'bill'
      if (!same) continue
      const t = computeTotals(d)
      ht += sign(d) * t.totalHT
      tva += sign(d) * t.totalTVA
      if (d.kind !== 'credit') open += balanceOf(d, documents)
      if (isOverdue(d, documents, now)) {
        late += balanceOf(d, documents)
        lateCount++
      }
    }
    return { ht: round2(ht), tva: round2(tva), open: round2(open), late: round2(late), lateCount }
  }, [documents, kind, now])

  function createDoc(): CommercialDocument {
    return newDocument(kind, documents)
  }

  /** Ajoute le tiers au fichier clients / fournisseurs s'il n'y est pas encore */
  function rememberParty(doc: CommercialDocument) {
    const name = doc.party.name.trim().toLowerCase()
    if (!name || parties.some((p) => p.role === role && p.name.trim().toLowerCase() === name)) return
    onPartiesChange([...parties, { ...doc.party, id: newId(), role, notes: '' }])
  }

  function save(doc: CommercialDocument) {
    const exists = documents.some((d) => d.id === doc.id)
    const saved = exists ? doc : { ...doc, createdBy: stamp().by }
    onChange(exists ? documents.map((d) => (d.id === doc.id ? saved : d)) : [...documents, saved])
    access.log(exists ? 'Pièce modifiée' : 'Pièce créée', `${DOC_LABELS[doc.kind].title} ${doc.number} · ${doc.party.name}`)
    rememberParty(doc)
    setView({ mode: 'list' })
  }

  // Pièces les plus récentes (la synchronisation peut en apporter pendant une attente réseau ;
  // si la page a été quittée entre-temps, on relit le stockage)
  const docsRef = useRef(documents)
  const mounted = useRef(true)
  useEffect(() => {
    docsRef.current = documents
  }, [documents])
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
    }
  }, [])
  const [validating, setValidating] = useState<string | null>(null)

  async function setStatus(doc: CommercialDocument, status: DocStatus) {
    const validate = status === 'validated' && doc.status === 'draft'
    const cancel = status === 'cancelled' && doc.status !== 'draft'
    if (!isSyncActive() || (!validate && !cancel)) return applyStatus(doc, status, undefined, documents)
    // Multi-postes : le serveur n'accorde l'opération qu'à un seul poste (numéro définitif, mouvements de stock)
    const local = finalNumber(doc, documents)
    const prefix = local.slice(0, local.lastIndexOf('-') + 1)
    setValidating(doc.id)
    try {
      const outcome = await runDocAction(
        {
          docId: doc.id,
          action: validate ? 'validate' : 'cancel',
          kind: doc.kind,
          year: Number(doc.date.slice(0, 4)),
          min: Number(local.slice(prefix.length)) - 1,
        },
        (seq) => {
          const latest = mounted.current ? docsRef.current : (readDocuments() ?? docsRef.current)
          const fresh = latest.find((d) => d.id === doc.id)
          // Pièce supprimée ou déjà passée à un autre état entre-temps
          if (!fresh || fresh.status !== doc.status) return
          applyStatus(fresh, status, validate && seq !== null ? prefix + String(seq).padStart(4, '0') : undefined, latest)
        },
      )
      if (outcome === 'already')
        alert(`Cette pièce vient d'être ${validate ? 'validée' : 'annulée'} sur un autre poste : elle sera à jour ici dans quelques secondes.`)
    } catch {
      alert(
        `${validate ? 'Validation' : 'Annulation'} impossible pour le moment : en mode multi-postes, le serveur doit confirmer l'opération (pour éviter un numéro ou un mouvement de stock en double). Vérifiez la connexion Internet puis réessayez.`,
      )
    } finally {
      if (mounted.current) setValidating(null)
    }
  }

  function applyStatus(doc: CommercialDocument, status: DocStatus, forcedNumber: string | undefined, documents: CommercialDocument[]) {
    // Validation : numéro définitif, à la suite des pièces déjà validées (aucun trou possible)
    const number = forcedNumber ?? (status === 'validated' && doc.status === 'draft' ? finalNumber(doc, documents) : doc.number)
    if (number !== doc.number && mounted.current) setMessage({ text: `Numéro définitif attribué : ${number} (brouillon ${doc.number}).` })
    access.log(status === 'validated' ? 'Pièce validée' : 'Pièce annulée', `${DOC_LABELS[doc.kind].title} ${number} · ${doc.party.name}`)
    const supplier = doc.party.name
    let moved: Record<string, number> | null = null

    if (status === 'validated') {
      if (doc.kind === 'delivery') moved = onStockMove?.(doc.lines, -1, '', number) ?? {}
      if (doc.kind === 'receipt') onStockMove?.(doc.lines, 1, supplier, number)
      if (invoiceMovesStock(doc, documents)) onStockMove?.(doc.lines.filter((l) => !l.depotRef), -1, '', number)
    }

    if (status === 'cancelled' && doc.status !== 'draft') {
      if (doc.kind === 'delivery')
        onStockMove?.(
          doc.lines.filter((l) => l.depot !== 'returned').map((l) => ({ ...l, quantity: l.movedQty ?? l.quantity })),
          1,
          '',
          `Annulation ${doc.number}`,
        )
      if (doc.kind === 'receipt') onStockMove?.(doc.lines, -1, '', `Annulation ${doc.number}`)
    }

    const by = stamp().by
    const multi = isSyncActive()
    // Mise à jour appliquée à la liste la plus récente (rien de ce qui a changé entre-temps n'est perdu)
    onChange((prev) => {
      let next = prev.map((d) => {
        if (d.id !== doc.id) return d
        const updated: CommercialDocument = { ...d, status, number, ...(status === 'validated' ? { validatedBy: by } : {}) }
        // BL : on retient la quantité réellement sortie (pour une annulation exacte) ;
        // BL en dépôt : chaque ligne reste à facturer à la pose
        if (moved)
          updated.lines = d.lines.map((l) => ({
            ...l,
            movedQty: moved[l.id] ?? l.quantity,
            depot: doc.consignment ? (l.depot ?? 'depot') : l.depot,
          }))
        return updated
      })
      // Un autre brouillon portait déjà ce numéro provisoire : on lui en donne un nouveau
      // (pas en multi-postes : ce brouillon peut appartenir à un autre poste, on ne le touche pas)
      const clash = next.find((d) => d.id !== doc.id && d.kind === doc.kind && d.status === 'draft' && d.number === number)
      if (clash && !multi) next = next.map((d) => (d.id === clash.id ? { ...d, number: nextNumber(d.kind, next, d.date) } : d))
      return next
    })
  }

  function addPayment(doc: CommercialDocument, payment: Payment) {
    const balance = balanceOf(doc, documents) - payment.amount
    onChange(
      documents.map((d) =>
        d.id === doc.id
          ? { ...d, payments: [...(d.payments ?? []), payment], status: balance <= 0.01 ? 'paid' : d.status }
          : d,
      ),
    )
    setPaying(null)
    access.log(isPurchase ? 'Règlement fournisseur' : 'Encaissement', `${doc.number} · ${formatMAD(payment.amount)} · ${doc.party.name}`)
  }

  function remove(doc: CommercialDocument) {
    if (!confirm(`Supprimer ${doc.number} ?`)) return
    access.log('Pièce supprimée', `${DOC_LABELS[doc.kind].title} ${doc.number} · ${doc.party.name}`)
    // Facture issue d'un dépôt : les implants redeviennent « en dépôt »
    const refs = doc.lines.map((l) => l.depotRef).filter((r): r is { docId: string; lineId: string } => !!r)
    onChange(
      documents
        .filter((d) => d.id !== doc.id)
        .map((d) =>
          refs.some((r) => r.docId === d.id)
            ? {
                ...d,
                lines: d.lines.map((l) => (refs.some((r) => r.lineId === l.id) ? { ...l, depot: 'depot' as const } : l)),
              }
            : d,
        ),
    )
  }

  function copyLines(lines: DocLine[]): DocLine[] {
    return lines.map((l) => ({ ...l, id: newId(), depot: undefined, depotRef: undefined, movedQty: undefined }))
  }

  function duplicate(doc: CommercialDocument) {
    setView({
      mode: 'edit',
      doc: {
        ...doc,
        id: newId(),
        number: nextNumber(kind, documents, now),
        date: now,
        dueDate: addDays(now, kind === 'quote' ? 30 : 60),
        status: 'draft',
        payments: undefined,
        paidDate: undefined,
        createdBy: undefined,
        validatedBy: undefined,
        sourceId: undefined,
        sourceNumber: undefined,
        lines: copyLines(doc.lines),
      },
    })
  }

  function convert(doc: CommercialDocument, to: DocKind) {
    const created: CommercialDocument = {
      ...doc,
      id: newId(),
      kind: to,
      number: nextNumber(to, documents, now),
      date: now,
      dueDate: addDays(now, to === 'quote' ? 30 : 60),
      status: 'draft',
      payments: undefined,
      paidDate: undefined,
      consignment: undefined,
      supplierRef: to === 'bill' ? '' : undefined,
      createdBy: stamp().by,
      validatedBy: undefined,
      sourceId: doc.id,
      sourceNumber: doc.number,
      lines: copyLines(doc.lines),
    }
    onChange([...documents, created])
    access.log('Pièce transformée', `${doc.number} → ${created.number}`)
    const label = DOC_LABELS[to]
    setMessage({ text: `${label.title} ${created.number} créé(e) en brouillon à partir de ${doc.number}.`, kind: to, id: created.id })
  }

  function exportJournal() {
    const kinds: DocKind[] = isPurchase ? ['bill'] : ['invoice', 'credit']
    const docs = documents.filter((d) => kinds.includes(d.kind) && d.status !== 'draft').sort((a, b) => a.date.localeCompare(b.date) || a.number.localeCompare(b.number))
    downloadCsv(`journal-${isPurchase ? 'achats' : 'ventes'}-${now}.csv`, journal(docs, documents))
  }

  if (view.mode === 'edit') {
    return (
      <DocumentEditor
        initial={view.doc}
        products={products}
        lots={lots}
        kits={kits}
        parties={roleParties}
        onSave={save}
        onCancel={() => setView({ mode: 'list' })}
      />
    )
  }

  if (view.mode === 'print') {
    const doc = documents.find((d) => d.id === view.id)
    if (doc)
      return (
        <DocumentPrint
          doc={doc}
          company={company}
          paid={paidAmount(doc)}
          balance={balanceOf(doc, documents)}
          onClose={() => setView({ mode: 'list' })}
        />
      )
  }

  if (view.mode === 'reminder') {
    const invoices = documents
      .filter((d) => d.party.name === view.partyName && isOverdue(d, documents, now) && d.kind === 'invoice')
      .map((doc) => ({ doc, balance: balanceOf(doc, documents) }))
    const party = invoices[0]?.doc.party ?? { ...emptyParty(), name: view.partyName }
    return <ReminderPrint company={company} party={party} invoices={invoices} onClose={() => setView({ mode: 'list' })} />
  }

  const showMoney = kind !== 'delivery' && kind !== 'receipt'
  const hasBalance = kind === 'invoice' || kind === 'bill'

  return (
    <div>
      {!company.name && !isPurchase && (
        <p className="doc-warning">
          Renseignez d'abord la fiche de votre entreprise (ICE, IF, RC…) dans Paramètres › Mon entreprise : ces
          mentions sont obligatoires sur les factures.
        </p>
      )}

      {stats && (
        <div className="doc-stats">
          <div>
            <span>{isPurchase ? 'Achats HT' : "Chiffre d'affaires HT (net d'avoirs)"}</span>
            <strong>{formatMAD(stats.ht)}</strong>
          </div>
          <div>
            <span>{isPurchase ? 'TVA déductible' : 'TVA collectée'}</span>
            <strong>{formatMAD(stats.tva)}</strong>
          </div>
          <div>
            <span>{isPurchase ? 'Reste à payer' : 'Reste à encaisser'}</span>
            <strong>{formatMAD(stats.open)}</strong>
          </div>
          <div className={stats.lateCount ? 'doc-stat-late' : undefined}>
            <span>Échu ({stats.lateCount})</span>
            <strong>{formatMAD(stats.late)}</strong>
          </div>
        </div>
      )}

      {message && (
        <p className="doc-info">
          {message.text}{' '}
          {onNavigate && message.kind && (
            <button type="button" onClick={() => onNavigate(message.kind!, message.id)}>
              Ouvrir
            </button>
          )}
        </p>
      )}

      <div className="doc-toolbar">
        {canWrite && (
          <button type="button" className="btn-primary" onClick={() => setView({ mode: 'edit', doc: createDoc() })}>
            + {info.newLabel}
          </button>
        )}
        <input
          className="doc-search"
          placeholder="Rechercher : n°, tiers, patient, lot, n° de série…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select value={filter} onChange={(e) => setFilter(e.target.value as Filter)}>
          <option value="">Tous les états</option>
          {Object.entries(STATUS_LABELS).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
          {hasBalance && <option value="open">Non soldées</option>}
          {hasBalance && <option value="late">Échues</option>}
        </select>
        {(kind === 'invoice' || kind === 'credit' || kind === 'bill') && (
          <button type="button" onClick={exportJournal}>
            Exporter le journal {isPurchase ? 'des achats' : 'des ventes'} (CSV)
          </button>
        )}
        <span className="doc-count">{list.length} pièce(s)</span>
      </div>

      {list.length === 0 ? (
        <p className="doc-empty">Aucune pièce pour le moment.</p>
      ) : (
        <div className="doc-table-wrap">
          <table className="doc-table doc-list">
            <thead>
              <tr>
                <th>N°</th>
                <th>Date</th>
                <th>{isPurchase ? 'Fournisseur' : 'Client'}</th>
                {kind === 'bill' && <th>Réf. fournisseur</th>}
                {!isPurchase && <th>Patient</th>}
                {showMoney && <th className="num">Total TTC</th>}
                {hasBalance && <th className="num">Reste dû</th>}
                {hasBalance && <th>Échéance</th>}
                <th>État</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {list.map((d) => {
                const t = computeTotals(d)
                const balance = balanceOf(d, documents)
                const late = isOverdue(d, documents, now)
                const settledByCredit = d.kind === 'invoice' && d.status === 'validated' && balance <= 0.01
                const depotLeft = d.consignment ? d.lines.filter((l) => l.depot === 'depot').length : 0
                return (
                  <tr key={d.id} className={late ? 'doc-row-late' : undefined}>
                    <td>
                      <button type="button" className="doc-link" onClick={() => setView(d.status === 'draft' && canWrite ? { mode: 'edit', doc: d } : { mode: 'print', id: d.id })}>
                        {d.number}
                      </button>
                    </td>
                    <td>{frDate(d.date)}</td>
                    <td>{d.party.name}</td>
                    {kind === 'bill' && <td>{d.supplierRef}</td>}
                    {!isPurchase && <td>{d.intervention?.patient}</td>}
                    {showMoney && <td className="num">{formatMAD(t.netToPay)}</td>}
                    {hasBalance && <td className="num">{isActive(d) ? formatMAD(balance) : ''}</td>}
                    {hasBalance && <td>{frDate(d.dueDate)}</td>}
                    <td>
                      <span className={`doc-badge doc-badge-${settledByCredit ? 'paid' : d.status}`}>
                        {settledByCredit ? 'Soldée' : d.kind === 'invoice' && d.status === 'paid' ? 'Payée' : STATUS_LABELS[d.status]}
                      </span>
                      {late && <span className="doc-badge doc-badge-late">Échue</span>}
                      {d.consignment && (
                        <span className="doc-badge doc-badge-depot">
                          Dépôt{depotLeft ? ` · ${depotLeft} chez le client` : ''}
                        </span>
                      )}
                    </td>
                    <td className="doc-actions">
                      <button type="button" onClick={() => setView({ mode: 'print', id: d.id })}>
                        Imprimer
                      </button>
                      {d.status === 'draft' && (
                        <>
                          {canWrite && (
                            <button type="button" onClick={() => setView({ mode: 'edit', doc: d })}>
                              Modifier
                            </button>
                          )}
                          {canValidate && (
                            <button
                              type="button"
                              className="btn-primary"
                              disabled={validating !== null}
                              onClick={() => void setStatus(d, 'validated')}
                            >
                              {validating === d.id ? 'Validation…' : 'Valider'}
                            </button>
                          )}
                          {canDelete && (
                            <button type="button" onClick={() => remove(d)}>
                              Supprimer
                            </button>
                          )}
                        </>
                      )}
                      {canPay && hasBalance && d.status === 'validated' && balance > 0.01 && (
                        <button type="button" onClick={() => setPaying(d)}>
                          {isPurchase ? 'Régler' : 'Encaisser'}
                        </button>
                      )}
                      {late && d.kind === 'invoice' && (
                        <button type="button" onClick={() => setView({ mode: 'reminder', partyName: d.party.name })}>
                          Relance
                        </button>
                      )}
                      {/* Une facture validée ne s'annule pas : on émet un avoir */}
                      {canDelete && d.status === 'validated' && d.kind !== 'invoice' && (
                        <button
                          type="button"
                          onClick={() => confirm(`Annuler ${d.number} ?`) && void setStatus(d, 'cancelled')}
                        >
                          Annuler
                        </button>
                      )}
                      {canWrite &&
                        d.status !== 'cancelled' &&
                        d.status !== 'draft' &&
                        CONVERSIONS[d.kind]
                          .filter((to) => !(d.consignment && to === 'invoice'))
                          .map((to) => (
                            <button key={to} type="button" onClick={() => convert(d, to)}>
                              → {DOC_LABELS[to].title}
                            </button>
                          ))}
                      {canWrite && (
                        <button type="button" onClick={() => duplicate(d)}>
                          Dupliquer
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {paying && (
        <PaymentDialog
          doc={paying}
          balance={balanceOf(paying, documents)}
          onSave={(p) => addPayment(paying, p)}
          onClose={() => setPaying(null)}
        />
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DocumentsPage.tsx"

cat > src/documents/InventoryPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { downloadCsv } from './csv'
import { frDate, newId, today } from './numbering'
import { formatMAD, round2 } from './tva'
import type { StockMovement } from './types'
import './documents.css'

interface Props {
  products: Product[]
  onProductsChange: (products: Product[]) => void
  onMovements: (movements: StockMovement[]) => void
}

/** Inventaire physique : saisie des quantités comptées, écarts valorisés, mise à jour du stock */
export default function InventoryPage({ products, onProductsChange, onMovements }: Props) {
  const [counts, setCounts] = useState<Record<string, string>>({})
  const [query, setQuery] = useState('')
  const [onlyGaps, setOnlyGaps] = useState(false)
  const [message, setMessage] = useState('')
  const access = useAccess()
  const canWrite = access.level('stock') === 'write'
  const showCosts = access.can('costs')

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return products
      .filter((p) => !q || [p.name, p.reference, p.category].join(' ').toLowerCase().includes(q))
      .map((p) => {
        const raw = counts[p.id]
        const counted = raw === undefined || raw.trim() === '' ? undefined : Math.max(0, Math.round(Number(raw.replace(',', '.'))))
        const theoretical = p.stock ?? 0
        const gap = counted === undefined || !Number.isFinite(counted) ? undefined : counted - theoretical
        return { product: p, theoretical, counted, gap }
      })
      .filter((r) => !onlyGaps || (r.gap !== undefined && r.gap !== 0))
  }, [products, counts, query, onlyGaps])

  const changed = rows.filter((r) => r.gap !== undefined && r.gap !== 0)
  const gapValue = round2(changed.reduce((s, r) => s + (r.gap ?? 0) * r.product.unitCost, 0))
  const stockValue = round2(products.reduce((s, p) => s + (p.stock ?? 0) * p.unitCost, 0))

  function validate() {
    const entered = rows.filter((r) => r.counted !== undefined && Number.isFinite(r.counted))
    if (entered.length === 0) return setMessage('Saisissez au moins une quantité comptée.')
    if (!confirm(`Mettre à jour le stock de ${entered.length} article(s) d'après le comptage ?`)) return
    const date = today()
    const reference = `Inventaire du ${frDate(date)}`
    const byId = new Map(entered.map((r) => [r.product.id, r]))
    onProductsChange(products.map((p) => (byId.has(p.id) ? { ...p, stock: byId.get(p.id)!.counted } : p)))
    onMovements(
      entered
        .filter((r) => r.gap !== 0 || r.product.stock === undefined)
        .map((r) => ({
          id: newId(),
          date,
          productId: r.product.id,
          productName: r.product.name,
          lot: '',
          serial: '',
          quantity: r.gap ?? 0,
          kind: 'adjust' as const,
          reference,
          stockAfter: r.counted,
        })),
    )
    setCounts({})
    access.log('Inventaire validé', `${entered.length} article(s), écart ${formatMAD(gapValue)}`)
    setMessage(`${reference} validé : ${entered.length} article(s) mis à jour, écart ${formatMAD(gapValue)}.`)
  }

  function exportSheet() {
    downloadCsv(`feuille-inventaire-${today()}.csv`, [
      ['Référence', 'Article', 'Catégorie', 'Stock théorique', 'Quantité comptée', 'Écart'],
      ...products.map((p) => [p.reference ?? '', p.name, p.category, String(p.stock ?? 0), '', '']),
    ])
  }

  return (
    <div>
      <div className="doc-stats">
        {showCosts && (
          <div>
            <span>Valeur du stock (coût d'achat)</span>
            <strong>{formatMAD(stockValue)}</strong>
          </div>
        )}
        <div>
          <span>Articles avec écart</span>
          <strong>{changed.length}</strong>
        </div>
        {showCosts && (
          <div className={gapValue < 0 ? 'doc-stat-danger' : undefined}>
            <span>Valeur des écarts</span>
            <strong>{formatMAD(gapValue)}</strong>
          </div>
        )}
      </div>

      <div className="doc-toolbar">
        <input className="doc-search" placeholder="Rechercher un article…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <label className="doc-check">
          <input type="checkbox" checked={onlyGaps} onChange={(e) => setOnlyGaps(e.target.checked)} /> Écarts seulement
        </label>
        <button type="button" onClick={exportSheet}>
          Feuille de comptage (CSV)
        </button>
        {canWrite && (
          <button type="button" className="btn-primary" onClick={validate}>
            Valider l'inventaire
          </button>
        )}
      </div>
      {message && <p className="doc-info">{message}</p>}

      <div className="doc-table-wrap">
        <table className="doc-table">
          <thead>
            <tr>
              <th>Référence</th>
              <th>Article</th>
              <th>Catégorie</th>
              <th className="num">Stock théorique</th>
              <th className="num">Quantité comptée</th>
              <th className="num">Écart</th>
              {showCosts && <th className="num">Valeur de l'écart</th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.product.id} className={r.gap ? (r.gap < 0 ? 'doc-row-danger' : 'doc-row-late') : undefined}>
                <td>{r.product.reference}</td>
                <td>{r.product.name}</td>
                <td>{r.product.category}</td>
                <td className="num">{r.product.stock ?? '—'}</td>
                <td className="num">
                  <input
                    className="num doc-qty"
                    type="number"
                    min={0}
                    value={counts[r.product.id] ?? ''}
                    readOnly={!canWrite}
                    onChange={(e) => setCounts({ ...counts, [r.product.id]: e.target.value })}
                  />
                </td>
                <td className="num">{r.gap === undefined ? '' : r.gap > 0 ? `+${r.gap}` : r.gap}</td>
                {showCosts && <td className="num">{r.gap ? formatMAD(round2(r.gap * r.product.unitCost)) : ''}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="doc-count">
        Les articles laissés vides ne sont pas modifiés. Chaque écart est enregistré dans les mouvements de stock.
      </p>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/InventoryPage.tsx"

cat > src/documents/KitsPage.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { newId } from './numbering'
import { formatMAD, round2 } from './tva'
import type { Kit } from './types'
import './documents.css'

interface Props {
  kits: Kit[]
  onChange: (kits: Kit[]) => void
  products: Product[]
}

/** Kits : ensembles d'articles insérés d'un coup dans un devis, un BL ou une facture (ex. kit PTH) */
export default function KitsPage({ kits, onChange, products }: Props) {
  const [editing, setEditing] = useState<Kit | null>(null)
  const [error, setError] = useState('')
  const canWrite = useAccess().level('stock') === 'write'
  const product = (id: string) => products.find((p) => p.id === id)
  const kitPrice = (k: Kit) => round2(k.items.reduce((s, i) => s + (product(i.productId)?.unitPrice ?? 0) * i.quantity, 0))

  function save() {
    if (!editing) return
    const items = editing.items.filter((i) => i.productId && i.quantity > 0)
    if (!editing.name.trim()) return setError('Donnez un nom au kit.')
    if (items.length === 0) return setError('Ajoutez au moins un article.')
    const kit = { ...editing, name: editing.name.trim(), items }
    onChange(kits.some((k) => k.id === kit.id) ? kits.map((k) => (k.id === kit.id ? kit : k)) : [...kits, kit])
    setEditing(null)
    setError('')
  }

  if (editing) {
    const setItem = (index: number, patch: Partial<Kit['items'][number]>) =>
      setEditing({ ...editing, items: editing.items.map((it, i) => (i === index ? { ...it, ...patch } : it)) })
    return (
      <div className="doc-panel">
        <div className="doc-panel-title">Kit</div>
        <label className="doc-notes">
          Nom du kit
          <input
            value={editing.name}
            placeholder="ex. Kit PTH cimentée taille 3"
            onChange={(e) => setEditing({ ...editing, name: e.target.value })}
          />
        </label>
        <table className="doc-table">
          <thead>
            <tr>
              <th>Article</th>
              <th className="num">Quantité</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {editing.items.map((it, i) => (
              <tr key={i}>
                <td>
                  <select value={it.productId} onChange={(e) => setItem(i, { productId: e.target.value })}>
                    <option value="">—</option>
                    {products.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.reference ? `${p.reference} · ` : ''}
                        {p.name}
                      </option>
                    ))}
                  </select>
                </td>
                <td>
                  <input
                    className="num doc-qty"
                    type="number"
                    min={1}
                    value={it.quantity}
                    onChange={(e) => setItem(i, { quantity: Number(e.target.value) })}
                  />
                </td>
                <td>
                  <button
                    type="button"
                    onClick={() => setEditing({ ...editing, items: editing.items.filter((_, j) => j !== i) })}
                  >
                    ✕
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {error && <p className="doc-error">{error}</p>}
        <div className="doc-toolbar">
          <button
            type="button"
            onClick={() => setEditing({ ...editing, items: [...editing.items, { productId: '', quantity: 1 }] })}
          >
            + Article
          </button>
          <button type="button" className="btn-primary" onClick={save}>
            Enregistrer le kit
          </button>
          <button type="button" onClick={() => setEditing(null)}>
            Annuler
          </button>
        </div>
      </div>
    )
  }

  return (
    <div>
      <div className="doc-toolbar">
        {canWrite && (
          <button
            type="button"
            className="btn-primary"
            onClick={() => setEditing({ id: newId(), name: '', items: [{ productId: '', quantity: 1 }] })}
          >
            + Nouveau kit
          </button>
        )}
        <span className="doc-count">Un kit s'insère en un clic dans un devis, un BL ou une facture.</span>
      </div>
      {kits.length === 0 ? (
        <p className="doc-empty">Aucun kit. Exemple : « Kit PTH » = tige fémorale + cotyle + insert + tête.</p>
      ) : (
        <table className="doc-table">
          <thead>
            <tr>
              <th>Kit</th>
              <th>Composition</th>
              <th className="num">Prix de vente HT</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {kits.map((k) => (
              <tr key={k.id}>
                <td>{k.name}</td>
                <td>
                  {k.items
                    .map((i) => `${i.quantity} × ${product(i.productId)?.name ?? '(article supprimé)'}`)
                    .join(', ')}
                </td>
                <td className="num">{formatMAD(kitPrice(k))}</td>
                <td className="doc-actions">
                  {canWrite && <>
                  <button type="button" onClick={() => setEditing(k)}>
                    Modifier
                  </button>
                  <button
                    type="button"
                    onClick={() => confirm(`Supprimer le kit « ${k.name} » ?`) && onChange(kits.filter((x) => x.id !== k.id))}
                  >
                    Supprimer
                  </button>
                  </>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/KitsPage.tsx"

cat > src/documents/LotsPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { frDate, newId, today } from './numbering'
import { expiryState, type ExpiryState } from './stockMoves'
import { DOC_LABELS, type CommercialDocument, type StockLot } from './types'
import './documents.css'

interface Props {
  lots: StockLot[]
  onChange: (lots: StockLot[]) => void
  products: Product[]
  documents: CommercialDocument[]
  /** Recherche initiale (lot ou n° de série venant de la recherche globale) */
  initialQuery?: string
}

const EXPIRY_LABELS: Record<ExpiryState, string> = {
  expired: 'Périmé',
  soon: '< 90 jours',
  ok: 'OK',
  none: 'Sans date',
}

type Filter = '' | 'available' | 'expired' | 'soon'

/** Stock par lot / numéro de série, péremptions et traçabilité (rappel de lot) */
export default function LotsPage({ lots, onChange, products, documents, initialQuery = '' }: Props) {
  const [query, setQuery] = useState(initialQuery)
  const [filter, setFilter] = useState<Filter>(initialQuery ? '' : 'available')
  const [draft, setDraft] = useState({ productId: '', lot: '', serial: '', expiry: '', quantity: '1', supplier: '' })
  const [error, setError] = useState('')
  const canWrite = useAccess().level('stock') === 'write'
  const now = today()
  const productName = (id: string) => products.find((p) => p.id === id)?.name ?? '(article supprimé)'

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return lots
      .filter((l) => {
        const st = expiryState(l.expiry, now)
        if (filter === 'available') return l.quantity > 0
        if (filter === 'expired') return l.quantity > 0 && st === 'expired'
        if (filter === 'soon') return l.quantity > 0 && st === 'soon'
        return true
      })
      .filter((l) => !q || [l.lot, l.serial, l.supplier, productName(l.productId)].join(' ').toLowerCase().includes(q))
      .sort((a, b) => (a.expiry || '9999').localeCompare(b.expiry || '9999'))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lots, query, filter, now, products])

  // Traçabilité : toutes les pièces qui citent le lot ou le n° de série recherché
  const trace = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (q.length < 2) return []
    const hits: { doc: CommercialDocument; qty: number; label: string }[] = []
    for (const d of documents) {
      if (d.status === 'draft') continue
      for (const l of d.lines) {
        if ([l.lot, l.serial].some((v) => v && v.toLowerCase().includes(q)))
          hits.push({ doc: d, qty: l.quantity, label: `${l.description} · ${[l.lot, l.serial].filter(Boolean).join(' / ')}` })
      }
    }
    return hits.sort((a, b) => a.doc.date.localeCompare(b.doc.date))
  }, [documents, query])

  function add() {
    const quantity = Number(draft.quantity)
    if (!draft.productId) return setError('Choisissez un article.')
    if (!draft.lot.trim() && !draft.serial.trim()) return setError('Indiquez un n° de lot ou de série.')
    if (!Number.isFinite(quantity) || quantity <= 0) return setError('Quantité invalide.')
    onChange([
      ...lots,
      {
        id: newId(),
        productId: draft.productId,
        lot: draft.lot.trim(),
        serial: draft.serial.trim(),
        expiry: draft.expiry,
        quantity,
        receivedDate: now,
        supplier: draft.supplier.trim(),
      },
    ])
    setDraft({ ...draft, lot: '', serial: '', expiry: '', quantity: '1' })
    setError('')
  }

  function setQty(id: string, quantity: number) {
    onChange(lots.map((l) => (l.id === id ? { ...l, quantity: Math.max(0, quantity) } : l)))
  }

  const expired = lots.filter((l) => l.quantity > 0 && expiryState(l.expiry, now) === 'expired').length
  const soon = lots.filter((l) => l.quantity > 0 && expiryState(l.expiry, now) === 'soon').length

  return (
    <div>
      <div className="doc-stats">
        <div>
          <span>Lots en stock</span>
          <strong>{lots.filter((l) => l.quantity > 0).length}</strong>
        </div>
        <div className={expired ? 'doc-stat-late' : undefined}>
          <span>Périmés à retirer</span>
          <strong>{expired}</strong>
        </div>
        <div className={soon ? 'doc-stat-late' : undefined}>
          <span>Péremption sous 90 jours</span>
          <strong>{soon}</strong>
        </div>
      </div>

      {canWrite && <div className="doc-panel">
        <div className="doc-panel-title">Entrée manuelle d'un lot (stock initial)</div>
        <div className="doc-grid">
          <label>
            Article
            <select value={draft.productId} onChange={(e) => setDraft({ ...draft, productId: e.target.value })}>
              <option value="">—</option>
              {products.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.reference ? `${p.reference} · ` : ''}
                  {p.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            N° de lot
            <input value={draft.lot} onChange={(e) => setDraft({ ...draft, lot: e.target.value })} />
          </label>
          <label>
            N° de série
            <input value={draft.serial} onChange={(e) => setDraft({ ...draft, serial: e.target.value })} />
          </label>
          <label>
            Péremption
            <input type="date" value={draft.expiry} onChange={(e) => setDraft({ ...draft, expiry: e.target.value })} />
          </label>
          <label>
            Quantité
            <input className="num" value={draft.quantity} onChange={(e) => setDraft({ ...draft, quantity: e.target.value })} />
          </label>
          <label>
            Fournisseur
            <input value={draft.supplier} onChange={(e) => setDraft({ ...draft, supplier: e.target.value })} />
          </label>
        </div>
        {error && <p className="doc-error">{error}</p>}
        <div className="doc-toolbar">
          <button type="button" className="btn-primary" onClick={add}>
            Ajouter le lot
          </button>
          <span className="doc-count">Les bons de réception validés créent les lots automatiquement.</span>
        </div>
      </div>}

      <div className="doc-toolbar">
        <input
          className="doc-search"
          placeholder="Rechercher un lot, un n° de série, un article…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <select value={filter} onChange={(e) => setFilter(e.target.value as Filter)}>
          <option value="available">En stock</option>
          <option value="soon">Péremption sous 90 jours</option>
          <option value="expired">Périmés</option>
          <option value="">Tous (y compris épuisés)</option>
        </select>
        <span className="doc-count">{rows.length} lot(s)</span>
      </div>

      <div className="doc-table-wrap">
        <table className="doc-table">
          <thead>
            <tr>
              <th>Article</th>
              <th>Lot</th>
              <th>N° série</th>
              <th>Péremption</th>
              <th>État</th>
              <th>Fournisseur</th>
              <th>Reçu le</th>
              <th className="num">Quantité</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((l) => {
              const st = expiryState(l.expiry, now)
              return (
                <tr key={l.id} className={st === 'expired' && l.quantity > 0 ? 'doc-row-late' : undefined}>
                  <td>{productName(l.productId)}</td>
                  <td>{l.lot}</td>
                  <td>{l.serial}</td>
                  <td>{frDate(l.expiry)}</td>
                  <td>
                    <span className={`doc-badge doc-exp-${st}`}>{EXPIRY_LABELS[st]}</span>
                  </td>
                  <td>{l.supplier}</td>
                  <td>{frDate(l.receivedDate)}</td>
                  <td className="num">
                    <input
                      className="num doc-qty"
                      type="number"
                      min={0}
                      value={l.quantity}
                      readOnly={!canWrite}
                      onChange={(e) => setQty(l.id, Number(e.target.value))}
                    />
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {trace.length > 0 && (
        <div className="doc-panel">
          <div className="doc-panel-title">Traçabilité de « {query.trim()} » : {trace.length} mouvement(s)</div>
          <table className="doc-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Pièce</th>
                <th>N°</th>
                <th>Tiers</th>
                <th>Patient</th>
                <th>Article</th>
                <th className="num">Qté</th>
              </tr>
            </thead>
            <tbody>
              {trace.map((h, i) => (
                <tr key={`${h.doc.id}-${i}`}>
                  <td>{frDate(h.doc.date)}</td>
                  <td>{DOC_LABELS[h.doc.kind].title}</td>
                  <td>{h.doc.number}</td>
                  <td>{h.doc.party.name}</td>
                  <td>{h.doc.intervention?.patient}</td>
                  <td>{h.label}</td>
                  <td className="num">{h.qty}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/LotsPage.tsx"

cat > src/documents/PartiesPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import ReminderPrint from './ReminderPrint'
import { balanceOf, isActive, isOverdue, sign } from './ledger'
import { frDate, newId, today } from './numbering'
import { computeTotals, formatMAD, round2 } from './tva'
import {
  DOC_LABELS,
  STATUS_LABELS,
  emptyParty,
  type CommercialDocument,
  type CompanyInfo,
  type PartyRecord,
  type PartyRole,
} from './types'
import './documents.css'

interface Props {
  role: PartyRole
  parties: PartyRecord[]
  onChange: (parties: PartyRecord[]) => void
  documents: CommercialDocument[]
  company: CompanyInfo
  /** Fiche à ouvrir directement (recherche globale) */
  openId?: string
}

const fields: { key: 'name' | 'address' | 'city' | 'ice' | 'ifNumber' | 'rc' | 'phone' | 'email'; label: string }[] = [
  { key: 'name', label: 'Raison sociale / Nom' },
  { key: 'address', label: 'Adresse' },
  { key: 'city', label: 'Ville' },
  { key: 'phone', label: 'Téléphone' },
  { key: 'email', label: 'E-mail' },
  { key: 'ice', label: 'ICE' },
  { key: 'ifNumber', label: 'IF' },
  { key: 'rc', label: 'RC' },
]

const same = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase()

/** Fichier clients ou fournisseurs : fiche, chiffre d'affaires, encours, historique, relance */
export default function PartiesPage({ role, parties, onChange, documents, company, openId }: Props) {
  const [query, setQuery] = useState('')
  const [editing, setEditing] = useState<PartyRecord | null>(() => parties.find((p) => p.id === openId) ?? null)
  const [reminder, setReminder] = useState<string | null>(null)
  const [error, setError] = useState('')
  const now = today()
  const isClient = role === 'client'
  const access = useAccess()
  const canWrite = access.level(isClient ? 'sales' : 'purchases') === 'write'
  const side = isClient ? 'sale' : 'purchase'

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return parties
      .filter((p) => p.role === role)
      .filter((p) => !q || [p.name, p.city, p.ice, p.phone].join(' ').toLowerCase().includes(q))
      .map((p) => {
        const docs = documents.filter((d) => DOC_LABELS[d.kind].side === side && same(d.party.name, p.name))
        let revenue = 0
        let balance = 0
        let late = 0
        for (const d of docs) {
          if (!isActive(d)) continue
          if (d.kind === 'invoice' || d.kind === 'credit' || d.kind === 'bill') revenue += sign(d) * computeTotals(d).totalHT
          if (d.kind === 'invoice' || d.kind === 'bill') balance += balanceOf(d, documents)
          if (isOverdue(d, documents, now)) late += balanceOf(d, documents)
        }
        const last = docs.reduce((m, d) => (d.date > m ? d.date : m), '')
        return { party: p, docs, revenue: round2(revenue), balance: round2(balance), late: round2(late), last }
      })
      .sort((a, b) => b.revenue - a.revenue || a.party.name.localeCompare(b.party.name))
  }, [parties, documents, role, side, query, now])

  function save() {
    if (!editing) return
    if (!editing.name.trim()) return setError('Le nom est obligatoire.')
    if (editing.ice && !/^\d{15}$/.test(editing.ice.trim())) return setError("L'ICE doit comporter 15 chiffres.")
    const duplicate = parties.some((p) => p.id !== editing.id && p.role === role && same(p.name, editing.name))
    if (duplicate) return setError('Un tiers porte déjà ce nom.')
    const rec = { ...editing, name: editing.name.trim() }
    onChange(parties.some((p) => p.id === rec.id) ? parties.map((p) => (p.id === rec.id ? rec : p)) : [...parties, rec])
    access.log(isClient ? 'Fiche client enregistrée' : 'Fiche fournisseur enregistrée', rec.name)
    setEditing(null)
    setError('')
  }

  if (reminder) {
    const invoices = documents
      .filter((d) => d.kind === 'invoice' && same(d.party.name, reminder) && isOverdue(d, documents, now))
      .map((doc) => ({ doc, balance: balanceOf(doc, documents) }))
    const party = invoices[0]?.doc.party ?? { ...emptyParty(), name: reminder }
    return <ReminderPrint company={company} party={party} invoices={invoices} onClose={() => setReminder(null)} />
  }

  if (editing) {
    const history = rows.find((r) => r.party.id === editing.id)?.docs ?? []
    return (
      <div>
        <div className="doc-editor-head">
          <h2>{editing.name || (isClient ? 'Nouveau client' : 'Nouveau fournisseur')}</h2>
          <div className="doc-editor-actions">
            {canWrite && (
              <button type="button" className="btn-primary" onClick={save}>
                Enregistrer
              </button>
            )}
            <button type="button" onClick={() => setEditing(null)}>
              Fermer
            </button>
          </div>
        </div>
        <fieldset className="doc-panel">
          <legend>Coordonnées</legend>
          <div className="doc-grid">
            {fields.map((f) => (
              <label key={f.key}>
                {f.label}
                <input value={editing[f.key]} onChange={(e) => setEditing({ ...editing, [f.key]: e.target.value })} />
              </label>
            ))}
            <label>
              Délai de paiement (jours)
              <input
                className="num"
                type="number"
                min={0}
                value={editing.paymentTerms ?? ''}
                onChange={(e) =>
                  setEditing({ ...editing, paymentTerms: e.target.value === '' ? undefined : Number(e.target.value) })
                }
              />
            </label>
            {isClient && (
              <label className="doc-check">
                <input
                  type="checkbox"
                  checked={!!editing.individual}
                  onChange={(e) => setEditing({ ...editing, individual: e.target.checked })}
                />
                Particulier (patient)
              </label>
            )}
          </div>
          <label className="doc-notes">
            Notes
            <textarea rows={3} value={editing.notes} onChange={(e) => setEditing({ ...editing, notes: e.target.value })} />
          </label>
        </fieldset>
        {error && <p className="doc-error">{error}</p>}

        {history.length > 0 && (
          <div className="doc-panel">
            <div className="doc-panel-title">Historique ({history.length} pièces)</div>
            <table className="doc-table">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Pièce</th>
                  <th>N°</th>
                  <th className="num">Total TTC</th>
                  <th className="num">Reste dû</th>
                  <th>État</th>
                </tr>
              </thead>
              <tbody>
                {[...history]
                  .sort((a, b) => b.date.localeCompare(a.date))
                  .map((d) => (
                    <tr key={d.id} className={isOverdue(d, documents, now) ? 'doc-row-late' : undefined}>
                      <td>{frDate(d.date)}</td>
                      <td>{DOC_LABELS[d.kind].title}</td>
                      <td>{d.number}</td>
                      <td className="num">{formatMAD(sign(d) * computeTotals(d).netToPay)}</td>
                      <td className="num">
                        {(d.kind === 'invoice' || d.kind === 'bill') && isActive(d) ? formatMAD(balanceOf(d, documents)) : ''}
                      </td>
                      <td>{STATUS_LABELS[d.status]}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    )
  }

  return (
    <div>
      <div className="doc-toolbar">
        {canWrite && (
          <button
            type="button"
            className="btn-primary"
            onClick={() => setEditing({ ...emptyParty(), id: newId(), role, notes: '' })}
          >
            + {isClient ? 'Nouveau client' : 'Nouveau fournisseur'}
          </button>
        )}
        <input
          className="doc-search"
          placeholder="Rechercher : nom, ville, ICE, téléphone…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <span className="doc-count">{rows.length} fiche(s)</span>
      </div>

      {rows.length === 0 ? (
        <p className="doc-empty">
          Aucune fiche. Les {isClient ? 'clients' : 'fournisseurs'} saisis sur les pièces sont ajoutés automatiquement.
        </p>
      ) : (
        <div className="doc-table-wrap">
          <table className="doc-table doc-list">
            <thead>
              <tr>
                <th>Nom</th>
                <th>Ville</th>
                <th>ICE</th>
                <th>Téléphone</th>
                <th className="num">{isClient ? 'CA HT' : 'Achats HT'}</th>
                <th className="num">Encours</th>
                <th className="num">Échu</th>
                <th>Dernière pièce</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.party.id} className={r.late > 0 ? 'doc-row-late' : undefined}>
                  <td>
                    <button type="button" className="doc-link" onClick={() => setEditing(r.party)}>
                      {r.party.name}
                    </button>
                  </td>
                  <td>{r.party.city}</td>
                  <td>{r.party.ice}</td>
                  <td>{r.party.phone}</td>
                  <td className="num">{formatMAD(r.revenue)}</td>
                  <td className="num">{formatMAD(r.balance)}</td>
                  <td className="num">{r.late > 0 ? formatMAD(r.late) : ''}</td>
                  <td>{frDate(r.last)}</td>
                  <td className="doc-actions">
                    <button type="button" onClick={() => setEditing(r.party)}>
                      Fiche
                    </button>
                    {isClient && r.late > 0 && (
                      <button type="button" onClick={() => setReminder(r.party.name)}>
                        Lettre de relance
                      </button>
                    )}
                    {canWrite && r.docs.length === 0 && (
                      <button
                        type="button"
                        onClick={() =>
                          confirm(`Supprimer la fiche « ${r.party.name} » ?`) &&
                          onChange(parties.filter((p) => p.id !== r.party.id))
                        }
                      >
                        Supprimer
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/PartiesPage.tsx"

cat > src/documents/PaymentDialog.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { newId, today } from './numbering'
import { formatMAD, round2 } from './tva'
import { PAYMENT_LABELS, type CommercialDocument, type Payment, type PaymentMethod } from './types'

interface Props {
  doc: CommercialDocument
  balance: number
  onSave: (payment: Payment) => void
  onClose: () => void
}

/** Saisie d'un règlement (total ou partiel) */
export default function PaymentDialog({ doc, balance, onSave, onClose }: Props) {
  const [date, setDate] = useState(today())
  const [amount, setAmount] = useState(String(balance))
  const [method, setMethod] = useState<PaymentMethod>(doc.paymentMethod)
  const [reference, setReference] = useState('')
  const [error, setError] = useState('')
  const isPurchase = doc.kind === 'bill'

  function submit() {
    const value = round2(Number(amount.replace(',', '.')))
    if (!Number.isFinite(value) || value <= 0) return setError('Montant invalide.')
    if (value > balance + 0.01) return setError(`Le montant dépasse le reste dû (${formatMAD(balance)}).`)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return setError('Date invalide.')
    onSave({ id: newId(), date, amount: value, method, reference: reference.trim() })
  }

  return (
    <div className="doc-modal-backdrop" onClick={onClose}>
      <div className="doc-modal" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <div className="doc-modal-title">
          {isPurchase ? 'Règlement fournisseur' : 'Encaissement'} · {doc.number}
        </div>
        <div className="doc-modal-body">
          <p>
            {doc.party.name} · reste dû : <strong>{formatMAD(balance)}</strong>
          </p>
          <div className="doc-grid">
            <label>
              Date
              <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
            </label>
            <label>
              Montant (DH)
              <input className="num" value={amount} onChange={(e) => setAmount(e.target.value)} autoFocus />
            </label>
            <label>
              Mode
              <select value={method} onChange={(e) => setMethod(e.target.value as PaymentMethod)}>
                {Object.entries(PAYMENT_LABELS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Référence (n° chèque, virement…)
              <input value={reference} onChange={(e) => setReference(e.target.value)} />
            </label>
          </div>
          {error && <p className="doc-error">{error}</p>}
        </div>
        <div className="doc-modal-actions">
          <button type="button" className="btn-primary" onClick={submit}>
            Enregistrer le règlement
          </button>
          <button type="button" onClick={onClose}>
            Annuler
          </button>
        </div>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/PaymentDialog.tsx"

cat > src/documents/PrintParts.tsx <<'FIN_DU_FICHIER'
import type { CompanyInfo } from './types'

/** En-tête société généré (quand on n'imprime pas sur papier à en-tête) */
export function CompanyHeader({ company }: { company: CompanyInfo }) {
  return (
    <header className="doc-print-head">
      <div className="doc-print-company">
        {company.logo && <img className="doc-logo" src={company.logo} alt="" />}
        <div>
          <strong className="doc-company">{company.name || 'Votre entreprise'}</strong>
          <div>{company.address}</div>
          <div>{company.city}</div>
          <div>{[company.phone, company.email].filter(Boolean).join(' · ')}</div>
        </div>
      </div>
    </header>
  )
}

/** Mentions légales de l'émetteur, répétées en bas de chaque page */
export function CompanyFooter({ company }: { company: CompanyInfo }) {
  const ids = [
    company.ice && `ICE : ${company.ice}`,
    company.ifNumber && `IF : ${company.ifNumber}`,
    company.rc && `RC : ${company.rc}`,
    company.patente && `Patente : ${company.patente}`,
    company.cnss && `CNSS : ${company.cnss}`,
  ].filter(Boolean)
  return (
    <footer className="doc-footer">
      <div>
        <strong>{company.name}</strong>
        {company.address ? ` · ${company.address}` : ''}
        {company.city ? `, ${company.city}` : ''}
        {company.phone ? ` · Tél. ${company.phone}` : ''}
      </div>
      {ids.length > 0 && <div>{ids.join(' · ')}</div>}
      {company.rib && (
        <div>
          {company.bank} · RIB : {company.rib}
        </div>
      )}
    </footer>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/PrintParts.tsx"

cat > src/documents/PrintSheet.tsx <<'FIN_DU_FICHIER'
import type { CSSProperties, ReactNode } from 'react'
import { printSettingsOf } from './printSettings'
import type { CompanyInfo, PrintSettings } from './types'

interface Props {
  company: CompanyInfo
  /** Réglages à appliquer (aperçu en direct depuis les paramètres) */
  settings?: PrintSettings
  /** Pied de page (mentions légales) quand le papier n'en a pas */
  footer?: ReactNode
  children: ReactNode
}

/**
 * Feuille A4 : place le papier à en-tête (image d'en-tête, de pied de page ou fond complet)
 * et réserve les marges. À l'impression, l'en-tête et le pied de page se répètent sur chaque page
 * (éléments fixes) et les marges sont réservées par l'en-tête et le pied d'un tableau englobant,
 * que le navigateur répète lui aussi sur chaque page.
 */
export default function PrintSheet({ company, settings, footer, children }: Props) {
  const s = settings ?? printSettingsOf(company)
  const style = {
    '--doc-accent': s.accent,
    '--sheet-top': `${s.top}mm`,
    '--sheet-bottom': `${s.bottom}mm`,
    '--sheet-side': `${s.side}mm`,
  } as CSSProperties

  return (
    <div className={`doc-sheet doc-sheet-${s.mode}`} style={style}>
      {/* Page imprimée bord à bord : les marges sont gérées par la feuille */}
      <style>{'@page { size: A4; margin: 0; }'}</style>
      {s.mode === 'background' && s.backgroundImg && <img className="sheet-bg" src={s.backgroundImg} alt="" />}
      {s.mode === 'images' && s.headerImg && <img className="sheet-header" src={s.headerImg} alt="" />}
      {s.mode === 'images' && s.footerImg && <img className="sheet-footer" src={s.footerImg} alt="" />}
      {s.mode === 'preprinted' && <div className="sheet-preprinted no-print">Zone réservée au papier pré-imprimé</div>}

      <table className="sheet-frame">
        <thead>
          <tr>
            <td>
              <div className="sheet-space-top" />
            </td>
          </tr>
        </thead>
        <tfoot>
          <tr>
            <td>
              <div className="sheet-space-bottom">{footer}</div>
            </td>
          </tr>
        </tfoot>
        <tbody>
          <tr>
            <td className="sheet-body">{children}</td>
          </tr>
        </tbody>
      </table>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/PrintSheet.tsx"

cat > src/documents/ReminderPrint.tsx <<'FIN_DU_FICHIER'
import PrintSheet from './PrintSheet'
import { CompanyFooter, CompanyHeader } from './PrintParts'
import { printSettingsOf, usesGeneratedHeader } from './printSettings'
import { daysBetween, frDate, today } from './numbering'
import { computeTotals, formatMAD, round2 } from './tva'
import type { CommercialDocument, CompanyInfo, Party } from './types'

interface Props {
  company: CompanyInfo
  party: Party
  invoices: { doc: CommercialDocument; balance: number }[]
  onClose: () => void
}

/** Lettre de relance des factures échues d'un client */
export default function ReminderPrint({ company, party, invoices, onClose }: Props) {
  const now = today()
  const settings = printSettingsOf(company)
  const total = round2(invoices.reduce((s, i) => s + i.balance, 0))

  return (
    <div>
      <div className="doc-toolbar no-print">
        <button type="button" className="btn-primary" onClick={() => window.print()}>
          Imprimer / PDF
        </button>
        <button type="button" onClick={onClose}>
          Retour
        </button>
      </div>

      <div className="doc-print">
        <PrintSheet company={company} footer={settings.showLegal ? <CompanyFooter company={company} /> : null}>
        {usesGeneratedHeader(settings) && <CompanyHeader company={company} />}
        <section className="doc-box doc-party doc-reminder-party">
          <div className="doc-party-name">{party.name}</div>
          <div>{party.address}</div>
          <div>{party.city}</div>
        </section>

        <p style={{ textAlign: 'right' }}>
          {company.city ? `${company.city}, le ` : 'Le '}
          {frDate(now)}
        </p>
        <p>
          <strong>Objet : relance pour factures échues</strong>
        </p>
        <p>Madame, Monsieur,</p>
        <p>
          Sauf erreur de notre part, les factures ci-dessous restent impayées à ce jour, alors que leur échéance
          est dépassée :
        </p>

        <table className="doc-table doc-print-lines">
          <thead>
            <tr>
              <th>Facture</th>
              <th>Date</th>
              <th>Échéance</th>
              <th className="num">Retard</th>
              <th className="num">Montant TTC</th>
              <th className="num">Reste dû</th>
            </tr>
          </thead>
          <tbody>
            {invoices.map(({ doc, balance }) => (
              <tr key={doc.id}>
                <td>{doc.number}</td>
                <td>{frDate(doc.date)}</td>
                <td>{frDate(doc.dueDate)}</td>
                <td className="num">{daysBetween(doc.dueDate, now)} j</td>
                <td className="num">{formatMAD(computeTotals(doc).netToPay)}</td>
                <td className="num">{formatMAD(balance)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="doc-total-row">
              <td colSpan={5}>Total restant dû</td>
              <td className="num">{formatMAD(total)}</td>
            </tr>
          </tfoot>
        </table>

        <p>
          Nous vous remercions de bien vouloir procéder à leur règlement dans les meilleurs délais
          {company.rib ? `, de préférence par virement sur notre compte ${company.bank} (RIB ${company.rib})` : ''}. Si
          votre paiement a été effectué entre-temps, merci de ne pas tenir compte de ce courrier.
        </p>
        <p>Veuillez agréer, Madame, Monsieur, nos salutations distinguées.</p>
        <p style={{ marginTop: 48 }}>
          <strong>{company.name}</strong>
          <br />
          Service comptabilité
        </p>

        </PrintSheet>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/ReminderPrint.tsx"

cat > src/documents/SchedulePage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import { downloadCsv } from './csv'
import { balanceOf, isActive } from './ledger'
import { addDays, daysBetween, frDate, today } from './numbering'
import { formatMAD, round2 } from './tva'
import type { CommercialDocument, DocKind } from './types'
import './documents.css'

interface Props {
  documents: CommercialDocument[]
  cash: number
  onCashChange: (cash: number) => void
  onNavigate: (kind: DocKind, openId?: string) => void
}

interface Entry {
  doc: CommercialDocument
  amount: number // + encaissement, − décaissement
  due: string
  late: number // jours de retard (0 si non échu)
}

const BUCKETS = [
  { key: 'late', label: 'Échu' },
  { key: 'w1', label: '7 prochains jours' },
  { key: 'd30', label: '8 à 30 jours' },
  { key: 'd60', label: '31 à 60 jours' },
  { key: 'd90', label: '61 à 90 jours' },
  { key: 'later', label: 'Au-delà de 90 jours' },
] as const

type BucketKey = (typeof BUCKETS)[number]['key']

function bucketOf(due: string, now: string): BucketKey {
  if (due < now) return 'late'
  const d = daysBetween(now, due)
  if (d <= 7) return 'w1'
  if (d <= 30) return 'd30'
  if (d <= 60) return 'd60'
  if (d <= 90) return 'd90'
  return 'later'
}

const AGES = [
  { label: 'Non échu', test: (late: number) => late === 0 },
  { label: '1 à 30 j', test: (late: number) => late > 0 && late <= 30 },
  { label: '31 à 60 j', test: (late: number) => late > 30 && late <= 60 },
  { label: '61 à 90 j', test: (late: number) => late > 60 && late <= 90 },
  { label: '+ 90 j', test: (late: number) => late > 90 },
]

/** Échéancier clients / fournisseurs, trésorerie prévisionnelle et balance âgée */
export default function SchedulePage({ documents, cash, onCashChange, onNavigate }: Props) {
  const now = today()
  const [cashText, setCashText] = useState(String(cash))
  const [side, setSide] = useState<'all' | 'in' | 'out'>('all')
  const canWrite = useAccess().level('finance') === 'write'

  const entries = useMemo<Entry[]>(() => {
    const list: Entry[] = []
    for (const d of documents) {
      if ((d.kind !== 'invoice' && d.kind !== 'bill') || !isActive(d)) continue
      const balance = balanceOf(d, documents)
      if (balance <= 0.01) continue
      const due = d.dueDate || addDays(d.date, 60)
      list.push({ doc: d, amount: d.kind === 'invoice' ? balance : -balance, due, late: due < now ? daysBetween(due, now) : 0 })
    }
    return list.sort((a, b) => a.due.localeCompare(b.due))
  }, [documents, now])

  // Trésorerie prévisionnelle : solde cumulé tranche par tranche
  const forecast = useMemo(() => {
    const rows: { key: BucketKey; label: string; inflow: number; outflow: number; balance: number }[] = []
    for (const b of BUCKETS) {
      const items = entries.filter((e) => bucketOf(e.due, now) === b.key)
      const inflow = round2(items.filter((e) => e.amount > 0).reduce((s, e) => s + e.amount, 0))
      const outflow = round2(items.filter((e) => e.amount < 0).reduce((s, e) => s - e.amount, 0))
      const previous = rows.length ? rows[rows.length - 1].balance : cash
      rows.push({ key: b.key, label: b.label, inflow, outflow, balance: round2(previous + inflow - outflow) })
    }
    return rows
  }, [entries, cash, now])

  // Balance âgée des clients
  const aged = useMemo(() => {
    const byClient = new Map<string, number[]>()
    for (const e of entries) {
      if (e.amount <= 0) continue
      const row = byClient.get(e.doc.party.name) ?? AGES.map(() => 0)
      row[AGES.findIndex((a) => a.test(e.late))] += e.amount
      byClient.set(e.doc.party.name, row)
    }
    return [...byClient.entries()]
      .map(([name, cols]) => ({ name, cols: cols.map(round2), total: round2(cols.reduce((s, v) => s + v, 0)) }))
      .sort((a, b) => b.total - a.total)
  }, [entries])

  const toCollect = round2(entries.filter((e) => e.amount > 0).reduce((s, e) => s + e.amount, 0))
  const toPay = round2(entries.filter((e) => e.amount < 0).reduce((s, e) => s - e.amount, 0))
  const shown = entries.filter((e) => side === 'all' || (side === 'in' ? e.amount > 0 : e.amount < 0))

  function saveCash(text: string) {
    setCashText(text)
    const n = Number(text.replace(/\s/g, '').replace(',', '.'))
    if (Number.isFinite(n)) onCashChange(n)
  }

  function exportCsv() {
    downloadCsv(`echeancier-${now}.csv`, [
      ['Échéance', 'Sens', 'Pièce', 'Tiers', 'Montant', 'Retard (jours)'],
      ...entries.map((e) => [e.due, e.amount > 0 ? 'Encaissement' : 'Décaissement', e.doc.number, e.doc.party.name, Math.abs(e.amount), String(e.late)]),
    ])
  }

  return (
    <div>
      <div className="doc-stats">
        <div>
          <span>Trésorerie disponible</span>
          <input className="num doc-cash-input" readOnly={!canWrite} value={cashText} onChange={(e) => saveCash(e.target.value)} aria-label="Trésorerie disponible" />
        </div>
        <div>
          <span>À encaisser (clients)</span>
          <strong>{formatMAD(toCollect)}</strong>
        </div>
        <div>
          <span>À payer (fournisseurs)</span>
          <strong>{formatMAD(toPay)}</strong>
        </div>
        <div className={cash + toCollect - toPay < 0 ? 'doc-stat-danger' : undefined}>
          <span>Solde prévisionnel</span>
          <strong>{formatMAD(round2(cash + toCollect - toPay))}</strong>
        </div>
      </div>

      <div className="doc-panel">
        <div className="doc-panel-title">Trésorerie prévisionnelle</div>
        <table className="doc-table">
          <thead>
            <tr>
              <th>Période</th>
              <th className="num">Encaissements</th>
              <th className="num">Décaissements</th>
              <th className="num">Solde cumulé</th>
            </tr>
          </thead>
          <tbody>
            {forecast.map((f) => (
              <tr key={f.key} className={f.balance < 0 ? 'doc-row-danger' : undefined}>
                <td>{f.label}</td>
                <td className="num">{f.inflow ? formatMAD(f.inflow) : ''}</td>
                <td className="num">{f.outflow ? formatMAD(f.outflow) : ''}</td>
                <td className="num">
                  <strong>{formatMAD(f.balance)}</strong>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="doc-count">
          Les montants échus sont supposés réglés immédiatement ; la trésorerie de départ se saisit en haut à gauche.
        </p>
      </div>

      {aged.length > 0 && (
        <div className="doc-panel">
          <div className="doc-panel-title">Balance âgée des clients</div>
          <table className="doc-table">
            <thead>
              <tr>
                <th>Client</th>
                {AGES.map((a) => (
                  <th key={a.label} className="num">
                    {a.label}
                  </th>
                ))}
                <th className="num">Total dû</th>
              </tr>
            </thead>
            <tbody>
              {aged.map((r) => (
                <tr key={r.name} className={r.cols[4] > 0 ? 'doc-row-danger' : r.cols.slice(1).some((v) => v > 0) ? 'doc-row-late' : undefined}>
                  <td>{r.name}</td>
                  {r.cols.map((v, i) => (
                    <td key={i} className="num">
                      {v ? formatMAD(v) : ''}
                    </td>
                  ))}
                  <td className="num">
                    <strong>{formatMAD(r.total)}</strong>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="doc-toolbar">
        <select value={side} onChange={(e) => setSide(e.target.value as 'all' | 'in' | 'out')}>
          <option value="all">Encaissements et décaissements</option>
          <option value="in">Encaissements clients</option>
          <option value="out">Règlements fournisseurs</option>
        </select>
        <button type="button" onClick={exportCsv}>
          Exporter l'échéancier (CSV)
        </button>
        <span className="doc-count">{shown.length} échéance(s)</span>
      </div>

      {shown.length === 0 ? (
        <p className="doc-empty">Aucune échéance ouverte.</p>
      ) : (
        <div className="doc-table-wrap">
          <table className="doc-table">
            <thead>
              <tr>
                <th>Échéance</th>
                <th>Sens</th>
                <th>Pièce</th>
                <th>Tiers</th>
                <th className="num">Montant</th>
                <th className="num">Retard</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {shown.map((e) => (
                <tr key={e.doc.id} className={e.late ? 'doc-row-late' : undefined}>
                  <td>{frDate(e.due)}</td>
                  <td>
                    <span className={`doc-badge ${e.amount > 0 ? 'doc-exp-ok' : 'doc-badge-validated'}`}>
                      {e.amount > 0 ? 'Encaissement' : 'Décaissement'}
                    </span>
                  </td>
                  <td>{e.doc.number}</td>
                  <td>{e.doc.party.name}</td>
                  <td className="num">{formatMAD(Math.abs(e.amount))}</td>
                  <td className="num">{e.late ? `${e.late} j` : ''}</td>
                  <td>
                    <button type="button" onClick={() => onNavigate(e.doc.kind, e.doc.id)}>
                      Ouvrir
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/SchedulePage.tsx"

cat > src/documents/StatsPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { isActive, sign } from './ledger'
import { today } from './numbering'
import { computeTotals, formatMAD, lineHT, round2 } from './tva'
import type { CommercialDocument } from './types'
import './documents.css'

interface Props {
  documents: CommercialDocument[]
  products: Product[]
}

const MONTHS = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.']
const MONTHS_LONG = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre']

const pct = (v: number) => `${v.toLocaleString('fr-FR', { maximumFractionDigits: 1 })} %`

/** Valeurs d'axe arrondies et compactes : 0 / 10 k / 20 k… */
function niceTicks(max: number): number[] {
  if (max <= 0) return [0]
  const rough = max / 4
  const pow = 10 ** Math.floor(Math.log10(rough))
  const step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= rough) ?? rough
  const ticks: number[] = []
  for (let v = 0; v <= max + step * 0.001; v += step) ticks.push(v)
  if (ticks[ticks.length - 1] < max) ticks.push(ticks[ticks.length - 1] + step)
  return ticks
}

const compact = (v: number) =>
  v >= 1e6 ? `${(v / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} M` : v >= 1000 ? `${(v / 1000).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} k` : String(v)

interface MonthPoint {
  month: number
  ht: number
  count: number
}

/** Histogramme du CA HT mensuel : une seule série, survol et focus clavier sur chaque colonne */
function MonthlyChart({ data }: { data: MonthPoint[] }) {
  const [hover, setHover] = useState<number | null>(null)
  const W = 760
  const H = 260
  const pad = { top: 22, right: 12, bottom: 28, left: 52 }
  const innerW = W - pad.left - pad.right
  const innerH = H - pad.top - pad.bottom
  const max = Math.max(...data.map((d) => d.ht), 0)
  const ticks = niceTicks(max)
  const top = ticks[ticks.length - 1] || 1
  const band = innerW / data.length
  // Le SVG s'agrandit avec la page : 16 unités ≈ 24 px sur un écran large
  const barW = Math.min(16, band * 0.5)
  const y = (v: number) => pad.top + innerH - (Math.max(v, 0) / top) * innerH
  const best = data.reduce((m, d, i) => (d.ht > data[m].ht ? i : m), 0)

  return (
    <div className="stats-chart">
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Chiffre d'affaires HT par mois">
        {ticks.map((t) => (
          <g key={t}>
            <line x1={pad.left} x2={W - pad.right} y1={y(t)} y2={y(t)} className="stats-grid" />
            <text x={pad.left - 8} y={y(t)} className="stats-tick" textAnchor="end" dominantBaseline="middle">
              {compact(t)}
            </text>
          </g>
        ))}
        {data.map((d, i) => {
          const cx = pad.left + band * i + band / 2
          const h = Math.max(pad.top + innerH - y(d.ht), 0)
          const r = Math.min(4, h)
          const x0 = cx - barW / 2
          const yTop = pad.top + innerH - h
          // Bout arrondi de 4 px côté valeur, angle droit sur la ligne de base
          const path = h
            ? `M${x0},${pad.top + innerH} V${yTop + r} Q${x0},${yTop} ${x0 + r},${yTop} H${x0 + barW - r} Q${x0 + barW},${yTop} ${x0 + barW},${yTop + r} V${pad.top + innerH} Z`
            : ''
          return (
            <g
              key={d.month}
              tabIndex={0}
              className={`stats-bar ${hover === i ? 'stats-bar-active' : ''}`}
              onPointerEnter={() => setHover(i)}
              onPointerLeave={() => setHover(null)}
              onFocus={() => setHover(i)}
              onBlur={() => setHover(null)}
            >
              {/* Zone de survol plus large que la colonne */}
              <rect x={pad.left + band * i} y={pad.top} width={band} height={innerH} fill="transparent" />
              {path && <path d={path} className="stats-bar-fill" />}
              {i === best && d.ht > 0 && (
                <text x={cx} y={yTop - 6} textAnchor="middle" className="stats-label">
                  {compact(round2(d.ht))}
                </text>
              )}
              <text x={cx} y={H - 8} textAnchor="middle" className="stats-tick">
                {MONTHS[d.month]}
              </text>
            </g>
          )
        })}
        <line x1={pad.left} x2={W - pad.right} y1={pad.top + innerH} y2={pad.top + innerH} className="stats-axis" />
      </svg>
      {hover !== null && (
        <div className="stats-tooltip" style={{ left: `${((pad.left + band * hover + band / 2) / W) * 100}%` }}>
          <strong>{formatMAD(round2(data[hover].ht))}</strong>
          <span>
            {MONTHS_LONG[data[hover].month]} · {data[hover].count} facture(s)
          </span>
        </div>
      )}
    </div>
  )
}

/** Statistiques de ventes : CA mensuel, marge, meilleurs clients et articles */
export default function StatsPage({ documents, products }: Props) {
  const years = useMemo(() => {
    const set = new Set<number>([new Date().getFullYear()])
    for (const d of documents) if (d.kind === 'invoice') set.add(Number(d.date.slice(0, 4)))
    return [...set].sort((a, b) => b - a)
  }, [documents])
  const [year, setYear] = useState(years[0])
  const [showTable, setShowTable] = useState(false)
  const showCosts = useAccess().can('costs')

  const stats = useMemo(() => {
    const cost = new Map(products.map((p) => [p.id, p.unitCost]))
    const months: MonthPoint[] = MONTHS.map((_, month) => ({ month, ht: 0, count: 0 }))
    const clients = new Map<string, { ht: number; count: number }>()
    const items = new Map<string, { name: string; qty: number; ht: number; cost: number; costKnown: boolean }>()
    const coverage = new Map<string, number>()
    let ht = 0
    let margin = 0
    let count = 0
    let previous = 0
    const thisYear = String(year)
    const lastYear = String(year - 1)
    const sameDay = today().slice(4)

    for (const d of documents) {
      if ((d.kind !== 'invoice' && d.kind !== 'credit') || !isActive(d)) continue
      const k = sign(d)
      const t = computeTotals(d)
      // Même période de l'année précédente, pour la comparaison
      if (d.date.startsWith(lastYear) && d.date.slice(4) <= sameDay) previous += k * t.totalHT
      if (!d.date.startsWith(thisYear)) continue

      const m = months[Number(d.date.slice(5, 7)) - 1]
      m.ht += k * t.totalHT
      ht += k * t.totalHT
      if (d.kind === 'invoice') {
        m.count++
        count++
      }
      const c = clients.get(d.party.name) ?? { ht: 0, count: 0 }
      c.ht += k * t.totalHT
      if (d.kind === 'invoice') c.count++
      clients.set(d.party.name, c)
      const cov = d.intervention?.coverage || 'Non renseigné'
      coverage.set(cov, (coverage.get(cov) ?? 0) + k * t.totalHT)

      for (const l of d.lines) {
        const lht = k * lineHT(l)
        const unit = l.productId ? cost.get(l.productId) : undefined
        const lcost = unit === undefined ? 0 : k * unit * l.quantity
        margin += lht - lcost
        const key = l.productId ?? `libre:${l.description}`
        const it = items.get(key) ?? { name: l.description, qty: 0, ht: 0, cost: 0, costKnown: unit !== undefined }
        it.qty += k * l.quantity
        it.ht += lht
        it.cost += lcost
        items.set(key, it)
      }
    }

    const topClients = [...clients.entries()].map(([name, v]) => ({ name, ...v })).sort((a, b) => b.ht - a.ht).slice(0, 10)
    const topItems = [...items.values()].sort((a, b) => b.ht - a.ht).slice(0, 10)
    const coverageRows = [...coverage.entries()].sort((a, b) => b[1] - a[1])
    return { months, ht, margin, count, previous, topClients, topItems, coverageRows }
  }, [documents, products, year])

  const rate = stats.ht ? (stats.margin / stats.ht) * 100 : 0
  const growth = stats.previous ? ((stats.ht - stats.previous) / Math.abs(stats.previous)) * 100 : null
  const maxClient = Math.max(...stats.topClients.map((c) => c.ht), 1)

  return (
    <div>
      <div className="doc-toolbar">
        <label>
          Exercice{' '}
          <select value={year} onChange={(e) => setYear(Number(e.target.value))}>
            {years.map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </select>
        </label>
        <span className="doc-count">Factures validées, avoirs déduits. Marge = prix de vente HT − coût d'achat des articles.</span>
      </div>

      <div className="doc-stats">
        <div>
          <span>Chiffre d'affaires HT</span>
          <strong>{formatMAD(round2(stats.ht))}</strong>
          {growth !== null && year === years[0] && (
            <small className={growth >= 0 ? 'doc-credit' : 'doc-error'}>
              {growth >= 0 ? '+' : ''}
              {pct(growth)} vs même période {year - 1}
            </small>
          )}
        </div>
        {showCosts && (
          <div>
            <span>Marge brute</span>
            <strong>{formatMAD(round2(stats.margin))}</strong>
          </div>
        )}
        {showCosts && (
          <div>
            <span>Taux de marge</span>
            <strong>{pct(rate)}</strong>
          </div>
        )}
        <div>
          <span>Factures · panier moyen HT</span>
          <strong>
            {stats.count} · {formatMAD(stats.count ? round2(stats.ht / stats.count) : 0)}
          </strong>
        </div>
      </div>

      <div className="doc-panel">
        <div className="doc-panel-title stats-title">
          Chiffre d'affaires HT par mois — {year}
          <button type="button" onClick={() => setShowTable(!showTable)}>
            {showTable ? 'Voir le graphique' : 'Voir le tableau'}
          </button>
        </div>
        {showTable ? (
          <table className="doc-table">
            <thead>
              <tr>
                <th>Mois</th>
                <th className="num">Factures</th>
                <th className="num">CA HT</th>
              </tr>
            </thead>
            <tbody>
              {stats.months.map((m) => (
                <tr key={m.month}>
                  <td>{MONTHS_LONG[m.month]}</td>
                  <td className="num">{m.count}</td>
                  <td className="num">{formatMAD(round2(m.ht))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <MonthlyChart data={stats.months} />
        )}
      </div>

      <div className="stats-columns">
        <div className="doc-panel">
          <div className="doc-panel-title">Meilleurs clients</div>
          <table className="doc-table">
            <thead>
              <tr>
                <th>Client</th>
                <th className="num">Factures</th>
                <th className="num">CA HT</th>
                <th className="num">Part</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {stats.topClients.map((c) => (
                <tr key={c.name}>
                  <td>{c.name}</td>
                  <td className="num">{c.count}</td>
                  <td className="num">{formatMAD(round2(c.ht))}</td>
                  <td className="num">{stats.ht ? pct((c.ht / stats.ht) * 100) : ''}</td>
                  <td className="stats-bar-cell">
                    <div className="stats-inline-bar" style={{ width: `${Math.max((c.ht / maxClient) * 100, 0)}%` }} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="doc-panel">
          <div className="doc-panel-title">CA par prise en charge</div>
          <table className="doc-table">
            <thead>
              <tr>
                <th>Prise en charge</th>
                <th className="num">CA HT</th>
                <th className="num">Part</th>
              </tr>
            </thead>
            <tbody>
              {stats.coverageRows.map(([cov, v]) => (
                <tr key={cov}>
                  <td>{cov}</td>
                  <td className="num">{formatMAD(round2(v))}</td>
                  <td className="num">{stats.ht ? pct((v / stats.ht) * 100) : ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="doc-panel">
        <div className="doc-panel-title">Articles les plus vendus</div>
        <table className="doc-table">
          <thead>
            <tr>
              <th>Article</th>
              <th className="num">Quantité</th>
              <th className="num">CA HT</th>
              {showCosts && <th className="num">Marge</th>}
              {showCosts && <th className="num">Taux de marge</th>}
            </tr>
          </thead>
          <tbody>
            {stats.topItems.map((it) => (
              <tr key={it.name}>
                <td>{it.name}</td>
                <td className="num">{it.qty}</td>
                <td className="num">{formatMAD(round2(it.ht))}</td>
                {showCosts && <td className="num">{it.costKnown ? formatMAD(round2(it.ht - it.cost)) : '—'}</td>}
                {showCosts && <td className="num">{it.costKnown && it.ht ? pct(((it.ht - it.cost) / it.ht) * 100) : '—'}</td>}
              </tr>
            ))}
          </tbody>
        </table>
        <p className="doc-count">« — » : ligne saisie librement, sans article du catalogue, donc sans coût d'achat connu.</p>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/StatsPage.tsx"

cat > src/documents/StockAlertsPage.tsx <<'FIN_DU_FICHIER'
import { useMemo } from 'react'
import { useAccess } from '../access/context'
import type { Product } from '../types'
import { getStockStatus } from '../utils/stock'
import { addDays, emptyLine, frDate, newId, nextNumber, today } from './numbering'
import { expiryState } from './stockMoves'
import { formatMAD, round2 } from './tva'
import { emptyParty, type CommercialDocument, type DocKind, type StockLot } from './types'
import './documents.css'

interface Props {
  products: Product[]
  lots: StockLot[]
  documents: CommercialDocument[]
  onChange: (docs: CommercialDocument[]) => void
  onNavigate: (kind: DocKind, openId?: string) => void
  onOpenStock: () => void
}

/** Quantités commandées aux fournisseurs (commandes validées pas encore réceptionnées) */
function onOrder(documents: CommercialDocument[]): Map<string, number> {
  const received = new Set(documents.filter((d) => d.kind === 'receipt' && d.status !== 'cancelled').map((d) => d.sourceId))
  const qty = new Map<string, number>()
  for (const d of documents) {
    if (d.kind !== 'purchase' || d.status !== 'validated' || received.has(d.id)) continue
    for (const l of d.lines) if (l.productId) qty.set(l.productId, (qty.get(l.productId) ?? 0) + l.quantity)
  }
  return qty
}

/** Quantité conseillée : remonter à 2 × le seuil d'alerte, déduction faite de ce qui est déjà commandé */
function suggestedQty(p: Product, ordered: number): number {
  const stock = p.stock ?? 0
  const target = Math.max((p.minStock ?? 0) * 2, 1)
  return Math.max(target - stock - ordered, 0)
}

/** Alertes de stock : ruptures, articles sous le seuil, lots périmés, et réapprovisionnement */
export default function StockAlertsPage({ products, lots, documents, onChange, onNavigate, onOpenStock }: Props) {
  const now = today()
  const access = useAccess()
  const canOrder = access.level('purchases') === 'write'
  const showCosts = access.can('costs')
  const ordered = useMemo(() => onOrder(documents), [documents])

  const alerts = useMemo(
    () =>
      products
        .map((p) => ({ product: p, status: getStockStatus(p), ordered: ordered.get(p.id) ?? 0 }))
        .filter((a) => a.status === 'out' || a.status === 'low')
        .map((a) => ({ ...a, suggested: suggestedQty(a.product, a.ordered) }))
        .sort((a, b) => (a.status === b.status ? a.product.name.localeCompare(b.product.name) : a.status === 'out' ? -1 : 1)),
    [products, ordered],
  )

  const lotAlerts = useMemo(
    () =>
      lots
        .filter((l) => l.quantity > 0)
        .map((l) => ({ lot: l, state: expiryState(l.expiry, now) }))
        .filter((x) => x.state === 'expired' || x.state === 'soon')
        .sort((a, b) => a.lot.expiry.localeCompare(b.lot.expiry)),
    [lots, now],
  )

  const unset = products.filter((p) => getStockStatus(p) === 'unset').length
  const out = alerts.filter((a) => a.status === 'out').length
  const low = alerts.length - out
  const expired = lotAlerts.filter((x) => x.state === 'expired').length

  // Réapprovisionnement regroupé par fournisseur
  const bySupplier = useMemo(() => {
    const groups = new Map<string, typeof alerts>()
    for (const a of alerts) {
      if (a.suggested <= 0) continue
      const key = a.product.supplier?.trim() || 'Fournisseur non renseigné'
      groups.set(key, [...(groups.get(key) ?? []), a])
    }
    return [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]))
  }, [alerts])

  function createPurchase(supplier: string, items: typeof alerts) {
    const id = newId()
    const known = supplier !== 'Fournisseur non renseigné'
    const order: CommercialDocument = {
      id,
      kind: 'purchase',
      number: nextNumber('purchase', documents, now),
      date: now,
      dueDate: addDays(now, 60),
      party: { ...emptyParty(), name: known ? supplier : '' },
      lines: items.map((a) => ({
        ...emptyLine(),
        productId: a.product.id,
        description: a.product.name,
        quantity: a.suggested,
        unitPriceHT: a.product.unitCost,
      })),
      status: 'draft',
      paymentMethod: 'virement',
      notes: 'Réapprovisionnement (alertes de stock)',
    }
    onChange([...documents, order])
    access.log('Commande de réapprovisionnement', `${order.number} · ${supplier}`)
    onNavigate('purchase', id)
  }

  const name = (id: string) => products.find((p) => p.id === id)?.name ?? '(article supprimé)'

  return (
    <div>
      <div className="doc-stats">
        <div className={out ? 'doc-stat-danger' : undefined}>
          <span>Ruptures</span>
          <strong>{out}</strong>
        </div>
        <div className={low ? 'doc-stat-late' : undefined}>
          <span>Sous le seuil d'alerte</span>
          <strong>{low}</strong>
        </div>
        <div className={expired ? 'doc-stat-danger' : lotAlerts.length ? 'doc-stat-late' : undefined}>
          <span>Lots périmés / sous 90 jours</span>
          <strong>
            {expired} / {lotAlerts.length - expired}
          </strong>
        </div>
        <div>
          <span>Articles sans stock renseigné</span>
          <strong>{unset}</strong>
        </div>
      </div>

      {alerts.length === 0 && lotAlerts.length === 0 && (
        <p className="doc-info">Aucune alerte : tous les articles suivis sont au-dessus de leur seuil.</p>
      )}
      {unset > 0 && (
        <p className="doc-warning">
          {unset} article(s) n'ont ni stock ni seuil d'alerte : ils ne peuvent pas déclencher d'alerte.{' '}
          <button type="button" onClick={onOpenStock}>
            Renseigner le stock
          </button>
        </p>
      )}

      {alerts.length > 0 && (
        <div className="doc-panel">
          <div className="doc-panel-title">Articles à surveiller</div>
          <div className="doc-table-wrap">
            <table className="doc-table">
              <thead>
                <tr>
                  <th>État</th>
                  <th>Référence</th>
                  <th>Article</th>
                  <th>Fournisseur</th>
                  <th className="num">Stock</th>
                  <th className="num">Seuil</th>
                  <th className="num">En commande</th>
                  <th className="num">À commander</th>
                  {showCosts && <th className="num">Coût estimé HT</th>}
                </tr>
              </thead>
              <tbody>
                {alerts.map((a) => (
                  <tr key={a.product.id} className={a.status === 'out' ? 'doc-row-danger' : 'doc-row-late'}>
                    <td>
                      <span className={`doc-badge ${a.status === 'out' ? 'doc-exp-expired' : 'doc-exp-soon'}`}>
                        {a.status === 'out' ? 'Rupture' : 'Sous le seuil'}
                      </span>
                    </td>
                    <td>{a.product.reference}</td>
                    <td>{a.product.name}</td>
                    <td>{a.product.supplier}</td>
                    <td className="num">{a.product.stock ?? 0}</td>
                    <td className="num">{a.product.minStock ?? 0}</td>
                    <td className="num">{a.ordered || ''}</td>
                    <td className="num">
                      <strong>{a.suggested || '—'}</strong>
                    </td>
                    {showCosts && <td className="num">{a.suggested ? formatMAD(round2(a.suggested * a.product.unitCost)) : ''}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="doc-count">
            Quantité conseillée : de quoi remonter à deux fois le seuil d'alerte, moins ce qui est déjà commandé.
          </p>
        </div>
      )}

      {bySupplier.length > 0 && (
        <div className="doc-panel">
          <div className="doc-panel-title">Réapprovisionnement par fournisseur</div>
          <table className="doc-table">
            <thead>
              <tr>
                <th>Fournisseur</th>
                <th>Articles</th>
                {showCosts && <th className="num">Montant estimé HT</th>}
                <th />
              </tr>
            </thead>
            <tbody>
              {bySupplier.map(([supplier, items]) => (
                <tr key={supplier}>
                  <td>{supplier}</td>
                  <td>{items.map((a) => `${a.suggested} × ${a.product.name}`).join(', ')}</td>
                  {showCosts && (
                    <td className="num">
                      {formatMAD(round2(items.reduce((s, a) => s + a.suggested * a.product.unitCost, 0)))}
                    </td>
                  )}
                  <td>
                    {canOrder && (
                      <button type="button" className="btn-primary" onClick={() => createPurchase(supplier, items)}>
                        Créer la commande fournisseur
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {lotAlerts.length > 0 && (
        <div className="doc-panel">
          <div className="doc-panel-title">Péremptions</div>
          <table className="doc-table">
            <thead>
              <tr>
                <th>État</th>
                <th>Article</th>
                <th>Lot</th>
                <th>N° série</th>
                <th>Péremption</th>
                <th className="num">Quantité</th>
              </tr>
            </thead>
            <tbody>
              {lotAlerts.map(({ lot, state }) => (
                <tr key={lot.id} className={state === 'expired' ? 'doc-row-danger' : 'doc-row-late'}>
                  <td>
                    <span className={`doc-badge doc-exp-${state}`}>{state === 'expired' ? 'Périmé' : '< 90 jours'}</span>
                  </td>
                  <td>{name(lot.productId)}</td>
                  <td>{lot.lot}</td>
                  <td>{lot.serial}</td>
                  <td>{frDate(lot.expiry)}</td>
                  <td className="num">{lot.quantity}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/StockAlertsPage.tsx"

cat > src/documents/StockMovesPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import type { Product } from '../types'
import { downloadCsv } from './csv'
import { frDate } from './numbering'
import type { MovementKind, StockMovement } from './types'
import './documents.css'

interface Props {
  movements: StockMovement[]
  products: Product[]
}

const KIND_LABELS: Record<MovementKind, string> = { in: 'Entrée', out: 'Sortie', adjust: 'Inventaire' }

/** Journal des mouvements de stock : réceptions, livraisons, retours, inventaires */
export default function StockMovesPage({ movements, products }: Props) {
  const [productId, setProductId] = useState('')
  const [kind, setKind] = useState<MovementKind | ''>('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [query, setQuery] = useState('')

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return movements
      .filter((m) => !productId || m.productId === productId)
      .filter((m) => !kind || m.kind === kind)
      .filter((m) => (!from || m.date >= from) && (!to || m.date <= to))
      .filter((m) => !q || [m.productName, m.lot, m.serial, m.reference].join(' ').toLowerCase().includes(q))
      .slice()
      .reverse()
  }, [movements, productId, kind, from, to, query])

  const inQty = rows.filter((m) => m.quantity > 0).reduce((s, m) => s + m.quantity, 0)
  const outQty = rows.filter((m) => m.quantity < 0).reduce((s, m) => s - m.quantity, 0)

  function exportCsv() {
    downloadCsv('mouvements-stock.csv', [
      ['Date', 'Type', 'Article', 'Lot', 'N° série', 'Quantité', 'Stock après', 'Pièce / motif'],
      ...rows.map((m) => [m.date, KIND_LABELS[m.kind], m.productName, m.lot, m.serial, String(m.quantity), m.stockAfter === undefined ? '' : String(m.stockAfter), m.reference]),
    ])
  }

  return (
    <div>
      <div className="doc-stats">
        <div>
          <span>Mouvements affichés</span>
          <strong>{rows.length}</strong>
        </div>
        <div>
          <span>Quantités entrées</span>
          <strong>+{inQty}</strong>
        </div>
        <div>
          <span>Quantités sorties</span>
          <strong>−{outQty}</strong>
        </div>
      </div>

      <div className="doc-toolbar">
        <input className="doc-search" placeholder="Rechercher : article, lot, n° de série, pièce…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select value={productId} onChange={(e) => setProductId(e.target.value)}>
          <option value="">Tous les articles</option>
          {products.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        <select value={kind} onChange={(e) => setKind(e.target.value as MovementKind | '')}>
          <option value="">Tous les types</option>
          <option value="in">Entrées</option>
          <option value="out">Sorties</option>
          <option value="adjust">Inventaires</option>
        </select>
        <label>
          Du <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
        </label>
        <label>
          au <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
        </label>
        <button type="button" onClick={exportCsv}>
          Exporter (CSV)
        </button>
      </div>

      {rows.length === 0 ? (
        <p className="doc-empty">
          Aucun mouvement. Les réceptions, les BL, les factures sans BL, les retours de dépôt et les inventaires
          validés s'enregistrent ici automatiquement.
        </p>
      ) : (
        <div className="doc-table-wrap">
          <table className="doc-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>Article</th>
                <th>Lot / N° série</th>
                <th className="num">Quantité</th>
                <th className="num">Stock après</th>
                <th>Pièce / motif</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((m) => (
                <tr key={m.id}>
                  <td>{frDate(m.date)}</td>
                  <td>
                    <span className={`doc-badge ${m.kind === 'in' ? 'doc-exp-ok' : m.kind === 'out' ? 'doc-badge-validated' : 'doc-badge-depot'}`}>
                      {KIND_LABELS[m.kind]}
                    </span>
                  </td>
                  <td>{m.productName}</td>
                  <td>{[m.lot, m.serial].filter(Boolean).join(' / ')}</td>
                  <td className={`num ${m.quantity > 0 ? 'doc-credit' : ''}`}>
                    <strong>{m.quantity > 0 ? `+${m.quantity}` : m.quantity}</strong>
                  </td>
                  <td className="num">{m.stockAfter ?? ''}</td>
                  <td>{m.reference}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/StockMovesPage.tsx"

cat > src/documents/VatPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { downloadCsv } from './csv'
import { isActive, paymentsOf } from './ledger'
import { computeTotals, formatMAD, round2 } from './tva'
import type { CommercialDocument, TvaRate } from './types'
import './documents.css'

interface Props {
  documents: CommercialDocument[]
}

/** Encaissements : régime de droit commun au Maroc. Débits : sur option, TVA due dès la facturation. */
type Regime = 'encaissement' | 'debit'
type Periodicity = 'month' | 'quarter'

const RATES: TvaRate[] = [20, 14, 10, 7]
const MONTHS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre']

interface PeriodRow {
  label: string
  ht: number
  collected: Record<number, number>
  totalCollected: number
  deductible: number
  purchasesHT: number
}

/**
 * Montants imputés à une date : au régime des encaissements, chaque règlement porte sa part
 * de HT et de TVA (prorata du montant réglé) ; au régime des débits, toute la pièce à sa date.
 */
function* imputations(d: CommercialDocument, useDocDate: boolean) {
  const t = computeTotals(d)
  if (useDocDate) {
    yield { date: d.date, ratio: 1, t }
    return
  }
  for (const p of paymentsOf(d)) yield { date: p.date, ratio: t.netToPay ? p.amount / t.netToPay : 0, t }
}

/** Tableau de préparation de la déclaration de TVA : collectée − déductible = TVA due */
export default function VatPage({ documents }: Props) {
  const years = useMemo(() => {
    const set = new Set<number>([new Date().getFullYear()])
    for (const d of documents) set.add(Number(d.date.slice(0, 4)))
    return [...set].sort((a, b) => b - a)
  }, [documents])

  const [year, setYear] = useState(years[0])
  const [regime, setRegime] = useState<Regime>('encaissement')
  const [periodicity, setPeriodicity] = useState<Periodicity>('month')

  const rows = useMemo(() => {
    const count = periodicity === 'month' ? 12 : 4
    const result: PeriodRow[] = Array.from({ length: count }, (_, i) => ({
      label: periodicity === 'month' ? MONTHS[i] : `T${i + 1} (${MONTHS[i * 3]} – ${MONTHS[i * 3 + 2]})`,
      ht: 0,
      collected: {},
      totalCollected: 0,
      deductible: 0,
      purchasesHT: 0,
    }))
    const rowOf = (date: string) => {
      if (Number(date.slice(0, 4)) !== year) return undefined
      const month = Number(date.slice(5, 7)) - 1
      return result[periodicity === 'month' ? month : Math.floor(month / 3)]
    }

    for (const d of documents) {
      if (!isActive(d)) continue
      if (d.kind === 'invoice' || d.kind === 'credit') {
        // Débits : les avoirs viennent en déduction à leur date. Encaissements : un avoir réduit
        // simplement ce qui reste à encaisser (seul un remboursement, saisi comme règlement, compte).
        const k = d.kind === 'credit' ? -1 : 1
        for (const { date, ratio, t } of imputations(d, regime === 'debit')) {
          const row = rowOf(date)
          if (!row) continue
          row.ht += k * t.totalHT * ratio
          for (const r of t.byRate) {
            row.collected[r.rate] = (row.collected[r.rate] ?? 0) + k * r.tva * ratio
            row.totalCollected += k * r.tva * ratio
          }
        }
      }
      if (d.kind === 'bill') {
        // TVA sur achats : déductible au paiement de la facture fournisseur
        for (const { date, ratio, t } of imputations(d, false)) {
          const row = rowOf(date)
          if (!row) continue
          row.purchasesHT += t.totalHT * ratio
          row.deductible += t.totalTVA * ratio
        }
      }
    }
    return result
  }, [documents, year, regime, periodicity])

  const sum = (f: (r: PeriodRow) => number) => round2(rows.reduce((s, r) => s + f(r), 0))
  const totalCollected = sum((r) => r.totalCollected)
  const totalDeductible = sum((r) => r.deductible)

  function exportCsv() {
    const header = ['Période', 'CA HT', ...RATES.map((r) => `TVA ${r} %`), 'TVA collectée', 'Achats HT', 'TVA déductible', 'TVA due']
    const body = rows.map((r) => [
      r.label,
      round2(r.ht),
      ...RATES.map((x) => round2(r.collected[x] ?? 0)),
      round2(r.totalCollected),
      round2(r.purchasesHT),
      round2(r.deductible),
      round2(r.totalCollected - r.deductible),
    ])
    downloadCsv(`declaration-tva-${year}-${regime}.csv`, [header, ...body])
  }

  return (
    <div>
      <div className="doc-toolbar">
        <label>
          Exercice{' '}
          <select value={year} onChange={(e) => setYear(Number(e.target.value))}>
            {years.map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </select>
        </label>
        <label>
          Régime{' '}
          <select value={regime} onChange={(e) => setRegime(e.target.value as Regime)}>
            <option value="encaissement">Encaissements (date de paiement)</option>
            <option value="debit">Débits (date de facture)</option>
          </select>
        </label>
        <label>
          Déclaration{' '}
          <select value={periodicity} onChange={(e) => setPeriodicity(e.target.value as Periodicity)}>
            <option value="month">Mensuelle</option>
            <option value="quarter">Trimestrielle</option>
          </select>
        </label>
        <button type="button" onClick={exportCsv}>
          Exporter (CSV)
        </button>
      </div>

      <div className="doc-stats">
        <div>
          <span>CA HT {year}</span>
          <strong>{formatMAD(sum((r) => r.ht))}</strong>
        </div>
        <div>
          <span>TVA collectée</span>
          <strong>{formatMAD(totalCollected)}</strong>
        </div>
        <div>
          <span>TVA déductible</span>
          <strong>{formatMAD(totalDeductible)}</strong>
        </div>
        <div className={totalCollected - totalDeductible < 0 ? undefined : 'doc-stat-late'}>
          <span>{totalCollected - totalDeductible < 0 ? 'Crédit de TVA' : 'TVA due'}</span>
          <strong>{formatMAD(Math.abs(round2(totalCollected - totalDeductible)))}</strong>
        </div>
      </div>

      <div className="doc-table-wrap">
        <table className="doc-table">
          <thead>
            <tr>
              <th>Période</th>
              <th className="num">CA HT</th>
              {RATES.map((r) => (
                <th key={r} className="num">
                  TVA {r} %
                </th>
              ))}
              <th className="num">Collectée</th>
              <th className="num">Achats HT</th>
              <th className="num">Déductible</th>
              <th className="num">TVA due</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const due = round2(r.totalCollected - r.deductible)
              return (
                <tr key={r.label}>
                  <td>{r.label}</td>
                  <td className="num">{formatMAD(round2(r.ht))}</td>
                  {RATES.map((x) => (
                    <td key={x} className="num">
                      {formatMAD(round2(r.collected[x] ?? 0))}
                    </td>
                  ))}
                  <td className="num">{formatMAD(round2(r.totalCollected))}</td>
                  <td className="num">{formatMAD(round2(r.purchasesHT))}</td>
                  <td className="num">{formatMAD(round2(r.deductible))}</td>
                  <td className={`num ${due < 0 ? 'doc-credit' : ''}`}>
                    <strong>{formatMAD(due)}</strong>
                  </td>
                </tr>
              )
            })}
          </tbody>
          <tfoot>
            <tr className="doc-total-row">
              <td>Total</td>
              <td className="num">{formatMAD(sum((r) => r.ht))}</td>
              {RATES.map((x) => (
                <td key={x} className="num">
                  {formatMAD(sum((r) => r.collected[x] ?? 0))}
                </td>
              ))}
              <td className="num">{formatMAD(totalCollected)}</td>
              <td className="num">{formatMAD(sum((r) => r.purchasesHT))}</td>
              <td className="num">{formatMAD(totalDeductible)}</td>
              <td className="num">{formatMAD(round2(totalCollected - totalDeductible))}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      <p className="doc-info">
        {regime === 'encaissement'
          ? 'Régime des encaissements : la TVA est comptée à chaque règlement reçu, au prorata du montant payé.'
          : 'Régime des débits : la TVA est comptée à la date de chaque facture validée, payée ou non.'}{' '}
        {regime === 'debit' && 'Les avoirs viennent en déduction à leur date. '}La TVA déductible provient des factures fournisseurs, au fur et
        à mesure de leur paiement. Ce tableau prépare votre déclaration : faites-la valider par votre comptable.
      </p>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/VatPage.tsx"

cat > src/documents/csv.ts <<'FIN_DU_FICHIER'
import { balanceOf, paidAmount, sign } from './ledger'
import { computeTotals, round2 } from './tva'
import { DOC_LABELS, PAYMENT_LABELS, STATUS_LABELS, type CommercialDocument } from './types'

type Cell = string | number

/** CSV au format Excel français : séparateur « ; », virgule décimale, BOM UTF-8 pour les accents */
export function toCsv(rows: Cell[][]): string {
  const cell = (v: Cell) => {
    const s = typeof v === 'number' ? v.toFixed(2).replace('.', ',') : v
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  return '﻿' + rows.map((r) => r.map(cell).join(';')).join('\r\n')
}

export function downloadFile(filename: string, content: string, type: string) {
  const url = URL.createObjectURL(new Blob([content], { type }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export function downloadCsv(filename: string, rows: Cell[][]) {
  downloadFile(filename, toCsv(rows), 'text/csv;charset=utf-8')
}

/**
 * Journal pour le comptable : une ligne par pièce, TVA ventilée par taux.
 * Les avoirs sont en négatif.
 */
export function journal(docs: CommercialDocument[], all: CommercialDocument[]): Cell[][] {
  const rates = [20, 14, 10, 7, 0] as const
  const header: Cell[] = ['Type', 'N°', 'Réf. fournisseur', 'Date', 'Tiers', 'ICE', 'Total HT']
  for (const r of rates) header.push(`Base ${r} %`, `TVA ${r} %`)
  header.push('Total TVA', 'Total TTC', 'Droit de timbre', 'Net', 'Réglé', 'Reste dû', 'Paiement', 'Statut', 'Pièce d\'origine')

  const rows: Cell[][] = [header]
  for (const d of docs) {
    const t = computeTotals(d)
    const k = sign(d)
    const row: Cell[] = [DOC_LABELS[d.kind].title, d.number, d.supplierRef ?? '', d.date, d.party.name, d.party.ice, k * t.totalHT]
    for (const r of rates) {
      const b = t.byRate.find((x) => x.rate === r)
      row.push(k * (b?.base ?? 0), k * (b?.tva ?? 0))
    }
    row.push(
      k * t.totalTVA,
      k * t.totalTTC,
      k * t.stampDuty,
      k * t.netToPay,
      paidAmount(d),
      d.kind === 'credit' ? 0 : round2(balanceOf(d, all)),
      PAYMENT_LABELS[d.paymentMethod],
      STATUS_LABELS[d.status],
      d.sourceNumber ?? '',
    )
    rows.push(row)
  }
  return rows
}
FIN_DU_FICHIER
echo "OK src/documents/csv.ts"

cat > src/documents/documents.css <<'FIN_DU_FICHIER'
/* Gestion commerciale : style « progiciel » (bandeaux, grilles denses, barres d'outils) */
:root {
  --pp-blue: #1f4e79;
  --pp-blue-2: #2b6cb0;
  --pp-bg: #e8ecf1;
  --pp-panel: #ffffff;
  --pp-border: #c3ccd7;
  --pp-border-soft: #e1e6ec;
  --pp-head-1: #f6f8fa;
  --pp-head-2: #e2e8ef;
  --pp-zebra: #f6f8fb;
  --pp-hover: #e6f0fa;
  --pp-select: #cfe2f7;
  --pp-text: #1e293b;
  --pp-muted: #5b6b7d;
  --pp-title: #1f3b57;
  --pp-danger: #b42318;
  --pp-warn-bg: #fff7e6;
  --pp-warn: #b45309;
  --pp-ok: #166534;
}

/* ---------- Barres d'outils et panneaux ---------- */
.doc-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  background: var(--pp-head-1);
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  padding: 6px 8px;
  margin: 0 0 10px;
}
.doc-toolbar label { font-size: 12.5px; color: var(--pp-title); }
.doc-search { flex: 1; min-width: 220px; }
.doc-count { color: var(--pp-muted); font-size: 12px; margin-left: auto; }

.doc-panel,
.doc-editor fieldset {
  background: var(--pp-panel);
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  padding: 10px 12px 12px;
  margin: 0 0 12px;
  min-width: 0;
}
.doc-panel legend,
.doc-editor fieldset legend {
  padding: 1px 8px;
  font-size: 12px;
  font-weight: 700;
  color: #fff;
  background: var(--pp-blue);
  border-radius: 2px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
}
.doc-panel-title {
  margin: -10px -12px 10px;
  padding: 7px 12px;
  background: linear-gradient(var(--pp-head-1), var(--pp-head-2));
  border-bottom: 1px solid var(--pp-border);
  font-weight: 600;
  color: var(--pp-title);
}

.doc-editor-head {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  background: linear-gradient(var(--pp-head-1), var(--pp-head-2));
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  padding: 6px 10px;
  margin-bottom: 10px;
}
.doc-editor-head h2 { margin: 0; font-size: 15px; color: var(--pp-blue); }
.doc-editor-head small { color: var(--pp-muted); font-weight: 400; }
.doc-editor-actions { display: flex; gap: 6px; align-items: center; }

.doc-panels {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: 0 12px;
}

.doc-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
  gap: 8px 10px;
  width: 100%;
}
.doc-grid label,
.doc-notes,
.doc-panel > label,
.doc-editor fieldset > label {
  display: flex;
  flex-direction: column;
  gap: 3px;
  font-size: 12px;
  color: var(--pp-muted);
}
.doc-editor fieldset > label { margin-bottom: 8px; }
.doc-check { flex-direction: row !important; align-items: center; gap: 6px !important; color: var(--pp-text) !important; }
.doc-check input { width: auto; }

/* ---------- Grilles ---------- */
.doc-table-wrap { overflow-x: auto; margin-bottom: 10px; }
.doc-table {
  width: 100%;
  border-collapse: collapse;
  background: var(--pp-panel);
  border: 1px solid var(--pp-border);
  font-size: 12.5px;
}
.doc-table th {
  background: linear-gradient(var(--pp-head-1), var(--pp-head-2));
  color: var(--pp-title);
  font-weight: 600;
  text-align: left;
  padding: 6px 8px;
  border-bottom: 1px solid #b5c1ce;
  border-right: 1px solid var(--pp-border-soft);
  white-space: nowrap;
}
.doc-table td {
  padding: 4px 8px;
  border-bottom: 1px solid var(--pp-border-soft);
  vertical-align: middle;
}
.doc-table tbody tr:nth-child(even) { background: var(--pp-zebra); }
.doc-table tbody tr:hover { background: var(--pp-hover); }
.doc-table .num, .doc-table input.num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
.doc-table tfoot td, .doc-total-row td, .doc-total-row th {
  font-weight: 700;
  background: #edf2f7;
  border-top: 1px solid #b5c1ce;
}
.doc-row-late td { background: #fff4e5 !important; }

.doc-lines input, .doc-lines select { width: 100%; min-width: 60px; box-sizing: border-box; }
.doc-lines td:nth-child(1) select { min-width: 170px; }
.doc-lines td:nth-child(2) input { min-width: 180px; }
.doc-lot-cell { min-width: 190px; }
.doc-lot-cell select { margin-bottom: 3px; }
.doc-lot-inputs { display: flex; gap: 3px; }
.doc-qty { width: 80px; }

.doc-actions { display: flex; flex-wrap: wrap; gap: 3px; }
.doc-actions button { padding: 2px 7px !important; font-size: 12px !important; }
.doc-link {
  background: none !important;
  border: 0 !important;
  padding: 0 !important;
  color: var(--pp-blue-2) !important;
  font-weight: 600;
  text-decoration: underline;
  cursor: pointer;
}

.doc-bottom {
  display: grid;
  grid-template-columns: 1fr minmax(280px, 360px);
  gap: 12px;
  align-items: start;
}
.doc-totals-box td:first-child { color: var(--pp-title); }

/* ---------- Indicateurs ---------- */
.doc-stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 10px;
  margin-bottom: 12px;
}
.doc-stats > div {
  background: var(--pp-panel);
  border: 1px solid var(--pp-border);
  border-top: 3px solid var(--pp-blue-2);
  border-radius: 3px;
  padding: 8px 12px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.doc-stats span { font-size: 11.5px; color: var(--pp-muted); text-transform: uppercase; letter-spacing: 0.3px; }
.doc-stats strong { font-size: 18px; color: var(--pp-text); font-variant-numeric: tabular-nums; }
.doc-stats .doc-stat-late { border-top-color: #d97706; background: #fffbeb; }

/* ---------- Badges et messages ---------- */
.doc-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 2px;
  font-size: 11px;
  font-weight: 600;
  background: #eef1f5;
  color: #475467;
  border: 1px solid #d0d7e0;
  margin-right: 3px;
  white-space: nowrap;
}
.doc-badge-validated { background: #e0ecfb; color: #1e40af; border-color: #b6cdf0; }
.doc-badge-paid { background: #dcfce7; color: var(--pp-ok); border-color: #a7e3bd; }
.doc-badge-cancelled { background: #fee2e2; color: #991b1b; border-color: #f5b5b5; text-decoration: line-through; }
.doc-badge-late { background: #fef3c7; color: #92400e; border-color: #f2cf7a; }
.doc-badge-depot { background: #ede9fe; color: #5b21b6; border-color: #cdbff7; }
.doc-exp-expired { background: #fee2e2; color: #991b1b; border-color: #f5b5b5; }
.doc-exp-soon { background: #fef3c7; color: #92400e; border-color: #f2cf7a; }
.doc-exp-ok { background: #dcfce7; color: var(--pp-ok); border-color: #a7e3bd; }
.doc-credit { color: var(--pp-ok); }

.doc-error { color: var(--pp-danger); font-weight: 600; }
.doc-warning, .doc-info, .doc-empty {
  border-radius: 3px;
  padding: 8px 12px;
  margin: 0 0 10px;
  font-size: 12.5px;
}
.doc-warning { background: var(--pp-warn-bg); border: 1px solid #f5c26b; color: #7c4a03; }
.doc-info { background: #eef4ff; border: 1px solid #a4bcfd; color: #1e3a8a; }
.doc-empty { background: var(--pp-panel); border: 1px dashed var(--pp-border); color: var(--pp-muted); }

.doc-logo-row { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.doc-logo { max-height: 64px; max-width: 200px; object-fit: contain; }

/* ---------- Fenêtre modale ---------- */
.doc-modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.35);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding-top: 10vh;
  z-index: 50;
}
.doc-modal {
  width: min(560px, calc(100vw - 32px));
  background: var(--pp-panel);
  border: 1px solid var(--pp-blue);
  border-radius: 3px;
  box-shadow: 0 12px 32px rgba(15, 23, 42, 0.3);
}
.doc-modal-title { background: var(--pp-blue); color: #fff; font-weight: 600; padding: 8px 12px; }
.doc-modal-body { padding: 12px; }
.doc-modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 6px;
  padding: 8px 12px;
  background: var(--pp-head-1);
  border-top: 1px solid var(--pp-border);
}

/* ---------- Pièce imprimable (feuille A4) ---------- */
.doc-print { overflow-x: auto; padding: 4px 0 16px; }

.doc-sheet {
  --doc-accent: var(--pp-blue);
  position: relative;
  width: 210mm;
  min-height: 297mm;
  margin: 0 auto;
  background: #fff;
  color: #111;
  box-shadow: 0 2px 12px rgba(15, 23, 42, 0.18);
  font-size: 12px;
  line-height: 1.45;
  overflow: hidden;
}
.sheet-bg { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: fill; z-index: 0; }
.sheet-header { position: absolute; top: 0; left: 0; width: 100%; z-index: 0; }
.sheet-footer { position: absolute; bottom: 0; left: 0; width: 100%; z-index: 0; }
.sheet-preprinted {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: var(--sheet-top);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #94a3b8;
  font-size: 11px;
  border-bottom: 1px dashed #cbd5e1;
  background: repeating-linear-gradient(45deg, #f8fafc 0 8px, #f1f5f9 8px 16px);
}
.doc-sheet .sheet-frame {
  position: relative;
  z-index: 1;
  width: 100%;
  height: 297mm;
  border-collapse: collapse;
  border: 0 !important;
  background: transparent !important;
}
.doc-sheet .sheet-frame > thead > tr > td,
.doc-sheet .sheet-frame > tfoot > tr > td,
.doc-sheet .sheet-frame > tbody > tr > td {
  padding: 0 var(--sheet-side) !important;
  border: 0 !important;
  background: transparent !important;
}
.doc-sheet .sheet-frame > tbody > tr,
.doc-sheet .sheet-frame > tbody > tr:hover { background: transparent !important; }
.doc-sheet .sheet-body { vertical-align: top; }
.sheet-space-top { height: var(--sheet-top); }
.sheet-space-bottom {
  min-height: var(--sheet-bottom);
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  padding-bottom: 6mm;
  box-sizing: border-box;
}

/* En-tête généré */
.doc-print-head {
  display: flex;
  justify-content: center;
  margin-bottom: 4mm;
  padding-bottom: 3mm;
  border-bottom: 2px solid var(--doc-accent);
}
.doc-print-company { display: flex; gap: 14px; align-items: center; text-align: left; }
.doc-company { font-size: 17px; color: var(--doc-accent); }
.doc-logo { max-height: 22mm; max-width: 60mm; object-fit: contain; }

/* Titre centré */
.doc-title-block { text-align: center; margin: 2mm 0 5mm; }
.doc-sheet .doc-title-block h2 {
  display: inline-block;
  margin: 0;
  padding: 1.5mm 10mm;
  font-size: 17px;
  letter-spacing: 2px;
  color: #fff !important;
  background: var(--doc-accent);
  border-radius: 2px;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.doc-title-number { margin-top: 1.5mm; font-size: 13px; font-weight: 600; color: var(--doc-accent); }

.doc-print-boxes { display: grid; grid-template-columns: 1fr 1fr; gap: 6mm; margin-bottom: 4mm; }
.doc-box { border: 1px solid #c9d1db; border-radius: 3px; padding: 2.5mm 3.5mm; background: rgba(255, 255, 255, 0.92); }
.doc-box > strong:first-child {
  display: block;
  font-size: 10px;
  text-transform: uppercase;
  color: var(--pp-muted);
  letter-spacing: 0.5px;
  margin-bottom: 1mm;
}
.doc-party-name { font-weight: 700; font-size: 13.5px; }
.doc-ref-table { border-collapse: collapse; width: 100%; font-size: 11.5px; }
.doc-ref-table th, .doc-ref-table td { border: 0; border-bottom: 1px dotted #d5dbe3; padding: 1mm 1.5mm; text-align: left; background: none; }
.doc-ref-table th { width: 38%; font-weight: 600; color: var(--pp-muted); }
.doc-ref-table tr:last-child th, .doc-ref-table tr:last-child td { border-bottom: 0; }
.doc-intervention { margin-bottom: 4mm; }
.doc-intervention-grid { display: flex; flex-wrap: wrap; gap: 1mm 6mm; }
.doc-reminder-party { width: 45%; margin: 0 0 6mm auto; }

/* Lignes et totaux */
.doc-sheet .doc-table { font-size: 11.5px; background: rgba(255, 255, 255, 0.92); border-color: #c9d1db; }
.doc-sheet .doc-print-lines th {
  background: var(--doc-accent) !important;
  color: #fff !important;
  border-color: var(--doc-accent) !important;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.doc-sheet .doc-table tbody tr:nth-child(even) { background: rgba(246, 248, 251, 0.9); }
.doc-sheet .doc-table tbody tr:hover { background: inherit; }
.doc-col-index { width: 6mm; text-align: center; color: var(--pp-muted); }
.doc-print-bottom { display: grid; grid-template-columns: 1fr 1fr; gap: 6mm; align-items: start; margin: 3mm 0 4mm; }
.doc-sheet .doc-grand-total td {
  font-weight: 700;
  font-size: 13px;
  color: #fff !important;
  background: var(--doc-accent) !important;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.doc-amount-words { text-align: center; margin: 3mm 0; }
.doc-terms { margin-top: 3mm; font-size: 11px; color: #374151; }
.doc-terms p { margin: 0 0 1.5mm; }
.doc-notes-print { white-space: pre-wrap; border-left: 3px solid var(--doc-accent); padding-left: 2mm; }
.doc-terms-text { font-style: italic; color: var(--pp-muted); }

.doc-signatures { display: flex; justify-content: space-between; gap: 8mm; margin-top: 6mm; page-break-inside: avoid; }
.doc-signatures div { flex: 1; height: 28mm; border: 1px solid #c9d1db; padding: 1.5mm 2mm; font-size: 10.5px; color: var(--pp-muted); background: rgba(255, 255, 255, 0.92); }

.doc-footer {
  padding-top: 2mm;
  border-top: 1px solid var(--doc-accent);
  font-size: 9.5px;
  text-align: center;
  color: #475467;
  line-height: 1.4;
}

/* ---------- Réglages de mise en page ---------- */
.doc-layout-settings { display: grid; grid-template-columns: minmax(320px, 1fr) auto; gap: 12px; align-items: start; }
.doc-mode-list { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; margin-bottom: 10px; }
.doc-mode {
  display: flex;
  gap: 8px;
  align-items: flex-start;
  padding: 6px 8px;
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  cursor: pointer;
  background: #fff;
}
.doc-mode span { display: flex; flex-direction: column; gap: 2px; }
.doc-mode small { color: var(--pp-muted); font-size: 11.5px; }
.doc-mode-active { border-color: var(--pp-blue-2); background: var(--pp-hover); }
.doc-layout-settings .doc-grid { margin-bottom: 8px; }
.doc-layout-settings input[type='color'] { width: 60px; height: 28px; padding: 0 2px; }

.doc-preview-panel { position: sticky; top: 8px; }
/* Feuille A4 réduite à 55 % */
.doc-preview { width: calc(210mm * 0.55); height: calc(297mm * 0.55); overflow: hidden; background: #dfe4ea; }
.doc-preview-inner { width: 210mm; transform: scale(0.55); transform-origin: top left; }
.doc-preview .doc-print { padding: 0; overflow: visible; }
.doc-preview .doc-sheet { box-shadow: none; }

/* ---------- Impression ---------- */
@media print {
  body * { visibility: hidden; }
  .doc-print, .doc-print * { visibility: visible; }
  .doc-preview-panel, .doc-preview-panel * { visibility: hidden !important; }
  .doc-print { position: absolute; left: 0; top: 0; width: 210mm; padding: 0; overflow: visible; }
  .doc-sheet { width: 210mm; min-height: 0; margin: 0; box-shadow: none; overflow: visible; }
  .doc-sheet .sheet-frame { height: auto; }
  /* Papier à en-tête répété sur chaque page */
  .sheet-bg { position: fixed; top: 0; left: 0; width: 210mm; height: 297mm; }
  .sheet-header { position: fixed; top: 0; left: 0; width: 210mm; }
  .sheet-footer { position: fixed; bottom: 0; left: 0; width: 210mm; }
  .doc-sheet tr { page-break-inside: avoid; }
  .no-print { display: none !important; }
  /* Le reste de l'application, masqué, ne doit pas ajouter de pages blanches */
  html, body, #root { height: auto !important; min-height: 0 !important; }
  body:has(.doc-print) .layout { height: 0 !important; min-height: 0 !important; overflow: hidden !important; }
}

/* ---------- Alertes de stock ---------- */
.doc-stats .doc-stat-danger { border-top-color: #dc2626; background: #fef2f2; }
.doc-stats .doc-stat-danger strong { color: #b91c1c; }
.doc-row-danger td { background: #fef2f2 !important; }
.stock-alert-banner {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 0 10px;
  padding: 7px 10px;
  background: #fef2f2;
  border: 1px solid #fca5a5;
  border-left: 4px solid #dc2626;
  border-radius: 3px;
  color: #7f1d1d;
  font-size: 12.5px;
}
.stock-alert-banner span { flex: 1; }
.stock-alert-banner .stock-alert-close { padding: 2px 7px !important; }

/* ---------- Statistiques ---------- */
.stats-title { display: flex; justify-content: space-between; align-items: center; }
.stats-title button { padding: 2px 8px !important; font-size: 12px !important; }
.stats-chart { position: relative; }
.stats-chart svg { display: block; width: 100%; height: auto; }
.stats-grid, .stats-axis { stroke: #e3e8ee; stroke-width: 1; }
.stats-axis { stroke: #b5c1ce; }
.stats-tick { font-size: 11px; fill: var(--pp-muted); font-variant-numeric: tabular-nums; }
.stats-label { font-size: 11px; font-weight: 600; fill: var(--pp-text); }
.stats-bar { cursor: default; outline: none; }
.stats-bar-fill { fill: #2a78d6; transition: fill 0.15s; }
.stats-bar-active .stats-bar-fill { fill: #4b8fe0; }
.stats-bar:focus-visible .stats-bar-fill { stroke: var(--pp-text); stroke-width: 1.5; }
.stats-tooltip {
  position: absolute;
  top: 0;
  transform: translateX(-50%);
  display: flex;
  flex-direction: column;
  gap: 1px;
  padding: 5px 9px;
  background: #fff;
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  box-shadow: 0 4px 12px rgba(15, 23, 42, 0.15);
  font-size: 12px;
  white-space: nowrap;
  pointer-events: none;
}
.stats-tooltip strong { font-size: 13px; color: var(--pp-text); }
.stats-tooltip span { color: var(--pp-muted); }
.stats-columns { display: grid; grid-template-columns: 3fr 2fr; gap: 12px; align-items: start; }
.stats-bar-cell { width: 25%; }
.stats-inline-bar { height: 10px; background: #2a78d6; border-radius: 0 4px 4px 0; min-width: 2px; }
.doc-stats small { font-size: 11.5px; }
.doc-cash-input { font-size: 16px !important; font-weight: 700; width: 100%; }

/* ---------- Espace de stockage ---------- */
.storage-gauge { height: 10px; background: #e5eaf0; border-radius: 5px; overflow: hidden; }
.storage-gauge-fill { height: 100%; background: #2a78d6; }
.storage-gauge-high { background: #dc2626; }
FIN_DU_FICHIER
echo "OK src/documents/documents.css"

cat > src/documents/ledger.ts <<'FIN_DU_FICHIER'
// Règlements, soldes, avoirs et retards
import { computeTotals, round2 } from './tva'
import { today } from './numbering'
import type { CommercialDocument, Payment } from './types'

/** Règlements d'un document (reprend l'ancien champ paidDate si besoin) */
export function paymentsOf(doc: CommercialDocument): Payment[] {
  if (doc.payments) return doc.payments
  if (doc.status === 'paid' && doc.paidDate)
    return [{ id: 'legacy', date: doc.paidDate, amount: computeTotals(doc).netToPay, method: doc.paymentMethod, reference: '' }]
  return []
}

export function paidAmount(doc: CommercialDocument): number {
  return round2(paymentsOf(doc).reduce((s, p) => s + p.amount, 0))
}

/** Avoirs validés émis sur cette facture */
export function creditsFor(doc: CommercialDocument, documents: CommercialDocument[]): CommercialDocument[] {
  return documents.filter((d) => d.kind === 'credit' && d.sourceId === doc.id && d.status !== 'draft' && d.status !== 'cancelled')
}

/** Reste dû : net à payer − règlements − avoirs */
export function balanceOf(doc: CommercialDocument, documents: CommercialDocument[]): number {
  if (doc.status === 'draft' || doc.status === 'cancelled') return 0
  const credits = creditsFor(doc, documents).reduce((s, c) => s + computeTotals(c).netToPay, 0)
  return round2(computeTotals(doc).netToPay - paidAmount(doc) - credits)
}

/** Facture (client ou fournisseur) validée, non soldée, dont l'échéance est dépassée */
export function isOverdue(doc: CommercialDocument, documents: CommercialDocument[], now = today()): boolean {
  return (
    (doc.kind === 'invoice' || doc.kind === 'bill') &&
    doc.status === 'validated' &&
    !!doc.dueDate &&
    doc.dueDate < now &&
    balanceOf(doc, documents) > 0.01
  )
}

/** Les avoirs viennent en déduction du chiffre d'affaires */
export function sign(doc: CommercialDocument): 1 | -1 {
  return doc.kind === 'credit' ? -1 : 1
}

/** Document pris en compte dans les chiffres (ni brouillon ni annulé) */
export function isActive(doc: CommercialDocument): boolean {
  return doc.status !== 'draft' && doc.status !== 'cancelled'
}
FIN_DU_FICHIER
echo "OK src/documents/ledger.ts"

cat > src/documents/numbering.ts <<'FIN_DU_FICHIER'
import { DOC_LABELS, type CommercialDocument, type DocKind, type DocLine } from './types'

/** Numérotation chronologique et continue par type et par année : FA-2026-0001, BL-2026-0001… */
export function nextNumber(kind: DocKind, docs: CommercialDocument[], date: string): string {
  const year = date.slice(0, 4)
  const prefix = `${DOC_LABELS[kind].prefix}-${year}-`
  let max = 0
  for (const d of docs) {
    if (d.kind !== kind || !d.number.startsWith(prefix)) continue
    const seq = Number(d.number.slice(prefix.length))
    if (Number.isFinite(seq) && seq > max) max = seq
  }
  return prefix + String(max + 1).padStart(4, '0')
}

export function newId(): string {
  return typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : Date.now().toString(36) + Math.random().toString(36).slice(2)
}

/** Date locale au format AAAA-MM-JJ (et non UTC : au Maroc, toISOString décale d'un jour entre minuit et 1 h) */
export function isoDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function today(): string {
  return isoDate(new Date())
}

export function addDays(date: string, days: number): string {
  const d = new Date(date + 'T00:00:00')
  d.setDate(d.getDate() + days)
  return isoDate(d)
}

export function daysBetween(from: string, to: string): number {
  return Math.round((new Date(to + 'T00:00:00').getTime() - new Date(from + 'T00:00:00').getTime()) / 86400000)
}

export function frDate(d: string | undefined): string {
  return d ? new Date(d + 'T00:00:00').toLocaleDateString('fr-FR') : ''
}

export function emptyLine(): DocLine {
  return { id: newId(), description: '', quantity: 1, unitPriceHT: 0, tvaRate: 20, discount: 0 }
}

/** Nouvelle pièce vierge (brouillon numéroté) */
export function newDocument(kind: DocKind, docs: CommercialDocument[]): CommercialDocument {
  const date = today()
  return {
    id: newId(),
    kind,
    number: nextNumber(kind, docs, date),
    date,
    // Facture : délai légal de paiement par défaut de 60 jours ; devis : validité de 30 jours
    dueDate: addDays(date, kind === 'quote' ? 30 : 60),
    party: { name: '', address: '', city: '', ice: '', ifNumber: '', rc: '', phone: '', email: '' },
    lines: [emptyLine()],
    status: 'draft',
    paymentMethod: 'virement',
    notes: '',
  }
}

/**
 * Numéro définitif attribué à la validation : il suit les pièces déjà validées du même type et de la
 * même année, si bien que la suppression d'un brouillon ne laisse jamais de trou dans la numérotation.
 */
export function finalNumber(doc: CommercialDocument, docs: CommercialDocument[]): string {
  return nextNumber(doc.kind, docs.filter((d) => d.status !== 'draft' && d.id !== doc.id), doc.date)
}
FIN_DU_FICHIER
echo "OK src/documents/numbering.ts"

cat > src/documents/printSettings.ts <<'FIN_DU_FICHIER'
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
FIN_DU_FICHIER
echo "OK src/documents/printSettings.ts"

cat > src/documents/stockMoves.ts <<'FIN_DU_FICHIER'
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
FIN_DU_FICHIER
echo "OK src/documents/stockMoves.ts"

cat > src/documents/storage.ts <<'FIN_DU_FICHIER'
import { useEffect, useState } from 'react'
import {
  emptyCompany,
  type CommercialDocument,
  type CompanyInfo,
  type Kit,
  type PartyRecord,
  type StockLot,
  type StockMovement,
} from './types'

export const DOCS_KEY = 'profitpilot:documents:v1'
export const COMPANY_KEY = 'profitpilot:company:v1'
export const LOTS_KEY = 'profitpilot:lots:v1'
export const KITS_KEY = 'profitpilot:kits:v1'
export const PARTIES_KEY = 'profitpilot:parties:v1'
export const MOVES_KEY = 'profitpilot:movements:v1'
export const CASH_KEY = 'profitpilot:cash:v1'
export const LAST_BACKUP_KEY = 'profitpilot:last-backup'

/** Événement émis quand le navigateur refuse d'enregistrer (stockage plein) */
export const STORAGE_ERROR_EVENT = 'profitpilot:storage-error'

/**
 * État React sauvegardé dans le localStorage, avec validation à la relecture.
 * Les autres onglets ouverts sont tenus à jour (événement « storage ») pour ne jamais
 * écraser une saisie faite ailleurs ; un échec d'enregistrement est signalé à l'application.
 */
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
      const raw = JSON.stringify(value)
      // Pas de réécriture si la valeur vient d'un autre onglet
      if (localStorage.getItem(key) !== raw) localStorage.setItem(key, raw)
    } catch {
      window.dispatchEvent(new CustomEvent(STORAGE_ERROR_EVENT, { detail: key }))
    }
  }, [key, value])

  useEffect(() => {
    function onStorage(e: StorageEvent) {
      if (e.key !== key || e.newValue === null) return
      try {
        const data: unknown = JSON.parse(e.newValue)
        if (isValid(data)) setValue(data)
      } catch {
        // valeur illisible : on garde l'état courant
      }
    }
    window.addEventListener('storage', onStorage)
    return () => window.removeEventListener('storage', onStorage)
    // isValid est une fonction stable définie au niveau du module
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  return [value, setValue] as const
}

/** Place occupée par les données de l'application (en caractères, ~ octets) */
export function storageUsage(): number {
  let size = 0
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      if (k?.startsWith('profitpilot:')) size += k.length + (localStorage.getItem(k) ?? '').length
    }
  } catch {
    // stockage indisponible
  }
  return size
}

/** Limite courante des navigateurs pour le localStorage (≈ 5 millions de caractères) */
export const STORAGE_LIMIT = 5_000_000

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

/** Pièces telles qu'enregistrées (lecture directe, hors React : après une attente réseau) */
export function readDocuments(): CommercialDocument[] | null {
  try {
    const data: unknown = JSON.parse(localStorage.getItem(DOCS_KEY) ?? 'null')
    return isDocumentList(data) ? data : null
  } catch {
    return null
  }
}

export const useDocuments = () => usePersistentState<CommercialDocument[]>(DOCS_KEY, () => [], isDocumentList)
export const useCompany = () => usePersistentState<CompanyInfo>(COMPANY_KEY, emptyCompany, isCompany)
export const useLots = () => usePersistentState<StockLot[]>(LOTS_KEY, () => [], isLotList)
export const useKits = () => usePersistentState<Kit[]>(KITS_KEY, () => [], isKitList)
const isMoveList = listOf<StockMovement>(
  (x) => isObj(x) && typeof x.id === 'string' && typeof x.productId === 'string' && typeof x.quantity === 'number',
)
const isNumber = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x)

export const useMovements = () => usePersistentState<StockMovement[]>(MOVES_KEY, () => [], isMoveList)
/** Trésorerie disponible saisie dans l'échéancier */
export const useCashBalance = () => usePersistentState<number>(CASH_KEY, () => 0, isNumber)
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
FIN_DU_FICHIER
echo "OK src/documents/storage.ts"

cat > src/documents/tva.ts <<'FIN_DU_FICHIER'
import type { CommercialDocument, DocLine, TvaRate } from './types'

export const TVA_RATES: { rate: TvaRate; label: string }[] = [
  { rate: 20, label: '20 % (taux normal)' },
  { rate: 14, label: '14 %' },
  { rate: 10, label: '10 %' },
  { rate: 7, label: '7 %' },
  { rate: 0, label: 'Exonéré (0 %)' },
]

/** Droit de timbre sur les factures réglées en espèces : 0,25 % du TTC. Vérifiez le taux avec votre comptable. */
export const STAMP_DUTY_RATE = 0.0025

export function round2(x: number): number {
  return Math.round((x + Number.EPSILON) * 100) / 100
}

export function lineHT(line: DocLine): number {
  return round2(line.quantity * line.unitPriceHT * (1 - line.discount / 100))
}

export interface TvaBreakdown {
  rate: TvaRate
  base: number
  tva: number
}

export interface DocTotals {
  totalHT: number
  totalTVA: number
  totalTTC: number
  byRate: TvaBreakdown[]
  stampDuty: number
  netToPay: number
}

/** La TVA est calculée par taux sur la somme des bases HT, comme sur une facture marocaine classique */
export function computeTotals(doc: Pick<CommercialDocument, 'lines' | 'kind' | 'paymentMethod'>): DocTotals {
  const bases = new Map<TvaRate, number>()
  for (const line of doc.lines) {
    bases.set(line.tvaRate, (bases.get(line.tvaRate) ?? 0) + lineHT(line))
  }
  const byRate = [...bases.entries()]
    .sort((a, b) => b[0] - a[0])
    .map(([rate, base]) => ({ rate, base: round2(base), tva: round2((base * rate) / 100) }))

  const totalHT = round2(byRate.reduce((s, r) => s + r.base, 0))
  const totalTVA = round2(byRate.reduce((s, r) => s + r.tva, 0))
  const totalTTC = round2(totalHT + totalTVA)
  const stampDuty =
    doc.kind === 'invoice' && doc.paymentMethod === 'especes' ? round2(totalTTC * STAMP_DUTY_RATE) : 0

  return { totalHT, totalTVA, totalTTC, byRate, stampDuty, netToPay: round2(totalTTC + stampDuty) }
}

export function formatMAD(x: number): string {
  return (
    x.toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' DH'
  )
}

// ---------- Montant en lettres (« Arrêtée la présente facture à la somme de … ») ----------

const UNITS = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix',
  'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize', 'dix-sept', 'dix-huit', 'dix-neuf',
]
const TENS = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante', 'soixante', 'quatre-vingt', 'quatre-vingt']

function below100(n: number): string {
  if (n < 20) return UNITS[n]
  const t = Math.floor(n / 10)
  const u = n % 10
  // 70-79 et 90-99 : soixante-dix, quatre-vingt-onze…
  if (t === 7 || t === 9) return TENS[t] + (t === 7 && u === 1 ? ' et ' : '-') + UNITS[10 + u]
  if (u === 0) return t === 8 ? 'quatre-vingts' : TENS[t]
  if (u === 1 && t !== 8) return TENS[t] + ' et un'
  return TENS[t] + '-' + UNITS[u]
}

function below1000(n: number): string {
  const h = Math.floor(n / 100)
  const r = n % 100
  let s = ''
  if (h > 0) s = h === 1 ? 'cent' : UNITS[h] + ' cent' + (r === 0 ? 's' : '')
  if (r > 0) s += (s ? ' ' : '') + below100(r)
  return s
}

export function numberToWordsFr(value: number): string {
  let n = Math.floor(Math.abs(value))
  if (n === 0) return 'zéro'
  const parts: string[] = []
  const billions = Math.floor(n / 1e9)
  n %= 1e9
  const millions = Math.floor(n / 1e6)
  n %= 1e6
  const thousands = Math.floor(n / 1000)
  const rest = n % 1000

  if (billions) parts.push(below1000(billions) + ' milliard' + (billions > 1 ? 's' : ''))
  if (millions) parts.push(below1000(millions) + ' million' + (millions > 1 ? 's' : ''))
  // « mille » est invariable et « vingts/cents » perdent leur s devant lui
  if (thousands) parts.push(thousands === 1 ? 'mille' : below1000(thousands).replace(/(vingt|cent)s$/, '$1') + ' mille')
  if (rest) parts.push(below1000(rest))
  return parts.join(' ')
}

export function amountInWordsMAD(amount: number): string {
  const cents = Math.round(round2(amount) * 100)
  const dh = Math.floor(cents / 100)
  const ct = cents % 100
  let s = numberToWordsFr(dh) + (dh > 1 ? ' dirhams' : ' dirham')
  if (ct > 0) s += ' et ' + numberToWordsFr(ct) + (ct > 1 ? ' centimes' : ' centime')
  return s.charAt(0).toUpperCase() + s.slice(1)
}
FIN_DU_FICHIER
echo "OK src/documents/tva.ts"

cat > src/documents/types.ts <<'FIN_DU_FICHIER'
// Types de la gestion commerciale : ventes, achats, stock par lot, tiers

/**
 * Ventes : quote = devis, order = bon de commande, delivery = bon de livraison (BL),
 * invoice = facture, credit = avoir.
 * Achats : purchase = commande fournisseur, receipt = bon de réception, bill = facture fournisseur.
 */
export type DocKind = 'quote' | 'order' | 'delivery' | 'invoice' | 'credit' | 'purchase' | 'receipt' | 'bill'

/** Taux de TVA en vigueur au Maroc (CGI, art. 98 à 100) */
export type TvaRate = 0 | 7 | 10 | 14 | 20

export type DocStatus = 'draft' | 'validated' | 'paid' | 'cancelled'

export type PaymentMethod = 'virement' | 'cheque' | 'especes' | 'effet' | 'carte'

export type Coverage = 'CNSS' | 'CNOPS' | 'AMO' | 'Mutuelle' | 'Privé'

/** Client ou fournisseur */
export interface Party {
  name: string
  address: string
  city: string
  ice: string // Identifiant Commun de l'Entreprise (15 chiffres)
  ifNumber: string // Identifiant fiscal
  rc: string // Registre du commerce
  phone: string
  email: string
  /** Particulier (patient) : l'ICE n'est pas exigé sur la facture */
  individual?: boolean
}

export type PartyRole = 'client' | 'supplier'

/** Fiche tiers enregistrée (clients et fournisseurs) */
export interface PartyRecord extends Party {
  id: string
  role: PartyRole
  notes: string
  /** Délai de paiement accordé, en jours */
  paymentTerms?: number
}

/**
 * Mise en page des pièces imprimées :
 * - generated : en-tête et pied de page générés à partir de la fiche société
 * - images : votre en-tête et votre pied de page (images) en haut et en bas de chaque page
 * - background : votre papier à en-tête complet (image A4) en fond de chaque page
 * - preprinted : impression sur papier déjà imprimé, on réserve seulement les marges
 */
export type LetterheadMode = 'generated' | 'images' | 'background' | 'preprinted'

export interface PrintSettings {
  mode: LetterheadMode
  headerImg?: string
  footerImg?: string
  backgroundImg?: string
  /** Marges en millimètres (haut et bas : place réservée à l'en-tête et au pied de page) */
  top: number
  bottom: number
  side: number
  /** Mentions légales (ICE, IF, RC…) en bas de page */
  showLegal: boolean
  /** Couleur des titres et bandeaux */
  accent: string
  /** Conditions imprimées par défaut sous les devis et les factures */
  quoteTerms: string
  invoiceTerms: string
}

export const defaultPrintSettings = (): PrintSettings => ({
  mode: 'generated',
  top: 15,
  bottom: 15,
  side: 15,
  showLegal: true,
  accent: '#1f4e79',
  quoteTerms: 'Devis valable 30 jours. Délai de livraison : selon disponibilité. Paiement : 60 jours à réception de facture.',
  invoiceTerms: 'Paiement à 60 jours à réception de facture. Tout retard de paiement donne lieu à des pénalités conformément à la loi 69-21.',
})

/** Informations de votre entreprise, imprimées sur chaque document */
export interface CompanyInfo extends Party {
  patente: string
  cnss: string
  bank: string
  rib: string
  /** Logo en data URL (PNG/JPEG) */
  logo?: string
  print?: PrintSettings
}

/** Suivi d'un implant laissé en dépôt chez une clinique */
export type DepotState = 'depot' | 'posed' | 'returned'

export interface DocLine {
  id: string
  productId?: string
  description: string
  quantity: number
  unitPriceHT: number
  tvaRate: TvaRate
  discount: number // remise en %
  /** Traçabilité */
  lotId?: string
  lot?: string
  serial?: string
  expiry?: string // AAAA-MM-JJ
  /** Quantité réellement sortie du stock à la validation (peut être inférieure si stock insuffisant) */
  movedQty?: number
  /** Lignes de BL en dépôt */
  depot?: DepotState
  /** Ligne de BL dépôt facturée par cette ligne (pour la remettre en dépôt si la facture est supprimée) */
  depotRef?: { docId: string; lineId: string }
}

export interface Payment {
  id: string
  date: string
  amount: number
  method: PaymentMethod
  reference: string
}

/** Intervention chirurgicale liée à une facture ou un BL */
export interface Intervention {
  patient: string
  patientRef: string // n° de dossier, CIN ou immatriculation
  surgeon: string
  clinic: string
  date: string
  coverage: Coverage | ''
}

export interface CommercialDocument {
  id: string
  kind: DocKind
  number: string // ex. FA-2026-0001
  date: string // AAAA-MM-JJ
  dueDate: string // échéance (factures) ou fin de validité (devis)
  party: Party
  lines: DocLine[]
  status: DocStatus
  paymentMethod: PaymentMethod
  notes: string
  /** Règlements reçus (ventes) ou effectués (achats) */
  payments?: Payment[]
  /** Ancien format : date d'encaissement unique */
  paidDate?: string
  /** BL en dépôt : le matériel reste chez le client jusqu'à la pose */
  consignment?: boolean
  intervention?: Intervention
  /** Numéro de la facture chez le fournisseur */
  supplierRef?: string
  /** Traçabilité : utilisateur qui a créé et validé la pièce */
  createdBy?: string
  validatedBy?: string
  /** Document d'origine (ex. le BC ayant donné ce BL) */
  sourceId?: string
  sourceNumber?: string
}

/** Lot (ou numéro de série) en stock, avec sa date de péremption */
export interface StockLot {
  id: string
  productId: string
  lot: string
  serial: string
  expiry: string
  quantity: number
  receivedDate: string
  supplier: string
}

/** Mouvement de stock (journal) : quantité signée, + entrée / − sortie */
export type MovementKind = 'in' | 'out' | 'adjust'

export interface StockMovement {
  id: string
  date: string
  productId: string
  productName: string
  lot: string
  serial: string
  quantity: number
  kind: MovementKind
  /** Pièce ou motif : « BL-2026-0003 », « Inventaire du 14/10/2026 »… */
  reference: string
  /** Stock de l'article après le mouvement */
  stockAfter?: number
}

export interface Kit {
  id: string
  name: string
  items: { productId: string; quantity: number }[]
}

export type DocSide = 'sale' | 'purchase'

export const DOC_LABELS: Record<
  DocKind,
  { title: string; plural: string; prefix: string; newLabel: string; side: DocSide; printTitle: string }
> = {
  quote: { title: 'Devis', plural: 'Devis', prefix: 'DV', newLabel: 'Nouveau devis', side: 'sale', printTitle: 'DEVIS' },
  order: {
    title: 'Bon de commande',
    plural: 'Bons de commande',
    prefix: 'BC',
    newLabel: 'Nouveau bon de commande',
    side: 'sale',
    printTitle: 'BON DE COMMANDE',
  },
  delivery: {
    title: 'Bon de livraison',
    plural: 'Bons de livraison',
    prefix: 'BL',
    newLabel: 'Nouveau bon de livraison',
    side: 'sale',
    printTitle: 'BON DE LIVRAISON',
  },
  invoice: { title: 'Facture', plural: 'Factures', prefix: 'FA', newLabel: 'Nouvelle facture', side: 'sale', printTitle: 'FACTURE' },
  credit: { title: 'Avoir', plural: 'Avoirs', prefix: 'AV', newLabel: 'Nouvel avoir', side: 'sale', printTitle: 'AVOIR' },
  purchase: {
    title: 'Commande fournisseur',
    plural: 'Commandes fournisseurs',
    prefix: 'CF',
    newLabel: 'Nouvelle commande fournisseur',
    side: 'purchase',
    printTitle: 'BON DE COMMANDE FOURNISSEUR',
  },
  receipt: {
    title: 'Bon de réception',
    plural: 'Bons de réception',
    prefix: 'BR',
    newLabel: 'Nouveau bon de réception',
    side: 'purchase',
    printTitle: 'BON DE RÉCEPTION',
  },
  bill: {
    title: 'Facture fournisseur',
    plural: 'Factures fournisseurs',
    prefix: 'FF',
    newLabel: 'Nouvelle facture fournisseur',
    side: 'purchase',
    printTitle: 'FACTURE FOURNISSEUR',
  },
}

export const ALL_KINDS = Object.keys(DOC_LABELS) as DocKind[]

export const STATUS_LABELS: Record<DocStatus, string> = {
  draft: 'Brouillon',
  validated: 'Validé',
  paid: 'Réglé',
  cancelled: 'Annulé',
}

export const PAYMENT_LABELS: Record<PaymentMethod, string> = {
  virement: 'Virement bancaire',
  cheque: 'Chèque',
  especes: 'Espèces',
  effet: 'Effet de commerce (LCN)',
  carte: 'Carte bancaire',
}

export const COVERAGES: Coverage[] = ['CNSS', 'CNOPS', 'AMO', 'Mutuelle', 'Privé']

export const emptyParty = (): Party => ({
  name: '',
  address: '',
  city: '',
  ice: '',
  ifNumber: '',
  rc: '',
  phone: '',
  email: '',
})

export const emptyCompany = (): CompanyInfo => ({
  ...emptyParty(),
  patente: '',
  cnss: '',
  bank: '',
  rib: '',
})

export const emptyIntervention = (): Intervention => ({
  patient: '',
  patientRef: '',
  surgeon: '',
  clinic: '',
  date: '',
  coverage: '',
})
FIN_DU_FICHIER
echo "OK src/documents/types.ts"

cat > src/shell/GlobalSearch.tsx <<'FIN_DU_FICHIER'
import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react'
import type { Product } from '../types'
import { frDate } from '../documents/numbering'
import { computeTotals, formatMAD } from '../documents/tva'
import { DOC_LABELS, type CommercialDocument, type PartyRecord, type StockLot } from '../documents/types'

export type SearchHit =
  | { type: 'doc'; doc: CommercialDocument }
  | { type: 'party'; party: PartyRecord }
  | { type: 'product'; product: Product }
  | { type: 'lot'; lot: StockLot; productName: string }

interface Props {
  documents: CommercialDocument[]
  parties: PartyRecord[]
  products: Product[]
  lots: StockLot[]
  onPick: (hit: SearchHit) => void
  onClose: () => void
}

const norm = (s: string | undefined) =>
  (s ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')

/** Recherche globale (Cmd/Ctrl + K) : pièces, tiers, articles, lots et n° de série */
export default function GlobalSearch({ documents, parties, products, lots, onPick, onClose }: Props) {
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const input = useRef<HTMLInputElement>(null)

  useEffect(() => input.current?.focus(), [])

  const hits = useMemo<SearchHit[]>(() => {
    const q = norm(query.trim())
    if (q.length < 2) return []
    const has = (...values: (string | undefined)[]) => values.some((v) => norm(v).includes(q))
    const docs = documents
      .filter((d) =>
        has(d.number, d.party.name, d.supplierRef, d.intervention?.patient, d.intervention?.patientRef, ...d.lines.flatMap((l) => [l.lot, l.serial])),
      )
      .sort((a, b) => b.date.localeCompare(a.date))
      .slice(0, 8)
      .map((doc): SearchHit => ({ type: 'doc', doc }))
    const tiers = parties
      .filter((p) => has(p.name, p.ice, p.city, p.phone))
      .slice(0, 5)
      .map((party): SearchHit => ({ type: 'party', party }))
    const items = products
      .filter((p) => has(p.name, p.reference, p.category))
      .slice(0, 5)
      .map((product): SearchHit => ({ type: 'product', product }))
    const lotHits = lots
      .filter((l) => has(l.lot, l.serial))
      .slice(0, 5)
      .map((lot): SearchHit => ({ type: 'lot', lot, productName: products.find((p) => p.id === lot.productId)?.name ?? '' }))
    return [...docs, ...tiers, ...items, ...lotHits]
  }, [query, documents, parties, products, lots])

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') onClose()
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((a) => Math.min(a + 1, hits.length - 1))
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((a) => Math.max(a - 1, 0))
    }
    if (e.key === 'Enter' && hits[active]) onPick(hits[active])
  }

  const describe = (h: SearchHit): [string, string, string] => {
    if (h.type === 'doc')
      return [
        DOC_LABELS[h.doc.kind].title,
        `${h.doc.number} · ${h.doc.party.name}`,
        `${frDate(h.doc.date)} · ${formatMAD(computeTotals(h.doc).netToPay)}`,
      ]
    if (h.type === 'party') return [h.party.role === 'client' ? 'Client' : 'Fournisseur', h.party.name, [h.party.city, h.party.ice].filter(Boolean).join(' · ')]
    if (h.type === 'product') return ['Article', h.product.name, [h.product.reference, h.product.stock !== undefined ? `stock ${h.product.stock}` : ''].filter(Boolean).join(' · ')]
    return ['Lot', [h.lot.lot, h.lot.serial].filter(Boolean).join(' / '), `${h.productName} · ${h.lot.quantity} en stock`]
  }

  return (
    <div className="erp-search-backdrop" onClick={onClose}>
      <div className="erp-search" role="dialog" aria-modal="true" aria-label="Recherche globale" onClick={(e) => e.stopPropagation()}>
        <input
          ref={input}
          value={query}
          placeholder="Rechercher une pièce, un client, un article, un lot, un n° de série, un patient…"
          onChange={(e) => {
            setQuery(e.target.value)
            setActive(0)
          }}
          onKeyDown={onKey}
        />
        <div className="erp-search-results">
          {query.trim().length < 2 ? (
            <p className="erp-search-hint">Tapez au moins 2 caractères · ↑ ↓ pour choisir · Entrée pour ouvrir · Échap pour fermer</p>
          ) : hits.length === 0 ? (
            <p className="erp-search-hint">Aucun résultat.</p>
          ) : (
            hits.map((h, i) => {
              const [kind, title, sub] = describe(h)
              return (
                <button
                  key={i}
                  type="button"
                  className={`erp-search-hit ${i === active ? 'erp-search-hit-active' : ''}`}
                  onMouseEnter={() => setActive(i)}
                  onClick={() => onPick(h)}
                >
                  <span className="erp-search-kind">{kind}</span>
                  <span className="erp-search-title">{title}</span>
                  <span className="erp-search-sub">{sub}</span>
                </button>
              )
            })
          )}
        </div>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/shell/GlobalSearch.tsx"

cat > src/shell/Launchpad.tsx <<'FIN_DU_FICHIER'
import { useMemo } from 'react'
import type { PageId, Product } from '../types'
import { getStockStatus } from '../utils/stock'
import { balanceOf, isActive, isOverdue, sign } from '../documents/ledger'
import { frDate, today } from '../documents/numbering'
import { expiryState } from '../documents/stockMoves'
import { computeTotals, formatMAD, round2 } from '../documents/tva'
import { DOC_LABELS, STATUS_LABELS, type CommercialDocument, type DocKind, type StockLot } from '../documents/types'
import Icon from './icons'
import { useAccess } from '../access/context'
import type { ModuleId } from './navigation'

interface Props {
  companyName: string
  documents: CommercialDocument[]
  products: Product[]
  lots: StockLot[]
  cash: number
  onNavigate: (page: PageId) => void
  onOpenDocument: (kind: DocKind, id?: string) => void
  onCreate: (kind: DocKind) => void
}

interface Tile {
  module: ModuleId
  title: string
  value: string
  sub: string
  page: PageId
  tone?: 'danger' | 'warning' | 'good'
}

const compactMAD = (v: number) =>
  Math.abs(v) >= 1e6
    ? `${(v / 1e6).toLocaleString('fr-FR', { maximumFractionDigits: 2 })} M DH`
    : Math.abs(v) >= 1e4
      ? `${(v / 1e3).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} k DH`
      : formatMAD(v)

/** Accueil façon « launchpad » : une tuile par indicateur clé, cliquable vers l'écran concerné */
export default function Launchpad({ companyName, documents, products, lots, cash, onNavigate, onOpenDocument, onCreate }: Props) {
  const now = today()
  const month = now.slice(0, 7)
  const access = useAccess()
  const showCosts = access.can('costs')

  const tiles = useMemo<Tile[]>(() => {
    let monthHT = 0
    let monthMargin = 0
    let receivable = 0
    let late = 0
    let lateCount = 0
    let payable = 0
    let quotesHT = 0
    let quotes = 0
    const converted = new Set(documents.map((d) => d.sourceId).filter(Boolean))
    const received = new Set(documents.filter((d) => d.kind === 'receipt' && d.status !== 'cancelled').map((d) => d.sourceId))
    let pendingPurchases = 0
    // TVA du mois, estimée sur les dates de facture (collectée − déductible)
    let monthVat = 0
    let depot = 0
    const cost = new Map(products.map((p) => [p.id, p.unitCost]))

    for (const d of documents) {
      if (!isActive(d)) continue
      if ((d.kind === 'invoice' || d.kind === 'credit') && d.date.startsWith(month)) {
        const t = computeTotals(d)
        monthHT += sign(d) * t.totalHT
        for (const l of d.lines) {
          const c = l.productId ? (cost.get(l.productId) ?? 0) : 0
          monthMargin += sign(d) * (l.quantity * l.unitPriceHT * (1 - l.discount / 100) - c * l.quantity)
        }
      }
      if (d.date.startsWith(month) && (d.kind === 'invoice' || d.kind === 'credit' || d.kind === 'bill'))
        monthVat += (d.kind === 'bill' ? -1 : sign(d)) * computeTotals(d).totalTVA
      if (d.kind === 'invoice') receivable += balanceOf(d, documents)
      if (d.kind === 'bill') payable += balanceOf(d, documents)
      if (d.kind === 'invoice' && isOverdue(d, documents, now)) {
        late += balanceOf(d, documents)
        lateCount++
      }
      if (d.kind === 'quote' && d.status === 'validated' && !converted.has(d.id) && d.dueDate >= now) {
        quotes++
        quotesHT += computeTotals(d).totalHT
      }
      if (d.kind === 'purchase' && d.status === 'validated' && !received.has(d.id)) pendingPurchases++
      if (d.kind === 'delivery' && d.consignment && d.status === 'validated') depot += d.lines.filter((l) => l.depot === 'depot').length
    }
    const out = products.filter((p) => getStockStatus(p) === 'out').length
    const low = products.filter((p) => getStockStatus(p) === 'low').length
    const expiring = lots.filter((l) => l.quantity > 0 && ['expired', 'soon'].includes(expiryState(l.expiry, now))).length
    const stockValue = products.reduce((s, p) => s + (p.stock ?? 0) * p.unitCost, 0)
    const forecast = cash + receivable - payable

    return [
      { module: 'sales', title: 'CA du mois (HT)', value: compactMAD(round2(monthHT)), sub: !monthHT ? 'aucune facture ce mois' : showCosts ? `marge ${Math.round((monthMargin / monthHT) * 100)} %` : 'net des avoirs', page: 'stats' },
      { module: 'sales', title: 'Devis en cours', value: String(quotes), sub: compactMAD(round2(quotesHT)) + ' HT à transformer', page: 'quotes' },
      { module: 'sales', title: 'Factures échues', value: String(lateCount), sub: compactMAD(round2(late)) + ' à relancer', page: 'invoices', tone: lateCount ? 'danger' : 'good' },
      { module: 'sales', title: 'Implants en dépôt', value: String(depot), sub: 'chez les cliniques', page: 'depots' },
      { module: 'purchases', title: 'Commandes à recevoir', value: String(pendingPurchases), sub: 'commandes fournisseurs validées', page: 'purchases' },
      { module: 'purchases', title: 'Fournisseurs à payer', value: compactMAD(round2(payable)), sub: 'factures fournisseurs ouvertes', page: 'bills' },
      { module: 'stock', title: 'Ruptures / sous le seuil', value: `${out} / ${low}`, sub: 'articles à réapprovisionner', page: 'alerts', tone: out ? 'danger' : low ? 'warning' : 'good' },
      { module: 'stock', title: 'Péremptions', value: String(expiring), sub: 'lots périmés ou < 90 jours', page: 'lots', tone: expiring ? 'warning' : 'good' },
      { module: 'stock', title: 'Valeur du stock', value: compactMAD(round2(stockValue)), sub: "au coût d'achat", page: 'inventory' },
      { module: 'finance', title: 'À encaisser', value: compactMAD(round2(receivable)), sub: 'créances clients', page: 'schedule' },
      { module: 'finance', title: 'Solde prévisionnel', value: compactMAD(round2(forecast)), sub: 'trésorerie + créances − dettes', page: 'schedule', tone: forecast < 0 ? 'danger' : undefined },
      { module: 'finance', title: 'TVA du mois (estimation)', value: compactMAD(round2(monthVat)), sub: monthVat < 0 ? 'crédit de TVA' : 'collectée − déductible', page: 'vat' },
    ]
  }, [documents, products, lots, cash, month, now, showCosts])

  const visibleTiles = tiles.filter((t) => access.level(t.module) !== 'none' && (showCosts || t.title !== 'Valeur du stock'))
  const sideOk = (d: CommercialDocument) => access.level(DOC_LABELS[d.kind].side === 'sale' ? 'sales' : 'purchases') !== 'none'
  const canCreate = (side: 'sales' | 'purchases') => access.level(side) === 'write'

  const recent = useMemo(
    () => [...documents].filter(sideOk).sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number)).slice(0, 8),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [documents, access],
  )

  const groups: { module: ModuleId; label: string }[] = [
    { module: 'sales', label: 'Ventes' },
    { module: 'purchases', label: 'Achats' },
    { module: 'stock', label: 'Stocks' },
    { module: 'finance', label: 'Finance' },
  ]
  const hour = new Date().getHours()

  return (
    <div className="erp-home">
      <div className="erp-home-head">
        <div>
          <h2>
            {hour < 18 ? 'Bonjour' : 'Bonsoir'}
            {access.user ? ` ${access.user.name}` : ''}
          </h2>
          <p>
            {companyName || 'Votre dossier'} · {new Date().toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
          </p>
        </div>
        <div className="erp-quick">
          {canCreate('sales') && (
            <>
              <button type="button" className="btn-primary" onClick={() => onCreate('quote')}>
                + Devis
              </button>
              <button type="button" onClick={() => onCreate('invoice')}>
                + Facture
              </button>
              <button type="button" onClick={() => onCreate('delivery')}>
                + BL
              </button>
            </>
          )}
          {canCreate('purchases') && (
            <button type="button" onClick={() => onCreate('purchase')}>
              + Commande fournisseur
            </button>
          )}
        </div>
      </div>

      {groups.filter((g) => visibleTiles.some((t) => t.module === g.module)).map((g) => (
        <section key={g.module} className="erp-tile-group">
          <h3>
            <Icon name={g.module} /> {g.label}
          </h3>
          <div className="erp-tiles">
            {visibleTiles
              .filter((t) => t.module === g.module)
              .map((t) => (
                <button key={t.title} type="button" className={`erp-tile ${t.tone ? `erp-tile-${t.tone}` : ''}`} onClick={() => onNavigate(t.page)}>
                  <span className="erp-tile-title">{t.title}</span>
                  <span className="erp-tile-value">{t.value}</span>
                  <span className="erp-tile-sub">{t.sub}</span>
                </button>
              ))}
          </div>
        </section>
      ))}

      <section className="erp-tile-group">
        <h3>Dernières pièces</h3>
        {recent.length === 0 ? (
          <p className="doc-empty">Aucune pièce pour l'instant : commencez par créer un devis ou une facture.</p>
        ) : (
          <table className="doc-table">
            <thead>
              <tr>
                <th>Pièce</th>
                <th>N°</th>
                <th>Date</th>
                <th>Tiers</th>
                <th className="num">Montant TTC</th>
                <th>État</th>
              </tr>
            </thead>
            <tbody>
              {recent.map((d) => (
                <tr key={d.id}>
                  <td>{DOC_LABELS[d.kind].title}</td>
                  <td>
                    <button type="button" className="doc-link" onClick={() => onOpenDocument(d.kind, d.id)}>
                      {d.number}
                    </button>
                  </td>
                  <td>{frDate(d.date)}</td>
                  <td>{d.party.name}</td>
                  <td className="num">{formatMAD(computeTotals(d).netToPay)}</td>
                  <td>
                    <span className={`doc-badge doc-badge-${d.status}`}>{STATUS_LABELS[d.status]}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/shell/Launchpad.tsx"

cat > src/shell/ModuleBar.tsx <<'FIN_DU_FICHIER'
import Icon from './icons'
import { MODULES, type ModuleId } from './navigation'
import type { PageId } from '../types'
import { useAccess } from '../access/context'

interface Props {
  current: ModuleId
  onOpen: (page: PageId) => void
  /** Alertes par module (pastille) */
  badges: Partial<Record<ModuleId, number>>
}

/** Ruban des modules : Accueil, Ventes, Achats, Stocks, Finance, Pilotage, Paramètres */
export default function ModuleBar({ current, onOpen, badges }: Props) {
  const access = useAccess()
  return (
    <nav className="erp-modules no-print" aria-label="Modules">
      {MODULES.map((m, i) => access.level(m.id) === 'none' ? null : (
        <button
          key={m.id}
          type="button"
          className={`erp-module ${m.id === current ? 'erp-module-active' : ''}`}
          title={`${m.label} (Alt+${i + 1})`}
          onClick={() => onOpen(m.groups[0].pages[0])}
        >
          <Icon name={m.id} />
          {m.label}
          {!!badges[m.id] && <span className="nav-badge">{badges[m.id]}</span>}
        </button>
      ))}
    </nav>
  )
}
FIN_DU_FICHIER
echo "OK src/shell/ModuleBar.tsx"

cat > src/shell/StatusBar.tsx <<'FIN_DU_FICHIER'
import type { SyncStatus } from '../sync/engine'

interface Props {
  companyName: string
  sync?: SyncStatus | null
  onOpenSync?: () => void
  documentsCount: number
  productsCount: number
  lastBackup: string
}

/** Barre d'état : dossier, exercice, volumes, dernière sauvegarde */
function syncLabel(s: SyncStatus): { text: string; tone: string } {
  if (s.phase === 'offline') return { text: `Hors ligne${s.pending ? ` · ${s.pending} modification(s) en attente` : ''}`, tone: 'erp-status-warn' }
  if (s.phase === 'auth') return { text: 'Multi-postes : reconnexion nécessaire', tone: 'erp-status-error' }
  if (s.phase === 'error') return { text: 'Multi-postes : erreur de synchronisation', tone: 'erp-status-error' }
  if (s.phase === 'ok' && s.lastSync) return { text: `Synchronisé à ${new Date(s.lastSync).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}`, tone: 'erp-status-ok' }
  if (s.phase === 'idle' && s.message) return { text: s.message, tone: 'erp-status-ok' }
  return { text: 'Synchronisation…', tone: '' }
}

export default function StatusBar({ companyName, documentsCount, productsCount, lastBackup, sync, onOpenSync }: Props) {
  const year = new Date().getFullYear()
  return (
    <footer className="erp-status no-print">
      <span>Dossier : {companyName || '—'}</span>
      <span>Exercice {year}</span>
      <span>{documentsCount} pièce(s)</span>
      <span>{productsCount} article(s)</span>
      <span className={lastBackup ? undefined : 'erp-status-warn'}>
        Sauvegarde : {lastBackup ? new Date(lastBackup + 'T00:00:00').toLocaleDateString('fr-FR') : 'jamais'}
      </span>
      {sync ? (
        <button type="button" className={`erp-status-sync ${syncLabel(sync).tone}`} onClick={onOpenSync} title={sync.message || 'État de la synchronisation'}>
          ● {syncLabel(sync).text}
        </button>
      ) : null}
      <span className="erp-status-right">
        {sync ? 'Données partagées entre les postes' : 'Données enregistrées sur ce poste'} · {new Date().toLocaleDateString('fr-FR')}
      </span>
    </footer>
  )
}
FIN_DU_FICHIER
echo "OK src/shell/StatusBar.tsx"

cat > src/shell/TopBar.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import Icon from './icons'
import type { PageId } from '../types'
import { DOC_LABELS, type DocKind } from '../documents/types'
import { useAccess } from '../access/context'
import { ROLE_LABELS } from '../access/types'

export interface Notification {
  id: string
  text: string
  severity: 'danger' | 'warning' | 'info'
  page: PageId
}

interface Props {
  companyName: string
  notifications: Notification[]
  onSearch: () => void
  onNavigate: (page: PageId) => void
  onCreate: (kind: DocKind) => void
  onLock: () => void
  onLogout: () => void
}

const CREATE: { kind: DocKind; label: string }[] = [
  { kind: 'quote', label: 'Devis' },
  { kind: 'order', label: 'Bon de commande' },
  { kind: 'delivery', label: 'Bon de livraison' },
  { kind: 'invoice', label: 'Facture' },
  { kind: 'credit', label: 'Avoir' },
  { kind: 'purchase', label: 'Commande fournisseur' },
  { kind: 'receipt', label: 'Bon de réception' },
  { kind: 'bill', label: 'Facture fournisseur' },
]

const isMac = typeof navigator !== 'undefined' && /Mac/.test(navigator.platform)

/** Barre supérieure : dossier, recherche globale, création rapide, notifications */
export default function TopBar({ companyName, notifications, onSearch, onNavigate, onCreate, onLock, onLogout }: Props) {
  const [menu, setMenu] = useState<'create' | 'notif' | 'user' | null>(null)
  const access = useAccess()
  const creatable = CREATE.filter((c) => access.level(DOC_LABELS[c.kind].side === 'sale' ? 'sales' : 'purchases') === 'write')
  const toggle = (m: 'create' | 'notif' | 'user') => setMenu((cur) => (cur === m ? null : m))
  const danger = notifications.filter((n) => n.severity === 'danger').length

  return (
    <header className="erp-topbar no-print">
      <button type="button" className="erp-brand" onClick={() => onNavigate('home')}>
        <span className="erp-logo">PP</span>
        <span>
          ProfitPilot <small>ERP</small>
        </span>
      </button>
      <span className="erp-dossier" title="Dossier ouvert">
        {companyName || 'Dossier sans nom'}
      </span>

      <button type="button" className="erp-search-trigger" onClick={onSearch}>
        <Icon name="search" />
        <span>Rechercher…</span>
        <kbd>{isMac ? '⌘' : 'Ctrl'} K</kbd>
      </button>

      <div className="erp-top-actions">
        {creatable.length > 0 && <div className="erp-menu-wrap">
          <button type="button" className="erp-create" onClick={() => toggle('create')} aria-expanded={menu === 'create'}>
            <Icon name="plus" /> Créer
          </button>
          {menu === 'create' && (
            <div className="erp-menu" onMouseLeave={() => setMenu(null)}>
              {creatable.map((c, i) => (
                <button
                  key={c.kind}
                  type="button"
                  className={i > 0 && DOC_LABELS[c.kind].side !== DOC_LABELS[creatable[i - 1].kind].side ? 'erp-menu-sep' : undefined}
                  onClick={() => {
                    setMenu(null)
                    onCreate(c.kind)
                  }}
                >
                  {c.label}
                </button>
              ))}
            </div>
          )}
        </div>}

        <div className="erp-menu-wrap">
          <button
            type="button"
            className="erp-icon-btn"
            title="Notifications"
            onClick={() => toggle('notif')}
            aria-expanded={menu === 'notif'}
          >
            <Icon name="bell" size={18} />
            {notifications.length > 0 && (
              <span className={`erp-notif-count ${danger ? 'erp-notif-danger' : ''}`}>{notifications.length}</span>
            )}
          </button>
          {menu === 'notif' && (
            <div className="erp-menu erp-notif-menu" onMouseLeave={() => setMenu(null)}>
              <div className="erp-menu-title">Notifications</div>
              {notifications.length === 0 ? (
                <p className="erp-menu-empty">Rien à signaler.</p>
              ) : (
                notifications.map((n) => (
                  <button
                    key={n.id}
                    type="button"
                    className={`erp-notif erp-notif-${n.severity}`}
                    onClick={() => {
                      setMenu(null)
                      onNavigate(n.page)
                    }}
                  >
                    {n.text}
                  </button>
                ))
              )}
            </div>
          )}
        </div>

        {access.level('settings') !== 'none' && (
          <button type="button" className="erp-icon-btn" title="Paramètres" onClick={() => onNavigate('company')}>
            <Icon name="settings" size={18} />
          </button>
        )}

        {access.user ? (
          <div className="erp-menu-wrap">
            <button type="button" className="erp-user" onClick={() => toggle('user')} aria-expanded={menu === 'user'}>
              <span className="login-avatar">{access.user.name.slice(0, 1).toUpperCase()}</span>
              <span>
                {access.user.name}
                <small>{ROLE_LABELS[access.user.role]}</small>
              </span>
            </button>
            {menu === 'user' && (
              <div className="erp-menu" onMouseLeave={() => setMenu(null)}>
                <div className="erp-menu-title">{access.user.login}</div>
                {access.isAdmin && (
                  <>
                    <button type="button" onClick={() => { setMenu(null); onNavigate('users') }}>
                      Utilisateurs et droits
                    </button>
                    <button type="button" onClick={() => { setMenu(null); onNavigate('audit') }}>
                      Journal d'activité
                    </button>
                  </>
                )}
                <button type="button" className="erp-menu-sep" onClick={() => { setMenu(null); onLock() }}>
                  Verrouiller la session
                </button>
                <button type="button" onClick={() => { setMenu(null); onLogout() }}>
                  Se déconnecter
                </button>
              </div>
            )}
          </div>
        ) : (
          <button type="button" className="erp-create erp-secure" onClick={() => onNavigate('users')} title="Protéger l'accès par des comptes utilisateurs">
            Sécuriser l'accès
          </button>
        )}
      </div>
    </header>
  )
}
FIN_DU_FICHIER
echo "OK src/shell/TopBar.tsx"

cat > src/shell/WorkTabs.tsx <<'FIN_DU_FICHIER'
import Icon from './icons'
import { PAGE_LABELS } from './navigation'
import type { PageId } from '../types'

interface Props {
  tabs: PageId[]
  current: PageId
  onOpen: (page: PageId) => void
  onClose: (page: PageId) => void
}

/** Onglets des écrans ouverts, pour passer de l'un à l'autre sans repasser par le menu */
export default function WorkTabs({ tabs, current, onOpen, onClose }: Props) {
  if (tabs.length <= 1) return null
  return (
    <div className="erp-tabs no-print" role="tablist">
      {tabs.map((t) => (
        <div key={t} className={`erp-tab ${t === current ? 'erp-tab-active' : ''}`} role="tab" aria-selected={t === current}>
          <button type="button" className="erp-tab-label" onClick={() => onOpen(t)}>
            {PAGE_LABELS[t]}
          </button>
          <button type="button" className="erp-tab-close" title="Fermer l'onglet" onClick={() => onClose(t)}>
            <Icon name="close" size={12} />
          </button>
        </div>
      ))}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/shell/WorkTabs.tsx"

cat > src/shell/icons.tsx <<'FIN_DU_FICHIER'
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
FIN_DU_FICHIER
echo "OK src/shell/icons.tsx"

cat > src/shell/navigation.ts <<'FIN_DU_FICHIER'
import type { PageId } from '../types'

export type ModuleId = 'home' | 'sales' | 'purchases' | 'stock' | 'finance' | 'analysis' | 'settings'

export interface ModuleDef {
  id: ModuleId
  label: string
  /** Pages du module, regroupées par rubrique dans le menu de gauche */
  groups: { title: string; pages: PageId[] }[]
}

/** Plan de l'application, découpée en modules comme un ERP */
export const MODULES: ModuleDef[] = [
  { id: 'home', label: 'Accueil', groups: [{ title: 'Accueil', pages: ['home'] }] },
  {
    id: 'sales',
    label: 'Ventes',
    groups: [
      { title: 'Pièces de vente', pages: ['quotes', 'orders', 'deliveries', 'invoices', 'credits'] },
      { title: 'Suivi', pages: ['depots', 'clients'] },
    ],
  },
  {
    id: 'purchases',
    label: 'Achats',
    groups: [
      { title: "Pièces d'achat", pages: ['purchases', 'receipts', 'bills'] },
      { title: 'Tiers', pages: ['suppliers'] },
    ],
  },
  {
    id: 'stock',
    label: 'Stocks',
    groups: [
      { title: 'Articles', pages: ['catalog', 'kits', 'import'] },
      { title: 'Stock', pages: ['stock', 'alerts', 'movements', 'inventory'] },
      { title: 'Traçabilité', pages: ['lots'] },
    ],
  },
  {
    id: 'finance',
    label: 'Finance',
    groups: [
      { title: 'Trésorerie', pages: ['schedule'] },
      { title: 'Fiscalité', pages: ['vat'] },
    ],
  },
  {
    id: 'analysis',
    label: 'Pilotage',
    groups: [
      { title: 'Tableaux de bord', pages: ['dashboard', 'stats'] },
      { title: 'Rentabilité', pages: ['products', 'breakeven', 'recommendations'] },
      { title: 'Simulation', pages: ['simulator', 'compare', 'decision'] },
    ],
  },
  {
    id: 'settings',
    label: 'Paramètres',
    groups: [
      { title: 'Dossier', pages: ['company', 'backup'] },
      { title: 'Administration', pages: ['users', 'audit', 'sync'] },
    ],
  },
]

/** Libellés courts (menu, onglets) */
export const PAGE_LABELS: Record<PageId, string> = {
  home: 'Accueil',
  dashboard: 'Tableau de bord',
  stats: 'Statistiques ventes',
  products: 'Rentabilité produits',
  breakeven: 'Résultat & seuil',
  recommendations: 'Recommandations',
  simulator: 'Simulateur',
  compare: 'Comparaison',
  decision: 'Garder ou abandonner',
  catalog: 'Articles',
  stock: 'État du stock',
  alerts: 'Alertes stock',
  movements: 'Mouvements',
  inventory: 'Inventaire',
  lots: 'Lots & traçabilité',
  kits: 'Kits',
  import: 'Import CSV',
  quotes: 'Devis',
  orders: 'Bons de commande',
  deliveries: 'Bons de livraison',
  depots: 'Dépôts cliniques',
  invoices: 'Factures',
  credits: 'Avoirs',
  clients: 'Clients',
  purchases: 'Commandes fournisseurs',
  receipts: 'Réceptions',
  bills: 'Factures fournisseurs',
  suppliers: 'Fournisseurs',
  schedule: 'Échéancier & trésorerie',
  vat: 'Déclaration de TVA',
  company: 'Société & mise en page',
  backup: 'Sauvegarde',
  users: 'Utilisateurs & droits',
  audit: "Journal d'activité",
  sync: 'Multi-postes',
}

/** Pages réservées à l'administrateur */
export const ADMIN_PAGES: PageId[] = ['users', 'audit', 'sync']

export function moduleOf(page: PageId): ModuleDef {
  return MODULES.find((m) => m.groups.some((g) => g.pages.includes(page))) ?? MODULES[0]
}
FIN_DU_FICHIER
echo "OK src/shell/navigation.ts"

cat > src/shell/shell.css <<'FIN_DU_FICHIER'
/* Structure « ERP » : barre supérieure, ruban des modules, menu du module, onglets, barre d'état */
.layout.erp {
  display: grid !important;
  grid-template-rows: auto auto 1fr auto;
  height: 100vh;
  min-height: 0;
  overflow: hidden;
}
.erp-body { display: flex; min-height: 0; overflow: hidden; }
.layout.erp .sidebar { position: static; height: auto; overflow-y: auto; width: 220px; }
.layout.erp .sidebar .brand {
  background: linear-gradient(#f7f9fb, #e9eef4);
  color: var(--pp-blue);
  font-size: 14px;
  padding: 11px 16px;
  border-bottom: 1px solid var(--pp-border);
}
.layout.erp .content { overflow-y: auto; min-height: 0; padding-top: 0; }

/* ---------- Barre supérieure ---------- */
.erp-topbar {
  display: flex;
  align-items: center;
  gap: 14px;
  height: 46px;
  padding: 0 14px;
  background: #13293d;
  color: #e2e8f0;
  font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  font-size: 13px;
}
.erp-topbar button { font: inherit; color: inherit; background: none; border: 0; cursor: pointer; }
.erp-brand { display: flex; align-items: center; gap: 8px; font-weight: 700; font-size: 15px; color: #fff !important; }
.erp-brand small { font-weight: 400; color: #93c5fd; margin-left: 2px; }
.erp-logo {
  display: grid;
  place-items: center;
  width: 28px;
  height: 28px;
  border-radius: 4px;
  background: #2b6cb0;
  font-size: 12px;
  letter-spacing: 0.5px;
}
.erp-dossier {
  padding: 3px 10px;
  border-left: 1px solid #334e68;
  color: #cbd5e1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 260px;
}
.erp-search-trigger {
  flex: 1;
  max-width: 520px;
  display: flex;
  align-items: center;
  gap: 8px;
  height: 30px;
  padding: 0 10px !important;
  background: #1e3a52 !important;
  border: 1px solid #335a7a !important;
  border-radius: 4px;
  color: #94a3b8 !important;
  text-align: left;
}
.erp-search-trigger:hover { border-color: #60a5fa !important; }
.erp-search-trigger span { flex: 1; }
.erp-search-trigger kbd {
  font-family: inherit;
  font-size: 11px;
  padding: 1px 6px;
  border: 1px solid #335a7a;
  border-radius: 3px;
  color: #cbd5e1;
}
.erp-top-actions { margin-left: auto; display: flex; align-items: center; gap: 6px; }
.erp-create {
  display: flex;
  align-items: center;
  gap: 5px;
  height: 30px;
  padding: 0 12px !important;
  background: #2b6cb0 !important;
  border-radius: 4px;
  color: #fff !important;
  font-weight: 600 !important;
}
.erp-create:hover { background: #3a7fcb !important; }
.erp-icon-btn { position: relative; display: grid; place-items: center; width: 34px; height: 34px; border-radius: 4px; }
.erp-icon-btn:hover { background: #1e3a52 !important; }
.erp-notif-count {
  position: absolute;
  top: 2px;
  right: 0;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  border-radius: 8px;
  background: #d97706;
  color: #fff;
  font-size: 10px;
  font-weight: 700;
  line-height: 16px;
}
.erp-notif-danger { background: #dc2626; }

.erp-menu-wrap { position: relative; }
.erp-menu {
  position: absolute;
  right: 0;
  top: calc(100% + 6px);
  z-index: 60;
  min-width: 220px;
  padding: 4px 0;
  background: #fff;
  color: var(--pp-text);
  border: 1px solid var(--pp-border);
  border-radius: 4px;
  box-shadow: 0 10px 28px rgba(15, 23, 42, 0.25);
}
.erp-menu button { display: block; width: 100%; padding: 7px 14px !important; text-align: left; color: var(--pp-text) !important; }
.erp-menu button:hover { background: var(--pp-hover) !important; }
.erp-menu .erp-menu-sep { border-top: 1px solid var(--pp-border-soft) !important; margin-top: 4px; }
.erp-menu-title { padding: 6px 14px; font-size: 11px; font-weight: 700; text-transform: uppercase; color: var(--pp-muted); }
.erp-menu-empty { padding: 6px 14px; margin: 0; color: var(--pp-muted); }
.erp-notif-menu { min-width: 320px; }
.erp-notif { border-left: 3px solid transparent !important; }
.erp-notif-danger { border-left-color: #dc2626 !important; }
.erp-notif-warning { border-left-color: #d97706 !important; }
.erp-notif-info { border-left-color: #2b6cb0 !important; }

/* ---------- Ruban des modules ---------- */
.erp-modules {
  display: flex;
  gap: 2px;
  padding: 0 10px;
  background: linear-gradient(#f9fbfc, #e7ecf2);
  border-bottom: 1px solid var(--pp-border);
  overflow-x: auto;
}
.erp-module {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 9px 14px 8px;
  background: none;
  border: 0;
  border-bottom: 3px solid transparent;
  font: inherit;
  font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  font-size: 13px;
  color: var(--pp-title);
  cursor: pointer;
  white-space: nowrap;
}
.erp-module:hover { background: rgba(43, 108, 176, 0.08); }
.erp-module-active { border-bottom-color: var(--pp-blue-2); color: var(--pp-blue); font-weight: 700; background: #fff; }

/* ---------- Onglets de travail et fil d'Ariane ---------- */
.erp-tabs {
  display: flex;
  gap: 2px;
  margin: 0 -20px;
  padding: 6px 20px 0;
  background: #dfe5ec;
  border-bottom: 1px solid var(--pp-border);
  overflow-x: auto;
}
.erp-tab {
  display: flex;
  align-items: center;
  background: #eef2f6;
  border: 1px solid var(--pp-border);
  border-bottom: 0;
  border-radius: 4px 4px 0 0;
  font-size: 12.5px;
}
.erp-tab-active { background: #fff; position: relative; top: 1px; }
.layout .content .erp-tab button { background: none; border: 0; box-shadow: none; padding: 5px 8px; }
.layout .content .erp-tab-label { color: var(--pp-title); white-space: nowrap; }
.erp-tab-active .erp-tab-label { font-weight: 600; color: var(--pp-blue); }
.layout .content .erp-tab-close { padding: 5px 6px 5px 0; color: var(--pp-muted); }
.layout .content .erp-tab-close:hover { color: var(--pp-danger); background: none; }

.erp-breadcrumb { display: flex; align-items: center; gap: 6px; padding: 8px 0 0; font-size: 12px; color: var(--pp-muted); }
.layout .content .erp-breadcrumb button { background: none; border: 0; padding: 0; color: var(--pp-blue-2); box-shadow: none; font-size: 12px; }
.layout .content .erp-breadcrumb button:hover { text-decoration: underline; background: none; }
.erp-breadcrumb strong { color: var(--pp-text); font-weight: 600; }
.layout.erp .content > h1 { margin-top: 4px; }

/* ---------- Barre d'état ---------- */
.erp-status {
  display: flex;
  gap: 18px;
  align-items: center;
  height: 24px;
  padding: 0 14px;
  background: #13293d;
  color: #a9b8c8;
  font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  font-size: 11.5px;
  white-space: nowrap;
  overflow: hidden;
}
.erp-status-warn { color: #fbbf24; }
.erp-status-right { margin-left: auto; }

/* ---------- Recherche globale ---------- */
.erp-search-backdrop {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: flex;
  justify-content: center;
  align-items: flex-start;
  padding-top: 12vh;
  background: rgba(15, 23, 42, 0.45);
}
.erp-search {
  width: min(680px, calc(100vw - 32px));
  background: #fff;
  border-radius: 6px;
  box-shadow: 0 20px 50px rgba(15, 23, 42, 0.35);
  overflow: hidden;
  font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
}
.erp-search input {
  width: 100%;
  box-sizing: border-box;
  padding: 14px 16px;
  border: 0;
  border-bottom: 1px solid var(--pp-border);
  font-size: 15px;
  outline: none;
}
.erp-search-results { max-height: 55vh; overflow-y: auto; padding: 4px 0; }
.erp-search-hint { margin: 0; padding: 14px 16px; color: var(--pp-muted); font-size: 12.5px; }
.erp-search-hit {
  display: grid;
  grid-template-columns: 130px 1fr;
  grid-template-rows: auto auto;
  column-gap: 12px;
  width: 100%;
  padding: 7px 16px;
  background: none;
  border: 0;
  text-align: left;
  cursor: pointer;
  font: inherit;
}
.erp-search-hit-active { background: var(--pp-hover); }
.erp-search-kind { grid-row: span 2; align-self: center; font-size: 11px; font-weight: 700; text-transform: uppercase; color: var(--pp-muted); }
.erp-search-title { font-size: 13.5px; color: var(--pp-text); font-weight: 600; }
.erp-search-sub { font-size: 12px; color: var(--pp-muted); }

/* ---------- Accueil ---------- */
.erp-home { padding-top: 6px; }
.erp-home-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  flex-wrap: wrap;
  margin: 6px 0 14px;
}
.erp-home-head h2 { margin: 0; font-size: 20px; color: var(--pp-blue) !important; }
.erp-home-head p { margin: 2px 0 0; color: var(--pp-muted); text-transform: none; }
.erp-quick { display: flex; gap: 6px; flex-wrap: wrap; }
.erp-tile-group { margin-bottom: 16px; }
.erp-tile-group h3 {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0 0 8px;
  font-size: 13px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--pp-title);
}
.erp-tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }
.layout .content .erp-tile {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 4px;
  min-height: 104px;
  padding: 12px 14px;
  background: #fff;
  border: 1px solid var(--pp-border);
  border-top: 3px solid var(--pp-blue-2);
  border-radius: 4px;
  text-align: left;
  cursor: pointer;
  transition: box-shadow 0.15s, transform 0.15s;
}
.layout .content .erp-tile:hover { background: #fff; box-shadow: 0 6px 16px rgba(15, 23, 42, 0.12); transform: translateY(-1px); }
.layout .content .erp-tile-danger { border-top-color: #dc2626; }
.layout .content .erp-tile-warning { border-top-color: #d97706; }
.layout .content .erp-tile-good { border-top-color: #16a34a; }
.erp-tile-title { font-size: 12px; font-weight: 600; color: var(--pp-title); }
.erp-tile-value { font-size: 24px; font-weight: 700; color: var(--pp-text); }
.erp-tile-danger .erp-tile-value { color: #b91c1c; }
.erp-tile-sub { font-size: 11.5px; color: var(--pp-muted); }

@media print {
  .layout.erp { display: block !important; height: auto; overflow: visible; }
  .erp-body { display: block; overflow: visible; }
  .layout.erp .content { overflow: visible; }
}

/* L'application occupe toute la fenêtre */
body:has(.layout.erp) { margin: 0; }
@media screen {
  .layout.erp .print-only { display: none; }
}
.erp-secure { background: #b45309 !important; }
.erp-secure:hover { background: #d97706 !important; }
.erp-status-sync { background: none; border: 0; padding: 0; font: inherit; color: inherit; cursor: pointer; }
.erp-status-ok { color: #86efac; }
.erp-status-error { color: #fca5a5; }
FIN_DU_FICHIER
echo "OK src/shell/shell.css"

cat > src/access/AuditPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { downloadCsv } from '../documents/csv'
import type { AuditEntry } from './types'
import '../documents/documents.css'

interface Props {
  entries: AuditEntry[]
}

/** Journal d'activité : qui a fait quoi, et quand (réservé à l'administrateur) */
export default function AuditPage({ entries }: Props) {
  const [query, setQuery] = useState('')
  const [user, setUser] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const users = useMemo(() => [...new Set(entries.map((e) => e.user))].sort(), [entries])

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase()
    return entries
      .filter((e) => !user || e.user === user)
      .filter((e) => (!from || e.at.slice(0, 10) >= from) && (!to || e.at.slice(0, 10) <= to))
      .filter((e) => !q || `${e.action} ${e.detail}`.toLowerCase().includes(q))
      .slice()
      .reverse()
  }, [entries, query, user, from, to])

  const fmt = (iso: string) => new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })

  return (
    <div>
      <div className="doc-toolbar">
        <input className="doc-search" placeholder="Rechercher : action, n° de pièce, client…" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select value={user} onChange={(e) => setUser(e.target.value)}>
          <option value="">Tous les utilisateurs</option>
          {users.map((u) => (
            <option key={u} value={u}>
              {u}
            </option>
          ))}
        </select>
        <label>
          Du <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
        </label>
        <label>
          au <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
        </label>
        <button type="button" onClick={() => downloadCsv('journal-activite.csv', [['Date', 'Utilisateur', 'Action', 'Détail'], ...rows.map((e) => [fmt(e.at), e.user, e.action, e.detail])])}>
          Exporter (CSV)
        </button>
        <span className="doc-count">{rows.length} action(s)</span>
      </div>
      {rows.length === 0 ? (
        <p className="doc-empty">Aucune action enregistrée.</p>
      ) : (
        <div className="doc-table-wrap">
          <table className="doc-table">
            <thead>
              <tr>
                <th>Date et heure</th>
                <th>Utilisateur</th>
                <th>Action</th>
                <th>Détail</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((e) => (
                <tr key={e.id}>
                  <td>{fmt(e.at)}</td>
                  <td>{e.user}</td>
                  <td>
                    <strong>{e.action}</strong>
                  </td>
                  <td>{e.detail}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/access/AuditPage.tsx"

cat > src/access/LoginScreen.tsx <<'FIN_DU_FICHIER'
import { useState, type FormEvent } from 'react'
import { hashPin } from './crypto'
import { ROLE_LABELS, type User } from './types'
import './access.css'

interface Props {
  users: User[]
  companyName: string
  logo?: string
  /** Écran de verrouillage : l'utilisateur est déjà choisi */
  lockedUser?: User
  onLogin: (user: User) => void
}

const MAX_TRIES = 5
const COOLDOWN_MS = 30_000

/** Connexion par utilisateur et code PIN */
export default function LoginScreen({ users, companyName, logo, lockedUser, onLogin }: Props) {
  const active = users.filter((u) => u.active)
  const [selected, setSelected] = useState<User | null>(lockedUser ?? (active.length === 1 ? active[0] : null))
  const [pin, setPin] = useState('')
  const [error, setError] = useState('')
  const [tries, setTries] = useState(0)
  const [blockedUntil, setBlockedUntil] = useState(0)

  async function submit(e: FormEvent) {
    e.preventDefault()
    if (!selected) return
    if (Date.now() < blockedUntil) return setError('Trop de tentatives : patientez 30 secondes.')
    const hash = await hashPin(pin, selected.salt)
    if (hash === selected.pinHash) return onLogin(selected)
    const n = tries + 1
    setTries(n)
    setPin('')
    if (n >= MAX_TRIES) {
      setBlockedUntil(Date.now() + COOLDOWN_MS)
      setTries(0)
      setError('Code incorrect. Trop de tentatives : patientez 30 secondes.')
    } else setError(`Code incorrect (${MAX_TRIES - n} essai(s) restant(s)).`)
  }

  return (
    <div className="login-screen">
      <div className="login-card">
        <div className="login-head">
          {logo ? <img src={logo} alt="" className="login-logo" /> : <span className="erp-logo">PP</span>}
          <div>
            <strong>ProfitPilot ERP</strong>
            <span>{companyName || 'Gestion commerciale'}</span>
          </div>
        </div>

        {!selected ? (
          <>
            <p className="login-title">Qui êtes-vous ?</p>
            <div className="login-users">
              {active.map((u) => (
                <button key={u.id} type="button" className="login-user" onClick={() => setSelected(u)}>
                  <span className="login-avatar">{u.name.slice(0, 1).toUpperCase()}</span>
                  <span>
                    <strong>{u.name}</strong>
                    <small>{ROLE_LABELS[u.role]}</small>
                  </span>
                </button>
              ))}
            </div>
          </>
        ) : (
          <form onSubmit={submit}>
            <p className="login-title">{lockedUser ? 'Session verrouillée' : 'Saisissez votre code'}</p>
            <div className="login-user login-user-selected">
              <span className="login-avatar">{selected.name.slice(0, 1).toUpperCase()}</span>
              <span>
                <strong>{selected.name}</strong>
                <small>{ROLE_LABELS[selected.role]}</small>
              </span>
            </div>
            <input
              className="login-pin"
              type="password"
              inputMode="numeric"
              autoComplete="current-password"
              placeholder="Code PIN"
              value={pin}
              autoFocus
              onChange={(e) => {
                setPin(e.target.value.replace(/\D/g, '').slice(0, 8))
                setError('')
              }}
            />
            {error && <p className="login-error">{error}</p>}
            <button type="submit" className="login-submit" disabled={pin.length < 4}>
              {lockedUser ? 'Déverrouiller' : 'Se connecter'}
            </button>
            {!lockedUser && active.length > 1 && (
              <button type="button" className="login-back" onClick={() => setSelected(null)}>
                ← Changer d'utilisateur
              </button>
            )}
            {lockedUser && (
              <button type="button" className="login-back" onClick={() => setSelected(null)}>
                Se connecter avec un autre compte
              </button>
            )}
          </form>
        )}
        <p className="login-foot">Le code PIN est demandé à chaque ouverture et après une période d'inactivité.</p>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/access/LoginScreen.tsx"

cat > src/access/ReadOnly.tsx <<'FIN_DU_FICHIER'
import type { ReactNode } from 'react'

/** Écran en lecture seule : bandeau d'information et champs désactivés si demandé */
export function ReadOnlyArea({ readOnly, lock, children }: { readOnly: boolean; lock: boolean; children: ReactNode }) {
  if (!readOnly) return <>{children}</>
  return (
    <>
      <p className="access-readonly-banner no-print">Lecture seule : vos droits ne permettent pas de modifier cet écran.</p>
      {lock ? (
        <fieldset disabled className="access-readonly">
          {children}
        </fieldset>
      ) : (
        children
      )}
    </>
  )
}

export function AccessDenied() {
  return (
    <div className="access-denied">
      <strong>Accès non autorisé</strong>
      Vos droits ne permettent pas d'ouvrir cet écran. Demandez à l'administrateur de modifier votre profil.
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/access/ReadOnly.tsx"

cat > src/access/UsersPage.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { useAccess } from './context'
import { hashPin, isValidPin, newSalt } from './crypto'
import {
  ACTIONS,
  ROLES,
  ROLE_LABELS,
  SECURED_MODULES,
  rolePermissions,
  type AccessSettings,
  type Level,
  type Permissions,
  type RoleId,
  type User,
} from './types'
import { frDate, newId } from '../documents/numbering'
import '../documents/documents.css'
import './access.css'

interface Props {
  users: User[]
  onChange: (users: User[]) => void
  settings: AccessSettings
  onSettingsChange: (settings: AccessSettings) => void
  /** Après création du premier administrateur : ouverture de sa session */
  onFirstAdmin: (user: User) => void
}

const LEVELS: { id: Level; label: string }[] = [
  { id: 'none', label: 'Aucun' },
  { id: 'read', label: 'Lecture' },
  { id: 'write', label: 'Modification' },
]

interface Draft {
  id: string
  name: string
  login: string
  role: RoleId
  permissions: Permissions
  active: boolean
  pin: string
  pin2: string
  isNew: boolean
}

/** Gestion des utilisateurs et de leurs droits (réservée à l'administrateur) */
export default function UsersPage({ users, onChange, settings, onSettingsChange, onFirstAdmin }: Props) {
  const access = useAccess()
  const firstRun = users.length === 0
  const [draft, setDraft] = useState<Draft | null>(() =>
    firstRun
      ? { id: newId(), name: '', login: 'admin', role: 'admin', permissions: rolePermissions('admin'), active: true, pin: '', pin2: '', isNew: true }
      : null,
  )
  const [error, setError] = useState('')

  const admins = users.filter((u) => u.role === 'admin' && u.active)

  function edit(u: User) {
    setDraft({ id: u.id, name: u.name, login: u.login, role: u.role, permissions: structuredClone(u.permissions), active: u.active, pin: '', pin2: '', isNew: false })
    setError('')
  }

  function setRole(role: RoleId) {
    if (!draft) return
    setDraft({ ...draft, role, permissions: role === 'custom' ? draft.permissions : rolePermissions(role) })
  }

  async function save() {
    if (!draft) return
    const name = draft.name.trim()
    const login = draft.login.trim().toLowerCase()
    if (!name) return setError('Indiquez le nom.')
    if (!/^[a-z0-9._-]{2,30}$/.test(login)) return setError('Identifiant : 2 à 30 caractères (lettres, chiffres, . _ -).')
    if (users.some((u) => u.id !== draft.id && u.login === login)) return setError('Cet identifiant est déjà utilisé.')
    if (draft.isNew || draft.pin) {
      if (!isValidPin(draft.pin)) return setError('Le code PIN doit comporter 4 à 8 chiffres.')
      if (draft.pin !== draft.pin2) return setError('Les deux codes PIN ne correspondent pas.')
    }
    const old = users.find((u) => u.id === draft.id)
    // On garde toujours au moins un administrateur actif
    const removesLastAdmin = old?.role === 'admin' && admins.length === 1 && (draft.role !== 'admin' || !draft.active)
    if (removesLastAdmin) return setError('Il doit rester au moins un administrateur actif.')

    const salt = draft.pin ? newSalt() : (old?.salt ?? newSalt())
    const pinHash = draft.pin ? await hashPin(draft.pin, salt) : (old?.pinHash ?? '')
    const user: User = {
      id: draft.id,
      name,
      login,
      role: draft.role,
      permissions: draft.role === 'admin' ? rolePermissions('admin') : draft.permissions,
      active: draft.active,
      salt,
      pinHash,
      createdAt: old?.createdAt ?? new Date().toISOString(),
      lastLogin: old?.lastLogin,
    }
    onChange(old ? users.map((u) => (u.id === user.id ? user : u)) : [...users, user])
    access.log(old ? 'Utilisateur modifié' : 'Utilisateur créé', `${name} (${ROLE_LABELS[user.role]})${draft.pin && old ? ', code PIN changé' : ''}`)
    setDraft(null)
    setError('')
    if (firstRun) onFirstAdmin(user)
  }

  function remove(u: User) {
    if (u.role === 'admin' && admins.length === 1) return setError('Impossible de supprimer le dernier administrateur.')
    if (u.id === access.user?.id) return setError('Vous ne pouvez pas supprimer votre propre compte.')
    if (!confirm(`Supprimer le compte de ${u.name} ?`)) return
    onChange(users.filter((x) => x.id !== u.id))
    access.log('Utilisateur supprimé', u.name)
  }

  if (draft) {
    const isAdminRole = draft.role === 'admin'
    const setModule = (m: keyof Permissions['modules'], level: Level) =>
      setDraft({ ...draft, role: 'custom', permissions: { ...draft.permissions, modules: { ...draft.permissions.modules, [m]: level } } })
    const setAction = (a: keyof Permissions['actions'], on: boolean) =>
      setDraft({ ...draft, role: 'custom', permissions: { ...draft.permissions, actions: { ...draft.permissions.actions, [a]: on } } })
    return (
      <div>
        {firstRun && (
          <p className="doc-info">
            Créez d'abord le compte <strong>administrateur</strong>. Ensuite, l'application demandera un code PIN à chaque
            ouverture et vous pourrez créer les comptes de vos employés.
          </p>
        )}
        <div className="doc-editor-head">
          <h2>{draft.isNew ? (firstRun ? 'Compte administrateur' : 'Nouvel utilisateur') : draft.name}</h2>
          <div className="doc-editor-actions">
            <button type="button" className="btn-primary" onClick={save}>
              Enregistrer
            </button>
            {!firstRun && (
              <button type="button" onClick={() => setDraft(null)}>
                Fermer
              </button>
            )}
          </div>
        </div>

        <fieldset className="doc-panel">
          <legend>Identité et connexion</legend>
          <div className="doc-grid">
            <label>
              Nom affiché
              <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="ex. Karim Bennani" />
            </label>
            <label>
              Identifiant
              <input value={draft.login} onChange={(e) => setDraft({ ...draft, login: e.target.value })} />
            </label>
            <label>
              {draft.isNew ? 'Code PIN (4 à 8 chiffres)' : 'Nouveau code PIN (laisser vide pour garder)'}
              <input type="password" inputMode="numeric" value={draft.pin} onChange={(e) => setDraft({ ...draft, pin: e.target.value.replace(/\D/g, '').slice(0, 8) })} />
            </label>
            <label>
              Confirmer le code PIN
              <input type="password" inputMode="numeric" value={draft.pin2} onChange={(e) => setDraft({ ...draft, pin2: e.target.value.replace(/\D/g, '').slice(0, 8) })} />
            </label>
            {!firstRun && (
              <label className="doc-check">
                <input type="checkbox" checked={draft.active} onChange={(e) => setDraft({ ...draft, active: e.target.checked })} />
                Compte actif
              </label>
            )}
          </div>
        </fieldset>

        {!firstRun && (
          <fieldset className="doc-panel">
            <legend>Profil et droits</legend>
            <div className="access-roles">
              {ROLES.map((r) => (
                <label key={r.id} className={`doc-mode ${draft.role === r.id ? 'doc-mode-active' : ''}`}>
                  <input type="radio" name="role" checked={draft.role === r.id} onChange={() => setRole(r.id)} />
                  <span>
                    <strong>{r.label}</strong>
                    <small>{r.description}</small>
                  </span>
                </label>
              ))}
              <label className={`doc-mode ${draft.role === 'custom' ? 'doc-mode-active' : ''}`}>
                <input type="radio" name="role" checked={draft.role === 'custom'} onChange={() => setRole('custom')} />
                <span>
                  <strong>Personnalisé</strong>
                  <small>Réglez chaque droit ci-dessous</small>
                </span>
              </label>
            </div>

            {isAdminRole ? (
              <p className="doc-info">L'administrateur a tous les droits, gère les utilisateurs et consulte le journal d'activité.</p>
            ) : (
              <div className="access-matrix">
                <table className="doc-table">
                  <thead>
                    <tr>
                      <th>Module</th>
                      {LEVELS.map((l) => (
                        <th key={l.id} className="access-center">
                          {l.label}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {SECURED_MODULES.map((m) => (
                      <tr key={m.id}>
                        <td>{m.label}</td>
                        {LEVELS.map((l) => (
                          <td key={l.id} className="access-center">
                            <input
                              type="radio"
                              name={`mod-${m.id}`}
                              aria-label={`${m.label} : ${l.label}`}
                              checked={draft.permissions.modules[m.id] === l.id}
                              onChange={() => setModule(m.id, l.id)}
                            />
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div className="access-actions">
                  <strong>Actions autorisées</strong>
                  {ACTIONS.map((a) => (
                    <label key={a.id} className="doc-check">
                      <input type="checkbox" checked={draft.permissions.actions[a.id]} onChange={(e) => setAction(a.id, e.target.checked)} />
                      <span>
                        {a.label} <small>({a.hint})</small>
                      </span>
                    </label>
                  ))}
                </div>
              </div>
            )}
          </fieldset>
        )}
        {error && <p className="doc-error">{error}</p>}
      </div>
    )
  }

  return (
    <div>
      <div className="doc-toolbar">
        <button
          type="button"
          className="btn-primary"
          onClick={() =>
            setDraft({ id: newId(), name: '', login: '', role: 'sales', permissions: rolePermissions('sales'), active: true, pin: '', pin2: '', isNew: true })
          }
        >
          + Nouvel utilisateur
        </button>
        <label>
          Verrouillage automatique après{' '}
          <select value={settings.lockMinutes} onChange={(e) => onSettingsChange({ lockMinutes: Number(e.target.value) })}>
            {[0, 5, 10, 15, 30, 60].map((m) => (
              <option key={m} value={m}>
                {m === 0 ? 'jamais' : `${m} min d'inactivité`}
              </option>
            ))}
          </select>
        </label>
        <span className="doc-count">{users.length} compte(s)</span>
      </div>
      {error && <p className="doc-error">{error}</p>}

      <table className="doc-table">
        <thead>
          <tr>
            <th>Nom</th>
            <th>Identifiant</th>
            <th>Profil</th>
            {SECURED_MODULES.map((m) => (
              <th key={m.id} className="access-center">
                {m.label}
              </th>
            ))}
            <th>Dernière connexion</th>
            <th>État</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id}>
              <td>
                <button type="button" className="doc-link" onClick={() => edit(u)}>
                  {u.name}
                </button>
                {u.id === access.user?.id && <small> (vous)</small>}
              </td>
              <td>{u.login}</td>
              <td>{ROLE_LABELS[u.role]}</td>
              {SECURED_MODULES.map((m) => {
                const level = u.role === 'admin' ? 'write' : u.permissions.modules[m.id]
                return (
                  <td key={m.id} className="access-center">
                    <span className={`access-level access-${level}`}>{level === 'write' ? 'M' : level === 'read' ? 'L' : '—'}</span>
                  </td>
                )
              })}
              <td>{u.lastLogin ? `${frDate(u.lastLogin.slice(0, 10))} ${u.lastLogin.slice(11, 16)}` : 'jamais'}</td>
              <td>
                <span className={`doc-badge ${u.active ? 'doc-badge-paid' : 'doc-badge-cancelled'}`}>{u.active ? 'Actif' : 'Désactivé'}</span>
              </td>
              <td className="doc-actions">
                <button type="button" onClick={() => edit(u)}>
                  Modifier
                </button>
                <button type="button" onClick={() => remove(u)}>
                  Supprimer
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="doc-count">M = modification · L = lecture seule · — = pas d'accès. Les changements de droits s'appliquent immédiatement.</p>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/access/UsersPage.tsx"

cat > src/access/access.css <<'FIN_DU_FICHIER'
/* ---------- Connexion ---------- */
.login-screen {
  position: fixed;
  inset: 0;
  display: grid;
  place-items: center;
  background: linear-gradient(160deg, #13293d 0%, #1f4e79 60%, #2b6cb0 100%);
  font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  z-index: 200;
}
.login-card {
  width: min(420px, calc(100vw - 32px));
  padding: 26px 28px 20px;
  background: #fff;
  border-radius: 8px;
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.35);
  color: #1e293b;
}
.login-head { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
.login-head .erp-logo { width: 40px; height: 40px; font-size: 15px; color: #fff; }
.login-head strong { display: block; font-size: 17px; color: #1f4e79; }
.login-head span { font-size: 13px; color: #5b6b7d; }
.login-logo { max-height: 44px; max-width: 120px; object-fit: contain; }
.login-title { margin: 0 0 10px; font-weight: 600; }
.login-users { display: flex; flex-direction: column; gap: 6px; max-height: 50vh; overflow-y: auto; }
.login-user {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 8px 10px;
  background: #f6f8fa;
  border: 1px solid #d5dce4;
  border-radius: 6px;
  text-align: left;
  cursor: pointer;
  font: inherit;
}
.login-user:hover { border-color: #2b6cb0; background: #eef5fc; }
.login-user span:last-child { display: flex; flex-direction: column; }
.login-user small { color: #5b6b7d; }
.login-user-selected { cursor: default; margin-bottom: 12px; }
.login-avatar {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: #2b6cb0;
  color: #fff;
  font-weight: 700;
}
.login-pin {
  width: 100%;
  box-sizing: border-box;
  padding: 10px 12px;
  font-size: 22px;
  letter-spacing: 8px;
  text-align: center;
  border: 1px solid #aebbc9;
  border-radius: 6px;
}
.login-pin:focus { outline: none; border-color: #2b6cb0; box-shadow: 0 0 0 3px rgba(43, 108, 176, 0.2); }
.login-error { color: #b42318; font-size: 13px; margin: 8px 0 0; }
.login-submit {
  width: 100%;
  margin-top: 12px;
  padding: 10px;
  border: 0;
  border-radius: 6px;
  background: #2b6cb0;
  color: #fff;
  font: inherit;
  font-weight: 700;
  cursor: pointer;
}
.login-submit:disabled { opacity: 0.5; cursor: not-allowed; }
.login-back { width: 100%; margin-top: 8px; background: none; border: 0; color: #2b6cb0; cursor: pointer; font: inherit; }
.login-foot { margin: 16px 0 0; font-size: 11.5px; color: #8a97a6; text-align: center; }

/* ---------- Droits ---------- */
.access-roles { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 6px; margin-bottom: 12px; }
.access-matrix { display: grid; grid-template-columns: minmax(320px, 1fr) minmax(260px, 1fr); gap: 16px; align-items: start; }
.access-actions { display: flex; flex-direction: column; gap: 8px; }
.access-actions small { color: var(--pp-muted); }
.access-center { text-align: center !important; }
.access-level { display: inline-block; min-width: 22px; padding: 1px 5px; border-radius: 2px; font-size: 11px; font-weight: 700; }
.access-write { background: #dcfce7; color: #166534; }
.access-read { background: #e0ecfb; color: #1e40af; }
.access-none { color: #94a3b8; }

/* ---------- Lecture seule et accès refusé ---------- */
.access-readonly-banner {
  margin: 0 0 10px;
  padding: 6px 10px;
  background: #eef4ff;
  border: 1px solid #a4bcfd;
  border-left: 4px solid #2b6cb0;
  border-radius: 3px;
  font-size: 12.5px;
  color: #1e3a8a;
}
fieldset.access-readonly { border: 0; padding: 0; margin: 0; min-width: 0; }
.access-denied { margin-top: 40px; text-align: center; color: var(--pp-muted); }
.access-denied strong { display: block; font-size: 16px; color: var(--pp-text); margin-bottom: 6px; }

/* ---------- Menu utilisateur ---------- */
.erp-user { display: flex; align-items: center; gap: 8px; padding: 3px 8px !important; border-radius: 4px; }
.erp-user:hover { background: #1e3a52 !important; }
.erp-user .login-avatar { width: 26px; height: 26px; font-size: 12px; }
.erp-user small { display: block; font-size: 10.5px; color: #93a5b8; }
.erp-user span:last-child { text-align: left; line-height: 1.15; }
FIN_DU_FICHIER
echo "OK src/access/access.css"

cat > src/access/context.ts <<'FIN_DU_FICHIER'
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
FIN_DU_FICHIER
echo "OK src/access/context.ts"

cat > src/access/crypto.ts <<'FIN_DU_FICHIER'
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
FIN_DU_FICHIER
echo "OK src/access/crypto.ts"

cat > src/access/storage.ts <<'FIN_DU_FICHIER'
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
FIN_DU_FICHIER
echo "OK src/access/storage.ts"

cat > src/access/types.ts <<'FIN_DU_FICHIER'
import type { ModuleId } from '../shell/navigation'

/** Niveau d'accès à un module */
export type Level = 'none' | 'read' | 'write'

/** Modules soumis à droits (l'accueil est toujours visible) */
export type SecuredModule = Exclude<ModuleId, 'home'>

export const SECURED_MODULES: { id: SecuredModule; label: string }[] = [
  { id: 'sales', label: 'Ventes' },
  { id: 'purchases', label: 'Achats' },
  { id: 'stock', label: 'Stocks' },
  { id: 'finance', label: 'Finance' },
  { id: 'analysis', label: 'Pilotage' },
  { id: 'settings', label: 'Paramètres' },
]

export type Action = 'validate' | 'payments' | 'delete' | 'costs'

export const ACTIONS: { id: Action; label: string; hint: string }[] = [
  { id: 'validate', label: 'Valider les pièces', hint: 'devis, BL, factures, réceptions…' },
  { id: 'payments', label: 'Saisir les règlements', hint: 'encaissements clients et paiements fournisseurs' },
  { id: 'delete', label: 'Supprimer des brouillons', hint: 'et annuler des pièces validées' },
  { id: 'costs', label: 'Voir les coûts et les marges', hint: "prix d'achat, marges, valeur du stock" },
]

export interface Permissions {
  modules: Record<SecuredModule, Level>
  actions: Record<Action, boolean>
}

export type RoleId = 'admin' | 'sales' | 'warehouse' | 'accountant' | 'viewer' | 'custom'

export interface User {
  id: string
  name: string
  login: string
  role: RoleId
  pinHash: string
  salt: string
  active: boolean
  permissions: Permissions
  createdAt: string
  lastLogin?: string
}

export interface AuditEntry {
  id: string
  at: string // date ISO
  user: string
  action: string
  detail: string
}

export interface AccessSettings {
  /** Verrouillage automatique après inactivité (minutes, 0 = jamais) */
  lockMinutes: number
}

const all = (level: Level): Record<SecuredModule, Level> => ({
  sales: level,
  purchases: level,
  stock: level,
  finance: level,
  analysis: level,
  settings: level,
})

/** Profils types, modifiables ensuite utilisateur par utilisateur */
export const ROLES: { id: RoleId; label: string; description: string; permissions: Permissions }[] = [
  {
    id: 'admin',
    label: 'Administrateur',
    description: 'Accès complet, gestion des utilisateurs et du journal',
    permissions: { modules: all('write'), actions: { validate: true, payments: true, delete: true, costs: true } },
  },
  {
    id: 'sales',
    label: 'Commercial',
    description: 'Devis, commandes, BL et factures ; consulte le stock',
    permissions: {
      modules: { ...all('none'), sales: 'write', stock: 'read' },
      actions: { validate: true, payments: false, delete: true, costs: false },
    },
  },
  {
    id: 'warehouse',
    label: 'Magasinier',
    description: 'Stock, lots, réceptions, BL et dépôts',
    permissions: {
      modules: { ...all('none'), sales: 'read', purchases: 'write', stock: 'write' },
      actions: { validate: true, payments: false, delete: false, costs: false },
    },
  },
  {
    id: 'accountant',
    label: 'Comptable',
    description: 'Factures, règlements, achats, trésorerie et TVA',
    permissions: {
      modules: { ...all('read'), sales: 'write', purchases: 'write', finance: 'write', settings: 'none' },
      actions: { validate: true, payments: true, delete: false, costs: true },
    },
  },
  {
    id: 'viewer',
    label: 'Consultation',
    description: 'Voit tout, ne modifie rien',
    permissions: { modules: { ...all('read'), settings: 'none' }, actions: { validate: false, payments: false, delete: false, costs: false } },
  },
]

export const ROLE_LABELS: Record<RoleId, string> = {
  admin: 'Administrateur',
  sales: 'Commercial',
  warehouse: 'Magasinier',
  accountant: 'Comptable',
  viewer: 'Consultation',
  custom: 'Personnalisé',
}

export const rolePermissions = (role: RoleId): Permissions =>
  structuredClone((ROLES.find((r) => r.id === role) ?? ROLES[ROLES.length - 1]).permissions)
FIN_DU_FICHIER
echo "OK src/access/types.ts"

cat > src/sync/SyncPage.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { useAccess } from '../access/context'
import { downloadFile } from '../documents/csv'
import { createBackup } from '../documents/storage'
import { today } from '../documents/numbering'
import { decodeInvite, encodeInvite, isValidDossier, loadConfig, normalizeUrl, refHint, saveConfig, urlProblem, type SyncConfig } from './config'
import { AuthError, OfflineError, SupabaseRemote } from './remote'
import { createEngine, currentEngine, stopEngine, useSyncStatus } from './runtime'
import { clearState } from './state'
import '../documents/documents.css'
import './sync.css'

type Step =
  | { kind: 'form' }
  | { kind: 'choose'; config: SyncConfig; remoteCount: number; localCount: number }
  | { kind: 'working'; text: string }

function localDataCount(): number {
  const count = (key: string) => {
    try {
      const v = JSON.parse(localStorage.getItem(key) ?? '[]') as unknown
      return Array.isArray(v) ? v.length : 0
    } catch {
      return 0
    }
  }
  return count('profitpilot:documents:v1') + count('profitpilot:parties:v1') + count('profitpilot:lots:v1')
}

function explain(e: unknown): string {
  if (e instanceof OfflineError)
    return 'Serveur injoignable. Causes possibles : une faute dans l’adresse du projet (copiez-la depuis Supabase plutôt que de la taper), un bloqueur de publicité qui bloque supabase.co, ou pas de connexion Internet. Utilisez le lien « Tester cette adresse » ci-dessous.'
  if (e instanceof AuthError) return `Connexion refusée : ${e.message}. Vérifiez l’e-mail, le mot de passe et la clé publique.`
  const msg = e instanceof Error ? e.message : String(e)
  if (/relation .* does not exist|Could not find the table|schema cache/i.test(msg))
    return 'La base en ligne n’est pas encore préparée : exécutez le script supabase/schema.sql (voir le guide).'
  return msg
}

/** Mise en place et suivi du mode multi-postes (réservé à l'administrateur) */
export default function SyncPage() {
  const access = useAccess()
  const status = useSyncStatus()
  const [config, setConfig] = useState(loadConfig)
  const [step, setStep] = useState<Step>({ kind: 'form' })
  const [form, setForm] = useState({
    invite: '',
    url: config?.url ?? '',
    anonKey: config?.anonKey ?? '',
    dossier: config?.dossier ?? '',
    email: config?.email ?? '',
    password: '',
  })
  const [error, setError] = useState('')
  /** Adresse injoignable : lien pour la tester directement dans le navigateur */
  const [testUrl, setTestUrl] = useState('')
  const [copied, setCopied] = useState(false)
  const joined = config?.joined === true

  function applyInvite(code: string) {
    const decoded = decodeInvite(code)
    setForm((f) => ({ ...f, invite: code, ...(decoded ?? {}) }))
    setError(code.trim() && !decoded ? 'Code de connexion illisible.' : '')
  }

  async function connect() {
    setError('')
    setTestUrl('')
    const url = normalizeUrl(form.url)
    const dossier = form.dossier.trim().toLowerCase()
    // L'adresse nettoyée est affichée telle qu'elle sera utilisée
    if (url !== form.url) setForm((f) => ({ ...f, url }))
    const problem = urlProblem(url)
    if (problem) return setError(problem)
    if (!form.anonKey.trim()) return setError('Indiquez la clé publique du projet.')
    if (!isValidDossier(dossier)) return setError('Nom de dossier : lettres minuscules, chiffres et tirets (ex. orthomed).')
    if (!form.email.trim() || !form.password) return setError('Indiquez l’e-mail et le mot de passe de ce poste.')
    setStep({ kind: 'working', text: 'Connexion…' })
    try {
      const remote = new SupabaseRemote(url, form.anonKey.trim(), dossier)
      const session = await remote.signIn(form.email.trim(), form.password)
      if (!(await remote.isMember()))
        throw new Error(
          `Le compte ${session.email} n’est pas membre du dossier « ${dossier} ». Ajoutez-le dans la table « members » (voir le guide).`,
        )
      const next: SyncConfig = { url, anonKey: form.anonKey.trim(), dossier, email: session.email, refreshToken: session.refreshToken, joined: false }
      saveConfig(next)
      setConfig(next)
      setStep({ kind: 'choose', config: next, remoteCount: await remote.count(), localCount: localDataCount() })
    } catch (e) {
      setStep({ kind: 'form' })
      const hint = e instanceof OfflineError ? refHint(url) : null
      setError(hint ? `Serveur injoignable. ${hint} Copiez l’adresse depuis Supabase plutôt que de la taper.` : explain(e))
      if (e instanceof OfflineError) setTestUrl(`${url}/auth/v1/health`)
    }
  }

  async function upload(c: SyncConfig) {
    setStep({ kind: 'working', text: 'Envoi des données de ce poste…' })
    try {
      const engine = createEngine(loadConfig() ?? c)
      const n = await engine.uploadAll()
      const done = { ...(loadConfig() ?? c), joined: true }
      saveConfig(done)
      setConfig(done)
      engine.start()
      access.log('Multi-postes activé', `Dossier ${c.dossier} créé en ligne (${n} enregistrements envoyés)`)
      setStep({ kind: 'form' })
    } catch (e) {
      stopEngine()
      setStep({ kind: 'form' })
      setError(explain(e))
    }
  }

  async function download(c: SyncConfig) {
    if (!confirm('Remplacer toutes les données de cet ordinateur par celles du dossier en ligne ?')) return
    setStep({ kind: 'working', text: 'Récupération du dossier en ligne…' })
    try {
      const engine = createEngine(loadConfig() ?? c)
      await engine.downloadAll()
      saveConfig({ ...(loadConfig() ?? c), joined: true })
      stopEngine()
      // Rechargement : chaque écran repart des données du dossier
      location.reload()
    } catch (e) {
      stopEngine()
      setStep({ kind: 'form' })
      setError(explain(e))
    }
  }

  async function reconnect() {
    if (!config) return
    setError('')
    try {
      const remote = new SupabaseRemote(config.url, config.anonKey, config.dossier)
      const session = await remote.signIn(config.email, form.password)
      const next = { ...config, refreshToken: session.refreshToken, email: session.email }
      saveConfig(next)
      setConfig(next)
      createEngine(next).start()
      setForm((f) => ({ ...f, password: '' }))
    } catch (e) {
      setError(explain(e))
    }
  }

  async function leave() {
    if (!config) return
    if (!confirm('Déconnecter cet ordinateur du dossier partagé ? Les données restent sur ce poste mais ne seront plus synchronisées.')) return
    access.log('Multi-postes désactivé sur ce poste', config.dossier)
    stopEngine()
    await clearState(config.dossier)
    saveConfig(null)
    setConfig(null)
    setStep({ kind: 'form' })
  }

  function backupNow() {
    downloadFile(`profitpilot-sauvegarde-${today()}.json`, JSON.stringify(createBackup(), null, 1), 'application/json')
  }

  const invite = config ? encodeInvite(config) : ''

  if (joined && config) {
    const s = status
    return (
      <div>
        <div className="doc-stats">
          <div className={s?.phase === 'ok' ? undefined : s?.phase === 'offline' ? 'doc-stat-late' : 'doc-stat-danger'}>
            <span>État</span>
            <strong>
              {s?.phase === 'ok'
                ? 'Synchronisé'
                : s?.phase === 'offline'
                  ? 'Hors ligne'
                  : s?.phase === 'auth'
                    ? 'Reconnexion nécessaire'
                    : s?.phase === 'error'
                      ? 'Erreur'
                      : 'En cours…'}
            </strong>
          </div>
          <div>
            <span>Dernière synchronisation</span>
            <strong>{s?.lastSync ? new Date(s.lastSync).toLocaleTimeString('fr-FR') : '—'}</strong>
          </div>
          <div className={s?.pending ? 'doc-stat-late' : undefined}>
            <span>Modifications en attente</span>
            <strong>{s?.pending ?? 0}</strong>
          </div>
          <div>
            <span>Dossier · poste</span>
            <strong className="sync-small">
              {config.dossier} · {config.email}
            </strong>
          </div>
        </div>
        {s?.message && <p className={s.phase === 'offline' ? 'doc-warning' : 'doc-error'}>{s.message}</p>}
        {!!s?.conflicts && (
          <p className="doc-info">
            {s.conflicts} enregistrement(s) modifié(s) en même temps sur un autre poste : la version de cet ordinateur a été
            conservée.
          </p>
        )}

        <div className="doc-toolbar">
          <button type="button" className="btn-primary" onClick={() => void currentEngine()?.syncNow()}>
            Synchroniser maintenant
          </button>
          <button type="button" onClick={() => void leave()}>
            Déconnecter ce poste
          </button>
        </div>

        {s?.phase === 'auth' && (
          <fieldset className="doc-panel">
            <legend>Se reconnecter</legend>
            <div className="doc-grid">
              <label>
                Mot de passe de {config.email}
                <input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
              </label>
            </div>
            <button type="button" className="btn-primary" onClick={() => void reconnect()}>
              Se reconnecter
            </button>
          </fieldset>
        )}

        <fieldset className="doc-panel">
          <legend>Ajouter un autre ordinateur</legend>
          <ol className="sync-steps">
            <li>Sur l'autre ordinateur, ouvrez l'application puis Paramètres › Multi-postes.</li>
            <li>Collez ce code de connexion, puis saisissez l'e-mail et le mot de passe du compte de ce poste.</li>
            <li>Choisissez « Récupérer le dossier sur ce poste ».</li>
          </ol>
          <div className="sync-invite">
            <code>{invite}</code>
            <button
              type="button"
              onClick={() => {
                void navigator.clipboard?.writeText(invite)
                setCopied(true)
              }}
            >
              {copied ? 'Copié ✓' : 'Copier'}
            </button>
          </div>
          <p className="doc-count">Le code ne contient ni e-mail ni mot de passe : chaque poste se connecte avec son propre compte.</p>
        </fieldset>
        {error && <p className="doc-error">{error}</p>}
      </div>
    )
  }

  return (
    <div>
      <p className="doc-info">
        Le mode multi-postes range les données dans une base en ligne (Supabase) partagée par tous vos ordinateurs. Chaque
        pièce, client ou lot est synchronisé séparément toutes les quelques secondes ; les numéros de pièces sont attribués
        par le serveur pour qu'aucun poste ne puisse donner le même. Préparez d'abord la base en suivant le guide
        docs/MULTIPOSTE.md (environ 15 minutes, une seule fois).
      </p>

      {step.kind === 'working' && <p className="doc-warning">{step.text}</p>}

      {step.kind === 'form' && (
        <fieldset className="doc-panel">
          <legend>Connecter cet ordinateur</legend>
          <label className="doc-notes">
            Code de connexion : laissez vide sur le premier ordinateur (à coller seulement sur les postes suivants)
            <input value={form.invite} placeholder="PP1-…" onChange={(e) => applyInvite(e.target.value)} />
          </label>
          <div className="doc-grid">
            <label>
              Adresse du projet Supabase
              <input value={form.url} placeholder="https://abcdefghijklmnopqrst.supabase.co" onChange={(e) => setForm({ ...form, url: e.target.value })} />
            </label>
            <label>
              Clé publique (anon / publishable)
              <input value={form.anonKey} onChange={(e) => setForm({ ...form, anonKey: e.target.value })} />
            </label>
            <label>
              Nom du dossier
              <input value={form.dossier} placeholder="orthomed" onChange={(e) => setForm({ ...form, dossier: e.target.value })} />
            </label>
            <label>
              E-mail du compte de ce poste
              <input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
            </label>
            <label>
              Mot de passe
              <input type="password" value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} />
            </label>
          </div>
          <button type="button" className="btn-primary" onClick={() => void connect()}>
            Se connecter
          </button>
        </fieldset>
      )}

      {step.kind === 'choose' && (
        <fieldset className="doc-panel">
          <legend>Dossier « {step.config.dossier} »</legend>
          {step.remoteCount === 0 ? (
            <>
              <p>
                Le dossier en ligne est <strong>vide</strong> : cet ordinateur est le premier. Ses données ({step.localCount}{' '}
                pièces, tiers et lots, plus les articles et les paramètres) vont être envoyées.
              </p>
              <button type="button" className="btn-primary" onClick={() => void upload(step.config)}>
                Envoyer les données de ce poste
              </button>
            </>
          ) : (
            <>
              <p>
                Le dossier en ligne contient déjà <strong>{step.remoteCount} enregistrements</strong>. Cet ordinateur va
                récupérer ces données.
              </p>
              {step.localCount > 0 && (
                <p className="doc-warning">
                  Cet ordinateur contient aussi des données ({step.localCount} pièces, tiers et lots) : elles seront
                  remplacées. Téléchargez d'abord une sauvegarde si vous voulez les garder.{' '}
                  <button type="button" onClick={backupNow}>
                    Télécharger une sauvegarde
                  </button>
                </p>
              )}
              <button type="button" className="btn-primary" onClick={() => void download(step.config)}>
                Récupérer le dossier sur ce poste
              </button>
            </>
          )}
          <button type="button" onClick={() => setStep({ kind: 'form' })}>
            Annuler
          </button>
        </fieldset>
      )}

      {error && <p className="doc-error">{error}</p>}
      {testUrl && (
        <p className="doc-info">
          <a href={testUrl} target="_blank" rel="noreferrer">
            Tester cette adresse dans un nouvel onglet
          </a>{' '}
          : si une page de texte s’affiche (même un message en anglais comme « No API key found »), l’adresse est bonne et
          c’est un bloqueur de publicité qui gêne ProfitPilot ; si le navigateur affiche « Ce site est inaccessible », l’adresse
          est fausse.
        </p>
      )}

      <fieldset className="doc-panel">
        <legend>À savoir</legend>
        <ul className="sync-steps">
          <li>Les comptes de connexion (e-mail + mot de passe) se créent dans Supabase ; les profils et droits ProfitPilot (code PIN) restent ceux de Paramètres › Utilisateurs et sont partagés entre les postes.</li>
          <li>Sans Internet, on continue à travailler : les modifications partent au retour de la connexion. Seules la validation et l'annulation des pièces, et la reprise d'un dépôt, demandent d'être en ligne (le serveur les accorde à un seul poste).</li>
          <li>Données de patients : leur hébergement est soumis à la loi 09-08 (CNDP). Choisissez une région européenne pour le projet et renseignez-vous auprès de la CNDP.</li>
        </ul>
      </fieldset>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/sync/SyncPage.tsx"

cat > src/sync/collections.ts <<'FIN_DU_FICHIER'
// Données synchronisées : chaque clé du stockage local devient une « collection » d'enregistrements
import { mergeDocument, protectDocument } from './merge'

export interface CollectionSpec {
  /** Nom côté serveur */
  name: string
  /** Clé du localStorage */
  key: string
  /** array : liste d'objets ayant un id ; value : une seule valeur (id « _ ») */
  kind: 'array' | 'value'
  /** Tableau rangé dans un champ d'un objet (array), ou objet privé de ce champ (value) */
  field?: string
  /** Journal : les suppressions locales (purge) ne sont jamais propagées */
  appendOnly?: boolean
  /** Nombre maximum d'éléments gardés sur ce poste (les plus récents selon sortKey) */
  maxLocal?: number
  sortKey?: string
  /**
   * Règles métier de fusion : local = version de ce poste, remote = version serveur,
   * base = dernière version commune (absente si ce poste n'a rien modifié : la version serveur est alors préférée)
   */
  merge?: (local: unknown, remote: unknown, base: unknown | undefined) => { result: unknown; conflict: boolean }
  /** Enregistrement qu'une suppression venue d'ailleurs ne doit pas effacer */
  protect?: (record: unknown) => boolean
  /** Compteurs : en cas de modification sur deux postes, les variations s'additionnent (stock, quantité) */
  deltaFields?: string[]
}

export const COLLECTIONS: CollectionSpec[] = [
  { name: 'documents', key: 'profitpilot:documents:v1', kind: 'array', merge: mergeDocument, protect: protectDocument },
  { name: 'parties', key: 'profitpilot:parties:v1', kind: 'array' },
  { name: 'products', key: 'profitpilot:v1', kind: 'array', field: 'products', deltaFields: ['stock'] },
  { name: 'products-meta', key: 'profitpilot:v1', kind: 'value', field: 'products' },
  { name: 'lots', key: 'profitpilot:lots:v1', kind: 'array', deltaFields: ['quantity'] },
  { name: 'kits', key: 'profitpilot:kits:v1', kind: 'array' },
  { name: 'movements', key: 'profitpilot:movements:v1', kind: 'array', appendOnly: true },
  { name: 'fixed-costs', key: 'profitpilot:fixed:v1', kind: 'array' },
  { name: 'users', key: 'profitpilot:users:v1', kind: 'array' },
  { name: 'audit', key: 'profitpilot:audit:v1', kind: 'array', appendOnly: true, maxLocal: 5000, sortKey: 'at' },
  { name: 'company', key: 'profitpilot:company:v1', kind: 'value' },
  { name: 'access', key: 'profitpilot:access:v1', kind: 'value' },
  { name: 'cash', key: 'profitpilot:cash:v1', kind: 'value' },
  { name: 'currency', key: 'profitpilot:currency:v1', kind: 'value' },
  { name: 'stock-period', key: 'profitpilot:stock-period:v1', kind: 'value' },
]

export const VALUE_ID = '_'

/** Le navigateur refuse d'enregistrer : rien n'est marqué comme reçu, tout sera réappliqué plus tard */
export class StorageFullError extends Error {}

type Rec = Record<string, unknown> & { id: string }

const isRec = (x: unknown): x is Rec =>
  typeof x === 'object' && x !== null && typeof (x as { id?: unknown }).id === 'string'

function readRaw(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function parse(raw: string | null): unknown {
  if (raw === null) return undefined
  try {
    return JSON.parse(raw)
  } catch {
    return undefined
  }
}

/** Enregistrements locaux d'une collection, indexés par id */
export function readLocal(spec: CollectionSpec): Map<string, unknown> {
  const raw = readRaw(spec.key)
  const out = new Map<string, unknown>()
  if (spec.kind === 'value') {
    if (raw === null) return out
    if (spec.field) {
      const obj = parse(raw)
      if (typeof obj === 'object' && obj !== null) {
        const rest = { ...(obj as Record<string, unknown>) }
        delete rest[spec.field]
        out.set(VALUE_ID, rest)
      }
    } else out.set(VALUE_ID, { raw })
    return out
  }
  const data = parse(raw)
  const list = spec.field ? (data as Record<string, unknown> | undefined)?.[spec.field] : data
  if (Array.isArray(list)) for (const item of list) if (isRec(item)) out.set(item.id, item)
  return out
}

/** Écrit une collection et prévient l'application (événement « storage » comme pour un autre onglet) */
export function writeLocal(spec: CollectionSpec, records: Map<string, unknown>, order: string[]) {
  const oldValue = readRaw(spec.key)
  let next: string | null
  if (spec.kind === 'value') {
    const v = records.get(VALUE_ID) as Record<string, unknown> | undefined
    if (spec.field) {
      const obj = (parse(oldValue) as Record<string, unknown> | undefined) ?? {}
      next = JSON.stringify({ ...(v ?? {}), [spec.field]: obj[spec.field] ?? [] })
    } else next = v && typeof v.raw === 'string' ? v.raw : null
  } else {
    // On garde l'ordre local existant, les nouveaux éléments à la fin
    let list = order.filter((id) => records.has(id)).map((id) => records.get(id))
    if (spec.maxLocal && list.length > spec.maxLocal) {
      const key = spec.sortKey ?? 'id'
      list = [...list]
        .sort((a, b) => String((a as Rec)[key]).localeCompare(String((b as Rec)[key])))
        .slice(-spec.maxLocal)
    }
    if (spec.field) {
      const obj = (parse(oldValue) as Record<string, unknown> | undefined) ?? {}
      next = JSON.stringify({ ...obj, [spec.field]: list })
    } else next = JSON.stringify(list)
  }
  if (next === oldValue) return
  try {
    if (next === null) localStorage.removeItem(spec.key)
    else localStorage.setItem(spec.key, next)
  } catch {
    throw new StorageFullError(
      'Stockage du navigateur plein : les modifications des autres postes ne peuvent plus être enregistrées ici. Libérez de la place (Paramètres › Sauvegarde) puis rechargez la page.',
    )
  }
  window.dispatchEvent(new StorageEvent('storage', { key: spec.key, oldValue, newValue: next, storageArea: localStorage }))
}

/** Ordre actuel des ids d'une collection (pour conserver l'ordre à la réécriture) */
export function localOrder(spec: CollectionSpec): string[] {
  return [...readLocal(spec).keys()]
}

export { fingerprint, stableStringify, threeWayMerge } from './json'
FIN_DU_FICHIER
echo "OK src/sync/collections.ts"

cat > src/sync/config.ts <<'FIN_DU_FICHIER'
// Configuration du mode multi-postes (stockée hors des clés « profitpilot: » : jamais synchronisée ni sauvegardée)

export const CONFIG_KEY = 'profitpilot-sync:config'

export interface SyncConfig {
  /** Adresse du projet Supabase, ex. https://abcd.supabase.co */
  url: string
  /** Clé publique du projet (anon / publishable) */
  anonKey: string
  /** Identifiant du dossier partagé (une société = un dossier) */
  dossier: string
  /** Compte de connexion de ce poste */
  email: string
  refreshToken: string
  /** Ce poste a rejoint le dossier (envoi initial ou récupération faits) */
  joined: boolean
}

export function loadConfig(): SyncConfig | null {
  try {
    const raw = localStorage.getItem(CONFIG_KEY)
    if (!raw) return null
    const c = JSON.parse(raw) as Partial<SyncConfig>
    if (typeof c.url !== 'string' || typeof c.anonKey !== 'string' || typeof c.dossier !== 'string') return null
    return {
      url: c.url,
      anonKey: c.anonKey,
      dossier: c.dossier,
      email: c.email ?? '',
      refreshToken: c.refreshToken ?? '',
      joined: c.joined === true,
    }
  } catch {
    return null
  }
}

export function saveConfig(config: SyncConfig | null) {
  try {
    if (config) localStorage.setItem(CONFIG_KEY, JSON.stringify(config))
    else localStorage.removeItem(CONFIG_KEY)
  } catch {
    // stockage indisponible
  }
}

/** Adresse nettoyée : https, sans barre finale */
/**
 * Adresse du projet nettoyée. Accepte aussi ce qu'on copie souvent par erreur : l'adresse de la page
 * Supabase (supabase.com/dashboard/project/<identifiant>/…), l'identifiant seul (20 lettres),
 * l'adresse sans https:// ou suivie de /rest/v1 ou /auth/v1.
 */
export function normalizeUrl(input: string): string {
  const raw = input.trim().replace(/\s+/g, '')
  const page = raw.match(/supabase\.com\/dashboard\/project\/([a-z0-9]{10,40})/i)
  if (page) return `https://${page[1].toLowerCase()}.supabase.co`
  if (/^[a-z]{20}$/.test(raw)) return `https://${raw}.supabase.co`
  const url = raw.replace(/\/(rest|auth)\/v1(\/.*)?$/i, '').replace(/\/+$/, '')
  return /^[a-z0-9-]+\.supabase\.co$/i.test(url) ? `https://${url}` : url
}

/** Identifiant d'un projet Supabase (20 lettres) dont la longueur est suspecte : conseil, ou null */
export function refHint(url: string): string | null {
  const ref = url.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co$/i)?.[1]
  if (!ref || ref.length === 20) return null
  return `L’identifiant du projet (« ${ref} ») compte ${ref.length} caractères alors qu’il en fait normalement 20 : une lettre manque ou est en trop.`
}

/** Erreur évidente dans une adresse déjà nettoyée (message en clair), ou null */
export function urlProblem(url: string): string | null {
  if (!/^https?:\/\/[^/\s]+$/i.test(url)) return 'Adresse du projet invalide : elle doit ressembler à https://abcdefghijklmnopqrst.supabase.co'
  const host = url.replace(/^https?:\/\//i, '').toLowerCase()
  if (host.endsWith('.supabase.com')) return 'L’adresse du projet se termine par « .supabase.co » (sans « m » à la fin).'
  if (/^(www\.|app\.)?supabase\.(com|co)$/.test(host))
    return 'Ceci est l’adresse du site Supabase, pas celle de votre projet : elle doit ressembler à https://abcdefghijklmnopqrst.supabase.co'
  return null
}

/** Code de connexion à transmettre aux autres postes (adresse, clé publique, dossier ; jamais de mot de passe) */
export function encodeInvite(c: Pick<SyncConfig, 'url' | 'anonKey' | 'dossier'>): string {
  const json = JSON.stringify({ u: c.url, k: c.anonKey, d: c.dossier })
  const bytes = new TextEncoder().encode(json)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return 'PP1-' + btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function decodeInvite(code: string): Pick<SyncConfig, 'url' | 'anonKey' | 'dossier'> | null {
  try {
    const body = code.trim().replace(/^PP1-/, '').replace(/-/g, '+').replace(/_/g, '/')
    const bin = atob(body + '='.repeat((4 - (body.length % 4)) % 4))
    const json = new TextDecoder().decode(Uint8Array.from(bin, (ch) => ch.charCodeAt(0)))
    const o = JSON.parse(json) as { u?: unknown; k?: unknown; d?: unknown }
    if (typeof o.u !== 'string' || typeof o.k !== 'string' || typeof o.d !== 'string') return null
    return { url: o.u, anonKey: o.k, dossier: o.d }
  } catch {
    return null
  }
}

/** Identifiant de dossier : minuscules, chiffres et tirets */
export const isValidDossier = (d: string) => /^[a-z0-9][a-z0-9-]{1,40}$/.test(d)

const DEVICE_KEY = 'profitpilot-sync:device'

/** Identifiant de ce navigateur (fixe), pour reconnaître ses propres actions après une coupure */
export function deviceId(): string {
  try {
    const existing = localStorage.getItem(DEVICE_KEY)
    if (existing) return existing
    const id = randomId()
    localStorage.setItem(DEVICE_KEY, id)
    return id
  } catch {
    return 'memoire-' + randomId()
  }
}

export function randomId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2)
}
FIN_DU_FICHIER
echo "OK src/sync/config.ts"

cat > src/sync/engine.ts <<'FIN_DU_FICHIER'
// Moteur de synchronisation : envoie les modifications de ce poste, applique celles des autres postes.
// Granularité : l'enregistrement (une pièce, un client, un lot…). Le serveur arbitre : un envoi fait sur une
// version périmée est refusé et renvoyé ; le poste fusionne puis renvoie. Rien n'est écrasé en silence.
import { deviceId, randomId } from './config'
import { COLLECTIONS, VALUE_ID, fingerprint, readLocal, threeWayMerge, writeLocal, type CollectionSpec } from './collections'
import { StorageFullError } from './collections'
import { AuthError, OfflineError, PushError, SupabaseRemote, type Claim, type PushResult, type PushRow, type RemoteRow } from './remote'
import { emptyState, loadState, saveState, type SyncState } from './state'

export type SyncPhase = 'idle' | 'syncing' | 'ok' | 'offline' | 'auth' | 'error'

export interface SyncStatus {
  phase: SyncPhase
  /** Dernière synchronisation réussie (ms) */
  lastSync: number | null
  /** Modifications locales pas encore envoyées */
  pending: number
  /** Modifications des deux côtés sur un même champ : la version de ce poste a été gardée */
  conflicts: number
  message: string
}

const SEP = '␟'
const keyOf = (collection: string, id: string) => collection + SEP + id
/** Marge de relecture : une ligne validée côté serveur juste avant notre lecture peut porter une date un peu antérieure */
const OVERLAP_MS = 15_000
const INTERVAL_MS = 4_000
/** Envois refusés (modifiés ailleurs entre-temps) : fusion puis nouvel envoi, au plus 3 fois par synchro */
const MAX_ROUNDS = 3
/** Envois sans réponse gardés par enregistrement */
const MAX_PENDING = 5

const minus = (iso: string, ms: number) => new Date(new Date(iso).getTime() - ms).toISOString()
/** Comparaison de dates serveur par leur valeur (indépendante du fuseau renvoyé) */
const isLater = (a: string, b: string | null) => !b || new Date(a).getTime() > new Date(b).getTime()
const hashOf = (x: unknown) => (x === undefined ? undefined : fingerprint(x))

export class SyncEngine {
  readonly remote: SupabaseRemote
  private readonly dossier: string
  private readonly device: string
  private state: SyncState = emptyState()
  private loaded = false
  private busy: Promise<void> | null = null
  private timer: number | null = null
  private listeners = new Set<(s: SyncStatus) => void>()
  status: SyncStatus = { phase: 'idle', lastSync: null, pending: 0, conflicts: 0, message: '' }

  constructor(remote: SupabaseRemote, dossier: string, device = deviceId()) {
    this.remote = remote
    this.dossier = dossier
    this.device = device
  }

  /** Mémorise la version serveur de référence d'un enregistrement (empreinte + copie pour la fusion) */
  private remember(k: string, data: unknown | undefined) {
    if (data === undefined) {
      delete this.state.base[k]
      delete this.state.snapshot[k]
    } else {
      this.state.base[k] = fingerprint(data)
      this.state.snapshot[k] = JSON.parse(JSON.stringify(data)) as unknown
    }
  }

  subscribe(fn: (s: SyncStatus) => void): () => void {
    this.listeners.add(fn)
    fn(this.status)
    return () => this.listeners.delete(fn)
  }

  private setStatus(patch: Partial<SyncStatus>) {
    this.status = { ...this.status, ...patch }
    for (const fn of this.listeners) fn(this.status)
  }

  private releaseLock: (() => void) | null = null
  private stopped = false
  /** Un autre onglet de ce poste synchronise : celui-ci attend son tour et ne synchronise pas */
  private waiting = false

  /**
   * Démarre la synchro automatique. Plusieurs onglets ouverts sur le même poste : un seul synchronise
   * (verrou du navigateur) ; si on le ferme, un autre onglet prend aussitôt le relais.
   */
  start() {
    this.stopped = false
    this.setStatus({ phase: 'idle', message: 'Synchronisé par un autre onglet ouvert sur ce poste' })
    const locks = (navigator as Navigator & { locks?: LockManager }).locks
    if (!locks) return this.beginLoop()
    this.waiting = true
    void locks.request(`profitpilot-sync:${this.dossier}`, () => {
      this.waiting = false
      if (this.stopped) return
      this.beginLoop()
      return new Promise<void>((resolve) => {
        this.releaseLock = resolve
      })
    })
  }

  private beginLoop() {
    if (this.timer !== null || this.stopped) return
    void this.syncNow()
    this.timer = window.setInterval(() => void this.syncNow(), INTERVAL_MS)
    window.addEventListener('online', this.onOnline)
  }

  stop() {
    this.stopped = true
    if (this.timer !== null) window.clearInterval(this.timer)
    this.timer = null
    window.removeEventListener('online', this.onOnline)
    this.releaseLock?.()
    this.releaseLock = null
  }

  /** Cet onglet est-il celui qui synchronise ? */
  get active(): boolean {
    return this.timer !== null
  }

  private onOnline = () => void this.syncNow()

  private async ensureLoaded() {
    if (this.loaded) return
    this.state = await loadState(this.dossier)
    this.loaded = true
  }

  /** Une seule synchronisation à la fois ; un appel pendant une synchro attend la fin de celle-ci */
  syncNow(): Promise<void> {
    if (this.waiting) return Promise.resolve()
    this.busy ??= this.run().finally(() => {
      this.busy = null
    })
    return this.busy
  }

  private async run() {
    this.setStatus({ phase: this.status.phase === 'ok' ? 'ok' : 'syncing' })
    try {
      await this.cycle()
      this.setStatus({ phase: 'ok', lastSync: Date.now(), pending: 0, message: '' })
    } catch (e) {
      // Ce qui a été reçu et confirmé avant l'erreur reste acquis
      if (this.loaded) await saveState(this.dossier, this.state)
      const pending = this.loaded ? this.localChanges().length : 0
      if (e instanceof OfflineError) this.setStatus({ phase: 'offline', pending, message: 'Hors ligne : les modifications partiront au retour de la connexion.' })
      else if (e instanceof AuthError) this.setStatus({ phase: 'auth', pending, message: `Connexion refusée : ${e.message}` })
      else this.setStatus({ phase: 'error', pending, message: e instanceof Error ? e.message : String(e) })
    }
  }

  /** Une synchronisation : réception, puis envoi conditionnel (refus → fusion → nouvel envoi) */
  private async cycle() {
    await this.ensureLoaded()
    const since = this.state.lastPull ? minus(this.state.lastPull, OVERLAP_MS) : null
    await this.receive(await this.remote.pull(since), true)
    for (let round = 0; round < MAX_ROUNDS; round++) {
      const changes = this.localChanges()
      if (changes.length === 0) break
      const rows: PushRow[] = changes.map((c) => ({ ...c.row, rev: `${this.device}.${randomId()}`, expected: this.state.seen[c.k] ?? null }))
      // Envoi noté avant de partir : si la réponse se perd, on reconnaîtra notre écriture à la relecture.
      // Une écriture réussie est toujours relue avant l'envoi suivant : quelques envois en attente suffisent.
      for (const r of rows) {
        const k = keyOf(r.collection, r.id)
        this.state.pending[k] = [...(this.state.pending[k] ?? []), { rev: r.rev, data: r.deleted ? null : r.data, deleted: r.deleted }].slice(-MAX_PENDING)
      }
      await saveState(this.dossier, this.state)
      const sent = new Map(rows.map((r) => [keyOf(r.collection, r.id), r]))
      let result: PushResult
      try {
        result = await this.remote.push(rows)
      } catch (e) {
        // Paquets déjà écrits avant l'erreur : confirmés tout de suite
        if (!(e instanceof PushError)) throw e
        this.confirm(e.partial.accepted, sent)
        throw e.original
      }
      this.confirm(result.accepted, sent)
      if (result.rejected.length === 0) break
      // Refusé : notre envoi n'a pas été écrit ; on fusionne avec la version serveur avant de renvoyer
      for (const row of result.rejected) {
        const k = keyOf(row.collection, row.id)
        const rev = sent.get(k)?.rev
        const list = this.state.pending[k]?.filter((p) => p.rev !== rev)
        if (list?.length) this.state.pending[k] = list
        else delete this.state.pending[k]
      }
      await this.receive(result.rejected)
    }
    await saveState(this.dossier, this.state)
  }

  /** Envois écrits par le serveur : ils deviennent la version de référence */
  private confirm(accepted: PushResult['accepted'], sent: Map<string, PushRow>) {
    for (const a of accepted) {
      const k = keyOf(a.collection, a.id)
      const r = sent.get(k)
      if (!r) continue
      this.remember(k, r.deleted ? undefined : r.data)
      this.state.seen[k] = a.updated_at
      delete this.state.pending[k]
    }
  }

  /**
   * Prépare puis applique des lignes reçues du serveur. Seule une lecture complète (fromPull) fait avancer
   * la date de dernière lecture : une ligne refusée à l'envoi peut être plus récente que d'autres pas encore lues.
   */
  private async receive(rows: RemoteRow[], fromPull = false) {
    if (rows.length === 0) return
    // Envoi sans réponse (coupure) puis ligne réécrite par un autre poste : le serveur dit si notre envoi a été écrit
    const unknown: string[] = []
    for (const r of rows) {
      const k = keyOf(r.collection, r.id)
      const pending = this.state.pending[k]
      if (pending && r.updated_at !== this.state.seen[k] && !pending.some((p) => p.rev === r.rev)) unknown.push(...pending.map((p) => p.rev))
    }
    this.applyRemote(rows, await this.remote.appliedRevs(unknown), fromPull)
  }

  /**
   * Applique les lignes reçues en respectant les modifications de ce poste pas encore envoyées.
   * L'état (versions de référence) n'avance qu'une fois les données écrites dans le navigateur :
   * si le stockage est plein, rien n'est perdu, tout sera réappliqué à la synchro suivante.
   */
  private applyRemote(rows: RemoteRow[], applied: Set<string>, fromPull: boolean) {
    const bySpec = new Map<string, RemoteRow[]>()
    let lastPull = this.state.lastPull
    for (const r of rows) {
      const list = bySpec.get(r.collection) ?? []
      list.push(r)
      bySpec.set(r.collection, list)
      if (fromPull && r.updated_at && isLater(r.updated_at, lastPull)) lastPull = r.updated_at
    }
    let conflicts = this.status.conflicts
    // Les collections qui partagent une clé (articles et leur méta) sont écrites l'une après l'autre
    for (const spec of COLLECTIONS) {
      const incoming = bySpec.get(spec.name)
      if (!incoming) continue
      const local = readLocal(spec)
      const order = [...local.keys()]
      let changed = false
      const accepted: { k: string; row: RemoteRow }[] = []
      for (const row of incoming) {
        const k = keyOf(spec.name, row.id)
        if (row.updated_at && this.state.seen[k] === row.updated_at) continue
        accepted.push({ k, row })
        if (row.deleted && spec.appendOnly) continue

        // Version de référence : la dernière reçue, ou notre propre envoi s'il a été écrit sans que nous le sachions
        let base: string | undefined = this.state.base[k]
        let snapshot = this.state.snapshot[k]
        let known = k in this.state.base || k in this.state.seen
        const mine = [...(this.state.pending[k] ?? [])].reverse().find((p) => p.rev === row.rev || applied.has(p.rev))
        if (mine) {
          base = mine.deleted ? undefined : fingerprint(mine.data)
          snapshot = mine.deleted ? undefined : mine.data
          known = true
        }

        const current = local.get(row.id)
        const localHash = hashOf(current)
        const remoteHash = row.deleted ? undefined : fingerprint(row.data)
        // Modifié sur ce poste depuis la version de référence
        const dirty = known && localHash !== base
        let result: unknown
        if (!known) {
          // Jamais vu sur ce poste (réglage créé sur deux postes, état de synchro perdu) : la version en ligne fait foi
          if (row.deleted) result = current !== undefined && spec.protect?.(current) ? current : undefined
          else if (current !== undefined && spec.merge) result = spec.merge(current, row.data, undefined).result
          else result = row.data
          if (current !== undefined && hashOf(result) !== localHash) conflicts++
        } else if (localHash === remoteHash && !(dirty && spec.deltaFields)) {
          result = current
        } else if (row.deleted) {
          if (current !== undefined && spec.protect?.(current)) result = current // pièce validée : on la garde et on la renvoie
          else if (dirty && current !== undefined) {
            conflicts++ // modifié ici, supprimé ailleurs : la modification l'emporte
            result = current
          } else result = undefined
        } else if (current === undefined) {
          if (dirty && !spec.protect?.(row.data)) {
            conflicts++ // supprimé ici, modifié ailleurs : la suppression l'emporte
            result = undefined
          } else result = row.data
        } else if (spec.merge) {
          // Règles métier : jamais de retour en arrière d'une pièce, règlements additionnés
          const merged = spec.merge(current, row.data, dirty ? snapshot : undefined)
          if (merged.conflict) conflicts++
          result = merged.result
        } else if (dirty) {
          // Modifié des deux côtés : fusion champ par champ à partir de la dernière version commune
          if (snapshot === undefined) {
            conflicts++
            result = row.data
          } else {
            const merged = threeWayMerge(snapshot, current, row.data, spec.deltaFields)
            if (merged.conflict) conflicts++
            result = merged.result
          }
        } else result = row.data

        // Si le résultat diffère de la version serveur, il sera envoyé (sur la base de cette version)
        if (result === undefined) {
          if (local.delete(row.id)) changed = true
        } else if (hashOf(result) !== localHash) {
          if (!local.has(row.id)) order.push(row.id)
          local.set(row.id, result)
          changed = true
        }
      }
      if (changed) writeLocal(spec, local, order) // StorageFullError : rien n'est marqué comme reçu
      for (const { k, row } of accepted) {
        this.remember(k, row.deleted ? undefined : row.data)
        if (row.updated_at) this.state.seen[k] = row.updated_at
        delete this.state.pending[k]
      }
    }
    this.state.lastPull = lastPull
    if (conflicts !== this.status.conflicts) this.setStatus({ conflicts })
  }

  /** Enregistrements locaux différents de leur version de référence */
  private localChanges(): { k: string; row: RemoteRow }[] {
    const out: { k: string; row: RemoteRow }[] = []
    for (const spec of COLLECTIONS) {
      const local = readLocal(spec)
      for (const [id, data] of local) {
        const k = keyOf(spec.name, id)
        if (this.state.base[k] !== fingerprint(data)) out.push({ k, row: { collection: spec.name, id, data, deleted: false } })
      }
      if (spec.appendOnly) continue
      // Supprimé sur ce poste depuis la dernière synchro : on propage la suppression
      const prefix = spec.name + SEP
      for (const k of Object.keys(this.state.base)) {
        if (!k.startsWith(prefix)) continue
        const id = k.slice(prefix.length)
        if (!local.has(id)) out.push({ k, row: { collection: spec.name, id, data: null, deleted: true } })
      }
    }
    return out
  }

  pendingCount(): number {
    return this.loaded ? this.localChanges().length : 0
  }

  /** Action unique sur une pièce (validation, annulation…) : un seul poste l'obtient */
  claim(docId: string, action: string, kind: string, year: number, min: number): Promise<Claim> {
    return this.remote.claim(docId, action, this.device, kind, year, min)
  }

  /** Premier poste : envoie toutes les données locales vers un dossier en ligne vide */
  async uploadAll(): Promise<number> {
    this.state = emptyState()
    this.loaded = true
    const count = this.localChanges().length
    await this.cycle()
    return count
  }

  /** Nouveau poste : remplace les données locales par celles du dossier en ligne */
  async downloadAll(): Promise<number> {
    const rows = await this.remote.pull(null)
    const state = emptyState()
    const bySpec = new Map<string, RemoteRow[]>()
    for (const r of rows) {
      bySpec.set(r.collection, [...(bySpec.get(r.collection) ?? []), r])
      if (r.updated_at) {
        state.seen[keyOf(r.collection, r.id)] = r.updated_at
        if (isLater(r.updated_at, state.lastPull)) state.lastPull = r.updated_at
      }
    }
    let count = 0
    for (const spec of COLLECTIONS) {
      const records = new Map<string, unknown>()
      const order: string[] = []
      for (const r of bySpec.get(spec.name) ?? []) {
        if (r.deleted) continue
        records.set(r.id, r.data)
        order.push(r.id)
        state.base[keyOf(spec.name, r.id)] = fingerprint(r.data)
        state.snapshot[keyOf(spec.name, r.id)] = r.data
        count++
      }
      // Réglage absent en ligne : on garde celui de ce poste (il sera envoyé)
      if (records.size === 0 && spec.kind === 'value' && !bySpec.has(spec.name)) continue
      writeLocal(spec, records, order)
    }
    this.state = state
    this.loaded = true
    await saveState(this.dossier, this.state)
    return count
  }
}

/** Valeur « _ » d'une collection de type value : exportée pour les tests */
export const VALUE_RECORD_ID = VALUE_ID
export { StorageFullError }
export type { CollectionSpec }
FIN_DU_FICHIER
echo "OK src/sync/engine.ts"

cat > src/sync/json.ts <<'FIN_DU_FICHIER'
// Comparaison et fusion d'enregistrements JSON (sans dépendance : utilisable partout)

/** JSON à clés triées : deux objets égaux donnent toujours le même texte (le serveur réordonne les clés) */
export function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null'
  if (Array.isArray(value)) return '[' + value.map((v) => (v === undefined ? 'null' : stableStringify(v))).join(',') + ']'
  const obj = value as Record<string, unknown>
  const keys = Object.keys(obj)
    .filter((k) => obj[k] !== undefined)
    .sort()
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + stableStringify(obj[k])).join(',') + '}'
}

/** Empreinte courte d'un enregistrement (FNV-1a 32 bits + longueur) */
export function fingerprint(value: unknown): string {
  const s = stableStringify(value)
  let h = 0x811c9dc5
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 0x01000193) >>> 0
  return h.toString(36) + '.' + s.length.toString(36)
}

export const same = (a: unknown, b: unknown) => stableStringify(a) === stableStringify(b)

/**
 * Fusion à trois versions, champ par champ : base = dernière version serveur connue,
 * local = version de ce poste, remote = nouvelle version serveur.
 * - champ changé d'un seul côté : ce changement est gardé ;
 * - compteur changé des deux côtés : les deux variations s'additionnent (10 → 8 ici, 10 → 7 ailleurs : 5) ;
 * - autre champ changé des deux côtés : la version de ce poste l'emporte (conflit compté).
 */
export function threeWayMerge(
  base: unknown,
  local: unknown,
  remote: unknown,
  deltaFields: string[] = [],
): { result: unknown; conflict: boolean } {
  const isObj = (x: unknown): x is Record<string, unknown> => typeof x === 'object' && x !== null && !Array.isArray(x)
  if (!isObj(base) || !isObj(local) || !isObj(remote)) return { result: local, conflict: true }
  const out: Record<string, unknown> = {}
  let conflict = false
  for (const key of new Set([...Object.keys(base), ...Object.keys(local), ...Object.keys(remote)])) {
    const b = base[key]
    const l = local[key]
    const r = remote[key]
    let v: unknown
    if (same(l, b)) v = r
    else if (same(r, b)) v = l
    // Compteur avant l'égalité : deux sorties de 1 sur deux postes (10 → 9 ici, 10 → 9 ailleurs) donnent 8, pas 9
    else if (deltaFields.includes(key) && typeof b === 'number' && typeof l === 'number' && typeof r === 'number') v = r + (l - b)
    else if (same(l, r)) v = l
    else {
      v = l
      conflict = true
    }
    if (v !== undefined) out[key] = v
  }
  return { result: out, conflict }
}
FIN_DU_FICHIER
echo "OK src/sync/json.ts"

cat > src/sync/merge.ts <<'FIN_DU_FICHIER'
// Règles métier appliquées quand une pièce a changé sur deux postes à la fois
import { computeTotals } from '../documents/tva'
import type { CommercialDocument, DocStatus, Payment } from '../documents/types'
import { threeWayMerge } from './json'

/** Une pièce avance (brouillon → validée → réglée / annulée) et ne recule jamais */
const RANK: Record<DocStatus, number> = { draft: 0, validated: 1, paid: 2, cancelled: 3 }

const isDoc = (x: unknown): x is CommercialDocument =>
  typeof x === 'object' && x !== null && typeof (x as { status?: unknown }).status === 'string'

const rank = (d: CommercialDocument) => RANK[d.status] ?? 0

/**
 * Fusion de deux versions d'une même pièce :
 * - la version la plus avancée l'emporte entière (une copie « brouillon » périmée ne modifie jamais une pièce validée) ;
 * - à avancement égal : sans modification sur ce poste (base absente) la version serveur est reprise,
 *   sinon fusion champ par champ à partir de la dernière version commune ;
 * - les règlements des deux versions sont additionnés (deux encaissements saisis sur deux postes).
 */
export function mergeDocument(local: unknown, remote: unknown, base: unknown | undefined): { result: unknown; conflict: boolean } {
  if (!isDoc(local) || !isDoc(remote)) return { result: base === undefined ? remote : local, conflict: base !== undefined }
  let winner: CommercialDocument
  let conflict = false
  if (rank(local) !== rank(remote)) {
    winner = rank(local) > rank(remote) ? local : remote
    conflict = base !== undefined
  } else if (base === undefined) winner = remote
  else {
    const merged = threeWayMerge(base, local, remote)
    winner = merged.result as CommercialDocument
    conflict = merged.conflict
  }
  const payments = new Map<string, Payment>()
  for (const p of [...(local.payments ?? []), ...(remote.payments ?? [])]) if (!payments.has(p.id)) payments.set(p.id, p)
  if (payments.size === 0) return { result: winner, conflict }
  const all = [...payments.values()].sort((a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id))
  // Deux acomptes saisis sur deux postes peuvent solder la facture à eux deux
  const paid = all.reduce((sum, p) => sum + p.amount, 0)
  const settled =
    (winner.kind === 'invoice' || winner.kind === 'bill') &&
    winner.status === 'validated' &&
    paid >= computeTotals(winner).netToPay - 0.01
  return { result: { ...winner, payments: all, ...(settled ? { status: 'paid' as const } : {}) }, conflict }
}

/** Une pièce validée ne peut pas être supprimée (seuls les brouillons le peuvent) */
export function protectDocument(record: unknown): boolean {
  return isDoc(record) && record.status !== 'draft'
}
FIN_DU_FICHIER
echo "OK src/sync/merge.ts"

cat > src/sync/remote.ts <<'FIN_DU_FICHIER'
// Client de la base en ligne (Supabase : authentification GoTrue + API REST PostgREST), en fetch simple

export interface RemoteRow {
  collection: string
  id: string
  data: unknown
  deleted: boolean
  updated_at?: string
  updated_by?: string | null
  /** Identifiant de l'envoi qui a écrit cette version */
  rev?: string | null
}

/** Ligne à envoyer : expected = date serveur de la version sur laquelle le poste s'appuie (null = nouvelle ligne) */
export interface PushRow extends RemoteRow {
  rev: string
  expected: string | null
}

export interface PushResult {
  /** Lignes écrites, avec leur nouvelle date serveur */
  accepted: { collection: string; id: string; updated_at: string }[]
  /** Lignes refusées (modifiées entre-temps sur un autre poste) : version serveur actuelle, à fusionner */
  rejected: RemoteRow[]
}

/** Résultat d'une action unique sur une pièce (validation, annulation, retour de dépôt) */
export interface Claim {
  /** Numéro définitif attribué par le serveur (validation) */
  number: number | null
  /** Action déjà faite par un autre poste : ne rien appliquer ici */
  already: boolean
}

export interface Session {
  accessToken: string
  refreshToken: string
  /** Expiration du jeton d'accès (ms depuis 1970) */
  expiresAt: number
  email: string
}

/** Réseau injoignable : on réessaiera plus tard */
export class OfflineError extends Error {}
/** Connexion refusée ou expirée : il faut se reconnecter */
export class AuthError extends Error {}
/** Erreur renvoyée par le serveur */
export class RemoteError extends Error {}

/** Envoi interrompu : les paquets déjà écrits (partial) sont à confirmer, puis l'erreur d'origine relancée */
export class PushError extends Error {
  readonly partial: PushResult
  readonly original: Error
  constructor(original: Error, partial: PushResult) {
    super(original.message)
    this.partial = partial
    this.original = original
  }
}

const PAGE = 1000
const PUSH_CHUNK = 200
const PUSH_BYTES = 400_000

async function send(input: string, init: RequestInit): Promise<Response> {
  try {
    return await fetch(input, init)
  } catch {
    throw new OfflineError('Serveur injoignable')
  }
}

async function errorText(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as Record<string, unknown>
    return String(body.error_description ?? body.msg ?? body.message ?? body.error ?? res.statusText)
  } catch {
    return res.statusText || `Erreur ${res.status}`
  }
}

interface TokenResponse {
  access_token: string
  refresh_token: string
  expires_in: number
  user?: { email?: string }
}

function toSession(t: TokenResponse, email: string): Session {
  return {
    accessToken: t.access_token,
    refreshToken: t.refresh_token,
    expiresAt: Date.now() + (t.expires_in ?? 3600) * 1000,
    email: t.user?.email ?? email,
  }
}

export class SupabaseRemote {
  private session: Session | null = null
  private refreshing: Promise<Session> | null = null
  private readonly url: string
  private readonly anonKey: string
  private readonly dossier: string
  /** Appelé quand le jeton de rafraîchissement change (à enregistrer) */
  onSession?: (s: Session) => void
  /** Dernier jeton de rafraîchissement enregistré (un autre onglet a pu le renouveler entre-temps) */
  latestRefreshToken?: () => string | undefined

  constructor(url: string, anonKey: string, dossier: string, refreshToken?: string, email = '') {
    this.url = url
    this.anonKey = anonKey
    this.dossier = dossier
    if (refreshToken) this.session = { accessToken: '', refreshToken, expiresAt: 0, email }
  }

  /** Connexion par e-mail et mot de passe */
  async signIn(email: string, password: string): Promise<Session> {
    const res = await send(`${this.url}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: this.anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    if (!res.ok) throw new AuthError(await errorText(res))
    this.session = toSession((await res.json()) as TokenResponse, email)
    this.onSession?.(this.session)
    return this.session
  }

  private async refresh(): Promise<Session> {
    const current = this.session
    if (!current?.refreshToken) throw new AuthError('Session absente')
    // Supabase n'accepte qu'une fois chaque jeton : on part toujours du plus récent enregistré
    const token = this.latestRefreshToken?.() || current.refreshToken
    const call = (refresh_token: string) =>
      send(`${this.url}/auth/v1/token?grant_type=refresh_token`, {
        method: 'POST',
        headers: { apikey: this.anonKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token }),
      })
    let res = await call(token)
    if (!res.ok && res.status < 500) {
      // Renouvelé par un autre onglet pendant l'appel : on réessaie avec le jeton enregistré par celui-ci
      const latest = this.latestRefreshToken?.()
      if (latest && latest !== token) res = await call(latest)
    }
    if (!res.ok) {
      if (res.status >= 500) throw new RemoteError(await errorText(res))
      throw new AuthError(await errorText(res))
    }
    this.session = toSession((await res.json()) as TokenResponse, current.email)
    this.onSession?.(this.session)
    return this.session
  }

  private async accessToken(force = false): Promise<string> {
    if (!this.session) throw new AuthError('Non connecté')
    if (force || this.session.expiresAt - 60_000 < Date.now()) {
      // Un seul rafraîchissement à la fois
      this.refreshing ??= this.refresh().finally(() => {
        this.refreshing = null
      })
      await this.refreshing
    }
    return this.session.accessToken
  }

  private async rest(path: string, init: RequestInit & { headers?: Record<string, string> } = {}): Promise<Response> {
    const call = async (force: boolean) =>
      send(`${this.url}/rest/v1/${path}`, {
        ...init,
        headers: {
          apikey: this.anonKey,
          Authorization: `Bearer ${await this.accessToken(force)}`,
          'Content-Type': 'application/json',
          ...init.headers,
        },
      })
    let res = await call(false)
    // Jeton expiré entre-temps : un nouvel essai après rafraîchissement
    if (res.status === 401) res = await call(true)
    if (res.status === 401 || res.status === 403) throw new AuthError(await errorText(res))
    if (!res.ok) throw new RemoteError(await errorText(res))
    return res
  }

  private filter(): string {
    return `dossier=eq.${encodeURIComponent(this.dossier)}`
  }

  private async rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const res = await this.rest(`rpc/${name}`, { method: 'POST', body: JSON.stringify({ p_dossier: this.dossier, ...args }) })
    return (await res.json()) as T
  }

  /**
   * Lignes modifiées depuis une date (toutes si null), par pages de 1 000 lues à la suite de la dernière ligne reçue
   * (date, collection, id) : une ligne modifiée pendant la lecture repasse en fin de liste, aucune n'est sautée.
   */
  async pull(since: string | null): Promise<RemoteRow[]> {
    const rows: RemoteRow[] = []
    let after: RemoteRow | null = null
    for (;;) {
      const page: RemoteRow[] = await this.rpc<RemoteRow[]>('pull_records', {
        p_since: since,
        p_after_ts: after?.updated_at ?? null,
        p_after_collection: after?.collection ?? null,
        p_after_id: after?.id ?? null,
        p_limit: PAGE,
      })
      rows.push(...page)
      if (page.length < PAGE) return rows
      after = page[page.length - 1]
    }
  }

  /**
   * Envoi conditionnel par paquets d'au plus 200 lignes et ~400 Ko (images du papier à en-tête) :
   * une ligne modifiée entre-temps sur un autre poste est refusée et renvoyée, jamais écrasée.
   */
  async push(rows: PushRow[]): Promise<PushResult> {
    const result: PushResult = { accepted: [], rejected: [] }
    let chunk: string[] = []
    let size = 0
    const flush = async () => {
      if (!chunk.length) return
      const res = await this.rest('rpc/push_records', {
        method: 'POST',
        body: `{"p_dossier":${JSON.stringify(this.dossier)},"p_rows":[${chunk.join(',')}]}`,
      })
      const part = (await res.json()) as Partial<PushResult>
      result.accepted.push(...(part.accepted ?? []))
      result.rejected.push(...(part.rejected ?? []))
      chunk = []
      size = 0
    }
    try {
      for (const r of rows) {
        const json = JSON.stringify({ collection: r.collection, id: r.id, data: r.data, deleted: r.deleted, rev: r.rev, expected: r.expected })
        if (chunk.length && (chunk.length >= PUSH_CHUNK || size + json.length > PUSH_BYTES)) await flush()
        chunk.push(json)
        size += json.length
      }
      await flush()
    } catch (e) {
      if (result.accepted.length === 0 || !(e instanceof Error)) throw e
      throw new PushError(e, result)
    }
    return result
  }

  /** Parmi ces envois (dont la réponse s'est perdue), ceux qui ont bien été écrits */
  async appliedRevs(revs: string[]): Promise<Set<string>> {
    if (revs.length === 0) return new Set()
    return new Set(await this.rpc<string[]>('applied_revs', { p_revs: revs }))
  }

  /** Le compte connecté figure-t-il dans la liste des membres du dossier ? */
  async isMember(): Promise<boolean> {
    const res = await this.rest(`members?select=dossier&${this.filter()}`)
    return ((await res.json()) as unknown[]).length > 0
  }

  /** Nombre d'enregistrements du dossier en ligne */
  async count(): Promise<number> {
    const res = await this.rest(`records?select=id&${this.filter()}&deleted=is.false`, {
      headers: { Prefer: 'count=exact', Range: '0-0' },
    })
    const range = res.headers.get('Content-Range') ?? ''
    const total = Number(range.split('/')[1])
    return Number.isFinite(total) ? total : (await res.json()).length
  }

  /**
   * Action unique sur une pièce : un seul poste l'obtient (avec le numéro définitif pour une validation).
   * Le même poste qui redemande après une coupure retrouve la même action et le même numéro.
   */
  async claim(docId: string, action: string, device: string, kind: string, year: number, min: number): Promise<Claim> {
    const value = await this.rpc<{ number?: unknown; already?: unknown }>('claim_doc_action', {
      p_doc_id: docId,
      p_action: action,
      p_device: device,
      p_kind: kind,
      p_year: year,
      p_min: min,
    })
    const n = value.number === null || value.number === undefined ? null : Number(value.number)
    if (n !== null && (!Number.isInteger(n) || n < 1)) throw new RemoteError('Numéro invalide reçu du serveur')
    return { number: n, already: value.already === true }
  }
}
FIN_DU_FICHIER
echo "OK src/sync/remote.ts"

cat > src/sync/runtime.ts <<'FIN_DU_FICHIER'
// Instance unique du moteur de synchronisation pour ce poste
import { useSyncExternalStore } from 'react'
import { loadConfig, saveConfig, type SyncConfig } from './config'
import { SyncEngine, type SyncStatus } from './engine'
import { SupabaseRemote } from './remote'

let engine: SyncEngine | null = null
let status: SyncStatus | null = null
const listeners = new Set<() => void>()
let unsubscribe: (() => void) | null = null

function notify() {
  for (const fn of listeners) fn()
}

/** Crée le client et le moteur pour une configuration (sans démarrer la synchro automatique) */
export function createEngine(config: SyncConfig): SyncEngine {
  stopEngine()
  const remote = new SupabaseRemote(config.url, config.anonKey, config.dossier, config.refreshToken, config.email)
  // Le jeton de rafraîchissement change à chaque renouvellement : on garde le dernier
  remote.onSession = (s) => {
    const current = loadConfig()
    if (current) saveConfig({ ...current, refreshToken: s.refreshToken, email: s.email })
  }
  remote.latestRefreshToken = () => loadConfig()?.refreshToken
  engine = new SyncEngine(remote, config.dossier)
  unsubscribe = engine.subscribe((s) => {
    status = s
    notify()
  })
  return engine
}

/** Au lancement : reprend la synchro si ce poste a rejoint un dossier */
export function startFromConfig() {
  const config = loadConfig()
  if (!config?.joined || engine) return
  createEngine(config).start()
}

export function stopEngine() {
  engine?.stop()
  unsubscribe?.()
  unsubscribe = null
  engine = null
  status = null
  notify()
}

export function currentEngine(): SyncEngine | null {
  return engine
}

/** Mode multi-postes actif sur ce poste */
export function isSyncActive(): boolean {
  return engine !== null && loadConfig()?.joined === true
}

/** Relance une synchronisation dès que possible (sans effet si un autre onglet de ce poste synchronise) */
export function syncSoon() {
  void engine?.syncNow()
}

const DONE_KEY = 'profitpilot-sync:done-actions'

function doneActions(): string[] {
  try {
    const list: unknown = JSON.parse(localStorage.getItem(DONE_KEY) ?? '[]')
    return Array.isArray(list) ? list.filter((x): x is string => typeof x === 'string') : []
  } catch {
    return []
  }
}

/**
 * Action unique sur une pièce (validation, annulation, retour de dépôt) en mode multi-postes :
 * le serveur ne l'accorde qu'à un seul poste (et attribue le numéro définitif d'une validation) ;
 * entre deux onglets du même poste, un verrou du navigateur et une marque locale évitent le doublon.
 * En mode un seul poste, l'action est appliquée directement (numéro null).
 * Renvoie 'already' si un autre poste ou onglet l'a déjà faite : rien n'est appliqué ici.
 * Lève une erreur hors ligne : on n'agit pas sans l'accord du serveur.
 */
export async function runDocAction(
  request: { docId: string; action: string; kind: string; year: number; min: number },
  apply: (number: number | null) => void,
): Promise<'applied' | 'already'> {
  const config = loadConfig()
  const current = engine
  if (!current || !config?.joined) {
    apply(null)
    return 'applied'
  }
  const mark = `${config.dossier}:${request.docId}:${request.action}`
  const run = async (): Promise<'applied' | 'already'> => {
    if (doneActions().includes(mark)) return 'already'
    const claim = await current.claim(request.docId, request.action, request.kind, request.year, request.min)
    if (claim.already) {
      syncSoon()
      return 'already'
    }
    apply(claim.number)
    try {
      localStorage.setItem(DONE_KEY, JSON.stringify([...doneActions(), mark].slice(-300)))
    } catch {
      // stockage plein : seul le verrou protège encore les autres onglets
    }
    return 'applied'
  }
  const locks = (navigator as Navigator & { locks?: LockManager }).locks
  return locks ? locks.request(`profitpilot-doc:${mark}`, run) : run()
}

export function useSyncStatus(): SyncStatus | null {
  return useSyncExternalStore(
    (fn) => {
      listeners.add(fn)
      return () => listeners.delete(fn)
    },
    () => status,
  )
}
FIN_DU_FICHIER
echo "OK src/sync/runtime.ts"

cat > src/sync/state.ts <<'FIN_DU_FICHIER'
// État de synchronisation de ce poste, rangé dans IndexedDB (pas dans le localStorage limité à 5 Mo)

/** Envoi parti sans réponse sûre (coupure) : gardé pour reconnaître notre propre écriture à la relecture */
export interface PendingPush {
  rev: string
  data: unknown
  deleted: boolean
}

export interface SyncState {
  /** Empreinte de chaque enregistrement tel que synchronisé : « collection␟id » → empreinte */
  base: Record<string, string>
  /** Date serveur de la version de référence (base) : « collection␟id » → updated_at, renvoyée à l'envoi */
  seen: Record<string, string>
  /** Date serveur la plus récente reçue */
  lastPull: string | null
  /** Dernière version serveur connue de chaque enregistrement (fusion à trois versions) */
  snapshot: Record<string, unknown>
  /** Envois en attente de confirmation, par enregistrement (du plus ancien au plus récent) */
  pending: Record<string, PendingPush[]>
}

const DB = 'profitpilot-sync'
const STORE = 'kv'

export const emptyState = (): SyncState => ({ base: {}, seen: {}, lastPull: null, snapshot: {}, pending: {} })

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') return reject(new Error('IndexedDB indisponible'))
    const req = indexedDB.open(DB, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

export async function loadState(dossier: string): Promise<SyncState> {
  try {
    const db = await open()
    return await new Promise((resolve) => {
      const req = db.transaction(STORE, 'readonly').objectStore(STORE).get(dossier)
      req.onsuccess = () => resolve({ ...emptyState(), ...((req.result as SyncState | undefined) ?? {}) })
      req.onerror = () => resolve(emptyState())
    })
  } catch {
    return emptyState()
  }
}

/**
 * Enregistre l'état. Si IndexedDB est indisponible (navigation privée…), l'état reste en mémoire :
 * la synchronisation continue ; après un rechargement, ce poste repart de la version en ligne
 * (règle « jamais vu sur ce poste : la version en ligne fait foi »), sans rien écraser chez les autres.
 */
export async function saveState(dossier: string, state: SyncState): Promise<void> {
  try {
    const db = await open()
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite')
      tx.objectStore(STORE).put(state, dossier)
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  } catch {
    // IndexedDB indisponible : état gardé en mémoire
  }
}

export async function clearState(dossier: string): Promise<void> {
  try {
    const db = await open()
    await new Promise<void>((resolve) => {
      const tx = db.transaction(STORE, 'readwrite')
      tx.objectStore(STORE).delete(dossier)
      tx.oncomplete = () => resolve()
      tx.onerror = () => resolve()
    })
  } catch {
    // rien à effacer
  }
}
FIN_DU_FICHIER
echo "OK src/sync/state.ts"

cat > src/sync/sync.css <<'FIN_DU_FICHIER'
.sync-small { font-size: 13px !important; word-break: break-all; }
.sync-steps { margin: 4px 0 8px; padding-left: 20px; line-height: 1.6; }
.sync-invite { display: flex; gap: 8px; align-items: center; }
.sync-invite code {
  flex: 1;
  padding: 6px 8px;
  background: #f4f6f9;
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  font-size: 12px;
  word-break: break-all;
}
FIN_DU_FICHIER
echo "OK src/sync/sync.css"

cat > src/pro-theme.css <<'FIN_DU_FICHIER'
/*
 * Thème « progiciel de gestion » (inspiré de Sage 100) : navigation à gauche en sections,
 * bandeau de titre, boutons et grilles compacts. Chargé après theme.css, il le complète.
 */
.layout {
  display: flex;
  min-height: 100vh;
  background: var(--pp-bg);
  color: var(--pp-text);
  font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
  font-size: 13px;
}

/* ---------- Navigation ---------- */
.layout .sidebar {
  width: 236px;
  flex-shrink: 0;
  position: sticky;
  top: 0;
  height: 100vh;
  overflow-y: auto;
  background: #f4f6f9;
  border-right: 1px solid var(--pp-border);
  padding: 0;
  color: var(--pp-text);
}
.layout .sidebar .brand {
  background: var(--pp-blue);
  color: #fff;
  font-size: 16px;
  font-weight: 700;
  letter-spacing: 0.5px;
  padding: 14px 16px;
}
.layout .sidebar .brand small { display: block; font-size: 11px; font-weight: 400; opacity: 0.8; letter-spacing: 0; }
.layout .sidebar nav { padding: 0 0 16px; display: block; }
.nav-section-title {
  margin-top: 6px;
  padding: 5px 14px;
  background: linear-gradient(#e3e9f0, #d6dee8);
  border-top: 1px solid var(--pp-border);
  border-bottom: 1px solid var(--pp-border);
  color: var(--pp-title);
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.6px;
}
.layout .sidebar .nav-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  margin: 0;
  padding: 6px 14px 6px 18px;
  background: none;
  border: 0;
  border-left: 3px solid transparent;
  border-radius: 0;
  color: var(--pp-text);
  font: inherit;
  font-size: 13px;
  text-align: left;
  cursor: pointer;
  box-shadow: none;
}
.layout .sidebar .nav-item:hover { background: var(--pp-hover); }
.layout .sidebar .nav-item.active {
  background: var(--pp-select);
  border-left-color: var(--pp-blue-2);
  font-weight: 600;
  color: var(--pp-blue);
}
.nav-badge {
  min-width: 18px;
  padding: 0 6px;
  border-radius: 9px;
  background: #d97706;
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  text-align: center;
}

/* ---------- Zone de travail ---------- */
.layout .content { flex: 1; min-width: 0; padding: 0 20px 28px; }
.layout .content > h1 {
  margin: 0 -20px 12px;
  padding: 11px 20px;
  background: #fff;
  border-bottom: 1px solid var(--pp-border);
  color: var(--pp-blue);
  font-size: 18px;
  font-weight: 600;
}
.layout .content h2 { font-size: 14px; color: var(--pp-title); }

.layout .content button {
  font: inherit;
  font-size: 12.5px;
  padding: 4px 10px;
  border: 1px solid #9fb0c3;
  border-radius: 3px;
  background: linear-gradient(#ffffff, #e9eef4);
  color: var(--pp-text);
  cursor: pointer;
  box-shadow: none;
}
.layout .content button:hover:not(:disabled) { background: linear-gradient(#f4f8fc, #dce7f3); border-color: var(--pp-blue-2); }
.layout .content button:disabled { opacity: 0.5; cursor: not-allowed; }
.layout .content button.btn-primary {
  background: linear-gradient(#3a7fcb, #255f9f);
  border-color: var(--pp-blue);
  color: #fff;
  font-weight: 600;
}
.layout .content button.btn-primary:hover:not(:disabled) { background: linear-gradient(#2f72ba, #1f4e85); }

.layout .content input:not([type='checkbox']):not([type='radio']):not([type='file']),
.layout .content select,
.layout .content textarea {
  font: inherit;
  font-size: 13px;
  padding: 3px 6px;
  min-height: 26px;
  border: 1px solid #aebbc9;
  border-radius: 2px;
  background: #fff;
  color: var(--pp-text);
  box-sizing: border-box;
}
.layout .content input:focus,
.layout .content select:focus,
.layout .content textarea:focus {
  outline: none;
  border-color: var(--pp-blue-2);
  box-shadow: 0 0 0 2px rgba(43, 108, 176, 0.2);
}

/* Grilles des autres écrans (tableau de bord, stock, rentabilité…) */
.layout .content table:not(.doc-ref-table):not(.sheet-frame) {
  border-collapse: collapse;
  background: #fff;
  border: 1px solid var(--pp-border);
  font-size: 12.5px;
}
.layout .content table:not(.doc-ref-table):not(.sheet-frame) th {
  background: linear-gradient(var(--pp-head-1), var(--pp-head-2));
  color: var(--pp-title);
  font-weight: 600;
  padding: 6px 8px;
  border-bottom: 1px solid #b5c1ce;
}
.layout .content table:not(.doc-ref-table):not(.sheet-frame) td { padding: 4px 8px; border-bottom: 1px solid var(--pp-border-soft); }
.layout .content table:not(.doc-ref-table):not(.sheet-frame) tbody tr:nth-child(even) { background: var(--pp-zebra); }
.layout .content table:not(.doc-ref-table):not(.sheet-frame) tbody tr:hover { background: var(--pp-hover); }

.layout .content .card {
  background: #fff;
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  box-shadow: none;
  padding: 12px 14px;
  margin-bottom: 12px;
}
.layout .content .card > h2:first-child {
  margin: -12px -14px 10px;
  padding: 7px 14px;
  background: linear-gradient(var(--pp-head-1), var(--pp-head-2));
  border-bottom: 1px solid var(--pp-border);
}
.layout .content .export-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  align-items: center;
  background: var(--pp-head-1);
  border: 1px solid var(--pp-border);
  border-radius: 3px;
  padding: 6px 8px;
  margin-bottom: 10px;
}
.layout .content .badge { border-radius: 2px; }

@media print {
  .layout { display: block; background: #fff; }
  .layout .sidebar { display: none; }
  .layout .content > h1 { margin: 0 0 8px; border: 0; padding: 0; }
}
FIN_DU_FICHIER
echo "OK src/pro-theme.css"

cat > src/components/Sidebar.tsx <<'FIN_DU_FICHIER'
import type { PageId } from '../types'
import { ADMIN_PAGES, PAGE_LABELS, type ModuleDef } from '../shell/navigation'
import { useAccess } from '../access/context'

interface SidebarProps {
  module: ModuleDef
  current: PageId
  onNavigate: (page: PageId) => void
  /** Compteurs d'alertes affichés à côté des pages (factures échues, lots périmés…) */
  badges?: Partial<Record<PageId, number>>
}

/** Menu du module en cours, rubrique par rubrique */
export default function Sidebar({ module, current, onNavigate, badges }: SidebarProps) {
  const { isAdmin } = useAccess()
  return (
    <aside className="sidebar no-print">
      <div className="brand">{module.label}</div>
      <nav>
        {module.groups.map((group) => {
          const pages = group.pages.filter((id) => isAdmin || !ADMIN_PAGES.includes(id))
          if (pages.length === 0) return null
          return (
          <div key={group.title}>
            <div className="nav-section-title">{group.title}</div>
            {pages.map((id) => {
              const badge = badges?.[id]
              return (
                <button
                  key={id}
                  className={id === current ? 'nav-item active' : 'nav-item'}
                  onClick={() => onNavigate(id)}
                >
                  {PAGE_LABELS[id]}
                  {!!badge && <span className="nav-badge">{badge}</span>}
                </button>
              )
            })}
          </div>
          )
        })}
      </nav>
    </aside>
  )
}
FIN_DU_FICHIER
echo "OK src/components/Sidebar.tsx"

cat > src/components/Dashboard.tsx <<'FIN_DU_FICHIER'
import type { PageId, Product } from '../types'
import KpiCard from './KpiCard'
import {
  computeProductMetrics,
  computeTotals,
  formatEuro,
  formatPercent,
} from '../utils/finance'
import { getStockStatus } from '../utils/stock'
import type { CommercialDocument, StockLot } from '../documents/types'
import { computeTotals as computeDocTotals, formatMAD, round2 } from '../documents/tva'
import { today } from '../documents/numbering'
import { balanceOf, isActive, isOverdue, sign } from '../documents/ledger'
import { expiryState } from '../documents/stockMoves'

interface DashboardProps {
  products: Product[]
  /** Devis, BC, BL et factures : alimentent le bloc « Ventes » */
  documents?: CommercialDocument[]
  lots?: StockLot[]
  onNavigate?: (page: PageId) => void
}

function badgeClass(rate: number): string {
  if (rate >= 40) return 'badge badge-good'
  if (rate >= 20) return 'badge badge-medium'
  return 'badge badge-low'
}

function rateTone(rate: number): 'good' | 'medium' | 'low' {
  if (rate >= 40) return 'good'
  if (rate >= 20) return 'medium'
  return 'low'
}

/** Synthèse commerciale en dirhams : facturé du mois (net d'avoirs), encours, retards, devis, achats à payer */
function salesSummary(documents: CommercialDocument[]) {
  const now = today()
  const month = now.slice(0, 7)
  let monthHT = 0
  let unpaid = 0
  let late = 0
  let lateCount = 0
  let invoiceCount = 0
  let toPay = 0
  for (const d of documents) {
    if (!isActive(d)) continue
    if (d.kind === 'invoice' || d.kind === 'credit') {
      if (d.kind === 'invoice') invoiceCount++
      if (d.date.startsWith(month)) monthHT += sign(d) * computeDocTotals(d).totalHT
    }
    if (d.kind === 'invoice') unpaid += balanceOf(d, documents)
    if (d.kind === 'bill') toPay += balanceOf(d, documents)
    if (d.kind === 'invoice' && isOverdue(d, documents, now)) {
      late += balanceOf(d, documents)
      lateCount++
    }
  }
  // Devis encore ouverts : validés, non expirés et pas encore transformés
  const converted = new Set(documents.map((d) => d.sourceId).filter(Boolean))
  const openQuotes = documents.filter(
    (d) => d.kind === 'quote' && d.status === 'validated' && !converted.has(d.id) && d.dueDate >= now,
  )
  const quotesHT = openQuotes.reduce((s, d) => s + computeDocTotals(d).totalHT, 0)
  const depotItems = documents.reduce(
    (n, d) => n + (d.consignment && d.status === 'validated' ? d.lines.filter((l) => l.depot === 'depot').length : 0),
    0,
  )
  return {
    active: invoiceCount > 0 || openQuotes.length > 0 || depotItems > 0 || toPay > 0,
    invoiceCount,
    monthHT: round2(monthHT),
    unpaid: round2(unpaid),
    late: round2(late),
    lateCount,
    openQuotes: openQuotes.length,
    quotesHT: round2(quotesHT),
    depotItems,
    toPay: round2(toPay),
  }
}

export default function Dashboard({ products, documents = [], lots = [], onNavigate }: DashboardProps) {
  if (products.length === 0) {
    return (
      <div className="card">
        <p className="muted">
          Aucun produit pour le moment. Ajoute des produits dans « Mes produits » ou importe un fichier CSV.
        </p>
      </div>
    )
  }

  const totals = computeTotals(products)
  const rows = products
    .map(computeProductMetrics)
    .sort((a, b) => b.margin - a.margin)
  const maxMargin = Math.max(...rows.map((r) => r.margin), 1)

  const best = rows[0]
  const weakest = [...rows].sort((a, b) => a.marginRate - b.marginRate)[0]
  const top3Margin = rows.slice(0, 3).reduce((sum, r) => sum + r.margin, 0)
  const top3Share = totals.margin > 0 ? (top3Margin / totals.margin) * 100 : 0

  const sales = salesSummary(documents)
  const lotAlerts = lots.filter((l) => l.quantity > 0 && ['expired', 'soon'].includes(expiryState(l.expiry)))
  const expiredLots = lotAlerts.filter((l) => expiryState(l.expiry) === 'expired').length
  const stockAlerts = products
    .map((p) => ({ product: p, status: getStockStatus(p) }))
    .filter((x) => x.status === 'out' || x.status === 'low')
    .sort((a, b) => (a.status === b.status ? 0 : a.status === 'out' ? -1 : 1))

  return (
    <div>
      <div className="kpi-grid">
        <KpiCard
          label="Chiffre d'affaires"
          value={formatEuro(totals.revenue)}
          hint={`${products.length} produits`}
          tone="primary"
        />
        <KpiCard label="Coûts variables" value={formatEuro(totals.totalCost)} tone="neutral" />
        <KpiCard label="Marge brute" value={formatEuro(totals.margin)} tone="good" />
        <KpiCard
          label="Taux de marge"
          value={formatPercent(totals.marginRate)}
          hint="Marge brute / chiffre d'affaires"
          tone={rateTone(totals.marginRate)}
        />
      </div>

      {sales.active && (
        <>
          <h2>Ventes</h2>
          <div className="kpi-grid">
            <KpiCard label="Facturé ce mois (HT)" value={formatMAD(sales.monthHT)} tone="primary" />
            <KpiCard
              label="Reste à encaisser"
              value={formatMAD(sales.unpaid)}
              hint={`${sales.invoiceCount} facture(s) émise(s)`}
              tone="neutral"
            />
            <KpiCard
              label="Factures en retard"
              value={formatMAD(sales.late)}
              hint={`${sales.lateCount} facture(s) à relancer`}
              tone={sales.lateCount > 0 ? 'low' : 'good'}
            />
            <KpiCard
              label="Devis en cours"
              value={formatMAD(sales.quotesHT)}
              hint={`${sales.openQuotes} devis à transformer`}
              tone="medium"
            />
            <KpiCard
              label="Implants en dépôt"
              value={String(sales.depotItems)}
              hint="chez les cliniques, à facturer à la pose"
              tone="neutral"
            />
            <KpiCard label="Fournisseurs à payer" value={formatMAD(sales.toPay)} tone="neutral" />
          </div>
        </>
      )}

      {stockAlerts.length > 0 && (
        <div className="card">
          <div className="insight-label">Alertes stock</div>
          <div className="insight-title">
            {stockAlerts.filter((x) => x.status === 'out').length} rupture(s),{' '}
            {stockAlerts.filter((x) => x.status === 'low').length} sous le seuil
          </div>
          <ul>
            {stockAlerts.slice(0, 5).map(({ product, status }) => (
              <li key={product.id}>
                <span className={status === 'out' ? 'badge badge-low' : 'badge badge-medium'}>
                  {status === 'out' ? 'Rupture' : 'Seuil'}
                </span>{' '}
                {product.name} : {product.stock ?? 0} en stock
                {product.minStock ? ` (seuil ${product.minStock})` : ''}
              </li>
            ))}
          </ul>
          {onNavigate && (
            <button type="button" onClick={() => onNavigate('stock')}>
              Voir le stock
            </button>
          )}
        </div>
      )}

      {lotAlerts.length > 0 && (
        <div className="card">
          <div className="insight-label">Péremptions</div>
          <div className="insight-title">
            {expiredLots} lot(s) périmé(s), {lotAlerts.length - expiredLots} à moins de 90 jours
          </div>
          {onNavigate && (
            <button type="button" onClick={() => onNavigate('lots')}>
              Voir les lots
            </button>
          )}
        </div>
      )}

      {rows.length >= 2 && (
        <div className="insight-grid">
          <div className="card">
            <div className="insight-label">Produit le plus rentable</div>
            <div className="insight-title">{best.product.name}</div>
            <div className="insight-text">
              {formatEuro(best.margin)} de marge brute, taux de {formatPercent(best.marginRate)}
            </div>
          </div>
          <div className="card">
            <div className="insight-label">Taux de marge le plus faible</div>
            <div className="insight-title">{weakest.product.name}</div>
            <div className="insight-text">
              {formatPercent(weakest.marginRate)} de taux de marge pour {formatEuro(weakest.revenue)} de chiffre d'affaires
            </div>
          </div>
          <div className="card">
            <div className="insight-label">Concentration</div>
            <div className="insight-title">{formatPercent(top3Share)}</div>
            <div className="insight-text">
              de la marge brute vient des {Math.min(3, rows.length)} premiers produits
            </div>
          </div>
        </div>
      )}

      <div className="card">
        <h2>Marge par produit</h2>
        <table>
          <thead>
            <tr>
              <th>Produit</th>
              <th>Catégorie</th>
              <th className="num">CA</th>
              <th className="num">Marge</th>
              <th className="num">Taux</th>
              <th>Contribution</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.product.id}>
                <td>{r.product.name}</td>
                <td>{r.product.category}</td>
                <td className="num">{formatEuro(r.revenue)}</td>
                <td className="num">{formatEuro(r.margin)}</td>
                <td className="num">
                  <span className={badgeClass(r.marginRate)}>{formatPercent(r.marginRate)}</span>
                </td>
                <td>
                  <div className="bar">
                    <div
                      className="bar-fill"
                      style={{ width: `${Math.max((r.margin / maxMargin) * 100, 0)}%` }}
                    />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/components/Dashboard.tsx"

cat > src/App.tsx <<'FIN_DU_FICHIER'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
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
import StockMovesPage from './documents/StockMovesPage'
import InventoryPage from './documents/InventoryPage'
import SchedulePage from './documents/SchedulePage'
import StatsPage from './documents/StatsPage'
import { getStockStatus } from './utils/stock'
import { isOverdue } from './documents/ledger'
import { applyMove, expiryState } from './documents/stockMoves'
import { useCashBalance, useCompany, useDocuments, useKits, useLots, useMovements, useParties } from './documents/storage'
import type { DocKind, DocLine, StockMovement } from './documents/types'
import { CURRENCIES, setCurrency } from './utils/finance'
import TopBar, { type Notification } from './shell/TopBar'
import ModuleBar from './shell/ModuleBar'
import WorkTabs from './shell/WorkTabs'
import StatusBar from './shell/StatusBar'
import GlobalSearch, { type SearchHit } from './shell/GlobalSearch'
import Launchpad from './shell/Launchpad'
import { ADMIN_PAGES, MODULES, moduleOf, type ModuleId } from './shell/navigation'
import { LAST_BACKUP_KEY, STORAGE_ERROR_EVENT } from './documents/storage'
import { AccessContext, accessFor } from './access/context'
import SyncPage from './sync/SyncPage'
import { startFromConfig, useSyncStatus } from './sync/runtime'
import { readSession, useAccessSettings, useAudit, useUsers, writeSession } from './access/storage'
import type { AuditEntry, User } from './access/types'
import LoginScreen from './access/LoginScreen'
import UsersPage from './access/UsersPage'
import AuditPage from './access/AuditPage'
import { AccessDenied, ReadOnlyArea } from './access/ReadOnly'
import { daysBetween, newId, today } from './documents/numbering'
import './theme.css'
import './documents/documents.css'
import './pro-theme.css'
import './shell/shell.css'

const STORAGE_KEY = 'profitpilot:v1'
const FIXED_KEY = 'profitpilot:fixed:v1'
const CURRENCY_KEY = 'profitpilot:currency:v1'

const titles: Record<PageId, string> = {
  home: 'Accueil',
  dashboard: 'Tableau de bord',
  catalog: 'Mes produits',
  stock: 'Gestion du stock',
  alerts: 'Alertes de stock',
  movements: 'Mouvements de stock',
  inventory: 'Inventaire physique',
  stats: 'Statistiques des ventes',
  schedule: 'Échéancier et trésorerie prévisionnelle',
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
  company: 'Société et mise en page des documents',
  backup: 'Sauvegarde des données',
  users: 'Utilisateurs et droits d’accès',
  sync: 'Multi-postes : utiliser l’ERP sur plusieurs ordinateurs',
  audit: 'Journal d’activité',
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
  'home',
  'depots',
  'clients',
  'suppliers',
  'lots',
  'kits',
  'alerts',
  'movements',
  'inventory',
  'stats',
  'schedule',
  'vat',
  'company',
  'backup',
  'users',
  'audit',
  'sync',
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
  const [page, setPage] = useState<PageId>('home')
  // Onglets de travail : écrans ouverts récemment
  const [tabs, setTabs] = useState<PageId[]>(['home'])
  const [searchOpen, setSearchOpen] = useState(false)
  const [lotQuery, setLotQuery] = useState('')
  const [partyId, setPartyId] = useState<string | undefined>()
  // Pièce à ouvrir directement en arrivant sur une page (après une conversion ou une facturation de dépôt)
  const [openId, setOpenId] = useState<string | undefined>()
  // Chaque ouverture demandée (Créer, recherche, lien) repart d'une vue neuve, même sur la page déjà affichée
  const [openSeq, setOpenSeq] = useState(0)
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
  const [movements, setMovements] = useMovements()
  const [cash, setCash] = useCashBalance()
  // Bandeau d'alerte de stock masquable jusqu'au prochain chargement
  const [alertBannerHidden, setAlertBannerHidden] = useState(false)

  // ---------- Utilisateurs, session et journal d'activité ----------
  const [users, setUsers] = useUsers()
  const [audit, setAudit] = useAudit()
  const [accessSettings, setAccessSettings] = useAccessSettings()
  const [sessionId, setSessionId] = useState(readSession)
  const [locked, setLocked] = useState(false)
  const currentUser = users.find((u) => u.id === sessionId && u.active) ?? null
  const needsLogin = users.length > 0 && (!currentUser || locked)

  const log = useCallback(
    (action: string, detail: string, who?: string) => {
      const entry: AuditEntry = { id: newId(), at: new Date().toISOString(), user: who ?? currentUser?.name ?? 'Administrateur (installation)', action, detail }
      // On garde les 5 000 dernières actions
      setAudit((a) => [...a, entry].slice(-5000))
    },
    [currentUser, setAudit],
  )
  const access = useMemo(() => accessFor(currentUser, log), [currentUser, log])

  function login(user: User) {
    const at = new Date().toISOString()
    setUsers((list) => list.map((u) => (u.id === user.id ? { ...u, lastLogin: at } : u)))
    writeSession(user.id)
    setSessionId(user.id)
    log(locked && user.id === sessionId ? 'Session déverrouillée' : 'Connexion', user.name, user.name)
    // Changement d'utilisateur : on repart de l'accueil (pas à la création du premier compte)
    if (sessionId && user.id !== sessionId) {
      setPage('home')
      setTabs(['home'])
    }
    setLocked(false)
  }

  function logout() {
    log('Déconnexion', currentUser?.name ?? '')
    writeSession(null)
    setSessionId(null)
    setLocked(false)
    setPage('home')
    setTabs(['home'])
  }

  // Verrouillage automatique après inactivité
  useEffect(() => {
    if (!currentUser || locked || !accessSettings.lockMinutes) return
    let timer = window.setTimeout(() => setLocked(true), accessSettings.lockMinutes * 60_000)
    const reset = () => {
      window.clearTimeout(timer)
      timer = window.setTimeout(() => setLocked(true), accessSettings.lockMinutes * 60_000)
    }
    const events = ['mousemove', 'keydown', 'click', 'scroll', 'touchstart']
    for (const e of events) window.addEventListener(e, reset, { passive: true })
    return () => {
      window.clearTimeout(timer)
      for (const e of events) window.removeEventListener(e, reset)
    }
  }, [currentUser, locked, accessSettings.lockMinutes])

  useEffect(() => {
    try {
      const raw = JSON.stringify({ products, isSampleData })
      if (localStorage.getItem(STORAGE_KEY) !== raw) localStorage.setItem(STORAGE_KEY, raw)
    } catch {
      window.dispatchEvent(new CustomEvent(STORAGE_ERROR_EVENT, { detail: STORAGE_KEY }))
    }
  }, [products, isSampleData])

  // Stockage plein : on prévient au lieu de perdre les saisies en silence
  const [storageFull, setStorageFull] = useState(false)
  useEffect(() => {
    const onError = () => setStorageFull(true)
    // Articles modifiés dans un autre onglet : on reprend leur version
    const onStorage = (e: StorageEvent) => {
      if (e.key !== STORAGE_KEY || !e.newValue) return
      const saved = loadSaved()
      if (saved) {
        setProducts(saved.products)
        setIsSampleData(saved.isSampleData)
      }
    }
    window.addEventListener(STORAGE_ERROR_EVENT, onError)
    window.addEventListener('storage', onStorage)
    return () => {
      window.removeEventListener(STORAGE_ERROR_EVENT, onError)
      window.removeEventListener('storage', onStorage)
    }
  }, [])

  useEffect(() => {
    try {
      const raw = JSON.stringify(fixedCosts)
      if (localStorage.getItem(FIXED_KEY) !== raw) localStorage.setItem(FIXED_KEY, raw)
    } catch {
      window.dispatchEvent(new CustomEvent(STORAGE_ERROR_EVENT, { detail: FIXED_KEY }))
    }
  }, [fixedCosts])

  // Charges fixes et devise modifiées sur un autre poste ou un autre onglet
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === FIXED_KEY) setFixedCosts(loadFixedCosts())
      if (e.key === CURRENCY_KEY) {
        const code = loadCurrency()
        setCurrency(code)
        setCurrencyState(code)
      }
    }
    window.addEventListener('storage', onStorage)
    return () => window.removeEventListener('storage', onStorage)
  }, [])

  // Mode multi-postes : reprise de la synchronisation au lancement
  useEffect(() => {
    startFromConfig()
  }, [])
  const syncStatus = useSyncStatus()

  function changeCurrency(code: string) {
    setCurrency(code)
    setCurrencyState(code)
    try {
      localStorage.setItem(CURRENCY_KEY, code)
    } catch {
      // stockage indisponible : on continue sans sauvegarde
    }
  }

  function show(next: PageId) {
    setPage(next)
    setTabs((t) => (t.includes(next) ? t : [...t, next].slice(-8)))
  }

  function navigate(next: PageId) {
    setOpenId(undefined)
    setPartyId(undefined)
    setLotQuery('')
    show(next)
  }

  function openDocument(kind: DocKind, id?: string) {
    setOpenId(id)
    setOpenSeq((n) => n + 1)
    show(pageOfKind[kind])
  }

  function closeTab(t: PageId) {
    const rest = tabs.filter((x) => x !== t)
    const next = rest.length ? rest : (['home'] as PageId[])
    setTabs(next)
    if (t === page) navigate(next[next.length - 1])
  }

  function pickSearch(hit: SearchHit) {
    setSearchOpen(false)
    if (hit.type === 'doc') return openDocument(hit.doc.kind, hit.doc.id)
    if (hit.type === 'party') {
      navigate(hit.party.role === 'client' ? 'clients' : 'suppliers')
      return setPartyId(hit.party.id)
    }
    if (hit.type === 'product') return navigate('catalog')
    navigate('lots')
    setLotQuery(hit.lot.serial || hit.lot.lot)
  }

  // Raccourcis clavier : Cmd/Ctrl+K recherche, Alt+1…7 modules
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setSearchOpen((o) => !o)
      }
      if (e.altKey && /^[1-7]$/.test(e.key)) {
        e.preventDefault()
        const m = MODULES[Number(e.key) - 1]
        setOpenId(undefined)
        setPage(m.groups[0].pages[0])
        setTabs((t) => (t.includes(m.groups[0].pages[0]) ? t : [...t, m.groups[0].pages[0]].slice(-8)))
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  function handleEdit(next: Product[]) {
    setProducts(next)
    setIsSampleData(false)
  }

  // BL, réceptions et retours de dépôt : mise à jour du stock des articles et des lots
  // Dernières valeurs connues : un mouvement de stock peut suivre une attente réseau (validation multi-postes)
  const latest = useRef({ products, lots })
  useEffect(() => {
    latest.current = { products, lots }
  }, [products, lots])

  function handleStockMove(lines: DocLine[], direction: 1 | -1, supplier?: string, reference?: string): Record<string, number> {
    const result = applyMove(latest.current, lines, direction, supplier, reference)
    latest.current = { products: result.products, lots: result.lots }
    handleEdit(result.products)
    setLots(result.lots)
    addMovements(result.movements)
    if (result.shortages.length) alert('Stock insuffisant, ramené à 0 pour :\n' + result.shortages.join('\n'))
    return result.moved
  }

  function addMovements(added: StockMovement[]) {
    if (added.length) setMovements((m) => [...m, ...added])
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

  const lastBackup = (() => {
    try {
      return localStorage.getItem(LAST_BACKUP_KEY) ?? ''
    } catch {
      return ''
    }
  })()

  const notifications = useMemo<Notification[]>(() => {
    const list: Notification[] = []
    if (badges.invoices) list.push({ id: 'inv', severity: 'danger', page: 'invoices', text: `${badges.invoices} facture(s) client échue(s) à relancer` })
    if (badges.bills) list.push({ id: 'bill', severity: 'warning', page: 'bills', text: `${badges.bills} facture(s) fournisseur échue(s)` })
    if (stockAlerts.out) list.push({ id: 'out', severity: 'danger', page: 'alerts', text: `${stockAlerts.out} article(s) en rupture de stock` })
    if (stockAlerts.low) list.push({ id: 'low', severity: 'warning', page: 'alerts', text: `${stockAlerts.low} article(s) sous le seuil d'alerte` })
    if (stockAlerts.expired) list.push({ id: 'exp', severity: 'danger', page: 'lots', text: `${stockAlerts.expired} lot(s) périmé(s) à retirer` })
    if (badges.depots) list.push({ id: 'dep', severity: 'info', page: 'depots', text: `${badges.depots} implant(s) en dépôt chez les cliniques` })
    if (!lastBackup || daysBetween(lastBackup, today()) > 7)
      list.push({ id: 'bak', severity: 'warning', page: 'backup', text: lastBackup ? 'Dernière sauvegarde il y a plus de 7 jours' : 'Aucune sauvegarde effectuée' })
    // Chacun ne voit que les alertes des modules qui lui sont ouverts
    return list.filter((n) => access.level(moduleOf(n.page).id) !== 'none')
  }, [badges, stockAlerts, lastBackup, access])

  const currentModule = moduleOf(page)
  const pageLevel = access.level(currentModule.id)
  const pageAllowed = pageLevel !== 'none' && (access.isAdmin || !ADMIN_PAGES.includes(page))
  // Pages d'origine sans gestion des droits : en lecture seule, on désactive leurs champs
  const lockFields = ['catalog', 'stock', 'import', 'breakeven'].includes(page)

  // Recherche limitée à ce que l'utilisateur a le droit de voir
  const searchable = {
    documents: documents.filter((d) => access.level(d.kind === 'purchase' || d.kind === 'receipt' || d.kind === 'bill' ? 'purchases' : 'sales') !== 'none'),
    parties: parties.filter((p) => access.level(p.role === 'client' ? 'sales' : 'purchases') !== 'none'),
    products: access.level('stock') !== 'none' ? products : [],
    lots: access.level('stock') !== 'none' ? lots : [],
  }

  if (needsLogin)
    return (
      <LoginScreen
        users={users}
        companyName={company.name}
        logo={company.logo}
        lockedUser={locked && currentUser ? currentUser : undefined}
        onLogin={login}
      />
    )

  const moduleBadges: Partial<Record<ModuleId, number>> = {
    sales: badges.invoices,
    purchases: badges.bills,
    stock: stockAlerts.total,
  }

  return (
    <AccessContext.Provider value={access}>
    <div className="layout erp">
      <TopBar
        companyName={company.name}
        notifications={notifications}
        onSearch={() => setSearchOpen(true)}
        onNavigate={navigate}
        onCreate={(kind) => openDocument(kind, 'new')}
        onLock={() => {
          log('Session verrouillée', currentUser?.name ?? '')
          setLocked(true)
        }}
        onLogout={logout}
      />
      <ModuleBar current={currentModule.id} onOpen={navigate} badges={moduleBadges} />
      <div className="erp-body">
      {currentModule.id !== 'home' && (
        <Sidebar module={currentModule} current={page} onNavigate={navigate} badges={badges} />
      )}
      <main className="content">
        <WorkTabs tabs={tabs} current={page} onOpen={navigate} onClose={closeTab} />
        <div className="erp-breadcrumb no-print">
          <button type="button" onClick={() => navigate('home')}>
            Accueil
          </button>
          {currentModule.id !== 'home' && (
            <>
              <span>›</span>
              <button type="button" onClick={() => navigate(currentModule.groups[0].pages[0])}>
                {currentModule.label}
              </button>
            </>
          )}
          {page !== 'home' && (
            <>
              <span>›</span>
              <strong>{titles[page]}</strong>
            </>
          )}
        </div>
        <p className="print-only">
          ProfitPilot · {titles[page]} · {new Date().toLocaleDateString('fr-FR')} · {currency}
          {isSampleData ? ' · données de démonstration' : ''}
        </p>
        {storageFull && (
          <div className="stock-alert-banner no-print">
            <span>
              <strong>Espace de stockage plein :</strong> vos dernières modifications n'ont pas pu être enregistrées.
              Téléchargez une sauvegarde tout de suite, puis allégez les images (logo, papier à en-tête) ou le
              journal d'activité.
            </span>
            <button type="button" onClick={() => navigate('backup')}>
              Sauvegarde
            </button>
          </div>
        )}
        {page !== 'home' && <h1>{titles[page]}</h1>}
        {stockAlerts.total > 0 && !alertBannerHidden && page !== 'alerts' && page !== 'home' && access.level('stock') !== 'none' && (
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
        {!pageAllowed && <AccessDenied />}
        {pageAllowed && (
        <ReadOnlyArea readOnly={pageLevel === 'read'} lock={lockFields}>
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
        {page === 'home' && (
          <Launchpad
            companyName={company.name}
            documents={documents}
            products={products}
            lots={lots}
            cash={cash}
            onNavigate={navigate}
            onOpenDocument={openDocument}
            onCreate={(kind) => openDocument(kind, 'new')}
          />
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
            key={`${docKind}:${openId ?? ''}:${openSeq}`} // réinitialise la vue en changeant de page ou à chaque ouverture
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
          <PartiesPage key={partyId} role="client" parties={parties} onChange={setParties} documents={documents} company={company} openId={partyId} />
        )}
        {page === 'suppliers' && (
          <PartiesPage key={partyId} role="supplier" parties={parties} onChange={setParties} documents={documents} company={company} openId={partyId} />
        )}
        {page === 'lots' && (
          <LotsPage key={lotQuery} lots={lots} onChange={setLots} products={products} documents={documents} initialQuery={lotQuery} />
        )}
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
        {page === 'movements' && <StockMovesPage movements={movements} products={products} />}
        {page === 'inventory' && (
          <InventoryPage products={products} onProductsChange={handleEdit} onMovements={addMovements} />
        )}
        {page === 'stats' && <StatsPage documents={documents} products={products} />}
        {page === 'schedule' && (
          <SchedulePage documents={documents} cash={cash} onCashChange={setCash} onNavigate={openDocument} />
        )}
        {page === 'kits' && <KitsPage kits={kits} onChange={setKits} products={products} />}
        {page === 'vat' && <VatPage documents={documents} />}
        {page === 'company' && <CompanySettings company={company} onChange={setCompany} />}
        {page === 'backup' && <BackupPage />}
        {page === 'users' && (
          <UsersPage
            users={users}
            onChange={setUsers}
            settings={accessSettings}
            onSettingsChange={setAccessSettings}
            onFirstAdmin={login}
          />
        )}
        {page === 'audit' && <AuditPage entries={audit} />}
        {page === 'sync' && <SyncPage />}
        </ReadOnlyArea>
        )}
      </main>
      </div>
      <StatusBar
        companyName={company.name}
        documentsCount={documents.length}
        productsCount={products.length}
        lastBackup={lastBackup}
        sync={syncStatus}
        onOpenSync={() => navigate('sync')}
      />
      {searchOpen && (
        <GlobalSearch
          documents={searchable.documents}
          parties={searchable.parties}
          products={searchable.products}
          lots={searchable.lots}
          onPick={pickSearch}
          onClose={() => setSearchOpen(false)}
        />
      )}
    </div>
    </AccessContext.Provider>
  )
}
FIN_DU_FICHIER
echo "OK src/App.tsx"

cat > supabase/schema.sql <<'FIN_DU_FICHIER'
-- ProfitPilot ERP : préparation de la base en ligne (Supabase)
-- À exécuter UNE fois : Supabase › SQL Editor › New query › coller ce fichier › Run.
-- Le script peut être relancé sans danger (après une mise à jour de ProfitPilot, recollez-le et relancez-le).

-- 1. Membres : quels comptes (e-mails) ont accès à quel dossier
create table if not exists public.members (
  dossier text not null,
  email   text not null,
  primary key (dossier, email)
);

-- 2. Données : un enregistrement par pièce, client, article, lot, réglage…
create table if not exists public.records (
  dossier    text        not null,
  collection text        not null,
  id         text        not null,
  data       jsonb,
  deleted    boolean     not null default false,
  updated_at timestamptz not null default now(),
  updated_by text,
  primary key (dossier, collection, id)
);
create index if not exists records_sync_idx on public.records (dossier, updated_at, collection, id);
-- Identifiant de chaque envoi : un poste reconnaît ses propres écritures, même après une réponse perdue
alter table public.records add column if not exists rev text;

-- 3. Compteurs de numérotation partagés (aucun doublon de numéro entre postes)
create table if not exists public.counters (
  dossier text    not null,
  kind    text    not null,
  year    integer not null,
  last    integer not null default 0,
  primary key (dossier, kind, year)
);

-- 3 bis. Actions uniques sur une pièce (validation, annulation, retour de dépôt) : un seul poste les exécute
create table if not exists public.doc_actions (
  dossier    text        not null,
  doc_id     text        not null,
  action     text        not null,
  device     text        not null,
  number     integer,
  created_at timestamptz not null default now(),
  primary key (dossier, doc_id, action)
);

-- 3 ter. Envois acceptés : un poste dont la réponse s'est perdue (coupure) sait ensuite si son envoi a été écrit
create table if not exists public.record_revs (
  dossier    text        not null,
  rev        text        not null,
  created_at timestamptz not null default now(),
  primary key (dossier, rev)
);
create index if not exists record_revs_age_idx on public.record_revs (dossier, created_at);

-- Date et auteur posés par le serveur (l'horloge des postes n'est jamais utilisée)
create or replace function public.touch_record() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := clock_timestamp();
  new.updated_by := auth.jwt() ->> 'email';
  return new;
end $$;

drop trigger if exists records_touch on public.records;
create trigger records_touch before insert or update on public.records
for each row execute function public.touch_record();

-- Appartenance du compte connecté à un dossier
create or replace function public.is_member(p_dossier text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.members m
    where m.dossier = p_dossier
      and lower(m.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- Règles d'accès (RLS) : chacun ne voit et ne modifie que les dossiers dont il est membre
alter table public.members  enable row level security;
alter table public.records  enable row level security;
alter table public.counters enable row level security;
alter table public.doc_actions enable row level security;
alter table public.record_revs enable row level security;

drop policy if exists members_read_own on public.members;
create policy members_read_own on public.members
  for select to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

drop policy if exists records_read on public.records;
create policy records_read on public.records
  for select to authenticated using (public.is_member(dossier));

-- Écritures uniquement par la fonction push_records (envoi conditionnel) ; jamais de suppression : on marque « deleted »
drop policy if exists records_insert on public.records;
drop policy if exists records_update on public.records;

-- Droits au plus juste : Supabase donne par défaut tous les droits (y compris DELETE et TRUNCATE,
-- que les règles RLS ne couvrent pas). On les retire puis on n'accorde que le nécessaire.
revoke all on public.members, public.records, public.counters, public.doc_actions, public.record_revs from anon, authenticated;
grant select on public.members to authenticated;
grant select on public.records to authenticated;

-- Prochain numéro de pièce : verrou sur le compteur, donc deux postes ne reçoivent jamais le même
create or replace function public.next_number(p_dossier text, p_kind text, p_year integer, p_min integer)
returns integer
language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  if not public.is_member(p_dossier) then
    raise exception 'Accès refusé au dossier %', p_dossier using errcode = '42501';
  end if;
  insert into public.counters as c (dossier, kind, year, last)
  values (p_dossier, p_kind, p_year, greatest(p_min, 0) + 1)
  on conflict (dossier, kind, year)
  do update set last = greatest(c.last, excluded.last - 1) + 1
  returning c.last into v;
  return v;
end $$;

revoke all on function public.next_number(text, text, integer, integer) from public, anon;
grant execute on function public.next_number(text, text, integer, integer) to authenticated;
revoke all on function public.is_member(text) from public, anon;
grant execute on function public.is_member(text) to authenticated;

-- Envoi conditionnel : une ligne n'est écrite que si le poste l'a lue dans sa dernière version.
-- Sinon elle est refusée et renvoyée : le poste fusionne puis renvoie (aucune modification écrasée en silence).
-- p_rows : [{collection, id, data, deleted, rev, expected}] ; expected = updated_at vu par le poste (null = nouvelle ligne)
create or replace function public.push_records(p_dossier text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
  cur public.records;
  accepted jsonb := '[]'::jsonb;
  rejected jsonb := '[]'::jsonb;
begin
  if not public.is_member(p_dossier) then
    raise exception 'Accès refusé au dossier %', p_dossier using errcode = '42501';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    select * into cur from public.records
      where dossier = p_dossier and collection = r->>'collection' and id = r->>'id'
      for update;
    if found then
      if r->>'expected' is null or cur.updated_at <> (r->>'expected')::timestamptz then
        rejected := rejected || to_jsonb(cur);
        continue;
      end if;
      update public.records
        set data = r->'data', deleted = coalesce((r->>'deleted')::boolean, false), rev = r->>'rev'
        where dossier = p_dossier and collection = r->>'collection' and id = r->>'id'
        returning * into cur;
    else
      insert into public.records (dossier, collection, id, data, deleted, rev)
        values (p_dossier, r->>'collection', r->>'id', r->'data', coalesce((r->>'deleted')::boolean, false), r->>'rev')
        on conflict (dossier, collection, id) do nothing
        returning * into cur;
      if not found then
        -- créée au même instant par un autre poste : refusée, le poste fusionnera
        select * into cur from public.records
          where dossier = p_dossier and collection = r->>'collection' and id = r->>'id';
        rejected := rejected || to_jsonb(cur);
        continue;
      end if;
    end if;
    if r->>'rev' is not null then
      insert into public.record_revs (dossier, rev) values (p_dossier, r->>'rev') on conflict do nothing;
    end if;
    accepted := accepted || jsonb_build_object('collection', cur.collection, 'id', cur.id, 'updated_at', cur.updated_at);
  end loop;
  -- Ménage occasionnel : les envois de plus de 90 jours ne servent plus
  if random() < 0.01 then
    delete from public.record_revs where dossier = p_dossier and created_at < now() - interval '90 days';
  end if;
  return jsonb_build_object('accepted', accepted, 'rejected', rejected);
end $$;

-- Lecture par clé (date, collection, id) : une ligne modifiée pendant la lecture passe en fin de liste
-- au lieu de décaler les pages (rien n'est sauté)
create or replace function public.pull_records(
  p_dossier text, p_since timestamptz, p_after_ts timestamptz, p_after_collection text, p_after_id text, p_limit integer
) returns setof public.records
language sql stable security invoker set search_path = public as $$
  select * from public.records
  where dossier = p_dossier
    and (p_since is null or updated_at >= p_since)
    and (p_after_ts is null or (updated_at, collection, id) > (p_after_ts, p_after_collection, p_after_id))
  order by updated_at, collection, id
  limit least(greatest(p_limit, 1), 1000);
$$;

-- Parmi ces envois, lesquels ont été écrits ?
create or replace function public.applied_revs(p_dossier text, p_revs text[]) returns text[]
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member(p_dossier) then
    raise exception 'Accès refusé au dossier %', p_dossier using errcode = '42501';
  end if;
  return coalesce((select array_agg(rev) from public.record_revs where dossier = p_dossier and rev = any(p_revs)), '{}');
end $$;

-- Action unique sur une pièce : le premier poste qui la demande l'obtient (avec le numéro pour une validation) ;
-- les autres reçoivent already = true et n'appliquent rien (la synchro leur apportera le résultat).
-- Le même poste qui redemande (réponse perdue) récupère la même action et le même numéro.
create or replace function public.claim_doc_action(
  p_dossier text, p_doc_id text, p_action text, p_device text, p_kind text, p_year integer, p_min integer
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  a public.doc_actions;
  v integer;
begin
  if not public.is_member(p_dossier) then
    raise exception 'Accès refusé au dossier %', p_dossier using errcode = '42501';
  end if;
  insert into public.doc_actions (dossier, doc_id, action, device)
    values (p_dossier, p_doc_id, p_action, p_device)
    on conflict do nothing
    returning * into a;
  if not found then
    select * into a from public.doc_actions where dossier = p_dossier and doc_id = p_doc_id and action = p_action;
    return jsonb_build_object('number', a.number, 'already', a.device <> p_device);
  end if;
  if p_action = 'validate' then
    insert into public.counters as c (dossier, kind, year, last)
      values (p_dossier, p_kind, p_year, greatest(p_min, 0) + 1)
      on conflict (dossier, kind, year)
      do update set last = greatest(c.last, excluded.last - 1) + 1
      returning c.last into v;
    update public.doc_actions set number = v where dossier = p_dossier and doc_id = p_doc_id and action = p_action;
  end if;
  return jsonb_build_object('number', v, 'already', false);
end $$;

revoke all on function public.push_records(text, jsonb) from public, anon;
grant execute on function public.push_records(text, jsonb) to authenticated;
revoke all on function public.pull_records(text, timestamptz, timestamptz, text, text, integer) from public, anon;
grant execute on function public.pull_records(text, timestamptz, timestamptz, text, text, integer) to authenticated;
revoke all on function public.applied_revs(text, text[]) from public, anon;
grant execute on function public.applied_revs(text, text[]) to authenticated;
revoke all on function public.claim_doc_action(text, text, text, text, text, integer, integer) from public, anon;
grant execute on function public.claim_doc_action(text, text, text, text, text, integer, integer) to authenticated;

-- 4. Ajoutez ici les comptes autorisés (un par ligne), puis exécutez :
-- insert into public.members (dossier, email) values
--   ('orthomed', 'admin@votre-societe.ma'),
--   ('orthomed', 'poste-magasin@votre-societe.ma')
-- on conflict do nothing;
FIN_DU_FICHIER
echo "OK supabase/schema.sql"

cat > docs/MULTIPOSTE.md <<'FIN_DU_FICHIER'
# Utiliser ProfitPilot sur plusieurs ordinateurs

Les données sont rangées dans une **base en ligne Supabase** partagée par tous vos ordinateurs.
Chaque pièce, client, article ou lot est synchronisé séparément toutes les 4 secondes environ.
Le serveur arbitre : une modification faite sur une version périmée est refusée, fusionnée avec celle de l'autre
poste puis renvoyée ; rien n'est écrasé en silence. Les numéros de pièces sont attribués par le serveur : deux postes
ne peuvent jamais donner le même numéro, ni valider deux fois la même pièce.

Durée : environ 15 minutes, une seule fois.

---

## Étape 1 — Créer le projet Supabase (gratuit pour démarrer)

1. Allez sur **https://supabase.com** › *Start your project* et créez un compte.
2. *New project* :
   - **Name** : `profitpilot`
   - **Database Password** : un mot de passe solide, à garder précieusement
   - **Region** : une région **européenne** (par exemple *West EU (Paris)* ou *Central EU (Frankfurt)*), la plus proche du Maroc
3. Attendez 1 à 2 minutes que le projet soit prêt.

## Étape 2 — Préparer la base (copier-coller)

1. Dans le projet : menu de gauche › **SQL Editor** › **New query**.
2. Ouvrez le fichier `supabase/schema.sql` de ProfitPilot, copiez **tout** son contenu, collez-le, puis cliquez **Run**.
   Le message *Success* doit s'afficher. (Le script peut être relancé sans danger.)
3. **Après chaque mise à jour de ProfitPilot**, recollez et relancez ce script de la même façon : il ajoute ce qui
   manque sans toucher à vos données.

## Étape 3 — Créer les comptes de connexion des ordinateurs

Chaque ordinateur (ou chaque employé) se connecte avec un e-mail et un mot de passe.

1. Menu **Authentication** › **Users** › **Add user** › **Create new user**.
2. Saisissez l'e-mail et le mot de passe, cochez **Auto Confirm User**, puis **Create user**.
3. Recommencez pour chaque ordinateur ou employé.

## Étape 4 — Autoriser ces comptes sur votre dossier

Le « dossier » est le nom de votre société dans la base, en minuscules, par exemple `orthomed`.

1. Menu **SQL Editor** › **New query**, collez (en remplaçant les e-mails) puis **Run** :

```sql
insert into public.members (dossier, email) values
  ('orthomed', 'admin@votre-societe.ma'),
  ('orthomed', 'magasin@votre-societe.ma')
on conflict do nothing;
```

Pour retirer l'accès à quelqu'un plus tard :

```sql
delete from public.members where dossier = 'orthomed' and email = 'ancien@votre-societe.ma';
```

## Étape 5 — Récupérer l'adresse et la clé publique

Menu **Project Settings** › **API** (ou *Data API* / *API Keys*) :
- **Project URL** : `https://xxxxxxxxxxxxxxxxxxxx.supabase.co` (20 lettres avant `.supabase.co`).
  Le plus sûr : **copiez** l'adresse de la page Supabase affichée en haut du navigateur
  (`supabase.com/dashboard/project/…`) et collez-la telle quelle dans ProfitPilot, qui en déduit l'adresse du projet.
- **Clé publique** : la clé `anon` *public* (ou *publishable*). **Jamais** la clé `service_role` / *secret*.

## Étape 6 — Premier ordinateur (celui qui a déjà vos données)

1. **Faites d'abord une sauvegarde** : Paramètres › Sauvegarde › *Télécharger une sauvegarde complète*.
2. Paramètres › Administration › **Multi-postes**.
3. Remplissez : adresse du projet, clé publique, nom du dossier (`orthomed`), e-mail et mot de passe de ce poste.
4. **Se connecter**, puis **Envoyer les données de ce poste**.
5. La barre d'état en bas affiche « ● Synchronisé à … ». Copiez le **code de connexion** affiché.

## Étape 7 — Chaque autre ordinateur

1. Ouvrez ProfitPilot sur cet ordinateur (voir « Mettre l'application en ligne » ci-dessous).
2. Paramètres › Administration › **Multi-postes**.
3. Collez le **code de connexion**, saisissez l'e-mail et le mot de passe de ce poste, **Se connecter**.
4. **Récupérer le dossier sur ce poste** : l'application se recharge avec les données partagées.

C'est fini : ce que vous saisissez sur un poste apparaît sur les autres en quelques secondes.

---

## Mettre l'application en ligne (pour l'ouvrir sur n'importe quel ordinateur)

Sans cette étape, chaque ordinateur doit avoir une copie du projet et lancer `npm run dev`.
Le plus simple est de publier l'application une fois :

1. Dans le terminal, dans le dossier du projet : `npm run build` (crée un dossier `dist`).
2. Allez sur **https://app.netlify.com/drop** (compte gratuit) et **glissez le dossier `dist`** dans la page.
3. Netlify donne une adresse du type `https://profitpilot-xxxx.netlify.app` : ouvrez-la sur chaque ordinateur
   (et ajoutez-la aux favoris).

À chaque mise à jour de ProfitPilot : `npm run build`, puis glissez à nouveau `dist` sur la page *Deploys* du site Netlify.
L'adresse est publique, mais les données restent protégées : il faut un compte autorisé sur le dossier pour les voir.

---

## Bon à savoir

- **Connexion Internet** : sans Internet, on continue à travailler ; les modifications partent au retour de la
  connexion (« Hors ligne · N modification(s) en attente » en bas de l'écran). Seules la **validation** et
  l'**annulation** d'une pièce, et la **reprise d'un dépôt**, demandent d'être en ligne : le serveur les accorde à un
  seul poste (numéro définitif, mouvements de stock jamais faits deux fois).
- **Deux personnes sur la même fiche** : si elles modifient des champs différents, les deux modifications sont
  gardées ; sur le même champ, la dernière enregistrée l'emporte. Les sorties et entrées de stock faites en même temps
  sur deux postes s'additionnent (10 en stock, une sortie de 1 sur chaque poste : 8). Une pièce validée ne revient
  jamais en brouillon et ne peut pas être supprimée par un autre poste ; les règlements saisis sur deux postes
  s'additionnent.
- **Inventaire** : faites le comptage d'un même article sur un seul poste à la fois (deux comptages saisis en même
  temps seraient additionnés comme deux mouvements).
- **Restaurer une sauvegarde** est désactivé en multi-postes (cela mélangerait d'anciennes données avec celles des
  autres postes).
- **Plusieurs onglets** sur un même ordinateur : c'est possible ; un seul onglet synchronise (« Synchronisé par un
  autre onglet » dans les autres) et un autre prend le relais si on le ferme.
- **Utilisateurs et droits** : les profils ProfitPilot (code PIN, droits par module) sont partagés entre les postes.
  Le compte Supabase sert à autoriser l'ordinateur ; le code PIN identifie la personne.
- **Sauvegardes** : continuez à télécharger une sauvegarde de temps en temps. Supabase fait aussi des sauvegardes
  quotidiennes sur les offres payantes.
- **Données de patients (loi 09-08)** : les noms de patients sont des données de santé. Leur hébergement à l'étranger
  est encadré par la **CNDP** : renseignez-vous (déclaration ou autorisation de transfert) avant d'y saisir des noms
  de patients, ou utilisez seulement des numéros de dossier.
- **Désactiver** : Paramètres › Multi-postes › *Déconnecter ce poste*. Les données restent sur l'ordinateur mais ne
  sont plus partagées.
FIN_DU_FICHIER
echo "OK docs/MULTIPOSTE.md"

# Nouvelles pages dans le type PageId
for id in sync users audit home stats schedule movements inventory alerts quotes orders deliveries depots invoices credits clients purchases receipts bills suppliers lots kits vat company backup; do
  grep -q "'$id'" src/types.ts || sed -i.tmp "s/'decision'/'decision' | '$id'/" src/types.ts
done
rm -f src/types.ts.tmp
echo "Type PageId :"
grep -n "type PageId" src/types.ts
echo "Installation terminée. Lancez : npm run dev"
