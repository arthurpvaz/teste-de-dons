# Testando o backend — Conecta Dons

Guia passo a passo para validar o backend Supabase (local ou hospedado). Os testes de leitura foram
verificados contra o projeto de produção; os de escrita criam dados de teste que o Passo 6 remove.

Os exemplos usam `curl` + `node` (já disponível). Para o projeto **hospedado**, defina no terminal:

```
REF=tfyahgtkxbyshxapibdz
KEY=sb_publishable_gsZkXPaBNRqUZmIdYEyziw_XRFi0vV9
BASE=https://$REF.supabase.co
API=$BASE/rest/v1/rpc
```

> Para testar o **local** (`npx supabase start`), troque por `BASE=http://127.0.0.1:54321` e use a
> anon key de `npx supabase status`.

---

## Passo 1 — Fluxo público, somente leitura

Confirma que o projeto está no ar e com o seed aplicado:

```
curl -s "$API/get_church_by_slug" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{"p_slug":"sapucaia"}'
curl -s "$API/get_gift_questions" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}'
```

**Esperado:** a igreja "IPB Sapucaia do Sul" e uma lista de 32 perguntas ativas.

## Passo 2 — Segurança do `anon`

O papel `anon` não pode ler tabela nenhuma diretamente (só os RPCs públicos):

```
curl -s "$BASE/rest/v1/members?select=*" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

**Esperado:** `{"code":"42501", ... "message":"permission denied for table members"}`.

## Passo 3 — Cadastro + teste de dons (happy path) — grava um membro de teste

```
REG=$(curl -s "$API/register_member" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"p_slug":"sapucaia","p_name":"Teste Backend","p_email":"teste@backend.com","p_phone":null,"p_bond":"visitante","p_consent":true}')
echo "$REG"
TOKEN=$(echo "$REG" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s)[0].submit_token))')

ANS=$(curl -s "$API/get_gift_questions" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.stringify(JSON.parse(s).map(q=>({question_id:q.id,value:5})))))')
curl -s "$API/submit_gift_test" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"p_token\":\"$TOKEN\",\"p_answers\":$ANS}"
```

**Esperado:** `register` devolve `{member_id, submit_token}`; `submit` devolve um UUID de submissão.
Reenviar com o mesmo token deve falhar (`Token inválido ou já utilizado`).

Validações que também devem falhar (teste rápido):
```
# sem consentimento
curl -s "$API/register_member" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"p_slug":"sapucaia","p_name":"X","p_email":null,"p_phone":null,"p_bond":"visitante","p_consent":false}'
```
**Esperado:** `É necessário aceitar o uso dos dados para enviar`.

## Passo 4 — Fluxo autenticado (pastor/admin, via RLS)

Pega um token do Admin Master e consulta como ele (troque e-mail/senha):

```
JWT=$(curl -s "$BASE/auth/v1/token?grant_type=password" -H "apikey: $KEY" -H "Content-Type: application/json" \
  -d '{"email":"SEU_MASTER@email.com","password":"SUA_SENHA"}' \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);console.log(j.access_token||("ERRO: "+(j.error_description||j.msg||s)))})')
echo "JWT: ${JWT:0:20}..."

# igrejas acessíveis (tenant switcher)
curl -s "$API/my_churches" -H "apikey: $KEY" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" -d '{}'

# como master, LÊ members (diferente do Passo 2 com anon)
curl -s "$BASE/rest/v1/members?select=full_name,status,church_id" -H "apikey: $KEY" -H "Authorization: Bearer $JWT"
```

**Esperado:** `my_churches` retorna Sapucaia com `level: "edit"`; a leitura de `members` funciona e traz
o "Teste Backend" do Passo 3. Prova que a **mesma tabela** é negada ao `anon` e liberada ao pastor — RLS ok.

## Passo 5 — Suite completa (opcional, SQL Editor)

Para validar isolamento entre igrejas, transferência e matching de uma vez: abra o **SQL Editor** do painel
e cole o conteúdo de [tests/smoke.sql](tests/smoke.sql). Ele roda em transação e dá `ROLLBACK` no fim
(não altera o banco). Todos os blocos devem imprimir `OK:` e terminar em `TODOS OS TESTES PASSARAM`.

## Passo 6 — Limpar os dados de teste

No SQL Editor:
```sql
delete from public.members where full_name = 'Teste Backend';
```
As submissões e respostas somem junto (`on delete cascade`).

## Passo 7 — Pela interface (frontend)

```
cd frontend && npm install && npm run dev
```
Abra `http://localhost:5173/login` e entre com o master. Login/sessão já funcionam; as demais telas
ainda são stubs.
