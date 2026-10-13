# Module Facturation / BC / BL (TVA Maroc)

## 1. Copier les fichiers
Copiez le dossier `src/documents/` dans votre projet et remplacez `src/App.tsx`.

## 2. Étendre `PageId` dans `src/types.ts`
```ts
export type PageId =
	| 'dashboard' | 'catalog' | 'stock' | 'products' | 'breakeven' | 'import'
	| 'simulator' | 'recommendations' | 'compare' | 'decision'
	| 'invoices' | 'orders' | 'deliveries' | 'company'
```

## 3. Ajouter les entrées dans `Sidebar`
Ajoutez à la liste de liens de votre `Sidebar` :
```ts
{ id: 'orders', label: 'Bons de commande' },
{ id: 'deliveries', label: 'Bons de livraison' },
{ id: 'invoices', label: 'Factures' },
{ id: 'company', label: 'Mon entreprise' },
```

## Fonctionnement
- Chaîne commerciale : BC → BL → Facture (bouton « → Bon de livraison », « → Facture »).
- Numérotation continue par année : `BC-2026-0001`, `BL-2026-0001`, `FA-2026-0001`.
- TVA marocaine : 20 %, 14 %, 10 %, 7 %, exonéré ; récapitulatif par taux.
- Droit de timbre de 0,25 % ajouté automatiquement aux factures payées en espèces.
- Montant en lettres en dirhams (« Arrêtée la présente facture à la somme de … »).
- Mentions légales : ICE (15 chiffres, obligatoire sur facture), IF, RC, Patente, CNSS, RIB.
- Un document validé n'est plus modifiable : utilisez « Annuler » puis « Dupliquer ».
- Le BL s'imprime sans prix, avec cadres de signature.
- Prix produits : `unitPrice` est considéré comme un prix **HT**.
