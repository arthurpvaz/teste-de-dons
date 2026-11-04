-- 0002_profiles.sql
-- Perfis de pastores/admins (1:1 com auth.users) + trigger de criação automática
-- + trava das colunas privilegiadas (is_master / home_church_id).
-- RF01 (auth pastoral) e RF02 (Admin Master).

create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  full_name      text,
  email          text,
  -- is_master: acesso global da plataforma (RF02). NUNCA auto-editável (ver trigger abaixo).
  is_master      boolean not null default false,
  -- home_church_id: igreja-sede do pastor; concede edit implícito nela (ver 0003). Master-set.
  home_church_id uuid references public.churches(id),
  created_at     timestamptz not null default now()
);

comment on table public.profiles is 'Perfil de pastor/admin. is_master e home_church_id só mudam via master/service_role.';

-- Cria o profile automaticamente quando um usuário é criado no Supabase Auth.
-- SECURITY DEFINER + search_path vazio (evita sequestro de search_path).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, is_master)
  values (
    new.id,
    new.email,
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    false   -- nunca confia em metadata do cliente para privilégio
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- current_is_master(): base de toda a lógica de permissão. DEFINER + STABLE;
-- lê profiles SEM disparar RLS (owner postgres ignora RLS), quebrando recursão de policy.
create or replace function public.current_is_master()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.is_master from public.profiles p where p.id = auth.uid()), false);
$$;

-- Impede que um pastor comum se promova a master ou troque a própria igreja-sede.
-- Só master (autenticado) ou conexões privilegiadas (postgres/service_role, usadas no
-- bootstrap do primeiro master) podem alterar is_master / home_church_id.
-- IMPORTANTE: SECURITY INVOKER (padrão) — precisamos do current_user do CHAMADOR real
-- (ex.: 'authenticated'). Se fosse SECURITY DEFINER, current_user seria sempre o dono
-- (postgres), que está na allow-list, e a trava nunca pegaria um pastor comum.
create or replace function public.lock_privileged_profile_cols()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_master is distinct from old.is_master
     or new.home_church_id is distinct from old.home_church_id then
    if not (
      public.current_is_master()
      or current_user in ('postgres', 'supabase_admin', 'service_role', 'supabase_auth_admin')
    ) then
      raise exception 'Alteração de is_master/home_church_id não permitida';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_lock_privileged
  before update on public.profiles
  for each row execute function public.lock_privileged_profile_cols();
