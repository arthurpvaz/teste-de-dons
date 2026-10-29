-- supabase/tests/smoke.sql
-- Testes de fumaça do backend Conecta Dons. Rodar com o stack local de pé.
-- Via container:
--   docker exec -i supabase_db_conecta-dons psql postgresql://postgres:postgres@127.0.0.1:5432/postgres \
--     -v ON_ERROR_STOP=1 < supabase/tests/smoke.sql
-- Com psql instalado:
--   psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -v ON_ERROR_STOP=1 -f supabase/tests/smoke.sql
--
-- Tudo roda em uma transação e termina em ROLLBACK (não suja o banco).
-- Qualquer assert/FALHOU interrompe e sinaliza erro (ON_ERROR_STOP).

\set ON_ERROR_STOP on
begin;

-- ============================ SETUP (como postgres) ============================
insert into auth.users (id, instance_id, aud, role, email)
values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'master@ipb.org'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pastora@ipb.org'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pastorb@ipb.org');

update public.profiles set is_master = true
 where id = '00000000-0000-0000-0000-00000000a001';
update public.profiles set home_church_id = (select id from public.churches where slug = 'sapucaia')
 where id = '00000000-0000-0000-0000-00000000a002';
update public.profiles set home_church_id = (select id from public.churches where slug = 'gravatai')
 where id = '00000000-0000-0000-0000-00000000a003';

insert into public.members (church_id, full_name, bond)
select id, 'Membro Sapucaia', 'comungante' from public.churches where slug = 'sapucaia';
insert into public.members (church_id, full_name, bond)
select id, 'Membro Gravatai', 'comungante' from public.churches where slug = 'gravatai';

-- =================== 1) FLUXO PÚBLICO (anon): cadastro + teste ===================
\echo '== 1) Fluxo publico anon =='
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
declare v_token text; v_answers jsonb; v_sub uuid;
begin
  -- RF05
  assert (select count(*) from public.get_church_by_slug('sapucaia')) = 1,
         'FALHOU: get_church_by_slug nao achou sapucaia';
  -- RF06: cadastro -> token
  select submit_token into v_token
    from public.register_member('sapucaia', 'Maria Dons', 'maria@teste.com', null, 'comungante', true);
  assert v_token is not null, 'FALHOU: register_member nao devolveu token';
  -- RF07: responde todas as perguntas ativas (nota 5) e envia
  select jsonb_agg(jsonb_build_object('question_id', q.id, 'value', 5)) into v_answers
    from public.get_gift_questions() q;
  v_sub := public.submit_gift_test(v_token, v_answers);
  assert v_sub is not null, 'FALHOU: submit_gift_test nao retornou submissao';
  raise notice 'OK: cadastro + teste de dons enviados (submissao %)', v_sub;
end $$;

-- token invalido deve falhar
do $$
begin
  perform public.submit_gift_test('token-que-nao-existe', '[]'::jsonb);
  raise exception 'FALHOU: token invalido deveria ser rejeitado';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: token invalido rejeitado (%)', sqlerrm;
end $$;

-- nota fora de 1..5 deve falhar
do $$
declare v_token text; v_answers jsonb;
begin
  select submit_token into v_token
    from public.register_member('sapucaia', 'Joao Nota', null, null, 'visitante', true);
  select jsonb_agg(jsonb_build_object('question_id', q.id, 'value', 9)) into v_answers
    from public.get_gift_questions() q;
  perform public.submit_gift_test(v_token, v_answers);
  raise exception 'FALHOU: nota 9 deveria ser rejeitada';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: nota fora de 1..5 rejeitada (%)', sqlerrm;
end $$;

-- consentimento falso deve falhar
do $$
begin
  perform public.register_member('sapucaia', 'Sem Consent', null, null, 'visitante', false);
  raise exception 'FALHOU: cadastro sem consentimento deveria ser rejeitado';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: consentimento exigido (%)', sqlerrm;
end $$;

reset role;

