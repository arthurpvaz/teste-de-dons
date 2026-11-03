-- 0014_gift_test_rework.sql
-- Reformula o teste de dons para a lógica real (matriz 7 linhas x 19 colunas = 133 perguntas):
-- 19 dons, 7 perguntas por dom, resposta 0..3, score = soma simples por dom (máx. 21).
-- Nomes/perguntas PROVISÓRIOS (dom_01..dom_19) até o grupo entregar o conteúdo oficial IPB.

-- 1) Limpa os dados antigos de dons (não há dados reais). Ordem respeita as FKs.
delete from public.gift_answers;
delete from public.gift_submissions;
delete from public.gift_questions;
delete from public.ministry_gift_needs;   -- referencia gifts(id)
delete from public.gifts;

-- 2) Escala de resposta: de 1..5 para 0..3 (remove qualquer CHECK antigo na coluna value).
do $$
declare c text;
begin
  for c in
    select conname from pg_constraint
     where conrelid = 'public.gift_answers'::regclass and contype = 'c'
  loop
    execute 'alter table public.gift_answers drop constraint ' || quote_ident(c);
  end loop;
end $$;
alter table public.gift_answers
  add constraint gift_answers_value_check check (value between 0 and 3);

-- 3) 19 dons provisórios (coluna da matriz = sort_order 1..19).
insert into public.gifts (code, name, description, sort_order)
select 'dom_' || lpad(n::text, 2, '0'),
       'Dom ' || n || ' (provisório)',
       'Nome e descrição provisórios — substituir pelo dom oficial IPB.',
       n
  from generate_series(1, 19) as n;

-- 4) 133 perguntas (7 por dom). sort_order = coluna*10 + linha (posição na matriz).
insert into public.gift_questions (text, gift_id, weight, is_active, version, sort_order)
select 'Pergunta ' || linha || ' do ' || g.name || ' (texto provisório).',
       g.id, 1, true, 1, g.sort_order * 10 + linha
  from public.gifts g
 cross join generate_series(1, 7) as linha;

-- 5) Remove as colunas do fluxo antigo de token (envio agora é combinado — ver 0016).
alter table public.members drop column if exists submit_token_hash;
alter table public.members drop column if exists submit_token_used;
