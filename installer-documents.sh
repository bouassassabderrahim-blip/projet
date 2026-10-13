#!/usr/bin/env bash
# À lancer à la racine du projet (dossier contenant src/)
set -e
[ -f src/types.ts ] || { echo "Erreur : lancez ce script dans le dossier du projet (src/types.ts introuvable)"; exit 1; }
mkdir -p src/documents src/components
for f in src/App.tsx src/components/Sidebar.tsx src/components/Dashboard.tsx; do [ -f "$f" ] && cp "$f" "$f.bak"; done; true

cat > src/documents/types.ts <<'FIN_DU_FICHIER'
// Types des documents commerciaux : facture, bon de commande, bon de livraison

/** quote = devis, order = bon de commande, delivery = bon de livraison (BL), invoice = facture */
export type DocKind = 'quote' | 'order' | 'delivery' | 'invoice'

/** Taux de TVA en vigueur au Maroc (CGI, art. 98 à 100) */
export type TvaRate = 0 | 7 | 10 | 14 | 20

export type DocStatus = 'draft' | 'validated' | 'paid' | 'cancelled'

export type PaymentMethod = 'virement' | 'cheque' | 'especes' | 'effet' | 'carte'

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
}

/** Informations de votre entreprise, imprimées sur chaque document */
export interface CompanyInfo extends Party {
  patente: string
  cnss: string
  bank: string
  rib: string
}

export interface DocLine {
  id: string
  productId?: string
  description: string
  quantity: number
  unitPriceHT: number
  tvaRate: TvaRate
  discount: number // remise en %
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
  /** Date d'encaissement, renseignée quand la facture passe en « Payée » */
  paidDate?: string
  /** Document d'origine (ex. le BC ayant donné ce BL) */
  sourceId?: string
  sourceNumber?: string
}

export const DOC_LABELS: Record<DocKind, { title: string; plural: string; prefix: string; newLabel: string }> = {
  quote: { title: 'Devis', plural: 'Devis', prefix: 'DV', newLabel: 'Nouveau devis' },
  order: { title: 'Bon de commande', plural: 'Bons de commande', prefix: 'BC', newLabel: 'Nouveau bon de commande' },
  delivery: { title: 'Bon de livraison', plural: 'Bons de livraison', prefix: 'BL', newLabel: 'Nouveau bon de livraison' },
  invoice: { title: 'Facture', plural: 'Factures', prefix: 'FA', newLabel: 'Nouvelle facture' },
}

export const STATUS_LABELS: Record<DocStatus, string> = {
  draft: 'Brouillon',
  validated: 'Validé',
  paid: 'Payée',
  cancelled: 'Annulé',
}

export const PAYMENT_LABELS: Record<PaymentMethod, string> = {
  virement: 'Virement bancaire',
  cheque: 'Chèque',
  especes: 'Espèces',
  effet: 'Effet de commerce (LCN)',
  carte: 'Carte bancaire',
}

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
FIN_DU_FICHIER
echo "OK src/documents/types.ts"

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

cat > src/documents/numbering.ts <<'FIN_DU_FICHIER'
import { DOC_LABELS, type CommercialDocument, type DocKind, type DocLine } from './types'

/** Numérotation chronologique et continue par type et par année : FA-2026-0001, BC-2026-0001, BL-2026-0001 */
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

export function today(): string {
  return new Date().toISOString().slice(0, 10)
}

export function addDays(date: string, days: number): string {
  const d = new Date(date + 'T00:00:00')
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
}

export function emptyLine(): DocLine {
  return { id: newId(), description: '', quantity: 1, unitPriceHT: 0, tvaRate: 20, discount: 0 }
}

/** Facture validée, non payée, dont l'échéance est dépassée */
export function isOverdue(doc: CommercialDocument, now = today()): boolean {
  return doc.kind === 'invoice' && doc.status === 'validated' && !!doc.dueDate && doc.dueDate < now
}
FIN_DU_FICHIER
echo "OK src/documents/numbering.ts"

cat > src/documents/storage.ts <<'FIN_DU_FICHIER'
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
    (d.kind === 'quote' || d.kind === 'order' || d.kind === 'delivery' || d.kind === 'invoice') &&
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
FIN_DU_FICHIER
echo "OK src/documents/storage.ts"

cat > src/documents/csv.ts <<'FIN_DU_FICHIER'
import { computeTotals } from './tva'
import { PAYMENT_LABELS, STATUS_LABELS, type CommercialDocument } from './types'

type Cell = string | number

