-- supabase/tests/smoke.sql
-- Suíte de fumaça do backend Conecta Dons. Rode via:  npm run test:backend
-- (ou manualmente com o stack de pé, ver supabase/TESTING.md).
-- Roda em transação e termina em ROLLBACK (não altera o banco).
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

-- =============== 1) FLUXO PÚBLICO: um link + campus + envio combinado ===============
\echo '== 1) Fluxo publico anon (campus + submit_questionnaire) =='
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
declare v_campus uuid; v_answers jsonb; v_member uuid; v_sub uuid; v_qtd int;
begin
  -- seletor de campus
  select id into v_campus from public.list_campuses() where name like 'IPB Sapucaia%' limit 1;
  assert v_campus is not null, 'FALHOU: list_campuses nao retornou Sapucaia';

  -- devem existir 133 perguntas (19 dons x 7)
  select count(*) into v_qtd from public.get_gift_questions();
  assert v_qtd = 133, 'FALHOU: esperava 133 perguntas, veio ' || v_qtd;

  -- responde todas com valor 3 e envia (cria cadastro + submissao numa so chamada)
  select jsonb_agg(jsonb_build_object('question_id', q.id, 'value', 3)) into v_answers
    from public.get_gift_questions() q;
  select member_id, submission_id into v_member, v_sub
    from public.submit_questionnaire(v_campus, 'Maria Dons', 'maria@teste.com', null, 'comungante', true, v_answers);
  assert v_member is not null and v_sub is not null, 'FALHOU: submit_questionnaire nao criou cadastro+submissao';
  raise notice 'OK: questionario enviado (membro %, submissao %)', v_member, v_sub;
end $$;

-- valor fora de 0..3 deve falhar
do $$
declare v_campus uuid; v_answers jsonb;
begin
  select id into v_campus from public.list_campuses() where name like 'IPB Sapucaia%' limit 1;
  select jsonb_agg(jsonb_build_object('question_id', q.id, 'value', 9)) into v_answers
    from public.get_gift_questions() q;
  perform public.submit_questionnaire(v_campus, 'Joao Nota', null, null, 'visitante', true, v_answers);
  raise exception 'FALHOU: valor 9 deveria ser rejeitado';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: valor fora de 0..3 rejeitado (%)', sqlerrm;
end $$;

-- respostas incompletas (menos que 133) deve falhar
do $$
declare v_campus uuid;
begin
  select id into v_campus from public.list_campuses() where name like 'IPB Sapucaia%' limit 1;
  perform public.submit_questionnaire(v_campus, 'Incompleto', null, null, 'visitante', true, '[]'::jsonb);
  raise exception 'FALHOU: respostas incompletas deveriam ser rejeitadas';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: respostas incompletas rejeitadas (%)', sqlerrm;
end $$;

-- consentimento falso deve falhar
do $$
declare v_campus uuid;
begin
  select id into v_campus from public.list_campuses() where name like 'IPB Sapucaia%' limit 1;
  perform public.submit_questionnaire(v_campus, 'Sem Consent', null, null, 'visitante', false, '[]'::jsonb);
  raise exception 'FALHOU: sem consentimento deveria ser rejeitado';
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

-- =================== 5) MATCHING (RF14) + perfil/gráfico + RF10/RF13 ===================
\echo '== 5) Matching, perfil de dons e exclusao de arquivados =='
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000a002","role":"authenticated"}', true);
set local role authenticated;
do $$
declare v_maria uuid; v_score numeric;
begin
  select id into v_maria from public.members
   where full_name='Maria Dons' and church_id=(select id from public.churches where slug='sapucaia');
  -- perfil: cada dom = 7 respostas x 3 = 21
  select score into v_score from public.get_member_gift_profile(v_maria) where gift_code='dom_01';
  assert v_score = 21, 'FALHOU: soma do dom_01 deveria ser 21, veio ' || coalesce(v_score::text,'null');
  raise notice 'OK: perfil dom_01 = % (7x3)', v_score;
end $$;

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

do $$
begin
  insert into public.members (church_id, full_name, bond)
  values ((select id from public.churches where slug='gravatai'), 'Intruso', 'visitante');
  raise exception 'FALHOU: inseriu membro em igreja sem permissao';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: insert de membro em igreja alheia bloqueado (%)', sqlerrm;
end $$;

do $$
declare n int;
begin
  update public.gifts set name='Hackeado' where code='dom_01';
  get diagnostics n = row_count;
  assert n = 0, 'FALHOU: nao-master editou a tabela gifts';
  raise notice 'OK: escrita em gifts negada p/ nao-master (linhas=%)', n;
end $$;

do $$
begin
  insert into public.church_access (user_id, church_id, level)
  values ('00000000-0000-0000-0000-00000000a002', (select id from public.churches where slug='gravatai'), 'edit');
  raise exception 'FALHOU: pastora concedeu acesso a si mesma';
exception when others then
  if sqlerrm like 'FALHOU:%' then raise; end if;
  raise notice 'OK: escrita direta em church_access bloqueada (%)', sqlerrm;
end $$;

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
