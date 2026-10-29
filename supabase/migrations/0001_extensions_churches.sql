-- 0001_extensions_churches.sql
-- Extensões e a tabela-raiz do multi-tenant: churches (cada igreja = um tenant).
-- RF02 (Admin Master cadastra igrejas) e RF05 (link público por igreja via slug).

-- pgcrypto fica no schema `extensions` (padrão Supabase) para que funções
-- SECURITY DEFINER com search_path='' consigam referenciá-lo de forma qualificada
-- (extensions.digest, extensions.gen_random_bytes). gen_random_uuid() é core (pg_catalog).
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table public.churches (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(trim(name)) > 0),
  -- slug é o identificador do link público; normalizado em minúsculas, kebab-case.
  slug       text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  city       text,
  created_at timestamptz not null default now()
);

comment on table public.churches is 'Igrejas (tenants). slug = identificador do link/QR público (RF05).';
