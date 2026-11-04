-- 0003_church_access_helpers.sql
-- Matriz de permissões cruzadas (RF03/RF04) + funções auxiliares de RLS.
-- As funções são o coração do isolamento multi-tenant.

create table public.church_access (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  church_id  uuid not null references public.churches(id) on delete cascade,
  level      text not null check (level in ('read', 'edit')),
  granted_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  primary key (user_id, church_id)
);
create index church_access_church_idx on public.church_access (church_id);

comment on table public.church_access is 'Acesso cruzado concedido pelo Admin Master (RF03). Alimenta o tenant switcher (RF04).';

-- Nível efetivo do usuário logado em uma igreja (pega o MAIOR nível aplicável):
--   master -> 'edit' (global); senão igreja-sede -> 'edit'; senão grant explícito; senão null.
-- A sede vem ANTES do grant de propósito: um grant 'read' redundante na própria sede não
-- pode rebaixar o pastor a somente-leitura na igreja dele.
-- DEFINER + STABLE + search_path='' : lê profiles/church_access sem RLS (sem recursão de policy).
create or replace function public.user_church_level(p_church_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.current_is_master() then 'edit'
    when exists (
      select 1 from public.profiles p
       where p.id = auth.uid() and p.home_church_id = p_church_id
    ) then 'edit'
    else (select ca.level
            from public.church_access ca
           where ca.user_id = auth.uid() and ca.church_id = p_church_id)
  end;
$$;

create or replace function public.has_church_read(p_church_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.user_church_level(p_church_id) in ('read', 'edit'), false);
$$;

create or replace function public.has_church_edit(p_church_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.user_church_level(p_church_id) = 'edit', false);
$$;
