-- 0010_rls_policies.sql
-- Row Level Security em todas as tabelas. Sem policy explícita = sem acesso.
-- Padrão: SELECT exige has_church_read(church_id); INSERT/UPDATE/DELETE exige has_church_edit.
-- Tabelas sem church_id usam EXISTS/join na tabela-pai.
-- As funções auxiliares são SECURITY DEFINER (não recursivas) — ver 0002/0003.

alter table public.churches              enable row level security;
alter table public.profiles              enable row level security;
alter table public.church_access         enable row level security;
alter table public.members               enable row level security;
alter table public.registration_log      enable row level security;
alter table public.gifts                 enable row level security;
alter table public.gift_questions        enable row level security;
alter table public.gift_submissions      enable row level security;
alter table public.gift_answers          enable row level security;
alter table public.ministries            enable row level security;
alter table public.ministry_gift_needs   enable row level security;
alter table public.ministry_assignments  enable row level security;
alter table public.pastoral_notes        enable row level security;
alter table public.pastoral_visits       enable row level security;
alter table public.transfer_requests     enable row level security;
alter table public.member_church_history enable row level security;
alter table public.audit_log             enable row level security;

-- ========================= churches (RF02) =========================
-- leitura: qualquer igreja a que o usuário tenha acesso. escrita: só master.
create policy churches_select on public.churches
  for select to authenticated using (public.has_church_read(id));
create policy churches_master_all on public.churches
  for all to authenticated
  using (public.current_is_master()) with check (public.current_is_master());

-- ========================= profiles (RF01) =========================
-- cada um lê/edita a própria linha; master lê/edita todas. (colunas privilegiadas travadas em 0002)
create policy profiles_select on public.profiles
  for select to authenticated using (id = auth.uid() or public.current_is_master());
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.current_is_master())
  with check (id = auth.uid() or public.current_is_master());

-- ========================= church_access (RF03/RF04) =========================
-- usuário lê os próprios grants (p/ o tenant switcher). só master escreve.
create policy church_access_select on public.church_access
  for select to authenticated using (user_id = auth.uid() or public.current_is_master());
create policy church_access_master_all on public.church_access
  for all to authenticated
  using (public.current_is_master()) with check (public.current_is_master());

-- ========================= members (RF06/RF09/RF13) =========================
create policy members_select on public.members
  for select to authenticated using (public.has_church_read(church_id));
create policy members_insert on public.members
  for insert to authenticated with check (public.has_church_edit(church_id));
create policy members_update on public.members
  for update to authenticated
  using (public.has_church_edit(church_id)) with check (public.has_church_edit(church_id));
create policy members_delete on public.members
  for delete to authenticated using (public.has_church_edit(church_id));

-- registration_log: sem policy (só os RPCs DEFINER escrevem/leem). RLS ligado = bloqueado p/ roles.

-- ========================= gifts / gift_questions (RF07/RF08) =========================
-- referência compartilhada: leitura p/ qualquer autenticado; escrita só master.
create policy gifts_select on public.gifts
  for select to authenticated using (true);
create policy gifts_master_all on public.gifts
  for all to authenticated
  using (public.current_is_master()) with check (public.current_is_master());

create policy gift_questions_select on public.gift_questions
  for select to authenticated using (true);
create policy gift_questions_master_all on public.gift_questions
  for all to authenticated
  using (public.current_is_master()) with check (public.current_is_master());

-- ========================= gift_submissions / gift_answers (RF07) =========================
create policy gift_submissions_select on public.gift_submissions
  for select to authenticated using (public.has_church_read(church_id));
create policy gift_submissions_edit_all on public.gift_submissions
  for all to authenticated
  using (public.has_church_edit(church_id))
  with check (
    public.has_church_edit(church_id)
    and exists (select 1 from public.members m
                 where m.id = member_id and m.church_id = gift_submissions.church_id));

-- gift_answers não tem church_id: acesso via submissão.
create policy gift_answers_select on public.gift_answers
  for select to authenticated using (exists (
    select 1 from public.gift_submissions s
     where s.id = submission_id and public.has_church_read(s.church_id)));
create policy gift_answers_edit_all on public.gift_answers
  for all to authenticated
  using (exists (
    select 1 from public.gift_submissions s
     where s.id = submission_id and public.has_church_edit(s.church_id)))
  with check (exists (
    select 1 from public.gift_submissions s
     where s.id = submission_id and public.has_church_edit(s.church_id)));

-- ========================= ministries / needs / assignments (RF10/RF14) =========================
create policy ministries_select on public.ministries
  for select to authenticated using (public.has_church_read(church_id));
create policy ministries_edit_all on public.ministries
  for all to authenticated
  using (public.has_church_edit(church_id)) with check (public.has_church_edit(church_id));

create policy ministry_gift_needs_select on public.ministry_gift_needs
  for select to authenticated using (exists (
    select 1 from public.ministries mi
     where mi.id = ministry_id and public.has_church_read(mi.church_id)));
create policy ministry_gift_needs_edit_all on public.ministry_gift_needs
  for all to authenticated
  using (exists (
    select 1 from public.ministries mi
     where mi.id = ministry_id and public.has_church_edit(mi.church_id)))
  with check (exists (
    select 1 from public.ministries mi
     where mi.id = ministry_id and public.has_church_edit(mi.church_id)));

create policy ministry_assignments_select on public.ministry_assignments
  for select to authenticated using (public.has_church_read(church_id));
create policy ministry_assignments_edit_all on public.ministry_assignments
  for all to authenticated
  using (public.has_church_edit(church_id))
  with check (
    public.has_church_edit(church_id)
    and exists (select 1 from public.members m
                 where m.id = member_id and m.church_id = ministry_assignments.church_id));

-- ========================= pastoral_notes / pastoral_visits (RF11) =========================
-- CONFIDENCIAL: exige has_church_edit (pastor local + master). Observador cross-church
-- com grant só-leitura NÃO vê. Uma única policy FOR ALL cobre leitura e escrita.
create policy pastoral_notes_edit_all on public.pastoral_notes
  for all to authenticated
  using (public.has_church_edit(church_id)) with check (public.has_church_edit(church_id));
create policy pastoral_visits_edit_all on public.pastoral_visits
  for all to authenticated
  using (public.has_church_edit(church_id)) with check (public.has_church_edit(church_id));

-- ========================= transfer_requests (RF12) =========================
-- visível a quem tem leitura na origem OU no destino. Criação exige edit na origem.
-- accept/reject acontecem via RPC DEFINER (sem policy de UPDATE: impede bypass da autorização).
create policy transfer_requests_select on public.transfer_requests
  for select to authenticated
  using (public.has_church_read(from_church_id) or public.has_church_read(to_church_id));
create policy transfer_requests_insert on public.transfer_requests
  for insert to authenticated with check (public.has_church_edit(from_church_id));

-- ========================= member_church_history =========================
create policy member_church_history_select on public.member_church_history
  for select to authenticated
  using (public.has_church_read(from_church_id) or public.has_church_read(to_church_id));

-- ========================= audit_log (RF02/RF03/RF13) =========================
create policy audit_log_select on public.audit_log
  for select to authenticated
  using (public.current_is_master() or (church_id is not null and public.has_church_edit(church_id)));