-- =================== 2) ISOLAMENTO MULTI-TENANT (RLS) ===================
\echo '== 2) Isolamento multi-tenant =='
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;
do $$
declare n_sap int; n_grav int;
begin
  select count(*) into n_sap  from public.members m join public.churches c on c.id=m.church_id where c.slug='sapucaia';
  select count(*) into n_grav from public.members m join public.churches c on c.id=m.church_id where c.slug='gravatai';
  assert n_sap  >= 1, 'FALHOU: pastora A nao ve membros da propria igreja';
  assert n_grav  = 0, 'FALHOU: pastora A esta vendo membros de Gravatai sem permissao';
  raise notice 'OK: pastora A ve % de Sapucaia e 0 de Gravatai', n_sap;
end $$;

-- pastora A NAO consegue se promover a master
do $$
begin
  update public.profiles set is_master = true where id = '00000000-0000-0000-0000-00000000a002';
  raise exception 'FALHOU: escalonamento de privilegio permitido!';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: auto-promocao a master bloqueada (%)', sqlerrm;
end $$;
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
set local role authenticated;
do $$
declare n int;
begin
  select count(*) into n from public.churches;
  assert n >= 2, 'FALHOU: master nao ve todas as igrejas';
  raise notice 'OK: master ve % igrejas', n;
end $$;
reset role;

-- =================== 3) PERMISSAO CRUZADA (RF03) + confidencialidade ===================
\echo '== 3) Permissao cruzada read-only + confidencialidade pastoral =='
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
set local role authenticated;
select public.grant_access('00000000-0000-0000-0000-00000000a003',
                           (select id from public.churches where slug='sapucaia'), 'read');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;
insert into public.pastoral_notes (member_id, church_id, author_id, body)
select m.id, m.church_id, '00000000-0000-0000-0000-00000000a002', 'Nota confidencial'
  from public.members m join public.churches c on c.id=m.church_id
 where c.slug='sapucaia' limit 1;
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a003","role":"authenticated"}', true);
set local role authenticated;
do $$
declare n_mem int; n_notes int; n_upd int;
begin
  select count(*) into n_mem   from public.members m join public.churches c on c.id=m.church_id where c.slug='sapucaia';
  select count(*) into n_notes from public.pastoral_notes p join public.churches c on c.id=p.church_id where c.slug='sapucaia';
  assert n_mem   >= 1, 'FALHOU: grant read nao deu visibilidade de membros';
  assert n_notes  = 0, 'FALHOU: observador read esta vendo notas confidenciais!';
  update public.members set phone='999' where church_id=(select id from public.churches where slug='sapucaia');
  get diagnostics n_upd = row_count;
  assert n_upd = 0, 'FALHOU: observador read conseguiu editar membros';
  raise notice 'OK: read ve % membros, 0 notas confidenciais, 0 edicoes', n_mem;
end $$;
reset role;

-- =================== 4) TRANSFERENCIA (RF12) ===================
\echo '== 4) Transferencia interna =='
-- pastora A pede; master aceita. Passamos o id da solicitacao via GUC de sessao.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;
select set_config('app.req_id',
  public.request_transfer(
    (select m.id from public.members m join public.churches c on c.id=m.church_id
      where c.slug='sapucaia' and m.full_name='Membro Sapucaia' limit 1),
    (select id from public.list_all_churches() where slug='gravatai')
  )::text, false);
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
set local role authenticated;
select public.accept_transfer(current_setting('app.req_id')::uuid);
do $$
declare v_slug text;
begin
  select c.slug into v_slug
    from public.members m join public.churches c on c.id=m.church_id
   where m.full_name='Membro Sapucaia';
  assert v_slug = 'gravatai', 'FALHOU: membro nao migrou para gravatai';
  assert exists (select 1 from public.member_church_history
                  where to_church_id=(select id from public.churches where slug='gravatai')),
         'FALHOU: historico de migracao nao registrado';
  raise notice 'OK: membro migrou para % e historico gravado', v_slug;
end $$;
do $$
begin
  perform public.accept_transfer(current_setting('app.req_id')::uuid);
  raise exception 'FALHOU: duplo-aceite permitido';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: duplo-aceite bloqueado (%)', sqlerrm;
