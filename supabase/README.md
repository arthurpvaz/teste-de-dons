# Backend — IPB "Conecta Dons"

Backend **100% Supabase** (Postgres + Row Level Security + funções RPC), versionado em migrations.
Não há servidor de API: o frontend fala direto com o Supabase via `@supabase/supabase-js`, e **todo o
isolamento entre igrejas e a segurança são impostos no banco (RLS)**.

Cobre os requisitos RF01–RF14 (autenticação pastoral, multi-tenant, matriz de permissões cruzadas,
cadastro público por igreja, teste de dons, gestão pastoral/resgate, histórico confidencial,
transferência interna, arquivamento e matching de ministérios).

## Como rodar localmente

Pré-requisitos: **Docker** rodando e **Node** (para `npx supabase`).

```bash
npx supabase start          # sobe Postgres + Auth + Studio locais
npx supabase db reset       # aplica todas as migrations + seed.sql
npx supabase status         # mostra URLs e chaves (API, anon key, DB URL)
```

Smoke tests (opcional, valida RLS e RPCs ponta a ponta):

```bash
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f supabase/tests/smoke.sql
```

Deploy para o projeto real:

```bash
npx supabase link --project-ref <ref-do-projeto>
npx supabase db push        # envia as migrations
# o seed NÃO é enviado pelo push; rode-o no SQL Editor se quiser dados de exemplo
```

## Estrutura

```
supabase/
  config.toml
  migrations/0001..0013_*.sql   # schema, RLS, RPCs, grants (ver cabeçalho de cada arquivo)
  seed.sql                      # 16 dons IPB, 2 igrejas demo, perguntas mock, ministérios
  tests/smoke.sql               # testes de fumaça
```

## Primeiro Admin Master (RF02)

O seed **não** cria usuários do Auth. Para bootstrapar o pastor master:

1. Crie o usuário em **Authentication → Users** (Studio) ou via `supabase.auth.signUp`. O trigger
   `handle_new_user` cria o `profiles` automaticamente (com `is_master = false`).
2. Promova-o rodando, como **service_role / postgres** (SQL Editor):

```sql
update public.profiles
   set is_master = true,
       home_church_id = (select id from public.churches where slug = 'sapucaia')
 where email = 'pastor.master@ipb.org';
```

> `is_master` e `home_church_id` **não** podem ser alterados por um pastor comum — só por um master
> já existente ou por conexão privilegiada (service_role/postgres). É a trava anti-escalonamento.

## Contrato para o frontend

Use **somente a chave pública (anon)** no frontend. Login via `supabase.auth.signInWithPassword`.

### Público (sem login) — `supabase.rpc(...)`

| RPC | Parâmetros | Retorno | RF |
|---|---|---|---|
| `get_church_by_slug` | `p_slug` | `{id, name, city}` | RF05 |
| `register_member` | `p_slug, p_name, p_email, p_phone, p_bond, p_consent` | `{member_id, submit_token}` | RF06 |
| `get_gift_questions` | — | `[{id, text, sort_order}]` | RF07/RF08 |
| `submit_gift_test` | `p_token, p_answers` | `submission_id (uuid)` | RF07 |

- `p_bond` ∈ `comungante | nao_comungante | visitante`. `p_consent` precisa ser `true` (LGPD).
- Guarde o `submit_token` devolvido pelo cadastro: ele é obrigatório (e de uso único) no envio do teste.
- `p_answers`: array `[{ "question_id": <uuid>, "value": 1..5 }]`, uma entrada por pergunta ativa.

```js
const { data: igreja } = await supabase.rpc('get_church_by_slug', { p_slug: 'sapucaia' })
const { data: reg } = await supabase.rpc('register_member', {
  p_slug: 'sapucaia', p_name: 'Maria', p_email: 'maria@x.com',
  p_phone: null, p_bond: 'comungante', p_consent: true
})
const { data: perguntas } = await supabase.rpc('get_gift_questions')
const p_answers = perguntas.map(q => ({ question_id: q.id, value: notas[q.id] }))
await supabase.rpc('submit_gift_test', { p_token: reg.submit_token, p_answers })
```

### Autenticado (pastor/admin)

Tabelas e views são acessíveis direto via PostgREST, **filtradas pela RLS** conforme as igrejas a que
o usuário tem acesso (leitura/edição). As ações sensíveis passam por RPC (autorizam + auditam):

| RPC | Papel | RF |
|---|---|---|
| `my_churches()` | igrejas acessíveis + nível (tenant switcher) | RF04 |
| `create_church(p_name, p_slug, p_city)` | criar igreja (só master) | RF02 |
| `grant_access(p_user, p_church, p_level)` / `revoke_access(p_user, p_church)` | permissões cruzadas (só master) | RF03 |
| `request_transfer(p_member, p_to_church)` / `accept_transfer(p_request)` / `reject_transfer(p_request)` | transferência interna | RF12 |
| `archive_member(p_member, p_reason)` | desligamento/arquivamento | RF13 |
| `suggest_members_for_ministry(p_ministry)` / `suggest_ministries_for_member(p_member)` | matching | RF14 |

Tabelas/views mais usadas pelo painel (via `supabase.from(...)`, já sob RLS):
- `members` — status pastoral (`ativo | em_alerta | inativo_desviado | transferido`), `archived` (RF09/RF10/RF13).
  Lista de resgate (RF10) = `members` com `status = 'inativo_desviado'`.
- `pastoral_notes` / `pastoral_visits` — **confidenciais** (só pastor com edição na igreja) (RF11).
- `ministries` / `ministry_gift_needs` / `ministry_assignments` — ministérios, dons requeridos e escala (RF14).
- `member_gift_scores` / `active_member_gift_scores` — perfil de dons por membro (base do matching).
- `church_access` — grants do próprio usuário (para montar o seletor de igrejas).

## Segurança (resumo)

- RLS em todas as tabelas; `anon` não acessa tabela nenhuma (só os 4 RPCs públicos).
- Funções auxiliares de permissão são `SECURITY DEFINER` (evitam recursão de policy) com `search_path` fixo.
- Cadastro/teste públicos validam tudo no servidor (consentimento, formato, rate-limit, notas 1–5,
  perguntas ativas) e derivam a igreja do slug/token — nunca de `church_id`/`member_id` do cliente.
- Ações privilegiadas gravam trilha em `audit_log`.
