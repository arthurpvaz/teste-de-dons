# IPB "Conecta Dons"

Plataforma **multi-igrejas** (presbitério) da IPB para **teste de dons**, **gestão pastoral** e
**alocação de ministérios**. Backend **100% Supabase** (Postgres + RLS + RPC) e frontend **React + Vite**
que fala direto com o Supabase. Cobre os requisitos RF01–RF14.

> Este é o guia principal: arquitetura, **como integrar o backend no frontend**, rodar localmente e
> **fazer deploy (Supabase + Vercel)**. Detalhes internos do banco estão em [supabase/README.md](supabase/README.md).

---

## Arquitetura

```
┌─────────────────────────┐        supabase-js         ┌──────────────────────────────┐
│  Frontend (React+Vite)  │ ─────────────────────────▶ │  Supabase (Postgres)         │
│  Vercel                 │   auth · rpc() · from()     │  • Auth (e-mail/senha)       │
│  - chave ANON pública   │ ◀───────────────────────── │  • RLS multi-tenant          │
└─────────────────────────┘      dados já filtrados     │  • RPCs (SECURITY DEFINER)   │
                                 pela RLS por igreja     └──────────────────────────────┘
```

- **Não existe servidor de API próprio.** O frontend usa a **chave anon pública** e toda a segurança /
  isolamento entre igrejas é imposta **no banco** via Row Level Security (RLS).
- Pastores/admins logam com **Supabase Auth**. Visitantes/membros se cadastram e fazem o teste de dons
  **sem login**, por um link público com o `slug` da igreja.

### Stack
- **Frontend:** React 19, Vite 8, react-router-dom 7, `@supabase/supabase-js` 2.
- **Backend:** Supabase CLI (migrations versionadas), Postgres 15 + RLS + plpgsql.

### Estrutura do repositório
```
supabase/              # backend (migrations, seed, testes) — ver supabase/README.md
  migrations/0001..0013_*.sql
  seed.sql
  tests/smoke.sql
frontend/              # app React + Vite (branch feature/frontend-core)
  src/services/supabase.js   # cliente supabase-js
  src/contexts/AuthContext.jsx
  src/routes/AppRoutes.jsx
  vercel.json          # (criar) rewrite SPA p/ react-router
readme.md              # este arquivo
```

---

## 1. Rodar o backend localmente

Pré-requisitos: **Docker** rodando e **Node**. O CLI do Supabase roda via `npx` (não precisa instalar global).

```bash
npx supabase start            # sobe Postgres + Auth + Studio locais
npx supabase db reset         # aplica migrations 0001..0013 + seed.sql
npx supabase status           # mostra URLs e chaves (API URL, anon key, DB URL)
```

Teste de fumaça (valida RLS e RPCs ponta a ponta — opcional):
```bash
docker exec -i supabase_db_conecta-dons \
  psql postgresql://postgres:postgres@127.0.0.1:5432/postgres -v ON_ERROR_STOP=1 \
  < supabase/tests/smoke.sql
```

Para parar o stack local: `npx supabase stop`.

---

## 2. Configurar o frontend

### 2.1. Variáveis de ambiente (`frontend/.env`)

> ⚠️ A `VITE_SUPABASE_URL` é a **URL base do projeto**, SEM `/rest/v1/` no final. O `supabase-js`
> monta os caminhos sozinho.
> A chave `sb_publishable_...` é **pública por design** (protegida pela RLS), por isso pode ficar aqui.
> **Nunca** coloque a `service_role` / `sb_secret_...` no frontend — ela ignora a RLS.

**Produção (projeto Supabase atual):**
```bash
VITE_SUPABASE_URL=https://tfyahgtkxbyshxapibdz.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_gsZkXPaBNRqUZmIdYEyziw_XRFi0vV9
```

**Desenvolvimento local** (valores de `npx supabase status`):
```bash
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_KEY=<anon/publishable key local>
```

> O **nome** da variável precisa ser exatamente o mesmo que o cliente lê em `src/services/supabase.js`
> (ver 2.2). Se preferir manter `VITE_SUPABASE_ANON_KEY`, use esse nome nos dois lugares — o importante
> é a consistência.

### 2.2. Cliente ([frontend/src/services/supabase.js](frontend/src/services/supabase.js))

```js
import { createClient } from '@supabase/supabase-js'

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
)
```

> O código atual do repo lê `VITE_SUPABASE_ANON_KEY`. Troque para `VITE_SUPABASE_PUBLISHABLE_KEY`
> (mesmo nome usado no `.env` em 2.1) para casar com a chave `sb_publishable_...` do projeto novo.

### 2.3. Rodar
```bash
cd frontend
npm install
npm run dev
```

---

