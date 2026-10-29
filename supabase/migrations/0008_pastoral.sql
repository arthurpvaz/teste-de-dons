-- 0008_pastoral.sql
-- Histórico pastoral confidencial (RF11) e visitas de resgate (RF10/RF11).
-- A confidencialidade (acesso só por pastor com edit) é imposta nas policies (0010).

create table public.pastoral_notes (
  id         uuid primary key default gen_random_uuid(),
  member_id  uuid not null references public.members(id) on delete cascade,
  church_id  uuid not null references public.churches(id),
  author_id  uuid references public.profiles(id),
  body       text not null check (char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);
create index pastoral_notes_member_idx on public.pastoral_notes (member_id);
create index pastoral_notes_church_idx on public.pastoral_notes (church_id);
comment on table public.pastoral_notes is 'Notas confidenciais do pastor (RF11). Dado sensível LGPD.';

-- Agendamento/registro de visitas pastorais (aba de resgate, RF10).
create table public.pastoral_visits (
  id           uuid primary key default gen_random_uuid(),
  member_id    uuid not null references public.members(id) on delete cascade,
  church_id    uuid not null references public.churches(id),
  scheduled_at timestamptz,
  done         boolean not null default false,
  outcome      text,
  author_id    uuid references public.profiles(id),
  created_at   timestamptz not null default now()
);
create index pastoral_visits_member_idx on public.pastoral_visits (member_id);
create index pastoral_visits_church_idx on public.pastoral_visits (church_id);
