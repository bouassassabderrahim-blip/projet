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
