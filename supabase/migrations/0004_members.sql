-- 0004_members.sql
-- Membros/visitantes da congregação, escopados por igreja.
-- RF06 (cadastro público), RF09 (status pastoral), RF13 (arquivamento).
-- Inclui o token de uso único do teste de dons e o log de rate-limit do cadastro público.

create table public.members (
  id                uuid primary key default gen_random_uuid(),
  church_id         uuid not null references public.churches(id) on delete cascade,
  full_name         text not null check (char_length(trim(full_name)) > 0),
  email             text,
  phone             text,
  -- vínculo comunitário (RF06)
  bond              text not null check (bond in ('comungante', 'nao_comungante', 'visitante')),
  -- status pastoral (RF09)
  status            text not null default 'ativo'
                      check (status in ('ativo', 'em_alerta', 'inativo_desviado', 'transferido')),
  -- arquivamento / desligamento externo (RF13) — preserva a linha p/ estatística do Conselho
  archived          boolean not null default false,
  archived_reason   text,
  archived_at       timestamptz,
  -- consentimento LGPD (RF06)
  consent           boolean not null default false,
  consent_at        timestamptz,
  -- token de uso único p/ responder o teste de dons sem login (guardado como hash sha256)
  submit_token_hash text,
  submit_token_used boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (not archived or archived_at is not null)
);

-- e-mail único POR IGREJA (não global: a mesma pessoa pode existir em igrejas diferentes).
create unique index members_church_email_uniq
  on public.members (church_id, lower(email))
  where email is not null and archived = false;

create index members_church_idx on public.members (church_id);
create index members_status_idx on public.members (status, church_id);

comment on table public.members is 'Congregação por igreja. Teste de dons vincula-se a esta tabela (RF07/RF14).';

-- updated_at automático
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger members_updated_at
  before update on public.members
  for each row execute function public.set_updated_at();

-- Impede mudança direta de church_id via UPDATE: a troca de igreja de um membro só pode
-- acontecer pelo fluxo auditado accept_transfer (RF12). Um pastor com edit em duas igrejas
-- não pode "mover" um membro por fora (sem histórico/auditoria) com um update cru.
-- SECURITY INVOKER (padrão): precisamos do current_user real. Dentro de accept_transfer
-- (SECURITY DEFINER, dono postgres) o current_user é 'postgres' -> permitido.
create or replace function public.lock_member_church()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.church_id is distinct from old.church_id
     and current_user not in ('postgres', 'supabase_admin', 'service_role') then
    raise exception 'A troca de igreja de um membro só é permitida via transferência (accept_transfer)';
  end if;
  return new;
end;
$$;

create trigger members_lock_church
  before update on public.members
  for each row execute function public.lock_member_church();

-- Rate-limit do cadastro público (RF05/RF06): uma linha por cadastro, consultada no RPC.
create table public.registration_log (
  id         uuid primary key default gen_random_uuid(),
  church_id  uuid not null references public.churches(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index registration_log_church_time_idx on public.registration_log (church_id, created_at);