/** CSV au format Excel français : séparateur « ; », virgule décimale, BOM UTF-8 pour les accents */
export function toCsv(rows: Cell[][]): string {
  const cell = (v: Cell) => {
    const s = typeof v === 'number' ? v.toFixed(2).replace('.', ',') : v
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  return '﻿' + rows.map((r) => r.map(cell).join(';')).join('\r\n')
}

export function downloadCsv(filename: string, rows: Cell[][]) {
  const url = URL.createObjectURL(new Blob([toCsv(rows)], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

/** Journal des ventes pour le comptable : une ligne par facture, TVA ventilée par taux */
export function salesJournal(invoices: CommercialDocument[]): Cell[][] {
  const rates = [20, 14, 10, 7, 0] as const
  const header: Cell[] = ['N°', 'Date', 'Client', 'ICE client', 'Total HT']
  for (const r of rates) header.push(`Base ${r} %`, `TVA ${r} %`)
  header.push('Total TVA', 'Total TTC', 'Droit de timbre', 'Net à payer', 'Paiement', 'Statut', 'Payée le')

  const rows: Cell[][] = [header]
  for (const d of invoices) {
    const t = computeTotals(d)
    const row: Cell[] = [d.number, d.date, d.party.name, d.party.ice, t.totalHT]
    for (const r of rates) {
      const b = t.byRate.find((x) => x.rate === r)
      row.push(b?.base ?? 0, b?.tva ?? 0)
    }
    row.push(
      t.totalTVA,
      t.totalTTC,
      t.stampDuty,
      t.netToPay,
      PAYMENT_LABELS[d.paymentMethod],
      STATUS_LABELS[d.status],
      d.paidDate ?? '',
    )
    rows.push(row)
  }
  return rows
}
FIN_DU_FICHIER
echo "OK src/documents/csv.ts"

cat > src/documents/DocumentEditor.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import type { Product } from '../types'
import {
  DOC_LABELS,
  PAYMENT_LABELS,
  type CommercialDocument,
  type DocLine,
  type Party,
  type PaymentMethod,
  type TvaRate,
} from './types'
import { TVA_RATES, computeTotals, formatMAD, lineHT } from './tva'
import { emptyLine } from './numbering'

interface Props {
  initial: CommercialDocument
  products: Product[]
  /** Clients déjà utilisés, pour les reprendre en un clic */
  knownParties: Party[]
  onSave: (doc: CommercialDocument) => void
  onCancel: () => void
}

const partyFields: { key: keyof Party; label: string }[] = [
  { key: 'name', label: 'Raison sociale / Nom' },
  { key: 'address', label: 'Adresse' },
  { key: 'city', label: 'Ville' },
  { key: 'ice', label: 'ICE' },
  { key: 'ifNumber', label: 'IF' },
  { key: 'rc', label: 'RC' },
  { key: 'phone', label: 'Téléphone' },
  { key: 'email', label: 'E-mail' },
]

export default function DocumentEditor({ initial, products, knownParties, onSave, onCancel }: Props) {
  const [doc, setDoc] = useState(initial)
  const [error, setError] = useState('')
  const totals = computeTotals(doc)
  const isInvoice = doc.kind === 'invoice'

  const update = (patch: Partial<CommercialDocument>) => setDoc((d) => ({ ...d, ...patch }))
  const updateParty = (key: keyof Party, value: string) =>
    setDoc((d) => ({ ...d, party: { ...d.party, [key]: value } }))
  const updateLine = (id: string, patch: Partial<DocLine>) =>
    setDoc((d) => ({ ...d, lines: d.lines.map((l) => (l.id === id ? { ...l, ...patch } : l)) }))

  function pickProduct(lineId: string, productId: string) {
    const p = products.find((x) => x.id === productId)
    if (!p) return updateLine(lineId, { productId: undefined })
    updateLine(lineId, { productId: p.id, description: p.name, unitPriceHT: p.unitPrice })
  }

  function pickParty(name: string) {
    const p = knownParties.find((x) => x.name === name)
    if (p) update({ party: { ...p } })
  }

  function submit() {
    if (!doc.party.name.trim()) return setError('Indiquez le nom du client.')
    if (isInvoice && !doc.party.ice.trim())
      return setError("L'ICE du client est obligatoire sur une facture entre professionnels.")
    if (isInvoice && doc.party.ice.trim() && !/^\d{15}$/.test(doc.party.ice.trim()))
      return setError("L'ICE doit comporter 15 chiffres.")
    const lines = doc.lines.filter((l) => l.description.trim() && l.quantity > 0)
    if (lines.length === 0) return setError('Ajoutez au moins une ligne.')
    onSave({ ...doc, lines })
  }

  const num = (v: string) => (v === '' ? 0 : Number(v))

  return (
    <div className="doc-editor">
      <h2>
        {DOC_LABELS[doc.kind].title} {doc.number}
        {doc.sourceNumber && <small> (issu de {doc.sourceNumber})</small>}
      </h2>

      <fieldset>
        <legend>Document</legend>
        <label>
          Date{' '}
          <input type="date" value={doc.date} onChange={(e) => update({ date: e.target.value })} />
        </label>
        {(isInvoice || doc.kind === 'quote') && (
          <label>
            {isInvoice ? 'Échéance' : "Valable jusqu'au"}{' '}
            <input type="date" value={doc.dueDate} onChange={(e) => update({ dueDate: e.target.value })} />
          </label>
        )}
        {isInvoice && (
          <>
            <label>
              Mode de paiement{' '}
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
          </>
        )}
      </fieldset>

      <fieldset>
        <legend>Client</legend>
        {knownParties.length > 0 && (
          <label>
            Client existant{' '}
            <select value="" onChange={(e) => pickParty(e.target.value)}>
              <option value="">— choisir —</option>
              {knownParties.map((p) => (
                <option key={p.name} value={p.name}>
                  {p.name}
                </option>
              ))}
            </select>
          </label>
        )}
        <div className="doc-grid">
          {partyFields.map((f) => (
            <label key={f.key}>
              {f.label}
              <input value={doc.party[f.key]} onChange={(e) => updateParty(f.key, e.target.value)} />
            </label>
          ))}
        </div>
      </fieldset>

      <table className="doc-table">
        <thead>
          <tr>
            <th>Produit</th>
            <th>Désignation</th>
            <th>Qté</th>
            <th>P.U. HT</th>
            <th>Remise %</th>
            <th>TVA</th>
            <th>Total HT</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {doc.lines.map((l) => (
            <tr key={l.id}>
              <td>
                <select value={l.productId ?? ''} onChange={(e) => pickProduct(l.id, e.target.value)}>
                  <option value="">Libre</option>
                  {products.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </td>
              <td>
                <input value={l.description} onChange={(e) => updateLine(l.id, { description: e.target.value })} />
              </td>
              <td>
                <input
                  type="number"
                  min={0}
                  step="any"
                  value={l.quantity}
                  onChange={(e) => updateLine(l.id, { quantity: num(e.target.value) })}
                />
              </td>
              <td>
                <input
                  type="number"
                  min={0}
                  step="0.01"
                  value={l.unitPriceHT}
                  onChange={(e) => updateLine(l.id, { unitPriceHT: num(e.target.value) })}
                />
              </td>
              <td>
                <input
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
                  onClick={() => setDoc((d) => ({ ...d, lines: d.lines.filter((x) => x.id !== l.id) }))}
                >
                  ✕
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <button type="button" onClick={() => setDoc((d) => ({ ...d, lines: [...d.lines, emptyLine()] }))}>
        + Ajouter une ligne
      </button>

      <div className="doc-totals">
        <div>Total HT : {formatMAD(totals.totalHT)}</div>
        {totals.byRate.map((r) => (
          <div key={r.rate}>
            TVA {r.rate} % sur {formatMAD(r.base)} : {formatMAD(r.tva)}
          </div>
        ))}
        <div>
          <strong>Total TTC : {formatMAD(totals.totalTTC)}</strong>
        </div>
        {totals.stampDuty > 0 && (
          <>
            <div>Droit de timbre (0,25 %) : {formatMAD(totals.stampDuty)}</div>
            <div>
              <strong>Net à payer : {formatMAD(totals.netToPay)}</strong>
            </div>
          </>
        )}
      </div>

      <label className="doc-notes">
        Notes / conditions
        <textarea rows={3} value={doc.notes} onChange={(e) => update({ notes: e.target.value })} />
      </label>

      {error && <p className="doc-error">{error}</p>}
      <div className="export-bar">
        <button type="button" onClick={submit}>
          Enregistrer
        </button>
        <button type="button" onClick={onCancel}>
          Annuler
        </button>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DocumentEditor.tsx"

cat > src/documents/DocumentPrint.tsx <<'FIN_DU_FICHIER'
import { DOC_LABELS, PAYMENT_LABELS, type CommercialDocument, type CompanyInfo } from './types'
import { amountInWordsMAD, computeTotals, formatMAD, lineHT } from './tva'

interface Props {
  doc: CommercialDocument
  company: CompanyInfo
  onClose: () => void
}

const frDate = (d: string) => (d ? new Date(d + 'T00:00:00').toLocaleDateString('fr-FR') : '')

/** Aperçu imprimable (Ctrl+P ou bouton « Imprimer / PDF ») */
export default function DocumentPrint({ doc, company, onClose }: Props) {
  const totals = computeTotals(doc)
  // Le BL sert à la livraison : on n'y imprime pas les prix
  const showPrices = doc.kind !== 'delivery'
  const label = DOC_LABELS[doc.kind].title

  return (
    <div>
      <div className="export-bar no-print">
        <button type="button" onClick={() => window.print()}>
          Imprimer / PDF
        </button>
        <button type="button" onClick={onClose}>
          Retour
        </button>
      </div>

      <div className="doc-print">
        <header className="doc-print-head">
          <div>
            <strong className="doc-company">{company.name || 'Votre entreprise'}</strong>
            <div>{company.address}</div>
            <div>{company.city}</div>
            <div>{[company.phone, company.email].filter(Boolean).join(' · ')}</div>
          </div>
          <div className="doc-print-title">
            <h2>{label.toUpperCase()}</h2>
            <div>N° {doc.number}</div>
            <div>Date : {frDate(doc.date)}</div>
            {doc.kind === 'invoice' && doc.dueDate && <div>Échéance : {frDate(doc.dueDate)}</div>}
            {doc.kind === 'quote' && doc.dueDate && <div>Valable jusqu'au : {frDate(doc.dueDate)}</div>}
            {doc.sourceNumber && <div>Réf. : {doc.sourceNumber}</div>}
          </div>
        </header>

        <section className="doc-party">
          <strong>{doc.kind === 'delivery' ? 'Livré à' : 'Client'}</strong>
          <div>{doc.party.name}</div>
          <div>{doc.party.address}</div>
          <div>{doc.party.city}</div>
          {doc.party.ice && <div>ICE : {doc.party.ice}</div>}
          {doc.party.ifNumber && <div>IF : {doc.party.ifNumber}</div>}
          {doc.party.rc && <div>RC : {doc.party.rc}</div>}
        </section>

        <table className="doc-table">
          <thead>
            <tr>
              <th>Désignation</th>
              <th className="num">Qté</th>
              {showPrices && (
                <>
                  <th className="num">P.U. HT</th>
                  <th className="num">Remise</th>
                  <th className="num">TVA</th>
                  <th className="num">Total HT</th>
                </>
              )}
            </tr>
          </thead>
          <tbody>
            {doc.lines.map((l) => (
              <tr key={l.id}>
                <td>{l.description}</td>
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
          <table className="doc-table doc-totals-table">
            <tbody>
              <tr>
                <td>Total HT</td>
                <td className="num">{formatMAD(totals.totalHT)}</td>
              </tr>
              {totals.byRate.map((r) => (
                <tr key={r.rate}>
                  <td>
                    TVA {r.rate} % (base {formatMAD(r.base)})
                  </td>
                  <td className="num">{formatMAD(r.tva)}</td>
                </tr>
              ))}
              <tr>
                <th>Total TTC</th>
                <th className="num">{formatMAD(totals.totalTTC)}</th>
              </tr>
              {totals.stampDuty > 0 && (
                <>
                  <tr>
                    <td>Droit de timbre 0,25 %</td>
                    <td className="num">{formatMAD(totals.stampDuty)}</td>
                  </tr>
                  <tr>
                    <th>Net à payer</th>
                    <th className="num">{formatMAD(totals.netToPay)}</th>
                  </tr>
                </>
              )}
            </tbody>
          </table>
        )}

        {doc.kind === 'invoice' && (
          <p>
            Arrêtée la présente facture à la somme de : <strong>{amountInWordsMAD(totals.netToPay)}</strong>{' '}
            TTC.
            <br />
            Mode de paiement : {PAYMENT_LABELS[doc.paymentMethod]}
          </p>
        )}

        {doc.notes && <p className="doc-notes-print">{doc.notes}</p>}

        {doc.kind !== 'invoice' && (
          <div className="doc-signatures">
            <div>{doc.kind === 'delivery' ? 'Signature du livreur' : "Cachet et signature de l'entreprise"}</div>
            <div>{doc.kind === 'delivery' ? 'Reçu conforme : cachet et signature du client' : 'Bon pour accord : cachet et signature du client'}</div>
          </div>
        )}

        <footer className="doc-footer">
          {[
            company.name,
            company.ice && `ICE : ${company.ice}`,
            company.ifNumber && `IF : ${company.ifNumber}`,
            company.rc && `RC : ${company.rc}`,
            company.patente && `Patente : ${company.patente}`,
            company.cnss && `CNSS : ${company.cnss}`,
          ]
            .filter(Boolean)
            .join(' · ')}
          {company.rib && (
            <div>
              {company.bank} · RIB : {company.rib}
            </div>
          )}
        </footer>
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DocumentPrint.tsx"

cat > src/documents/DocumentsPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import type { Product } from '../types'
import DocumentEditor from './DocumentEditor'
import DocumentPrint from './DocumentPrint'
import { downloadCsv, salesJournal } from './csv'
import { addDays, emptyLine, isOverdue, newId, nextNumber, today } from './numbering'
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
  type Party,
} from './types'
import './documents.css'

interface Props {
  kind: DocKind
  documents: CommercialDocument[]
  onChange: (docs: CommercialDocument[]) => void
  products: Product[]
  company: CompanyInfo
  /** Aller vers la page d'un autre type de document (après une conversion) */
  onNavigate?: (kind: DocKind) => void
  /** Appelé quand un BL est validé (quantités positives) ou annulé (quantités négatives) */
  onDelivered?: (lines: DocLine[]) => void
}

type View = { mode: 'list' } | { mode: 'edit'; doc: CommercialDocument } | { mode: 'print'; id: string }

/** Chaîne commerciale : Devis → BC → BL → Facture */
const CONVERSIONS: Record<DocKind, DocKind[]> = {
  quote: ['order', 'invoice'],
  order: ['delivery', 'invoice'],
  delivery: ['invoice'],
  invoice: [],
}

export default function DocumentsPage({
  kind,
  documents,
  onChange,
  products,
  company,
  onNavigate,
  onDelivered,
}: Props) {
  const [view, setView] = useState<View>({ mode: 'list' })
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<DocStatus | ''>('')
  const [message, setMessage] = useState<{ text: string; kind: DocKind } | null>(null)
  const labels = DOC_LABELS[kind]

  const list = useMemo(() => {
    const q = search.trim().toLowerCase()
    return documents
      .filter((d) => d.kind === kind)
      .filter((d) => !statusFilter || d.status === statusFilter)
      .filter((d) => !q || d.number.toLowerCase().includes(q) || d.party.name.toLowerCase().includes(q))
      .sort((a, b) => b.date.localeCompare(a.date) || b.number.localeCompare(a.number))
  }, [documents, kind, search, statusFilter])

  const knownParties = useMemo(() => {
    const byName = new Map<string, Party>()
    for (const d of documents) if (d.party.name) byName.set(d.party.name, d.party)
    return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name))
  }, [documents])

  // Indicateurs pour les factures validées ou payées
  const stats = useMemo(() => {
    if (kind !== 'invoice') return null
    const now = today()
    let ht = 0
    let tva = 0
    let unpaid = 0
    let late = 0
    let lateCount = 0
    for (const d of documents) {
      if (d.kind !== 'invoice' || d.status === 'cancelled' || d.status === 'draft') continue
      const t = computeTotals(d)
      ht += t.totalHT
      tva += t.totalTVA
      if (d.status !== 'paid') unpaid += t.netToPay
      if (isOverdue(d, now)) {
        late += t.netToPay
        lateCount++
      }
    }
    return { ht: round2(ht), tva: round2(tva), unpaid: round2(unpaid), late: round2(late), lateCount }
  }, [documents, kind])

  function createDoc(): CommercialDocument {
    const date = today()
    return {
      id: newId(),
      kind,
      number: nextNumber(kind, documents, date),
      date,
      // Facture : délai légal de paiement par défaut de 60 jours ; devis : validité de 30 jours
      dueDate: addDays(date, kind === 'quote' ? 30 : 60),
      party: emptyParty(),
      lines: [emptyLine()],
      status: 'draft',
      paymentMethod: 'virement',
      notes: '',
    }
  }

  function save(doc: CommercialDocument) {
    const exists = documents.some((d) => d.id === doc.id)
    onChange(exists ? documents.map((d) => (d.id === doc.id ? doc : d)) : [...documents, doc])
    setView({ mode: 'list' })
  }

  function setStatus(doc: CommercialDocument, status: DocStatus) {
    let paidDate: string | undefined
    if (status === 'paid') {
      // La date d'encaissement sert à la déclaration de TVA (régime des encaissements)
      const answer = prompt("Date d'encaissement (AAAA-MM-JJ)", today())
      if (answer === null) return
      if (!/^\d{4}-\d{2}-\d{2}$/.test(answer.trim())) return alert('Date invalide : utilisez le format AAAA-MM-JJ.')
      paidDate = answer.trim()
    }
    onChange(documents.map((d) => (d.id === doc.id ? { ...d, status, paidDate } : d)))
    if (doc.kind === 'delivery' && status === 'validated') onDelivered?.(doc.lines)
    // Annuler un BL déjà validé remet les quantités en stock
    if (doc.kind === 'delivery' && status === 'cancelled' && doc.status === 'validated')
      onDelivered?.(doc.lines.map((l) => ({ ...l, quantity: -l.quantity })))
  }

  function exportJournal() {
    const invoices = documents
      .filter((d) => d.kind === 'invoice' && d.status !== 'draft')
      .sort((a, b) => a.number.localeCompare(b.number))
    downloadCsv(`journal-ventes-${today()}.csv`, salesJournal(invoices))
  }

  function remove(doc: CommercialDocument) {
    if (!confirm(`Supprimer ${doc.number} ?`)) return
    onChange(documents.filter((d) => d.id !== doc.id))
  }

  function duplicate(doc: CommercialDocument) {
    const date = today()
    setView({
      mode: 'edit',
      doc: {
        ...doc,
        id: newId(),
        number: nextNumber(kind, documents, date),
        date,
        dueDate: addDays(date, kind === 'quote' ? 30 : 60),
        status: 'draft',
        paidDate: undefined,
        sourceId: undefined,
        sourceNumber: undefined,
        lines: doc.lines.map((l) => ({ ...l, id: newId() })),
      },
    })
  }

  function convert(doc: CommercialDocument, to: DocKind) {
    const date = today()
    const created: CommercialDocument = {
      ...doc,
      id: newId(),
      kind: to,
      number: nextNumber(to, documents, date),
      date,
      dueDate: addDays(date, to === 'quote' ? 30 : 60),
      status: 'draft',
      paidDate: undefined,
      sourceId: doc.id,
      sourceNumber: doc.number,
      lines: doc.lines.map((l) => ({ ...l, id: newId() })),
    }
    onChange([...documents, created])
    setMessage({ text: `${DOC_LABELS[to].title} ${created.number} créé(e) en brouillon à partir de ${doc.number}.`, kind: to })
  }

  if (view.mode === 'edit') {
    return (
      <DocumentEditor
        initial={view.doc}
        products={products}
        knownParties={knownParties}
        onSave={save}
        onCancel={() => setView({ mode: 'list' })}
      />
    )
  }

  if (view.mode === 'print') {
    const doc = documents.find((d) => d.id === view.id)
    if (doc) return <DocumentPrint doc={doc} company={company} onClose={() => setView({ mode: 'list' })} />
  }

  return (
    <div>
      {!company.name && (
        <p className="doc-warning">
          Renseignez d'abord les informations de votre entreprise (ICE, IF, RC…) : elles sont obligatoires sur
          les factures.
        </p>
      )}

      {stats && (
        <div className="doc-stats">
          <div>
            <span>Chiffre d'affaires HT</span>
            <strong>{formatMAD(stats.ht)}</strong>
          </div>
          <div>
            <span>TVA collectée</span>
            <strong>{formatMAD(stats.tva)}</strong>
          </div>
          <div>
            <span>Reste à encaisser</span>
            <strong>{formatMAD(stats.unpaid)}</strong>
          </div>
          <div className={stats.lateCount ? 'doc-stat-late' : undefined}>
            <span>En retard ({stats.lateCount})</span>
            <strong>{formatMAD(stats.late)}</strong>
          </div>
        </div>
      )}

      {message && (
        <p className="doc-info">
          {message.text}{' '}
          {onNavigate && (
            <button type="button" onClick={() => onNavigate(message.kind)}>
              Voir
            </button>
          )}
        </p>
      )}

      <div className="export-bar">
        <button type="button" onClick={() => setView({ mode: 'edit', doc: createDoc() })}>
          + {labels.newLabel}
        </button>
        {kind === 'invoice' && (
          <button type="button" onClick={exportJournal}>
            Exporter le journal des ventes (CSV)
          </button>
        )}
        <input placeholder="Rechercher (n°, client)" value={search} onChange={(e) => setSearch(e.target.value)} />
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value as DocStatus | '')}>
          <option value="">Tous les statuts</option>
          {Object.entries(STATUS_LABELS).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
      </div>

      {list.length === 0 ? (
        <p>Aucun document pour le moment.</p>
      ) : (
        <table className="doc-table">
          <thead>
            <tr>
              <th>N°</th>
              <th>Date</th>
              <th>Client</th>
              <th className="num">Total TTC</th>
              <th>Statut</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {list.map((d) => {
              const t = computeTotals(d)
              return (
                <tr key={d.id}>
                  <td>{d.number}</td>
                  <td>{new Date(d.date + 'T00:00:00').toLocaleDateString('fr-FR')}</td>
                  <td>{d.party.name}</td>
                  <td className="num">{formatMAD(t.netToPay)}</td>
                  <td>
                    <span className={`doc-badge doc-badge-${d.status}`}>{STATUS_LABELS[d.status]}</span>
                    {isOverdue(d) && <span className="doc-badge doc-badge-late">En retard</span>}
                  </td>
                  <td className="doc-actions">
                    <button type="button" onClick={() => setView({ mode: 'print', id: d.id })}>
                      Voir / imprimer
                    </button>
                    {d.status === 'draft' && (
                      <>
                        <button type="button" onClick={() => setView({ mode: 'edit', doc: d })}>
                          Modifier
                        </button>
                        <button type="button" onClick={() => setStatus(d, 'validated')}>
                          Valider
                        </button>
                        <button type="button" onClick={() => remove(d)}>
                          Supprimer
                        </button>
                      </>
                    )}
                    {d.kind === 'invoice' && d.status === 'validated' && (
                      <button type="button" onClick={() => setStatus(d, 'paid')}>
                        Marquer payée
                      </button>
                    )}
                    {d.status === 'validated' && (
                      <button type="button" onClick={() => setStatus(d, 'cancelled')}>
                        Annuler
                      </button>
                    )}
                    {d.status !== 'cancelled' &&
                      CONVERSIONS[d.kind].map((to) => (
                        <button key={to} type="button" onClick={() => convert(d, to)}>
                          → {DOC_LABELS[to].title}
                        </button>
                      ))}
                    <button type="button" onClick={() => duplicate(d)}>
                      Dupliquer
                    </button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/DocumentsPage.tsx"

cat > src/documents/CompanySettings.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import type { CompanyInfo } from './types'

interface Props {
  company: CompanyInfo
  onChange: (company: CompanyInfo) => void
}

const fields: { key: keyof CompanyInfo; label: string; hint?: string }[] = [
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

/** Mentions légales de l'émetteur, imprimées sur les factures, BC et BL */
export default function CompanySettings({ company, onChange }: Props) {
  const [draft, setDraft] = useState(company)
  const [saved, setSaved] = useState(false)
  const iceInvalid = draft.ice !== '' && !/^\d{15}$/.test(draft.ice)

  return (
    <div className="doc-editor">
      <div className="doc-grid">
        {fields.map((f) => (
          <label key={f.key}>
            {f.label}
            {f.hint && <small> ({f.hint})</small>}
            <input
              value={draft[f.key]}
              onChange={(e) => {
                setDraft({ ...draft, [f.key]: e.target.value })
                setSaved(false)
              }}
            />
          </label>
        ))}
      </div>
      {iceInvalid && <p className="doc-error">L'ICE doit comporter exactement 15 chiffres.</p>}
      <div className="export-bar">
        <button
          type="button"
          disabled={iceInvalid}
          onClick={() => {
            onChange(draft)
            setSaved(true)
          }}
        >
          Enregistrer
        </button>
        {saved && <span>Enregistré ✓</span>}
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/CompanySettings.tsx"

cat > src/documents/VatPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { downloadCsv } from './csv'
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
  tva: Record<number, number>
  total: number
  count: number
}

/** TVA collectée par période, à reporter sur la déclaration (la TVA déductible sur achats n'est pas suivie ici) */
export default function VatPage({ documents }: Props) {
  const years = useMemo(() => {
    const set = new Set<number>([new Date().getFullYear()])
    for (const d of documents) if (d.kind === 'invoice') set.add(Number(d.date.slice(0, 4)))
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
      tva: {},
      total: 0,
      count: 0,
    }))

    for (const d of documents) {
      if (d.kind !== 'invoice' || d.status === 'draft' || d.status === 'cancelled') continue
      const ref = regime === 'encaissement' ? (d.status === 'paid' ? d.paidDate : undefined) : d.date
      if (!ref || Number(ref.slice(0, 4)) !== year) continue
      const month = Number(ref.slice(5, 7)) - 1
      const row = result[periodicity === 'month' ? month : Math.floor(month / 3)]
      const t = computeTotals(d)
      row.ht += t.totalHT
      row.count++
      for (const r of t.byRate) {
        row.tva[r.rate] = (row.tva[r.rate] ?? 0) + r.tva
        row.total += r.tva
      }
    }
    return result
  }, [documents, year, regime, periodicity])

  const totals = rows.reduce(
    (acc, r) => {
      acc.ht += r.ht
      acc.total += r.total
      for (const rate of RATES) acc.tva[rate] = (acc.tva[rate] ?? 0) + (r.tva[rate] ?? 0)
      return acc
    },
    { ht: 0, total: 0, tva: {} as Record<number, number> },
  )

  function exportCsv() {
    const header = ['Période', 'Factures', 'CA HT', ...RATES.map((r) => `TVA ${r} %`), 'TVA collectée']
    const body = rows.map((r) => [r.label, String(r.count), round2(r.ht), ...RATES.map((x) => round2(r.tva[x] ?? 0)), round2(r.total)])
    downloadCsv(`tva-collectee-${year}-${regime}.csv`, [header, ...body])
  }

  return (
    <div>
      <div className="export-bar">
        <label>
          Année{' '}
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
          <strong>{formatMAD(round2(totals.ht))}</strong>
        </div>
        <div>
          <span>TVA collectée {year}</span>
          <strong>{formatMAD(round2(totals.total))}</strong>
        </div>
      </div>

      <table className="doc-table">
        <thead>
          <tr>
            <th>Période</th>
            <th className="num">Factures</th>
            <th className="num">CA HT</th>
            {RATES.map((r) => (
              <th key={r} className="num">
                TVA {r} %
              </th>
            ))}
            <th className="num">TVA collectée</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.label}>
              <td>{r.label}</td>
              <td className="num">{r.count}</td>
              <td className="num">{formatMAD(round2(r.ht))}</td>
              {RATES.map((x) => (
                <td key={x} className="num">
                  {formatMAD(round2(r.tva[x] ?? 0))}
                </td>
              ))}
              <td className="num">
                <strong>{formatMAD(round2(r.total))}</strong>
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <th>Total</th>
            <th className="num">{rows.reduce((s, r) => s + r.count, 0)}</th>
            <th className="num">{formatMAD(round2(totals.ht))}</th>
            {RATES.map((x) => (
              <th key={x} className="num">
                {formatMAD(round2(totals.tva[x] ?? 0))}
              </th>
            ))}
            <th className="num">{formatMAD(round2(totals.total))}</th>
          </tr>
        </tfoot>
      </table>

      <p className="doc-info">
        {regime === 'encaissement'
          ? 'Régime des encaissements : seules les factures marquées « Payée » sont comptées, à leur date de paiement.'
          : 'Régime des débits : les factures validées sont comptées à leur date de facturation, payées ou non.'}{' '}
        Ce tableau donne la TVA collectée sur vos ventes. La TVA déductible sur vos achats n'y figure pas : faites
        valider votre déclaration par votre comptable.
      </p>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/VatPage.tsx"

cat > src/documents/documents.css <<'FIN_DU_FICHIER'
.doc-editor fieldset {
  border: 1px solid #d0d5dd;
  border-radius: 8px;
  margin-bottom: 16px;
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.doc-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 10px;
  width: 100%;
}

.doc-grid label,
.doc-notes {
  display: flex;
  flex-direction: column;
  font-size: 14px;
  gap: 4px;
}

.doc-table {
  width: 100%;
  border-collapse: collapse;
  margin: 12px 0;
  font-size: 14px;
}

.doc-table th,
.doc-table td {
  border-bottom: 1px solid #e4e7ec;
  padding: 6px 8px;
  text-align: left;
}

.doc-table input {
  width: 100%;
  min-width: 60px;
  box-sizing: border-box;
}

.doc-table .num {
  text-align: right;
  white-space: nowrap;
}

.doc-totals {
  margin: 12px 0;
  text-align: right;
  line-height: 1.7;
}

.doc-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.doc-stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 16px;
}

.doc-stats div {
  border: 1px solid #e4e7ec;
  border-radius: 8px;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.doc-badge {
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 12px;
  background: #f2f4f7;
}
.doc-badge-validated { background: #dbeafe; color: #1e40af; }
.doc-badge-paid { background: #dcfce7; color: #166534; }
.doc-badge-cancelled { background: #fee2e2; color: #991b1b; text-decoration: line-through; }

.doc-error { color: #b42318; }
.doc-warning { background: #fff7e6; border: 1px solid #f5c26b; padding: 8px 12px; border-radius: 8px; }
.doc-info { background: #eef4ff; border: 1px solid #a4bcfd; padding: 8px 12px; border-radius: 8px; }

/* ---------- Document imprimable ---------- */
.doc-print {
  background: #fff;
  color: #111;
  max-width: 800px;
  padding: 32px;
  border: 1px solid #e4e7ec;
  font-size: 13px;
}

.doc-print-head {
  display: flex;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 24px;
}

.doc-company { font-size: 18px; }
.doc-print-title { text-align: right; }
.doc-print-title h2 { margin: 0 0 4px; letter-spacing: 2px; }

.doc-party {
  margin-left: auto;
  width: 45%;
  border: 1px solid #d0d5dd;
  border-radius: 6px;
  padding: 10px 14px;
  margin-bottom: 16px;
}

.doc-totals-table {
  width: 50%;
  margin-left: auto;
}

.doc-signatures {
  display: flex;
  justify-content: space-between;
  gap: 24px;
  margin-top: 32px;
}
.doc-signatures div {
  flex: 1;
  height: 90px;
  border: 1px dashed #98a2b3;
  padding: 8px;
  font-size: 12px;
}

.doc-footer {
  margin-top: 32px;
  padding-top: 8px;
  border-top: 1px solid #d0d5dd;
  font-size: 11px;
  text-align: center;
  color: #475467;
}

@media (max-width: 640px) {
  .doc-print { padding: 16px; }
  .doc-print-head { flex-direction: column; }
  .doc-party, .doc-totals-table { width: 100%; }
}

/* À l'impression, seul le document est visible */
@media print {
  body * { visibility: hidden; }
  .doc-print, .doc-print * { visibility: visible; }
  .doc-print {
    position: absolute;
    left: 0;
    top: 0;
    width: 100%;
    max-width: none;
    border: none;
    padding: 0;
  }
  .no-print { display: none !important; }
}

.doc-badge-late { background: #fef3c7; color: #92400e; margin-left: 4px; }
.doc-stats .doc-stat-late { border-color: #f5c26b; background: #fffbeb; }
FIN_DU_FICHIER
echo "OK src/documents/documents.css"

cat > src/components/Sidebar.tsx <<'FIN_DU_FICHIER'
import type { PageId } from '../types'

interface SidebarProps {
  current: PageId
  onNavigate: (page: PageId) => void
  /** Petit compteur affiché à côté d'une page (ex. factures en retard) */
  badges?: Partial<Record<PageId, number>>
}

const sections: { title: string; items: { id: PageId; label: string }[] }[] = [
  {
    title: 'Pilotage',
    items: [
      { id: 'dashboard', label: 'Tableau de bord' },
      { id: 'products', label: 'Rentabilité produits' },
      { id: 'breakeven', label: 'Résultat & seuil' },
      { id: 'recommendations', label: 'Recommandations' },
    ],
  },
  {
    title: 'Produits & stock',
    items: [
      { id: 'catalog', label: 'Mes produits' },
      { id: 'stock', label: 'Stock' },
      { id: 'import', label: 'Import CSV' },
      { id: 'simulator', label: 'Simulateur' },
      { id: 'compare', label: 'Comparaison' },
      { id: 'decision', label: 'Garder ou abandonner' },
    ],
  },
  {
    title: 'Ventes',
    items: [
      { id: 'quotes', label: 'Devis' },
      { id: 'orders', label: 'Bons de commande' },
      { id: 'deliveries', label: 'Bons de livraison' },
      { id: 'invoices', label: 'Factures' },
      { id: 'vat', label: 'Déclaration TVA' },
    ],
  },
  {
    title: 'Paramètres',
    items: [{ id: 'company', label: 'Mon entreprise' }],
  },
]

export default function Sidebar({ current, onNavigate, badges }: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="brand">ProfitPilot</div>
      <nav>
        {sections.map((section) => (
          <div key={section.title}>
            <div
              style={{
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: 1,
                textTransform: 'uppercase',
                opacity: 0.6,
                margin: '16px 0 4px',
              }}
            >
              {section.title}
            </div>
            {section.items.map((item) => {
              const badge = badges?.[item.id]
              return (
                <button
                  key={item.id}
                  className={item.id === current ? 'nav-item active' : 'nav-item'}
                  onClick={() => onNavigate(item.id)}
                >
                  {item.label}
                  {!!badge && (
                    <span
                      title="Factures en retard"
                      style={{
                        marginLeft: 8,
                        padding: '0 7px',
                        borderRadius: 999,
                        fontSize: 12,
                        background: '#f59e0b',
                        color: '#111827',
                      }}
                    >
                      {badge}
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        ))}
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
import type { CommercialDocument } from '../documents/types'
import { computeTotals as computeDocTotals, formatMAD, round2 } from '../documents/tva'
import { isOverdue, today } from '../documents/numbering'

interface DashboardProps {
  products: Product[]
  /** Devis, BC, BL et factures : alimentent le bloc « Ventes » */
  documents?: CommercialDocument[]
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

/** Synthèse des ventes en dirhams : mois en cours, encours clients, retards, devis ouverts */
function salesSummary(documents: CommercialDocument[]) {
  const now = today()
  const month = now.slice(0, 7)
  let monthHT = 0
  let unpaid = 0
  let late = 0
  let lateCount = 0
  let invoiceCount = 0
  for (const d of documents) {
    if (d.kind !== 'invoice' || d.status === 'draft' || d.status === 'cancelled') continue
    invoiceCount++
    const t = computeDocTotals(d)
    if (d.date.startsWith(month)) monthHT += t.totalHT
    if (d.status !== 'paid') unpaid += t.netToPay
    if (isOverdue(d, now)) {
      late += t.netToPay
      lateCount++
    }
  }
  // Devis encore ouverts : non annulés et pas encore transformés en BC ou facture
  const converted = new Set(documents.map((d) => d.sourceId).filter(Boolean))
  const openQuotes = documents.filter(
    (d) => d.kind === 'quote' && d.status !== 'cancelled' && !converted.has(d.id) && d.dueDate >= now,
  )
  const quotesHT = openQuotes.reduce((s, d) => s + computeDocTotals(d).totalHT, 0)
  return {
    invoiceCount,
    monthHT: round2(monthHT),
    unpaid: round2(unpaid),
    late: round2(late),
    lateCount,
    openQuotes: openQuotes.length,
    quotesHT: round2(quotesHT),
  }
}

export default function Dashboard({ products, documents = [], onNavigate }: DashboardProps) {
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

      {(sales.invoiceCount > 0 || sales.openQuotes > 0) && (
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
import { useEffect, useMemo, useState } from 'react'
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
import { isOverdue } from './documents/numbering'
import { useCompany, useDocuments } from './documents/storage'
import type { DocKind, DocLine } from './documents/types'
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
  quotes: 'Devis',
  orders: 'Bons de commande',
  deliveries: 'Bons de livraison',
  invoices: 'Factures',
  vat: 'Déclaration de TVA',
  company: 'Mon entreprise',
}

// Correspondance entre les pages et les types de documents commerciaux
const docPages: Partial<Record<PageId, DocKind>> = {
  quotes: 'quote',
  invoices: 'invoice',
  orders: 'order',
  deliveries: 'delivery',
}
const pageOfKind: Record<DocKind, PageId> = {
  quote: 'quotes',
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

  // Validation d'un BL : on retire les quantités livrées du stock (ou on les remet si le BL est annulé)
  function handleDelivered(lines: DocLine[]) {
    const qty = new Map<string, number>()
    for (const l of lines) if (l.productId) qty.set(l.productId, (qty.get(l.productId) ?? 0) + l.quantity)
    if (qty.size === 0) return
    const short: string[] = []
    const next = products.map((p) => {
      const q = qty.get(p.id)
      if (!q || p.stock === undefined) return p
      if (p.stock - q < 0) short.push(`${p.name} (stock ${p.stock}, livré ${q})`)
      return { ...p, stock: Math.max(0, p.stock - q) }
    })
    handleEdit(next)
    if (short.length) alert('Stock insuffisant, ramené à 0 pour :\n' + short.join('\n'))
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
  // Pages sans sélecteur de devise ni export produits : tout y est en dirhams
  const salesPage = !!docKind || page === 'vat' || page === 'company'
  const overdueCount = useMemo(() => documents.filter((d) => isOverdue(d)).length, [documents])

  return (
    <div className="layout">
      <Sidebar current={page} onNavigate={setPage} badges={{ invoices: overdueCount }} />
      <main className="content">
        <p className="print-only">
          ProfitPilot · {titles[page]} · {new Date().toLocaleDateString('fr-FR')} · {currency}
          {isSampleData ? ' · données de démonstration' : ''}
        </p>
        <h1>{titles[page]}</h1>
        {!salesPage && (
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
        {page === 'dashboard' && (
          <Dashboard products={products} documents={documents} onNavigate={setPage} />
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
            key={docKind} // réinitialise la vue (liste) en changeant de page
            kind={docKind}
            documents={documents}
            onChange={setDocuments}
            products={products}
            company={company}
            onNavigate={(k) => setPage(pageOfKind[k])}
            onDelivered={handleDelivered}
          />
        )}
        {page === 'vat' && <VatPage documents={documents} />}
        {page === 'company' && <CompanySettings company={company} onChange={setCompany} />}
      </main>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/App.tsx"

# Nouvelles pages dans le type PageId
cp src/types.ts src/types.ts.bak
grep -q "'invoices'" src/types.ts || sed -i.tmp "s/'decision'/'decision' | 'invoices' | 'orders' | 'deliveries' | 'company'/" src/types.ts
grep -q "'quotes'" src/types.ts || sed -i.tmp "s/'deliveries'/'deliveries' | 'quotes' | 'vat'/" src/types.ts
rm -f src/types.ts.tmp
grep -n "'quotes'" src/types.ts
echo "Installation terminée. Lancez : npm run dev"
