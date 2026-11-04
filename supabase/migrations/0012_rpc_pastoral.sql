-- 0012_rpc_pastoral.sql
-- RPCs autenticados. Os privilegiados são SECURITY DEFINER (autorizam + auditam).
-- Os de matching são SECURITY INVOKER: a RLS das tabelas-base já escopa por igreja.

-- ---- RF04: igrejas acessíveis pelo usuário logado (tenant switcher) ----
create or replace function public.my_churches()
returns table (id uuid, name text, city text, slug text, level text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, c.city, c.slug, public.user_church_level(c.id) as level
    from public.churches c
   where public.current_is_master() or public.user_church_level(c.id) is not null
   order by c.name;
$$;

-- ---- RF12: lista mínima de TODAS as igrejas do presbitério (nome/cidade/slug) ----
-- Necessária para o pastor escolher a igreja de DESTINO de uma transferência, mesmo
-- sem ter acesso a ela. Não expõe dados de membros — só a identificação pública da igreja.
create or replace function public.list_all_churches()
returns table (id uuid, name text, city text, slug text)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.name, c.city, c.slug from public.churches c order by c.name;
$$;

-- ---- RF02: Admin Master cadastra uma nova igreja ----
create or replace function public.create_church(p_name text, p_slug text, p_city text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   uuid;
  v_slug text;
begin
  if not public.current_is_master() then
    raise exception 'Apenas o Admin Master pode criar igrejas';
  end if;
  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'Nome da igreja é obrigatório';
  end if;
  -- normaliza o slug: minúsculas, kebab-case
  v_slug := lower(regexp_replace(trim(coalesce(p_slug, '')), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  if v_slug = '' then
    raise exception 'Slug inválido';
  end if;

  insert into public.churches (name, slug, city)
  values (trim(p_name), v_slug, nullif(trim(p_city), ''))
  returning id into v_id;

  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'create_church', 'church', v_id, v_id, jsonb_build_object('slug', v_slug));

  return v_id;
end;
$$;

-- ---- RF03: Admin Master concede/revoga acesso cruzado ----
create or replace function public.grant_access(p_user uuid, p_church uuid, p_level text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.current_is_master() then
    raise exception 'Apenas o Admin Master pode conceder acesso';
  end if;
  if p_level not in ('read', 'edit') then
    raise exception 'Nível inválido (use read ou edit)';
  end if;
  if not exists (select 1 from public.churches where id = p_church) then
    raise exception 'Igreja inválida';
  end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'Usuário inválido';
  end if;

  insert into public.church_access (user_id, church_id, level, granted_by)
  values (p_user, p_church, p_level, auth.uid())
  on conflict (user_id, church_id)
    do update set level = excluded.level, granted_by = auth.uid();

  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'grant_access', 'church_access', p_church, p_church,
          jsonb_build_object('user_id', p_user, 'level', p_level));
end;
$$;

create or replace function public.revoke_access(p_user uuid, p_church uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.current_is_master() then
    raise exception 'Apenas o Admin Master pode revogar acesso';
  end if;
  delete from public.church_access where user_id = p_user and church_id = p_church;
  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'revoke_access', 'church_access', p_church, p_church,
          jsonb_build_object('user_id', p_user));
end;
$$;

-- ---- RF12: solicitar transferência (exige edit na igreja de origem) ----
create or replace function public.request_transfer(p_member uuid, p_to_church uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from uuid;
  v_id   uuid;
begin
  select m.church_id into v_from from public.members m where m.id = p_member;
  -- erro único (não revela se o membro existe em outra igreja a quem não tem permissão)
  if v_from is null or not public.has_church_edit(v_from) then
    raise exception 'Membro não encontrado ou sem permissão';
  end if;
  if v_from = p_to_church then
    raise exception 'A igreja de destino deve ser diferente da origem';
  end if;
  if not exists (select 1 from public.churches where id = p_to_church) then
    raise exception 'Igreja de destino inválida';
  end if;

  insert into public.transfer_requests (member_id, from_church_id, to_church_id, status, requested_by)
  values (p_member, v_from, p_to_church, 'pending', auth.uid())
  returning id into v_id;

  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'request_transfer', 'transfer_request', v_id, v_from,
          jsonb_build_object('member', p_member, 'to', p_to_church));
  return v_id;
end;
$$;

-- ---- RF12: aceitar transferência (exige edit no destino; transição de estado atômica) ----
-- Migra o membro E seu histórico (submissões, notas, visitas) para a igreja de destino,
-- registra em member_church_history e desativa alocações antigas de ministério.
create or replace function public.accept_transfer(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.transfer_requests;
begin
  select * into r from public.transfer_requests where id = p_request for update;
  if r.id is null then
    raise exception 'Solicitação não encontrada';
  end if;
  if not public.has_church_edit(r.to_church_id) then
    raise exception 'Sem permissão na igreja de destino';
  end if;

  -- transição atômica: só resolve se ainda estava pendente (mata corrida / duplo-aceite)
  update public.transfer_requests
     set status = 'accepted', resolved_by = auth.uid(), resolved_at = now()
   where id = p_request and status = 'pending';
  if not found then
    raise exception 'Solicitação já resolvida';
  end if;

  -- migra o membro e o histórico vinculado
  update public.members
     set church_id = r.to_church_id, status = 'ativo'
   where id = r.member_id;
  update public.gift_submissions set church_id = r.to_church_id where member_id = r.member_id;
  update public.pastoral_notes    set church_id = r.to_church_id where member_id = r.member_id;
  update public.pastoral_visits   set church_id = r.to_church_id where member_id = r.member_id;
  update public.ministry_assignments
     set active = false, church_id = r.to_church_id
   where member_id = r.member_id;

  insert into public.member_church_history (member_id, from_church_id, to_church_id, reason, moved_by)
  values (r.member_id, r.from_church_id, r.to_church_id, 'transfer', auth.uid());

  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'accept_transfer', 'transfer_request', p_request, r.to_church_id,
          jsonb_build_object('member', r.member_id, 'from', r.from_church_id));
end;
$$;

-- ---- RF12: rejeitar transferência (exige edit no destino) ----
create or replace function public.reject_transfer(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.transfer_requests;
begin
  select * into r from public.transfer_requests where id = p_request for update;
  if r.id is null then
    raise exception 'Solicitação não encontrada';
  end if;
  if not public.has_church_edit(r.to_church_id) then
    raise exception 'Sem permissão na igreja de destino';
  end if;
  update public.transfer_requests
     set status = 'rejected', resolved_by = auth.uid(), resolved_at = now()
   where id = p_request and status = 'pending';
  if not found then
    raise exception 'Solicitação já resolvida';
  end if;
  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'reject_transfer', 'transfer_request', p_request, r.to_church_id,
          jsonb_build_object('member', r.member_id));
end;
$$;

-- ---- RF13: arquivar/desligar membro (preserva a linha p/ estatística do Conselho) ----
create or replace function public.archive_member(p_member uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_church uuid;
begin
  select m.church_id into v_church from public.members m where m.id = p_member;
  if v_church is null or not public.has_church_edit(v_church) then
    raise exception 'Membro não encontrado ou sem permissão';
  end if;

  update public.members
     set archived = true,
         archived_reason = nullif(trim(coalesce(p_reason, '')), ''),
         archived_at = now()
   where id = p_member;
  -- sai da escala de ministérios
  update public.ministry_assignments set active = false where member_id = p_member;

  insert into public.audit_log (actor_id, action, entity_type, entity_id, church_id, detail)
  values (auth.uid(), 'archive_member', 'member', p_member, v_church,
          jsonb_build_object('reason', p_reason));
end;
$$;

-- ---- RF14: matching — sugerir membros para um ministério ----
-- SECURITY INVOKER: active_member_gift_scores (view security_invoker) já aplica a RLS do
-- chamador, então só retorna dados das igrejas a que ele tem acesso. Só membros ativos.
create or replace function public.suggest_members_for_ministry(p_ministry uuid)
returns table (member_id uuid, full_name text, match_score numeric)
language sql
stable
set search_path = ''
as $$
  select s.member_id, m.full_name, sum(s.score * n.weight)::numeric as match_score
    from public.ministry_gift_needs n
    join public.ministries mi               on mi.id = n.ministry_id
    join public.active_member_gift_scores s  on s.gift_id = n.gift_id and s.church_id = mi.church_id
    join public.members m                    on m.id = s.member_id
   where n.ministry_id = p_ministry
   group by s.member_id, m.full_name
   order by sum(s.score * n.weight) desc;
$$;

-- ---- RF14: matching — sugerir ministérios para um membro ----
create or replace function public.suggest_ministries_for_member(p_member uuid)
returns table (ministry_id uuid, ministry_name text, match_score numeric)
language sql
stable
set search_path = ''
as $$
  select mi.id, mi.name, sum(s.score * n.weight)::numeric as match_score
    from public.active_member_gift_scores s
    join public.ministries mi          on mi.church_id = s.church_id and mi.active
    join public.ministry_gift_needs n   on n.ministry_id = mi.id and n.gift_id = s.gift_id
   where s.member_id = p_member
   group by mi.id, mi.name
   order by sum(s.score * n.weight) desc;
$$;
