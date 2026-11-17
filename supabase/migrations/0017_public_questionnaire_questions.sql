-- 0017_public_questionnaire_questions.sql
-- Expõe somente as perguntas ativas necessárias ao formulário público.
-- O anon continua sem acesso direto às tabelas; a leitura passa por RPC.
create or replace function public.get_questionnaire_questions()
returns table (
  id uuid,
  text text,
  gift_id uuid,
  gift_name text,
  sort_order int
)
language sql
stable
security definer
set search_path = ''
as $$
  select q.id, q.text, q.gift_id, g.name, q.sort_order
    from public.gift_questions q
    join public.gifts g on g.id = q.gift_id
   where q.is_active
   order by q.sort_order;
$$;

grant execute on function public.get_questionnaire_questions() to anon, authenticated;
