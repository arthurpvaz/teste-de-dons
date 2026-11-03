-- seed.sql
-- Dados de DEMONSTRAÇÃO aplicados por `supabase db reset` (roda como superusuário, sem RLS).
--
-- Observação: os 19 dons e as 133 perguntas são DADOS DE REFERÊNCIA e vivem na migration
-- 0014_gift_test_rework.sql (aplicados por `db push`/`db reset` em qualquer ambiente).
-- Aqui ficam só as igrejas demo e ministérios de exemplo.
--
-- NÃO cria usuários do Auth. Veja supabase/README.md para promover o primeiro Admin Master.

-- ======================= Igrejas (campi) de demonstração =======================
insert into public.churches (name, slug, city) values
  ('IPB Sapucaia do Sul', 'sapucaia', 'Sapucaia do Sul'),
  ('IPB Gravataí',        'gravatai', 'Gravataí');

-- ======================= Ministérios de exemplo (RF14) =======================
insert into public.ministries (church_id, name, description)
select c.id, m.name, m.descr
  from public.churches c
 cross join (values
   ('Louvor',   'Ministério de música e adoração'),
   ('Diaconia', 'Assistência e serviço prático à comunidade'),
   ('EBD',      'Escola Bíblica Dominical')
 ) as m(name, descr)
 where c.slug = 'sapucaia';

-- Dons requeridos por ministério (pesos) — base do matching. Referencia os dons PROVISÓRIOS
-- (dom_*); reconfigurar quando os 19 dons oficiais forem semeados.
insert into public.ministry_gift_needs (ministry_id, gift_id, weight)
select mi.id, g.id, w.weight
  from public.ministries mi
  join public.churches c on c.id = mi.church_id and c.slug = 'sapucaia'
  join (values ('dom_01', 3), ('dom_02', 2), ('dom_03', 1)) as w(code, weight) on true
  join public.gifts g on g.code = w.code
 where mi.name = 'Louvor';

insert into public.ministry_gift_needs (ministry_id, gift_id, weight)
select mi.id, g.id, w.weight
  from public.ministries mi
  join public.churches c on c.id = mi.church_id and c.slug = 'sapucaia'
  join (values ('dom_04', 3), ('dom_05', 2), ('dom_06', 2), ('dom_07', 1)) as w(code, weight) on true
  join public.gifts g on g.code = w.code
 where mi.name = 'Diaconia';

insert into public.ministry_gift_needs (ministry_id, gift_id, weight)
select mi.id, g.id, w.weight
  from public.ministries mi
  join public.churches c on c.id = mi.church_id and c.slug = 'sapucaia'
  join (values ('dom_02', 3), ('dom_08', 1), ('dom_09', 1)) as w(code, weight) on true
  join public.gifts g on g.code = w.code
 where mi.name = 'EBD';
