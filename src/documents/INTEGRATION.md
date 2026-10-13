# ProfitPilot : gestion commerciale

## Installation (Git Bash sous Windows, terminal sous Mac/Linux)
À la racine du projet :
```bash
curl -fsSL https://raw.githubusercontent.com/bouassassabderrahim-blip/projet/claude/profitpilot-app-setup-2timay/installer-documents.sh | bash
```
Sauvegardes automatiques : `App.tsx.bak`, `Sidebar.tsx.bak`, `Dashboard.tsx.bak`, `types.ts.bak`.

## Modules
- **Ventes** : Devis → BC → BL → Facture → Avoir. Numérotation DV/BC/BL/FA/AV-AAAA-0001.
- **Achats** : Commande fournisseur → Réception → Facture fournisseur (CF/BR/FF).
- **Dépôts cliniques** : BL « en dépôt », facturation à la pose, retour en stock.
- **Lots & traçabilité** : lot, n° de série et péremption sur chaque ligne ; lots créés par les réceptions,
  choisis en FEFO sur les BL ; alertes de péremption à 90 jours ; recherche de rappel de lot.
- **Kits** : ensembles d'articles insérés en un clic.
- **Patients / interventions** : patient, dossier, chirurgien, clinique, prise en charge (CNSS, CNOPS, AMO…).
- **Règlements** : partiels, plusieurs par facture ; reste dû ; factures échues ; lettre de relance.
- **Clients / fournisseurs** : fiches, CA, encours, historique, délai de paiement.
- **TVA** : collectée, déductible, due ; régime des encaissements ou des débits ; mensuelle ou trimestrielle.
- **Exports** : journaux des ventes et des achats (CSV Excel), déclaration TVA (CSV).
- **Sauvegarde** : export / restauration de toutes les données en un fichier JSON.
- **Thème pro** (`src/pro-theme.css`) : navigation en sections, bandeaux, grilles denses.