## 3. Contrato de uso no frontend

Há dois estilos de chamada:
- **`supabase.rpc('fn', { ... })`** — funções (cadastro público, ações pastorais sensíveis).
- **`supabase.from('tabela').select()/insert()/update()`** — leitura/escrita direta, **já filtrada pela RLS**
  conforme as igrejas a que o usuário tem acesso.

Toda mensagem de erro de validação do backend vem em **português** em `error.message` — mostre-a ao usuário.

### 3.1. Autenticação (pastor/admin) — RF01

```js
// login
const { error } = await supabase.auth.signInWithPassword({ email, password })
// sessão atual / logout
const { data } = await supabase.auth.getSession()
await supabase.auth.signOut()
```
O [AuthContext](frontend/src/contexts/AuthContext.jsx) já expõe `user`, `session`, `login`, `logout`.

### 3.2. Perfil, Admin Master e seletor de igrejas — RF02/RF04

```js
// o usuário logado é master?
const { data: perfil } = await supabase
  .from('profiles').select('is_master, home_church_id').eq('id', user.id).single()

// igrejas às quais tenho acesso (alimenta o Tenant Switcher da sidebar)
const { data: igrejas } = await supabase.rpc('my_churches')
// -> [{ id, name, city, slug, level: 'read' | 'edit' }]
```
Guarde no estado a **igreja selecionada** (`churchId`) e filtre as consultas por `.eq('church_id', churchId)`.
A RLS garante que o usuário só recebe dados das igrejas permitidas; o filtro serve para exibir uma por vez.

### 3.3. Cadastro público + teste de dons (sem login) — RF05/RF06/RF07/RF08

Fluxo da página pública `/{slug}` (ex.: link/QR `https://app.exemplo.com/cadastro/sapucaia`):

```js
// 1) dados mínimos da igreja pelo slug da URL
const { data: igreja } = await supabase.rpc('get_church_by_slug', { p_slug: 'sapucaia' })

// 2) cadastro -> devolve { member_id, submit_token } (guarde o token!)
const { data: reg, error } = await supabase.rpc('register_member', {
  p_slug: 'sapucaia',
  p_name: 'Maria Silva',
  p_email: 'maria@email.com',   // ou null
  p_phone: null,
  p_bond: 'comungante',         // 'comungante' | 'nao_comungante' | 'visitante'
  p_consent: true               // precisa ser true (LGPD)
})
const { submit_token } = reg[0]

// 3) perguntas ativas
const { data: perguntas } = await supabase.rpc('get_gift_questions')
// -> [{ id, text, sort_order }]

// 4) envio do teste (nota 1..5 por pergunta, todas respondidas, token de uso único)
const p_answers = perguntas.map(q => ({ question_id: q.id, value: notas[q.id] }))
await supabase.rpc('submit_gift_test', { p_token: submit_token, p_answers })
```
Não há resultado para exibir ao respondente — mostre apenas um agradecimento. A análise é feita pelo pastor.

### 3.4. Dashboard pastoral — RF09/RF10/RF11

```js
// membros da igreja selecionada
const { data: membros } = await supabase
  .from('members').select('*').eq('church_id', churchId).eq('archived', false)

// lista de resgate (inativos/desviados) — RF10
const { data: resgate } = await supabase
  .from('members').select('*').eq('church_id', churchId).eq('status', 'inativo_desviado')

// mudar status pastoral — RF09  ('ativo' | 'em_alerta' | 'inativo_desviado' | 'transferido')
await supabase.from('members').update({ status: 'em_alerta' }).eq('id', memberId)

// histórico confidencial (só pastor com edição na igreja) — RF11
await supabase.from('pastoral_notes').insert({ member_id, church_id: churchId, body: 'Atendimento...' })
const { data: notas } = await supabase.from('pastoral_notes').select('*').eq('member_id', memberId)

// visitas de resgate — RF10/RF11
await supabase.from('pastoral_visits').insert({ member_id, church_id: churchId, scheduled_at })
```

### 3.5. Ministérios e matching — RF14

```js
// ministérios e dons requeridos
const { data: ministerios } = await supabase.from('ministries').select('*').eq('church_id', churchId)

// sugestões (só membros ATIVOS entram) — RF14
const { data: candidatos } = await supabase.rpc('suggest_members_for_ministry', { p_ministry: ministryId })
const { data: ministeriosSugeridos } = await supabase.rpc('suggest_ministries_for_member', { p_member: memberId })

// alocar membro num ministério (escala)
await supabase.from('ministry_assignments').insert({ ministry_id, member_id, church_id: churchId })
```

### 3.6. Transferência e arquivamento — RF12/RF13

