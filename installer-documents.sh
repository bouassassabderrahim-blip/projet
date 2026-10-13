#!/usr/bin/env bash
# ProfitPilot : gestion commerciale complète (ventes, achats, lots, dépôts, TVA, thème pro)
# À lancer à la racine du projet (dossier contenant src/)
set -e
[ -f src/types.ts ] || { echo "Erreur : lancez ce script dans le dossier du projet (src/types.ts introuvable)"; exit 1; }
mkdir -p src/documents src/components
for f in src/App.tsx src/components/Sidebar.tsx src/components/Dashboard.tsx src/types.ts; do [ -f "$f" ] && cp "$f" "$f.bak"; done; true

cat > src/documents/BackupPage.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
import { downloadFile } from './csv'
import { LAST_BACKUP_KEY, createBackup, isBackupFile, restoreBackup } from './storage'
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
  const age = last ? daysBetween(last, today()) : null

  function exportAll() {
    const backup = createBackup()
    downloadFile(`profitpilot-sauvegarde-${today()}.json`, JSON.stringify(backup, null, 1), 'application/json')
    try {
      localStorage.setItem(LAST_BACKUP_KEY, today())
    } catch {
      // stockage indisponible
    }
    setLast(today())
    setMessage(`Sauvegarde téléchargée (${Object.keys(backup.data).length} jeux de données).`)
  }

  function importAll(file: File | undefined) {
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => {
      try {
        const data: unknown = JSON.parse(String(reader.result))
        if (!isBackupFile(data)) return setError("Ce fichier n'est pas une sauvegarde ProfitPilot.")
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
        <legend>Sauvegarder</legend>
        <p>Télécharge un fichier contenant les produits, le stock, les lots, les pièces, les tiers et les paramètres.</p>
        <button type="button" className="btn-primary" onClick={exportAll}>
          Télécharger une sauvegarde complète
        </button>
      </fieldset>

      <fieldset className="doc-panel">
        <legend>Restaurer</legend>
        <p>Remplace toutes les données de ce navigateur par celles d'un fichier de sauvegarde.</p>
        <input type="file" accept="application/json,.json" onChange={(e) => importAll(e.target.files?.[0])} />
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
import type { CompanyInfo } from './types'
import './documents.css'

interface Props {
  company: CompanyInfo
  onChange: (company: CompanyInfo) => void
}

const fields: { key: Exclude<keyof CompanyInfo, 'logo' | 'individual'>; label: string; hint?: string }[] = [
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

const MAX_LOGO = 300 * 1024

/** Mentions légales de l'émetteur et logo, imprimés sur toutes les pièces */
export default function CompanySettings({ company, onChange }: Props) {
  const [draft, setDraft] = useState(company)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState('')
  const iceInvalid = draft.ice !== '' && !/^\d{15}$/.test(draft.ice)
  const ribInvalid = draft.rib !== '' && !/^\d{24}$/.test(draft.rib.replace(/\s/g, ''))

  const set = (patch: Partial<CompanyInfo>) => {
    setDraft({ ...draft, ...patch })
    setSaved(false)
  }

  function loadLogo(file: File | undefined) {
    if (!file) return
    if (!file.type.startsWith('image/')) return setError('Choisissez une image (PNG ou JPEG).')
    if (file.size > MAX_LOGO) return setError('Logo trop lourd : 300 Ko maximum.')
    const reader = new FileReader()
    reader.onload = () => {
      set({ logo: String(reader.result) })
      setError('')
    }
    reader.readAsDataURL(file)
  }

  return (
    <div>
      <div className="doc-editor-head">
        <h2>Fiche société</h2>
        <div className="doc-editor-actions">
          <button
            type="button"
            className="btn-primary"
            disabled={iceInvalid}
            onClick={() => {
              onChange(draft)
              setSaved(true)
            }}
          >
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
      </fieldset>

      <fieldset className="doc-panel">
        <legend>Logo</legend>
        <div className="doc-logo-row">
          {draft.logo ? <img className="doc-logo" src={draft.logo} alt="Logo" /> : <span className="doc-count">Aucun logo</span>}
          <input type="file" accept="image/png,image/jpeg" onChange={(e) => loadLogo(e.target.files?.[0])} />
          {draft.logo && (
            <button type="button" onClick={() => set({ logo: undefined })}>
              Retirer
            </button>
          )}
        </div>
        {error && <p className="doc-error">{error}</p>}
      </fieldset>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/CompanySettings.tsx"

cat > src/documents/DepotPage.tsx <<'FIN_DU_FICHIER'
import { useMemo, useState } from 'react'
import { addDays, daysBetween, emptyLine, frDate, newId, nextNumber, today } from './numbering'
import { formatMAD, lineHT } from './tva'
import { emptyIntervention, type CommercialDocument, type DocKind, type DocLine } from './types'
import './documents.css'

interface Props {
  documents: CommercialDocument[]
  onChange: (docs: CommercialDocument[]) => void
  onNavigate: (kind: DocKind, openId?: string) => void
  onStockMove: (lines: DocLine[], direction: 1 | -1) => void
}

interface DepotItem {
  bl: CommercialDocument
  line: DocLine
}

/** Implants livrés en dépôt : à facturer après la pose ou à reprendre en stock */
export default function DepotPage({ documents, onChange, onNavigate, onStockMove }: Props) {
  const [selected, setSelected] = useState<string[]>([])
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
    setSelected([])
    onNavigate('invoice', id)
  }

  function giveBack(item: DepotItem) {
    if (!confirm(`Reprendre « ${item.line.description} » en stock ?`)) return
    onChange(setDepot(documents, [item], 'returned'))
    onStockMove([item.line], 1)
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
                        <button type="button" className="btn-primary" onClick={() => invoice([item])}>
                          Posé → facturer
                        </button>
                        <button type="button" onClick={() => giveBack(item)}>
                          Retour en stock
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {chosen.length > 1 && (
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
import { DOC_LABELS, PAYMENT_LABELS, type CommercialDocument, type CompanyInfo } from './types'
import { amountInWordsMAD, computeTotals, formatMAD, lineHT } from './tva'
import { frDate } from './numbering'

interface Props {
  doc: CommercialDocument
  company: CompanyInfo
  /** Règlements et avoirs déjà imputés (factures) */
  paid?: number
  balance?: number
  onClose: () => void
}

export function CompanyHeader({ company }: { company: CompanyInfo }) {
  return (
    <div className="doc-print-company">
      {company.logo && <img className="doc-logo" src={company.logo} alt="" />}
      <div>
        <strong className="doc-company">{company.name || 'Votre entreprise'}</strong>
        <div>{company.address}</div>
        <div>{company.city}</div>
        <div>{[company.phone, company.email].filter(Boolean).join(' · ')}</div>
      </div>
    </div>
  )
}

export function CompanyFooter({ company }: { company: CompanyInfo }) {
  return (
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
  )
}

/** Aperçu imprimable (bouton « Imprimer / PDF ») */
export default function DocumentPrint({ doc, company, paid = 0, balance, onClose }: Props) {
  const totals = computeTotals(doc)
  const info = DOC_LABELS[doc.kind]
  // BL et bons de réception servent à la logistique : pas de prix
  const showPrices = doc.kind !== 'delivery' && doc.kind !== 'receipt'
  const showTrace = doc.lines.some((l) => l.lot || l.serial || l.expiry)
  const iv = doc.intervention
  const partyLabel =
    info.side === 'purchase' ? 'Fournisseur' : doc.kind === 'delivery' ? 'Livré à' : 'Client'

  return (
    <div>
      <div className="doc-toolbar no-print">
        <button type="button" className="btn-primary" onClick={() => window.print()}>
          Imprimer / PDF
        </button>
        <button type="button" onClick={onClose}>
          Retour à la liste
        </button>
      </div>

      <div className="doc-print">
        <header className="doc-print-head">
          <CompanyHeader company={company} />
          <div className="doc-print-title">
            <h2>
              {info.printTitle}
              {doc.consignment ? ' (DÉPÔT)' : ''}
            </h2>
            <table className="doc-ref-table">
              <tbody>
                <tr>
                  <th>N°</th>
                  <td>{doc.number}</td>
                </tr>
                <tr>
                  <th>Date</th>
                  <td>{frDate(doc.date)}</td>
                </tr>
                {(doc.kind === 'invoice' || doc.kind === 'bill') && doc.dueDate && (
                  <tr>
                    <th>Échéance</th>
                    <td>{frDate(doc.dueDate)}</td>
                  </tr>
                )}
                {doc.kind === 'quote' && doc.dueDate && (
                  <tr>
                    <th>Validité</th>
                    <td>{frDate(doc.dueDate)}</td>
                  </tr>
                )}
                {doc.supplierRef && (
                  <tr>
                    <th>Réf. fournisseur</th>
                    <td>{doc.supplierRef}</td>
                  </tr>
                )}
                {doc.sourceNumber && (
                  <tr>
                    <th>{doc.kind === 'credit' ? 'Sur facture' : 'Votre réf.'}</th>
                    <td>{doc.sourceNumber}</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </header>

        <div className="doc-print-boxes">
          {iv ? (
            <section className="doc-box">
              <strong>Intervention</strong>
              {iv.patient && <div>Patient : {iv.patient}</div>}
              {iv.patientRef && <div>Dossier / CIN : {iv.patientRef}</div>}
              {iv.surgeon && <div>Chirurgien : {iv.surgeon}</div>}
              {iv.clinic && <div>Établissement : {iv.clinic}</div>}
              {iv.date && <div>Date : {frDate(iv.date)}</div>}
              {iv.coverage && <div>Prise en charge : {iv.coverage}</div>}
            </section>
          ) : (
            <span />
          )}
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

        <table className="doc-table doc-print-lines">
          <thead>
            <tr>
              <th>Désignation</th>
              {showTrace && (
                <>
                  <th>Lot / N° série</th>
                  <th>Péremption</th>
                </>
              )}
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
            {doc.lines.map((l) => (
              <tr key={l.id}>
                <td>{l.description}</td>
                {showTrace && (
                  <>
                    <td>{[l.lot, l.serial].filter(Boolean).join(' / ')}</td>
                    <td>{frDate(l.expiry)}</td>
                  </>
                )}
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
                  <th>Taux</th>
                  <th className="num">Base HT</th>
                  <th className="num">TVA</th>
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
                <tr className="doc-total-row">
                  <td>Total TTC</td>
                  <td className="num">{formatMAD(totals.totalTTC)}</td>
                </tr>
                {totals.stampDuty > 0 && (
                  <>
                    <tr>
                      <td>Droit de timbre 0,25 %</td>
                      <td className="num">{formatMAD(totals.stampDuty)}</td>
                    </tr>
                    <tr className="doc-total-row">
                      <td>Net à payer</td>
                      <td className="num">{formatMAD(totals.netToPay)}</td>
                    </tr>
                  </>
                )}
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

        {(doc.kind === 'invoice' || doc.kind === 'credit') && (
          <p>
            {doc.kind === 'invoice' ? 'Arrêtée la présente facture' : 'Arrêté le présent avoir'} à la somme de :{' '}
            <strong>{amountInWordsMAD(totals.netToPay)}</strong> TTC.
            <br />
            Mode de règlement : {PAYMENT_LABELS[doc.paymentMethod]}
          </p>
        )}

        {doc.notes && <p className="doc-notes-print">{doc.notes}</p>}

        {(doc.kind === 'quote' || doc.kind === 'order' || doc.kind === 'delivery' || doc.kind === 'receipt' || doc.kind === 'purchase') && (
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
                  : 'Bon pour accord : cachet et signature'}
            </div>
          </div>
        )}

        <CompanyFooter company={company} />
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
import PaymentDialog from './PaymentDialog'
import ReminderPrint from './ReminderPrint'
import { downloadCsv, journal } from './csv'
import { balanceOf, isActive, isOverdue, paidAmount, sign } from './ledger'
import { addDays, emptyLine, frDate, newId, nextNumber, today } from './numbering'
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
  onChange: (docs: CommercialDocument[]) => void
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
  onStockMove?: (lines: DocLine[], direction: 1 | -1, supplier?: string) => void
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
    const doc = openId ? documents.find((d) => d.id === openId) : undefined
    return doc ? { mode: 'edit', doc } : { mode: 'list' }
  })
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<Filter>('')
  const [paying, setPaying] = useState<CommercialDocument | null>(null)
  const [message, setMessage] = useState<{ text: string; kind?: DocKind; id?: string } | null>(null)
  const info = DOC_LABELS[kind]
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
    return {
      id: newId(),
      kind,
      number: nextNumber(kind, documents, now),
      date: now,
      // Facture : délai légal de paiement par défaut de 60 jours ; devis : validité de 30 jours
      dueDate: addDays(now, kind === 'quote' ? 30 : 60),
      party: emptyParty(),
      lines: [emptyLine()],
      status: 'draft',
      paymentMethod: 'virement',
      notes: '',
    }
  }

  /** Ajoute le tiers au fichier clients / fournisseurs s'il n'y est pas encore */
  function rememberParty(doc: CommercialDocument) {
    const name = doc.party.name.trim().toLowerCase()
    if (!name || parties.some((p) => p.role === role && p.name.trim().toLowerCase() === name)) return
    onPartiesChange([...parties, { ...doc.party, id: newId(), role, notes: '' }])
  }

  function save(doc: CommercialDocument) {
    const exists = documents.some((d) => d.id === doc.id)
    onChange(exists ? documents.map((d) => (d.id === doc.id ? doc : d)) : [...documents, doc])
    rememberParty(doc)
    setView({ mode: 'list' })
  }

  function setStatus(doc: CommercialDocument, status: DocStatus) {
    let next = documents.map((d) => (d.id === doc.id ? { ...d, status } : d))
    const supplier = doc.party.name

    if (status === 'validated') {
      if (doc.kind === 'delivery') {
        onStockMove?.(doc.lines, -1)
        // BL en dépôt : chaque ligne reste à facturer à la pose
        if (doc.consignment)
          next = next.map((d) =>
            d.id === doc.id ? { ...d, lines: d.lines.map((l) => ({ ...l, depot: l.depot ?? 'depot' })) } : d,
          )
      }
      if (doc.kind === 'receipt') onStockMove?.(doc.lines, 1, supplier)
      if (invoiceMovesStock(doc, documents)) onStockMove?.(doc.lines.filter((l) => !l.depotRef), -1)
    }

    if (status === 'cancelled' && doc.status !== 'draft') {
      if (doc.kind === 'delivery') onStockMove?.(doc.lines.filter((l) => l.depot !== 'returned'), 1)
      if (doc.kind === 'receipt') onStockMove?.(doc.lines, -1)
    }
    onChange(next)
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
  }

  function remove(doc: CommercialDocument) {
    if (!confirm(`Supprimer ${doc.number} ?`)) return
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
    return lines.map((l) => ({ ...l, id: newId(), depot: undefined, depotRef: undefined }))
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
      sourceId: doc.id,
      sourceNumber: doc.number,
      lines: copyLines(doc.lines),
    }
    onChange([...documents, created])
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
        <button type="button" className="btn-primary" onClick={() => setView({ mode: 'edit', doc: createDoc() })}>
          + {info.newLabel}
        </button>
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
                      <button type="button" className="doc-link" onClick={() => setView(d.status === 'draft' ? { mode: 'edit', doc: d } : { mode: 'print', id: d.id })}>
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
                          <button type="button" onClick={() => setView({ mode: 'edit', doc: d })}>
                            Modifier
                          </button>
                          <button type="button" className="btn-primary" onClick={() => setStatus(d, 'validated')}>
                            Valider
                          </button>
                          <button type="button" onClick={() => remove(d)}>
                            Supprimer
                          </button>
                        </>
                      )}
                      {hasBalance && d.status === 'validated' && balance > 0.01 && (
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
                      {d.status === 'validated' && d.kind !== 'invoice' && (
                        <button
                          type="button"
                          onClick={() => confirm(`Annuler ${d.number} ?`) && setStatus(d, 'cancelled')}
                        >
                          Annuler
                        </button>
                      )}
                      {d.status !== 'cancelled' &&
                        d.status !== 'draft' &&
                        CONVERSIONS[d.kind]
                          .filter((to) => !(d.consignment && to === 'invoice'))
                          .map((to) => (
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

cat > src/documents/KitsPage.tsx <<'FIN_DU_FICHIER'
import { useState } from 'react'
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
        <button
          type="button"
          className="btn-primary"
          onClick={() => setEditing({ id: newId(), name: '', items: [{ productId: '', quantity: 1 }] })}
        >
          + Nouveau kit
        </button>
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
                  <button type="button" onClick={() => setEditing(k)}>
                    Modifier
                  </button>
                  <button
                    type="button"
                    onClick={() => confirm(`Supprimer le kit « ${k.name} » ?`) && onChange(kits.filter((x) => x.id !== k.id))}
                  >
                    Supprimer
                  </button>
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
}

const EXPIRY_LABELS: Record<ExpiryState, string> = {
  expired: 'Périmé',
  soon: '< 90 jours',
  ok: 'OK',
  none: 'Sans date',
}

type Filter = '' | 'available' | 'expired' | 'soon'

/** Stock par lot / numéro de série, péremptions et traçabilité (rappel de lot) */
export default function LotsPage({ lots, onChange, products, documents }: Props) {
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState<Filter>('available')
  const [draft, setDraft] = useState({ productId: '', lot: '', serial: '', expiry: '', quantity: '1', supplier: '' })
  const [error, setError] = useState('')
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

      <div className="doc-panel">
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
      </div>

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
export default function PartiesPage({ role, parties, onChange, documents, company }: Props) {
  const [query, setQuery] = useState('')
  const [editing, setEditing] = useState<PartyRecord | null>(null)
  const [reminder, setReminder] = useState<string | null>(null)
  const [error, setError] = useState('')
  const now = today()
  const isClient = role === 'client'
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
            <button type="button" className="btn-primary" onClick={save}>
              Enregistrer
            </button>
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
        <button
          type="button"
          className="btn-primary"
          onClick={() => setEditing({ ...emptyParty(), id: newId(), role, notes: '' })}
        >
          + {isClient ? 'Nouveau client' : 'Nouveau fournisseur'}
        </button>
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
                    {r.docs.length === 0 && (
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

cat > src/documents/ReminderPrint.tsx <<'FIN_DU_FICHIER'
import { CompanyFooter, CompanyHeader } from './DocumentPrint'
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
        <header className="doc-print-head">
          <CompanyHeader company={company} />
          <section className="doc-box doc-party">
            <div className="doc-party-name">{party.name}</div>
            <div>{party.address}</div>
            <div>{party.city}</div>
          </section>
        </header>

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

        <CompanyFooter company={company} />
      </div>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/documents/ReminderPrint.tsx"

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

/* ---------- Pièce imprimable (format A4) ---------- */
.doc-print {
  background: #fff;
  color: #111;
  max-width: 820px;
  padding: 36px 40px;
  border: 1px solid var(--pp-border);
  box-shadow: 0 2px 10px rgba(15, 23, 42, 0.12);
  font-size: 12.5px;
  line-height: 1.45;
}
.doc-print-head {
  display: flex;
  justify-content: space-between;
  gap: 24px;
  margin-bottom: 20px;
  padding-bottom: 12px;
  border-bottom: 2px solid var(--pp-blue);
}
.doc-print-company { display: flex; gap: 12px; align-items: flex-start; }
.doc-company { font-size: 17px; color: var(--pp-blue); }
.doc-print-title { text-align: right; }
.doc-print-title h2 { margin: 0 0 6px; font-size: 18px; letter-spacing: 1.5px; color: var(--pp-blue); }
.doc-ref-table { border-collapse: collapse; margin-left: auto; font-size: 12px; }
.doc-ref-table th, .doc-ref-table td { border: 1px solid var(--pp-border); padding: 2px 8px; text-align: left; }
.doc-ref-table th { background: var(--pp-head-1); font-weight: 600; color: var(--pp-title); }

.doc-print-boxes { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 16px; }
.doc-box { border: 1px solid var(--pp-border); border-radius: 3px; padding: 8px 12px; }
.doc-box > strong:first-child {
  display: block;
  font-size: 11px;
  text-transform: uppercase;
  color: var(--pp-muted);
  letter-spacing: 0.4px;
  margin-bottom: 2px;
}
.doc-party-name { font-weight: 700; font-size: 14px; }
.doc-print .doc-table { font-size: 12px; }
.doc-print .doc-table tbody tr:nth-child(even) { background: #fafbfc; }
.doc-print-bottom { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; align-items: start; margin: 8px 0 12px; }
.doc-notes-print { white-space: pre-wrap; border-left: 3px solid var(--pp-border); padding-left: 8px; color: #374151; }

.doc-signatures { display: flex; justify-content: space-between; gap: 24px; margin-top: 28px; }
.doc-signatures div { flex: 1; height: 90px; border: 1px solid var(--pp-border); padding: 6px 8px; font-size: 11px; color: var(--pp-muted); }

.doc-footer {
  margin-top: 28px;
  padding-top: 8px;
  border-top: 1px solid var(--pp-border);
  font-size: 10.5px;
  text-align: center;
  color: #475467;
}

/* À l'impression, seule la pièce est visible */
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
    box-shadow: none;
    padding: 0;
  }
  .doc-print .doc-table th { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .no-print { display: none !important; }
}
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

export function today(): string {
  return new Date().toISOString().slice(0, 10)
}

export function addDays(date: string, days: number): string {
  const d = new Date(date + 'T00:00:00')
  d.setDate(d.getDate() + days)
  return d.toISOString().slice(0, 10)
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
FIN_DU_FICHIER
echo "OK src/documents/numbering.ts"

cat > src/documents/stockMoves.ts <<'FIN_DU_FICHIER'
// Mouvements de stock déclenchés par les BL, les réceptions et les retours de dépôt
import type { Product } from '../types'
import { newId, today } from './numbering'
import type { DocLine, StockLot } from './types'

export interface StockState {
  products: Product[]
  lots: StockLot[]
}

export interface MoveResult extends StockState {
  /** Articles dont le stock était insuffisant (ramené à 0) */
  shortages: string[]
}

/**
 * direction = -1 : sortie (BL validé, réception annulée)
 * direction = +1 : entrée (réception validée, BL annulé, retour de dépôt)
 */
export function applyMove(state: StockState, lines: DocLine[], direction: 1 | -1, supplier = ''): MoveResult {
  const products = new Map(state.products.map((p) => [p.id, { ...p }]))
  const lots = state.lots.map((l) => ({ ...l }))
  const shortages: string[] = []

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
  }

  return { products: state.products.map((p) => products.get(p.id) ?? p), lots, shortages }
}

export type ExpiryState = 'expired' | 'soon' | 'ok' | 'none'

/** Péremption : « soon » = dans les 90 jours */
export function expiryState(expiry: string, now = today(), soonDays = 90): ExpiryState {
  if (!expiry) return 'none'
  if (expiry < now) return 'expired'
  const limit = new Date(now + 'T00:00:00')
  limit.setDate(limit.getDate() + soonDays)
  return expiry <= limit.toISOString().slice(0, 10) ? 'soon' : 'ok'
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

/** Informations de votre entreprise, imprimées sur chaque document */
export interface CompanyInfo extends Party {
  patente: string
  cnss: string
  bank: string
  rib: string
  /** Logo en data URL (PNG/JPEG) */
  logo?: string
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
.layout .content table:not(.doc-ref-table) {
  border-collapse: collapse;
  background: #fff;
  border: 1px solid var(--pp-border);
  font-size: 12.5px;
}
.layout .content table:not(.doc-ref-table) th {
  background: linear-gradient(var(--pp-head-1), var(--pp-head-2));
  color: var(--pp-title);
  font-weight: 600;
  padding: 6px 8px;
  border-bottom: 1px solid #b5c1ce;
}
.layout .content table:not(.doc-ref-table) td { padding: 4px 8px; border-bottom: 1px solid var(--pp-border-soft); }
.layout .content table:not(.doc-ref-table) tbody tr:nth-child(even) { background: var(--pp-zebra); }
.layout .content table:not(.doc-ref-table) tbody tr:hover { background: var(--pp-hover); }

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

interface SidebarProps {
  current: PageId
  onNavigate: (page: PageId) => void
  /** Compteurs d'alertes affichés à côté des pages (factures échues, lots périmés…) */
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
    title: 'Articles & stock',
    items: [
      { id: 'catalog', label: 'Mes produits' },
      { id: 'stock', label: 'Stock' },
      { id: 'lots', label: 'Lots & traçabilité' },
      { id: 'kits', label: 'Kits' },
      { id: 'import', label: 'Import CSV' },
    ],
  },
  {
    title: 'Ventes',
    items: [
      { id: 'quotes', label: 'Devis' },
      { id: 'orders', label: 'Bons de commande' },
      { id: 'deliveries', label: 'Bons de livraison' },
      { id: 'depots', label: 'Dépôts cliniques' },
      { id: 'invoices', label: 'Factures' },
      { id: 'credits', label: 'Avoirs' },
      { id: 'clients', label: 'Clients' },
    ],
  },
  {
    title: 'Achats',
    items: [
      { id: 'purchases', label: 'Commandes fournisseurs' },
      { id: 'receipts', label: 'Réceptions' },
      { id: 'bills', label: 'Factures fournisseurs' },
      { id: 'suppliers', label: 'Fournisseurs' },
    ],
  },
  {
    title: 'Analyse & fiscalité',
    items: [
      { id: 'vat', label: 'Déclaration de TVA' },
      { id: 'simulator', label: 'Simulateur' },
      { id: 'compare', label: 'Comparaison' },
      { id: 'decision', label: 'Garder ou abandonner' },
    ],
  },
  {
    title: 'Paramètres',
    items: [
      { id: 'company', label: 'Mon entreprise' },
      { id: 'backup', label: 'Sauvegarde' },
    ],
  },
]

export default function Sidebar({ current, onNavigate, badges }: SidebarProps) {
  return (
    <aside className="sidebar">
      <div className="brand">
        ProfitPilot
        <small>Gestion commerciale</small>
      </div>
      <nav>
        {sections.map((section) => (
          <div key={section.title}>
            <div className="nav-section-title">{section.title}</div>
            {section.items.map((item) => {
              const badge = badges?.[item.id]
              return (
                <button
                  key={item.id}
                  className={item.id === current ? 'nav-item active' : 'nav-item'}
                  onClick={() => onNavigate(item.id)}
                >
                  {item.label}
                  {!!badge && <span className="nav-badge">{badge}</span>}
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
import DepotPage from './documents/DepotPage'
import LotsPage from './documents/LotsPage'
import KitsPage from './documents/KitsPage'
import PartiesPage from './documents/PartiesPage'
import BackupPage from './documents/BackupPage'
import { isOverdue } from './documents/ledger'
import { applyMove, expiryState } from './documents/stockMoves'
import { useCompany, useDocuments, useKits, useLots, useParties } from './documents/storage'
import type { DocKind, DocLine } from './documents/types'
import { CURRENCIES, setCurrency } from './utils/finance'
import './theme.css'
import './documents/documents.css'
import './pro-theme.css'

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
  company: 'Mon entreprise',
  backup: 'Sauvegarde des données',
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
  'depots',
  'clients',
  'suppliers',
  'lots',
  'kits',
  'vat',
  'company',
  'backup',
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
  const [page, setPage] = useState<PageId>('dashboard')
  // Pièce à ouvrir directement en arrivant sur une page (après une conversion ou une facturation de dépôt)
  const [openId, setOpenId] = useState<string | undefined>()
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

  function navigate(next: PageId) {
    setOpenId(undefined)
    setPage(next)
  }

  function openDocument(kind: DocKind, id?: string) {
    setOpenId(id)
    setPage(pageOfKind[kind])
  }

  function handleEdit(next: Product[]) {
    setProducts(next)
    setIsSampleData(false)
  }

  // BL, réceptions et retours de dépôt : mise à jour du stock des articles et des lots
  function handleStockMove(lines: DocLine[], direction: 1 | -1, supplier?: string) {
    const result = applyMove({ products, lots }, lines, direction, supplier)
    handleEdit(result.products)
    setLots(result.lots)
    if (result.shortages.length) alert('Stock insuffisant, ramené à 0 pour :\n' + result.shortages.join('\n'))
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
  const badges = useMemo(() => {
    const overdue = (kind: DocKind) => documents.filter((d) => d.kind === kind && isOverdue(d, documents)).length
    return {
      invoices: overdue('invoice'),
      bills: overdue('bill'),
      lots: lots.filter((l) => l.quantity > 0 && ['expired', 'soon'].includes(expiryState(l.expiry))).length,
      depots: documents.reduce(
        (n, d) => n + (d.consignment && d.status === 'validated' ? d.lines.filter((l) => l.depot === 'depot').length : 0),
        0,
      ),
    }
  }, [documents, lots])

  return (
    <div className="layout">
      <Sidebar current={page} onNavigate={navigate} badges={badges} />
      <main className="content">
        <p className="print-only">
          ProfitPilot · {titles[page]} · {new Date().toLocaleDateString('fr-FR')} · {currency}
          {isSampleData ? ' · données de démonstration' : ''}
        </p>
        <h1>{titles[page]}</h1>
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
            key={docKind + (openId ?? '')} // réinitialise la vue en changeant de page
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
          <PartiesPage role="client" parties={parties} onChange={setParties} documents={documents} company={company} />
        )}
        {page === 'suppliers' && (
          <PartiesPage role="supplier" parties={parties} onChange={setParties} documents={documents} company={company} />
        )}
        {page === 'lots' && <LotsPage lots={lots} onChange={setLots} products={products} documents={documents} />}
        {page === 'kits' && <KitsPage kits={kits} onChange={setKits} products={products} />}
        {page === 'vat' && <VatPage documents={documents} />}
        {page === 'company' && <CompanySettings company={company} onChange={setCompany} />}
        {page === 'backup' && <BackupPage />}
      </main>
    </div>
  )
}
FIN_DU_FICHIER
echo "OK src/App.tsx"

# Nouvelles pages dans le type PageId
for id in quotes orders deliveries depots invoices credits clients purchases receipts bills suppliers lots kits vat company backup; do
  grep -q "'$id'" src/types.ts || sed -i.tmp "s/'decision'/'decision' | '$id'/" src/types.ts
done
rm -f src/types.ts.tmp
echo "Type PageId :"
grep -n "type PageId" src/types.ts
echo "Installation terminée. Lancez : npm run dev"
