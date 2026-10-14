-- ProfitPilot ERP : préparation de la base en ligne (Supabase)
-- À exécuter UNE fois : Supabase › SQL Editor › New query › coller ce fichier › Run.
-- Le script peut être relancé sans danger.

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
create index if not exists records_sync_idx on public.records (dossier, updated_at);

-- 3. Compteurs de numérotation partagés (aucun doublon de numéro entre postes)
create table if not exists public.counters (
  dossier text    not null,
  kind    text    not null,
  year    integer not null,
  last    integer not null default 0,
  primary key (dossier, kind, year)
);

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

drop policy if exists members_read_own on public.members;
create policy members_read_own on public.members
  for select to authenticated
  using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

drop policy if exists records_read on public.records;
create policy records_read on public.records
  for select to authenticated using (public.is_member(dossier));

drop policy if exists records_insert on public.records;
create policy records_insert on public.records
  for insert to authenticated with check (public.is_member(dossier));

drop policy if exists records_update on public.records;
create policy records_update on public.records
  for update to authenticated
  using (public.is_member(dossier)) with check (public.is_member(dossier));
-- Pas de règle de suppression : on ne supprime jamais, on marque « deleted »

-- Droits au plus juste : Supabase donne par défaut tous les droits (y compris DELETE et TRUNCATE,
-- que les règles RLS ne couvrent pas). On les retire puis on n'accorde que le nécessaire.
revoke all on public.members, public.records, public.counters from anon, authenticated;
grant select on public.members to authenticated;
grant select, insert, update on public.records to authenticated;

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

-- 4. Ajoutez ici les comptes autorisés (un par ligne), puis exécutez :
-- insert into public.members (dossier, email) values
--   ('orthomed', 'admin@votre-societe.ma'),
--   ('orthomed', 'poste-magasin@votre-societe.ma')
-- on conflict do nothing;
