-- 0006_scores_views.sql
-- Views de pontuação por membro/dom, usadas pelo matching (RF14).
-- security_invoker=true (PG15+): a view respeita a RLS das tabelas-base conforme o
-- usuário que consulta — sem isso, views vazariam dados de todas as igrejas.

-- Score por membro/dom considerando apenas a ÚLTIMA submissão de cada membro.
create view public.member_gift_scores
with (security_invoker = true) as
with latest as (
  select distinct on (gs.member_id)
         gs.id as submission_id, gs.member_id, gs.church_id
    from public.gift_submissions gs
   order by gs.member_id, gs.created_at desc
)
select l.member_id,
       l.church_id,
       q.gift_id,
       sum(a.value * q.weight)::numeric as score
  from latest l
  join public.gift_answers a   on a.submission_id = l.submission_id
  join public.gift_questions q on q.id = a.question_id
 group by l.member_id, l.church_id, q.gift_id;

comment on view public.member_gift_scores is 'Dons declarados por membro (última submissão). security_invoker respeita RLS.';

-- Apenas membros ATIVOS e não arquivados entram no matching (RF10: inativos saem da escala).
create view public.active_member_gift_scores
with (security_invoker = true) as
select s.member_id, s.church_id, s.gift_id, s.score
  from public.member_gift_scores s
  join public.members m on m.id = s.member_id
 where m.status = 'ativo' and m.archived = false;
