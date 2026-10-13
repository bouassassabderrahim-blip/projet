# Module Ventes : devis, BC, BL, factures, TVA Maroc

## Installation
À la racine du projet :
```bash
curl -fsSL https://raw.githubusercontent.com/bouassassabderrahim-blip/projet/claude/profitpilot-app-setup-2timay/installer-documents.sh | bash
```
Le script sauvegarde `App.tsx`, `Sidebar.tsx`, `Dashboard.tsx` et `types.ts` en `.bak`, puis ajoute
`'invoices' | 'orders' | 'deliveries' | 'company' | 'quotes' | 'vat'` au type `PageId`.

## Fonctionnalités
- Chaîne commerciale : Devis → BC → BL → Facture, numérotation DV/BC/BL/FA-AAAA-0001.
- TVA marocaine 20/14/10/7 % et exonéré, récapitulatif par taux, montant en lettres en dirhams.
- Droit de timbre 0,25 % sur les factures payées en espèces.
- Factures en retard (échéance dépassée) signalées dans la liste, le menu et le tableau de bord.
- Date d'encaissement saisie au passage en « Payée ».
- Déclaration de TVA : TVA collectée par mois ou trimestre, régime des encaissements ou des débits, export CSV.
- Journal des ventes exportable en CSV pour le comptable.
- Validation d'un BL : les quantités livrées sont retirées du stock (et remises si le BL est annulé).
- Tableau de bord : bloc Ventes (facturé du mois, encours, retards, devis en cours) et alertes stock.