```js
// destino pode ser qualquer igreja do presbitério (lista dedicada)
const { data: todas } = await supabase.rpc('list_all_churches')  // [{ id, name, city, slug }]

await supabase.rpc('request_transfer', { p_member: memberId, p_to_church: destinoId }) // RF12
await supabase.rpc('accept_transfer',  { p_request: requestId })   // igreja de destino aceita
await supabase.rpc('reject_transfer',  { p_request: requestId })

await supabase.rpc('archive_member', { p_member: memberId, p_reason: 'Mudou de cidade' }) // RF13
```

### 3.7. Admin Master — RF02/RF03

```js
await supabase.rpc('create_church', { p_name: 'IPB Canoas', p_slug: 'canoas', p_city: 'Canoas' })
await supabase.rpc('grant_access',  { p_user: userId, p_church: churchId, p_level: 'read' }) // ou 'edit'
await supabase.rpc('revoke_access', { p_user: userId, p_church: churchId })
```

---

## 4. Deploy do backend (Supabase hospedado)

1. Crie um projeto em [supabase.com](https://supabase.com) e anote **Project URL** e **anon key**
   (Project Settings → API) e o **Project Ref**.
2. Aplique as migrations:
   ```bash
   npx supabase link --project-ref <SEU-REF>
   npx supabase db push          # envia supabase/migrations/*
   ```
   > O `db push` **não** envia o `seed.sql`. Para popular os 16 dons / perguntas mock / igreja demo,
   > rode o conteúdo de `supabase/seed.sql` no **SQL Editor** do painel (opcional em produção).
3. **Primeiro Admin Master:** crie o usuário em Authentication → Users (o trigger cria o `profiles`),
   depois promova-o no SQL Editor (como service_role):
   ```sql
   update public.profiles set is_master = true,
          home_church_id = (select id from public.churches where slug = 'sapucaia')
    where email = 'pastor.master@ipb.org';
   ```
4. **Auth → URL Configuration:** em *Site URL* e *Redirect URLs*, adicione a URL da Vercel
   (ex.: `https://conecta-dons.vercel.app`) para o login funcionar em produção.

---

## 5. Deploy do frontend (Vercel)

O app é uma SPA Vite com `react-router` (BrowserRouter) → precisa de **rewrite** para servir `index.html`
em qualquer rota.

### 5.1. `frontend/vercel.json` (criar)
```json
{
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }]
}
```

### 5.2. Projeto na Vercel
1. **Import** do repositório Git na Vercel.
2. **Root Directory:** `frontend`.
3. **Framework Preset:** Vite (Build Command `npm run build`, Output Directory `dist` — detectados).
4. **Environment Variables** (Settings → Environment Variables):
   | Nome | Valor |
   |---|---|
   | `VITE_SUPABASE_URL` | `https://tfyahgtkxbyshxapibdz.supabase.co` |
   | `VITE_SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_gsZkXPaBNRqUZmIdYEyziw_XRFi0vV9` |
5. **Deploy.** A cada push na branch de produção a Vercel rebuilda.
6. Volte ao Supabase e confirme que a URL da Vercel está nas **Redirect URLs** (passo 4 da seção 4).

> As variáveis `VITE_*` são embutidas no bundle em build-time — são **públicas** por natureza (a anon key
> é pública mesmo). Nada sensível vai para o cliente; a `service_role` nunca entra aqui.

---

## 6. Checklist de publicação
- [ ] Migrations aplicadas no projeto Supabase (`db push`).
- [ ] Admin Master criado e promovido (`is_master = true`).
- [ ] `VITE_SUPABASE_URL` (base, sem `/rest/v1/`) e `VITE_SUPABASE_ANON_KEY` na Vercel.
- [ ] URL da Vercel nas *Redirect URLs* do Supabase Auth.
- [ ] `frontend/vercel.json` com o rewrite SPA.
- [ ] Rotas protegidas (`/dashboard`, `/admin`) exigem sessão; sem login → `/login`.
- [ ] Página pública de cadastro por `slug` testada ponta a ponta (cadastro → teste → agradecimento).
- [ ] Usar só a chave anon no frontend.

## 7. Segurança (resumo)
- RLS em todas as tabelas; `anon` sem acesso direto a nenhuma tabela (só os 4 RPCs públicos).
- Isolamento entre igrejas e matriz de permissões (read/edit) impostos no banco.
- Notas/visitas pastorais são confidenciais (só pastor com edição na igreja).
- Cadastro/teste públicos validam tudo no servidor (consentimento, formato, rate-limit, notas 1–5) e
  derivam a igreja do `slug`/token — nunca confiam em `church_id`/`member_id` do cliente.
- Ações privilegiadas (criar igreja, conceder acesso, transferir, arquivar) gravam trilha em `audit_log`.
