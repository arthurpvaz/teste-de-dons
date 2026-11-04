-- 0009_transfers_audit.sql
-- Transferência interna entre igrejas (RF12), histórico de migração e trilha de auditoria.

create table public.transfer_requests (
  id             uuid primary key default gen_random_uuid(),
  member_id      uuid not null references public.members(id) on delete cascade,
  from_church_id uuid not null references public.churches(id),
  to_church_id   uuid not null references public.churches(id),
  status         text not null default 'pending' check (status in ('pending', 'accepted', 'rejected')),
  requested_by   uuid references public.profiles(id),
  resolved_by    uuid references public.profiles(id),
  resolved_at    timestamptz,
  created_at     timestamptz not null default now(),
  check (from_church_id <> to_church_id)
);
create index transfer_requests_to_idx   on public.transfer_requests (to_church_id, status);
create index transfer_requests_from_idx on public.transfer_requests (from_church_id, status);
-- no máximo uma solicitação pendente por membro
create unique index transfer_requests_one_pending
  on public.transfer_requests (member_id) where status = 'pending';

-- Log append-only das migrações de igreja (preserva o histórico mesmo após a migração, RF12).
create table public.member_church_history (
  id             uuid primary key default gen_random_uuid(),
  member_id      uuid not null references public.members(id) on delete cascade,
  from_church_id uuid references public.churches(id),
  to_church_id   uuid not null references public.churches(id),
  reason         text,
  moved_by       uuid references public.profiles(id),
  created_at     timestamptz not null default now()
);
create index member_church_history_member_idx on public.member_church_history (member_id);

-- Auditoria de ações privilegiadas (RF02/RF03/RF13): criar igreja, conceder/revogar acesso,
-- transferir, arquivar. Escrita apenas via RPCs SECURITY DEFINER.
create table public.audit_log (
  id          uuid primary key default gen_random_uuid(),
  actor_id    uuid references public.profiles(id),
  action      text not null,
  entity_type text,
  entity_id   uuid,
  church_id   uuid references public.churches(id),
  detail      jsonb,
  created_at  timestamptz not null default now()
);
create index audit_log_church_idx on public.audit_log (church_id);
