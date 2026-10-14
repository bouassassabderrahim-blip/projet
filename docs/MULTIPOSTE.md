# Utiliser ProfitPilot sur plusieurs ordinateurs

Les données sont rangées dans une **base en ligne Supabase** partagée par tous vos ordinateurs.
Chaque pièce, client, article ou lot est synchronisé séparément toutes les 4 secondes environ.
Les numéros de pièces sont attribués par le serveur : deux postes ne peuvent jamais donner le même numéro.

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
- **Project URL** : `https://xxxxxxxx.supabase.co`
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
  connexion (« Hors ligne · N modification(s) en attente » en bas de l'écran). Seule la **validation** d'une pièce
  demande d'être en ligne, car son numéro définitif vient du serveur.
- **Deux personnes sur la même pièce** : la dernière modification enregistrée l'emporte, avec deux exceptions :
  une pièce validée ne revient jamais en brouillon et ne peut pas être supprimée par un autre poste, et les
  règlements saisis sur deux postes s'additionnent.
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
