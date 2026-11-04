-- 0016_public_flow_rework.sql
-- Fluxo público novo: UM link + seletor de campus + envio combinado
-- (o cadastro do membro nasce junto com o envio das respostas, numa submissão só).

-- Remove os RPCs do fluxo antigo (slug + token de 2 passos).
drop function if exists public.get_church_by_slug(text);
drop function if exists public.register_member(text, text, text, text, text, boolean);
drop function if exists public.submit_gift_test(text, jsonb);

-- Lista de campi (igrejas) para o seletor do formulário público.
create or replace function public.list_campuses()
returns table (id uuid, name text, city text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, c.city from public.churches c order by c.name;
$$;

-- Envio combinado: valida tudo no servidor e cria membro + submissão + respostas atomicamente.
-- p_answers: jsonb array de { "question_id": uuid, "value": 0..3 }, uma por pergunta ativa (133).
create or replace function public.submit_questionnaire(
  p_church_id uuid,
  p_name      text,
  p_email     text,
  p_phone     text,
  p_bond      text,
  p_consent   boolean,
  p_answers   jsonb
)
returns table (member_id uuid, submission_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member       uuid;
  v_submission   uuid;
  v_active_count int;
  v_answer_count int;
  v_recent       int;
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
  if not exists (select 1 from public.churches c where c.id = p_church_id) then
    raise exception 'Campus inválido';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'array' then
    raise exception 'Formato de respostas inválido';
  end if;

  -- rate-limit por campus
  select count(*) into v_recent
    from public.registration_log r
   where r.church_id = p_church_id and r.created_at > now() - interval '1 hour';
  if v_recent >= 60 then
    raise exception 'Muitos cadastros recentes. Tente novamente mais tarde.';
  end if;

  select count(*) into v_active_count from public.gift_questions q where q.is_active;
  if v_active_count = 0 then
    raise exception 'Nenhuma pergunta disponível no momento';
  end if;

  select count(*) into v_answer_count from jsonb_array_elements(p_answers) e;
  if v_answer_count <> v_active_count then
    raise exception 'Responda todas as perguntas com notas de 0 a 3';
  end if;

  -- toda resposta aponta p/ pergunta ATIVA existente, com nota 0..3
  if exists (
    select 1
      from jsonb_array_elements(p_answers) e
      left join public.gift_questions q
             on q.id = (e->>'question_id')::uuid and q.is_active
     where q.id is null
        or (e->>'value')::int < 0
        or (e->>'value')::int > 3
  ) then
    raise exception 'Responda todas as perguntas com notas de 0 a 3';
  end if;

  -- sem perguntas repetidas (com a contagem exata, garante bijeção com as ativas)
  if exists (
    select (e->>'question_id')::uuid
      from jsonb_array_elements(p_answers) e
     group by (e->>'question_id')::uuid
    having count(*) > 1
  ) then
    raise exception 'Responda todas as perguntas com notas de 0 a 3';
  end if;

  -- cria o membro (dedup amigável por e-mail dentro do campus)
  begin
    insert into public.members (church_id, full_name, email, phone, bond, consent, consent_at)
    values (p_church_id, trim(p_name), nullif(trim(p_email), ''), nullif(trim(p_phone), ''),
            p_bond, true, now())
    returning id into v_member;
  exception when unique_violation then
    raise exception 'Já existe um cadastro com este e-mail neste campus';
  end;

  insert into public.registration_log (church_id) values (p_church_id);

  insert into public.gift_submissions (member_id, church_id)
  values (v_member, p_church_id)
  returning id into v_submission;

  insert into public.gift_answers (submission_id, question_id, value)
  select v_submission, (e->>'question_id')::uuid, (e->>'value')::int
    from jsonb_array_elements(p_answers) e;

  member_id := v_member;
  submission_id := v_submission;
  return next;
end;
$$;

-- Grants dos novos RPCs públicos + do perfil (autenticado). Os RPCs removidos acima perdem
-- seus grants automaticamente ao serem dropados.
grant execute on function public.list_campuses() to anon, authenticated;
grant execute on function public.submit_questionnaire(uuid, text, text, text, text, boolean, jsonb) to anon;
grant execute on function public.get_member_gift_profile(uuid) to authenticated;
