-- seed.sql
-- Dados iniciais aplicados por `supabase db reset`. Roda como superusuário (sem RLS).
-- Contém: os 16 dons oficiais IPB, duas igrejas de demonstração, perguntas MOCK (RF08)
-- e ministérios de exemplo com seus dons requeridos.
--
-- NÃO cria usuários do Auth aqui (isso é feito pelo Supabase Auth). Veja supabase/README.md
-- para promover o primeiro Admin Master.

-- ======================= 16 Dons Oficiais IPB (RF07) =======================
-- O documento cita "17 dons" mas lista 16 nomes; semeamos os 16 e a tabela segue extensível.
insert into public.gifts (code, name, description, sort_order) values
  ('profecia',             'Profecia',             'Proclamar a verdade de Deus com convicção.',            1),
  ('ensino',               'Ensino',               'Explicar e aplicar as Escrituras com clareza.',         2),
  ('administracao',        'Administração',        'Organizar pessoas e recursos para um fim comum.',       3),
  ('lideranca',            'Liderança',            'Guiar e inspirar pessoas rumo a objetivos.',            4),
  ('pastor',               'Pastor',               'Cuidar, nutrir e acompanhar pessoas espiritualmente.',  5),
  ('evangelismo',          'Evangelismo',          'Comunicar o evangelho a quem ainda não o conhece.',     6),
  ('encorajamento',        'Encorajamento',        'Consolar, exortar e fortalecer os irmãos.',             7),
  ('misericordia',         'Misericórdia',         'Compaixão ativa para com os que sofrem.',               8),
  ('hospitalidade',        'Hospitalidade',        'Acolher pessoas com generosidade e cuidado.',           9),
  ('contribuir',           'Contribuir',           'Partilhar recursos com alegria e liberalidade.',       10),
  ('discernimento',        'Discernimento',        'Distinguir a verdade do erro com sabedoria.',          11),
  ('fe',                   'Fé',                   'Confiança firme na ação e nas promessas de Deus.',     12),
  ('intercessao',          'Intercessão',          'Perseverar em oração pelos outros.',                   13),
  ('auxilio',              'Auxílio',              'Servir nas tarefas práticas que sustentam a igreja.',  14),
  ('comunicacao_criativa', 'Comunicação Criativa', 'Comunicar a verdade por meios artísticos e criativos.',15),
  ('artesanato',           'Artesanato',           'Trabalhar com habilidade manual a serviço do Reino.',  16);

-- ======================= Igrejas de demonstração =======================
insert into public.churches (name, slug, city) values
  ('IPB Sapucaia do Sul', 'sapucaia', 'Sapucaia do Sul'),
  ('IPB Gravataí',        'gravatai', 'Gravataí');

-- ======================= Perguntas MOCK (RF08) =======================
-- Duas afirmações por dom (32 perguntas). Estrutura flexível até o questionário definitivo.
insert into public.gift_questions (text, gift_id, weight, sort_order)
select 'Sinto afinidade e satisfação ao exercer o dom de ' || g.name || '.',
       g.id, 1, g.sort_order * 10 + 1
  from public.gifts g;

insert into public.gift_questions (text, gift_id, weight, sort_order)
select 'Pessoas ao meu redor reconhecem em mim o dom de ' || g.name || '.',
       g.id, 1, g.sort_order * 10 + 2
  from public.gifts g;

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

-- Dons requeridos por ministério (pesos) — base do matching.
-- Louvor
insert into public.ministry_gift_needs (ministry_id, gift_id, weight)
select mi.id, g.id, w.weight
  from public.ministries mi
  join public.churches c on c.id = mi.church_id and c.slug = 'sapucaia'
  join (values ('comunicacao_criativa', 3), ('lideranca', 2), ('artesanato', 1)) as w(code, weight) on true
  join public.gifts g on g.code = w.code
 where mi.name = 'Louvor';

-- Diaconia
insert into public.ministry_gift_needs (ministry_id, gift_id, weight)
select mi.id, g.id, w.weight
  from public.ministries mi
  join public.churches c on c.id = mi.church_id and c.slug = 'sapucaia'
  join (values ('misericordia', 3), ('hospitalidade', 2), ('auxilio', 2), ('contribuir', 1)) as w(code, weight) on true
  join public.gifts g on g.code = w.code
 where mi.name = 'Diaconia';

-- EBD
insert into public.ministry_gift_needs (ministry_id, gift_id, weight)
select mi.id, g.id, w.weight
  from public.ministries mi
  join public.churches c on c.id = mi.church_id and c.slug = 'sapucaia'
  join (values ('ensino', 3), ('lideranca', 1), ('encorajamento', 1)) as w(code, weight) on true
  join public.gifts g on g.code = w.code
 where mi.name = 'EBD';
