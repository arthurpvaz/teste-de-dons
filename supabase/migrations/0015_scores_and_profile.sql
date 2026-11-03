-- 0015_scores_and_profile.sql
-- Pontuação por SOMA simples (0..3) da última submissão + RPC de perfil para o gráfico.

-- Score por membro/dom = soma das respostas da coluna (antes era soma(valor*peso)).
create or replace view public.member_gift_scores
with (security_invoker = true) as
with latest as (
  select distinct on (gs.member_id) gs.id as submission_id, gs.member_id, gs.church_id
    from public.gift_submissions gs
   order by gs.member_id, gs.created_at desc
)
select l.member_id,
       l.church_id,
       q.gift_id,
       sum(a.value)::numeric as score
  from latest l
  join public.gift_answers a   on a.submission_id = l.submission_id
  join public.gift_questions q on q.id = a.question_id
 group by l.member_id, l.church_id, q.gift_id;

create or replace view public.active_member_gift_scores
with (security_invoker = true) as
select s.member_id, s.church_id, s.gift_id, s.score
  from public.member_gift_scores s
  join public.members m on m.id = s.member_id
 where m.status = 'ativo' and m.archived = false;

-- Perfil de dons do membro (soma por dom, 0..21) — pronto para o gráfico do pastor.
-- SECURITY INVOKER: a RLS das tabelas-base escopa por igreja. Retorna todos os 19 dons
-- (0 onde não houver pontuação), ordenados pela coluna da matriz.
create or replace function public.get_member_gift_profile(p_member uuid)
returns table (gift_code text, gift_name text, score numeric, sort_order int)
language sql
stable
set search_path = ''
as $$
  select g.code, g.name, coalesce(s.score, 0)::numeric, g.sort_order
    from public.gifts g
    left join public.member_gift_scores s
           on s.gift_id = g.id and s.member_id = p_member
   order by g.sort_order;
$$;
