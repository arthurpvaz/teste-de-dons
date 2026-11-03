# Testando o backend — Conecta Dons

## Forma mais fácil (um comando)

Com **Docker rodando**, na raiz do repositório:

```bash
npm run test:backend
```

Isso sobe o stack local, aplica todas as migrations + seed e roda toda a suíte `supabase/tests/*.sql`.
Verde (`TODOS OS TESTES PASSARAM ✅`) = sistema funcionando. Sai com código ≠ 0 se algo falhar (serve p/ CI).

A suíte cobre: fluxo público (campus + envio das 133 respostas 0–3), isolamento multi-tenant, permissão
cruzada + confidencialidade das notas, transferência, matching, perfil de dons (soma por dom) e
autorização negativa.

---

## Testes manuais contra um projeto (local ou hospedado)

Os exemplos usam `curl` + `node`. Para o projeto **hospedado**, defina:

```
REF=tfyahgtkxbyshxapibdz
KEY=sb_publishable_gsZkXPaBNRqUZmIdYEyziw_XRFi0vV9
BASE=https://$REF.supabase.co
API=$BASE/rest/v1/rpc
```
Para o **local**, use `BASE=http://127.0.0.1:54321` e a anon key de `npx supabase status`.

### Passo 1 — Fluxo público (leitura)

```
# campi para o seletor
curl -s "$API/list_campuses" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}'
# perguntas (devem ser 133)
curl -s "$API/get_gift_questions" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log("perguntas:",JSON.parse(s).length))'
```
**Esperado:** a lista de igrejas e `perguntas: 133`.

### Passo 2 — Segurança do `anon`

```
curl -s "$BASE/rest/v1/members?select=*" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```
**Esperado:** `permission denied for table members`.

### Passo 3 — Envio do questionário (cria um membro de teste)

```
CAMPUS=$(curl -s "$API/list_campuses" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).find(c=>/Sapucaia/.test(c.name)).id))')

BODY=$(curl -s "$API/get_gift_questions" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const qs=JSON.parse(s);console.log(JSON.stringify({p_church_id:process.env.CAMPUS,p_name:"Teste Backend",p_email:"teste@backend.com",p_phone:null,p_bond:"visitante",p_consent:true,p_answers:qs.map(q=>({question_id:q.id,value:3}))}))}' CAMPUS=$CAMPUS)

curl -s "$API/submit_questionnaire" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$BODY"
```
**Esperado:** `[{ "member_id": "...", "submission_id": "..." }]`. Reenviar o mesmo e-mail no mesmo campus
deve falhar (`Já existe um cadastro com este e-mail neste campus`); valor fora de 0–3 ou menos de 133
respostas → erro em PT.

### Passo 4 — Fluxo autenticado (pastor/admin) + gráfico de dons

```
JWT=$(curl -s "$BASE/auth/v1/token?grant_type=password" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"SEU_MASTER@email.com","password":"SUA_SENHA"}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.access_token||("ERRO: "+(j.error_description||s)))})')

# igrejas acessíveis (tenant switcher)
curl -s "$API/my_churches" -H "apikey: $KEY" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{}'

# membros (como anon dá "denied"; como pastor funciona)
curl -s "$BASE/rest/v1/members?select=id,full_name,status" -H "apikey: $KEY" -H "Authorization: Bearer $JWT"

# gráfico de dons de um membro (soma por dom, 0..21)
curl -s "$API/get_member_gift_profile" -H "apikey: $KEY" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -d '{"p_member":"<ID_DO_MEMBRO>"}'
```
**Esperado:** `my_churches` lista as igrejas do master; a leitura de `members` funciona; o perfil traz os
19 dons com a soma (quem respondeu tudo com 3 terá 21 em cada dom).

### Passo 5 — Edge Function (cadastro de pastor pelo master)

Local: `npx supabase functions serve create-pastor`. Depois, com o JWT de master do Passo 4:
```
curl -s "$BASE/functions/v1/create-pastor" -H "apikey: $KEY" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -d '{"email":"pastor.novo@ipb.org","full_name":"Pastor Novo"}'
```
**Esperado:** `{ user_id, email, temp_password }`. Sem JWT → 401; com um pastor não-master → 403.

### Passo 6 — Suite completa no SQL Editor (opcional)

Cole `supabase/tests/smoke.sql` no SQL Editor do painel. Roda em transação e dá `ROLLBACK` no fim
(não altera o banco). Deve terminar em `TODOS OS TESTES PASSARAM`.

### Passo 7 — Limpar dados de teste

```sql
delete from public.members where full_name = 'Teste Backend';
```
Submissões e respostas somem junto (`on delete cascade`).