end $$;
reset role;

-- =================== 5) MATCHING (RF14) + RF10/RF13 ===================
\echo '== 5) Matching de ministerios (so membros ativos) =='
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;
do $$
declare n_before int; n_after int; v_louvor uuid; v_maria uuid;
begin
  select id into v_louvor from public.ministries where name='Louvor'
    and church_id=(select id from public.churches where slug='sapucaia');
  select count(*) into n_before from public.suggest_members_for_ministry(v_louvor);
  assert n_before >= 1, 'FALHOU: matching nao sugeriu nenhum membro';

  select id into v_maria from public.members
   where full_name='Maria Dons' and church_id=(select id from public.churches where slug='sapucaia');
  perform public.archive_member(v_maria, 'Mudou de cidade');
  select count(*) into n_after from public.suggest_members_for_ministry(v_louvor);
  assert n_after < n_before, 'FALHOU: membro arquivado continua no matching';
  raise notice 'OK: matching antes=% depois de arquivar=%', n_before, n_after;
end $$;
reset role;

-- =================== 6) AUTORIZACAO NEGATIVA (RLS/RPC) ===================
\echo '== 6) Autorizacao negativa =='
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;

-- pastora A (sede sapucaia) NAO insere membro em gravatai
do $$
begin
  insert into public.members (church_id, full_name, bond)
  values ((select id from public.churches where slug='gravatai'), 'Intruso', 'visitante');
  raise exception 'FALHOU: inseriu membro em igreja sem permissao';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: insert de membro em igreja alheia bloqueado (%)', sqlerrm;
end $$;

-- pastora A (nao-master) NAO edita a matriz oficial de dons
do $$
declare n int;
begin
  update public.gifts set name='Hackeado' where code='profecia';
  get diagnostics n = row_count;
  assert n = 0, 'FALHOU: nao-master editou a tabela gifts';
  raise notice 'OK: escrita em gifts negada p/ nao-master (linhas=%)', n;
end $$;

-- pastora A NAO escreve direto em church_access (so via grant_access do master)
do $$
declare n int;
begin
  insert into public.church_access (user_id, church_id, level)
  values ('00000000-0000-0000-0000-00000000a002', (select id from public.churches where slug='gravatai'), 'edit');
  raise exception 'FALHOU: pastora concedeu acesso a si mesma';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: escrita direta em church_access bloqueada (%)', sqlerrm;
end $$;

-- pastora A NAO cria igreja (so master)
do $$
begin
  perform public.create_church('Igreja Pirata', 'pirata', 'Lugar Nenhum');
  raise exception 'FALHOU: nao-master criou igreja';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: create_church negado p/ nao-master (%)', sqlerrm;
end $$;
reset role;

-- =================== 7) CORRECOES DE REVISAO ===================
\echo '== 7) Correcoes de revisao =='
-- P1: grant 'read' redundante na propria sede NAO rebaixa o pastor (mantem edit).
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a001","role":"authenticated"}', true);
set local role authenticated;
select public.grant_access('00000000-0000-0000-0000-00000000a002',
                           (select id from public.churches where slug='sapucaia'), 'read');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;
do $$
declare n int;
begin
  update public.members set phone='123' where church_id=(select id from public.churches where slug='sapucaia');
  get diagnostics n = row_count;
  assert n >= 1, 'FALHOU: grant read na sede rebaixou o pastor (perdeu edit)';
  raise notice 'OK: sede mantem edit apesar de grant read (linhas=%)', n;
end $$;

-- P2: troca direta de church_id via UPDATE e bloqueada (so via accept_transfer).
do $$
begin
  update public.members set church_id=(select id from public.churches where slug='gravatai')
   where church_id=(select id from public.churches where slug='sapucaia');
  raise exception 'FALHOU: troca direta de church_id permitida';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: troca direta de igreja bloqueada (%)', sqlerrm;
end $$;
reset role;

\echo '== TODOS OS TESTES PASSARAM =='
rollback;
