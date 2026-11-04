-- 0011_rpc_public.sql
-- RPCs chamáveis por anon (sem login). Todos SECURITY DEFINER + search_path=''.
-- Nunca confiam em church_id/member_id vindos do cliente: derivam do slug/token.

-- ---- RF05: dados mínimos da igreja a partir do slug (link público) ----
create or replace function public.get_church_by_slug(p_slug text)
returns table (id uuid, name text, city text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, c.city
    from public.churches c
   where c.slug = lower(trim(p_slug));
$$;

-- ---- RF06: cadastro público de membro/visitante ----
-- Valida consentimento (LGPD), nome, vínculo, existência da igreja e rate-limit.
-- Devolve o id do membro + um token de uso único p/ o teste de dons (o member_id nunca
-- vira uma "capacidade de escrita" solta: o teste exige o token, não o id).
create or replace function public.register_member(
  p_slug    text,
  p_name    text,
  p_email   text,
  p_phone   text,
  p_bond    text,
  p_consent boolean
)
returns table (member_id uuid, submit_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_church uuid;
  v_token  text;
  v_recent int;
begin
  if coalesce(p_consent, false) is not true then
    raise exception 'É necessário aceitar o uso dos dados para enviar';
  end if;
  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'Nome é obrigatório';
  end if;
  if char_length(trim(p_name)) > 200 then
    raise exception 'Nome muito longo';
  end if;
  if p_bond is null or p_bond not in ('comungante', 'nao_comungante', 'visitante') then
    raise exception 'Vínculo inválido';
  end if;

  select c.id into v_church from public.churches c where c.slug = lower(trim(p_slug));
  if v_church is null then
    raise exception 'Igreja não encontrada';
  end if;

  -- rate-limit: no máximo 30 cadastros por igreja por hora
  select count(*) into v_recent
    from public.registration_log r
   where r.church_id = v_church and r.created_at > now() - interval '1 hour';
  if v_recent >= 30 then
    raise exception 'Muitos cadastros recentes. Tente novamente mais tarde.';
  end if;

  v_token := encode(extensions.gen_random_bytes(18), 'hex');

  insert into public.members (church_id, full_name, email, phone, bond, consent, consent_at, submit_token_hash)
  values (
    v_church,
    trim(p_name),
    nullif(trim(p_email), ''),
    nullif(trim(p_phone), ''),
    p_bond,
    true,
    now(),
    encode(extensions.digest(v_token, 'sha256'), 'hex')
  )
  returning id into member_id;

  insert into public.registration_log (church_id) values (v_church);

  submit_token := v_token;
  return next;
end;
$$;

-- ---- RF07/RF08: perguntas ativas (sem login) ----
-- Devolve só id/text/sort_order — nunca gift_id/weight (não revela a chave de pontuação).
create or replace function public.get_gift_questions()
returns table (id uuid, text text, sort_order int)
language sql
stable
security definer
set search_path = ''
as $$
  select q.id, q.text, q.sort_order
    from public.gift_questions q
   where q.is_active
   order by q.sort_order, q.id;
$$;

-- ---- RF07: envio do teste de dons ----
-- p_answers: jsonb array de { "question_id": uuid, "value": 1..5 }.
-- Resolve o membro pelo token (uso único), deriva a igreja do próprio membro,
-- exige que TODAS as perguntas ativas sejam respondidas (sem repetição, notas 1..5).
create or replace function public.submit_gift_test(p_token text, p_answers jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member       uuid;
  v_church       uuid;
  v_submission   uuid;
  v_active_count int;
  v_answer_count int;
begin
  if p_token is null or char_length(trim(p_token)) = 0 then
    raise exception 'Token inválido';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'array' then
    raise exception 'Formato de respostas inválido';
  end if;

  select m.id, m.church_id into v_member, v_church
    from public.members m
   where m.submit_token_hash = encode(extensions.digest(trim(p_token), 'sha256'), 'hex')
     and m.submit_token_used = false;
  if v_member is null then
    raise exception 'Token inválido ou já utilizado';
  end if;

  select count(*) into v_active_count from public.gift_questions q where q.is_active;
  if v_active_count = 0 then
    raise exception 'Nenhuma pergunta disponível no momento';
  end if;

  -- quantidade de respostas enviadas
  select count(*) into v_answer_count
    from jsonb_array_elements(p_answers) e;
  if v_answer_count <> v_active_count then
    raise exception 'Responda todas as perguntas com notas de 1 a 5';
  end if;

  -- toda resposta precisa apontar p/ pergunta ATIVA existente, com nota 1..5
  if exists (
    select 1
      from jsonb_array_elements(p_answers) e
      left join public.gift_questions q
             on q.id = (e->>'question_id')::uuid and q.is_active
     where q.id is null
        or (e->>'value')::int < 1
        or (e->>'value')::int > 5
  ) then
    raise exception 'Responda todas as perguntas com notas de 1 a 5';
  end if;

  -- sem perguntas repetidas (com a contagem exata acima, garante bijeção com as ativas)
  if exists (
    select (e->>'question_id')::uuid
      from jsonb_array_elements(p_answers) e
     group by (e->>'question_id')::uuid
    having count(*) > 1
  ) then
    raise exception 'Responda todas as perguntas com notas de 1 a 5';
  end if;

  insert into public.gift_submissions (member_id, church_id)
  values (v_member, v_church)
  returning id into v_submission;

  insert into public.gift_answers (submission_id, question_id, value)
  select v_submission, (e->>'question_id')::uuid, (e->>'value')::int
    from jsonb_array_elements(p_answers) e;

  update public.members set submit_token_used = true where id = v_member;

  return v_submission;
end;
$$;
