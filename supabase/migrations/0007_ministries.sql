-- 0007_ministries.sql
-- Ministérios locais, seus dons requeridos e a alocação efetiva de membros (RF10/RF14).

create table public.ministries (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references public.churches(id) on delete cascade,
  name        text not null check (char_length(trim(name)) > 0),
  description text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (church_id, name)
);
create index ministries_church_idx on public.ministries (church_id);

-- Dons requeridos por ministério, com peso (base do matching RF14).
create table public.ministry_gift_needs (
  ministry_id uuid not null references public.ministries(id) on delete cascade,
  gift_id     uuid not null references public.gifts(id),
  weight      numeric not null default 1 check (weight >= 0),
  primary key (ministry_id, gift_id)
);

-- Alocação efetiva membro <-> ministério ("escala"). RF10: membro inativo é desativado aqui.
create table public.ministry_assignments (
  id          uuid primary key default gen_random_uuid(),
  ministry_id uuid not null references public.ministries(id) on delete cascade,
  member_id   uuid not null references public.members(id) on delete cascade,
  church_id   uuid not null references public.churches(id),
  role        text,
  active      boolean not null default true,
  assigned_by uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  unique (ministry_id, member_id)
);
create index ministry_assignments_church_idx on public.ministry_assignments (church_id);
create index ministry_assignments_member_idx on public.ministry_assignments (member_id);
