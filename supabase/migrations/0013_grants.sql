-- 0013_grants.sql
-- Endurecimento de privilégios (defesa em profundidade atrás da RLS).
-- anon não tem acesso direto a tabela nenhuma: só EXECUTE nos 4 RPCs públicos.

grant usage on schema public to anon, authenticated;

-- authenticated: CRUD nas tabelas/views (a RLS restringe as linhas). Padrão do Supabase.
grant select, insert, update, delete on all tables in schema public to authenticated;

-- anon: zero acesso a tabelas/views.
revoke all on all tables in schema public from anon;

-- Nenhuma função exposta por padrão; liberamos caso a caso.
revoke all on all routines in schema public from anon, authenticated;

-- RPCs públicos (anon + authenticated)
grant execute on function public.get_church_by_slug(text)                     to anon, authenticated;
grant execute on function public.get_gift_questions()                         to anon, authenticated;
grant execute on function public.register_member(text,text,text,text,text,boolean) to anon;
grant execute on function public.submit_gift_test(text, jsonb)                to anon;

-- Funções auxiliares de RLS (precisam de EXECUTE p/ avaliar as policies)
grant execute on function public.current_is_master()         to anon, authenticated;
grant execute on function public.user_church_level(uuid)     to anon, authenticated;
grant execute on function public.has_church_read(uuid)       to anon, authenticated;
grant execute on function public.has_church_edit(uuid)       to anon, authenticated;

-- RPCs autenticados
grant execute on function public.my_churches()                            to authenticated;
grant execute on function public.list_all_churches()                      to authenticated;
grant execute on function public.create_church(text,text,text)            to authenticated;
grant execute on function public.grant_access(uuid,uuid,text)             to authenticated;
grant execute on function public.revoke_access(uuid,uuid)                 to authenticated;
grant execute on function public.request_transfer(uuid,uuid)              to authenticated;
grant execute on function public.accept_transfer(uuid)                    to authenticated;
grant execute on function public.reject_transfer(uuid)                    to authenticated;
grant execute on function public.archive_member(uuid,text)                to authenticated;
grant execute on function public.suggest_members_for_ministry(uuid)       to authenticated;
grant execute on function public.suggest_ministries_for_member(uuid)      to authenticated;
