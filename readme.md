# Documentação da API: Teste de Dons (Frontend)

Oct 8, 2026 · @Arthur Vaz

## Visão geral

O backend é um projeto Supabase que expõe duas funções públicas para o membro responder o formulário e uma view protegida para o admin ver as respostas. O membro nunca acessa as tabelas diretamente.

| Quem | O que faz | Como acessa |
| --- | --- | --- |
| Membro (sem login) | Carrega as perguntas e envia as respostas | `rpc('get_questions')` e `rpc('submit_answers')` |
| Admin (com login) | Cadastra perguntas e vê as respostas | Tabela `questions` e view `admin_answers_detail` |

O site não calcula nem mostra resultado: a análise das respostas é feita por uma pessoa, depois. Cada resposta é uma nota de 1 a 5.

## Configuração

Instale o cliente oficial e crie uma única instância compartilhada no app.

```bash
npm install @supabase/supabase-js
```

```js
import { createClient } from '@supabase/supabase-js'

export const supabase = createClient(
  'https://SEU-PROJETO.supabase.co',  // Project Settings > API > Project URL
  'SUA_CHAVE_PUBLICA'                 // chave anon ou publishable
)
```

Use somente a chave pública (anon ou publishable). Nunca coloque a `service_role` no frontend: ela ignora todas as regras de segurança.

## Membro: carregar as perguntas

`get_questions` devolve as perguntas ativas, já na ordem de exibição. Não exige login.

```js
const { data: questions, error } = await supabase.rpc('get_questions')
```

A resposta é uma lista de objetos com `id` e `text`:

```json
[
  { "id": "b3f1…", "text": "Gosto de estudar a Bíblia e explicar o que aprendi." },
  { "id": "9c2a…", "text": "Sinto alegria em ajudar nas tarefas práticas da igreja." }
]
```

Guarde o `id` de cada pergunta: ele é obrigatório no envio. Lista vazia significa que o admin ainda não cadastrou perguntas ativas.

## Membro: enviar as respostas

`submit_answers` grava o envio e todas as notas de uma vez. Não exige login e não devolve nenhuma análise.

| Parâmetro | Tipo | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `p_name` | texto | Sim | Nome de quem respondeu |
| `p_email` | texto | Não | Envie `null` se estiver vazio |
| `p_phone` | texto | Não | Envie `null` se estiver vazio |
| `p_consent` | booleano | Sim | Precisa ser `true` (aceite do uso dos dados, LGPD) |
| `p_answers` | lista | Sim | Uma entrada para cada pergunta ativa |

Cada item de `p_answers` tem `question_id` (o id recebido em `get_questions`) e `value` (inteiro de 1 a 5, de "discordo totalmente" a "concordo totalmente"). Todas as perguntas ativas precisam ser respondidas, sem repetir nenhuma.

```js
const { data: submissionId, error } = await supabase.rpc('submit_answers', {
  p_name: 'Maria Silva',
  p_email: 'maria@email.com',
  p_phone: null,
  p_consent: true,
  p_answers: [
    { question_id: 'b3f1…', value: 4 },
    { question_id: '9c2a…', value: 5 }
  ]
})
```

No sucesso, `data` é o id do envio (uuid) e `error` é `null`. Mostre uma mensagem de agradecimento: não há resultado para exibir.

## Erros e validações

Se algo estiver errado, `error.message` traz a causa em português. Mostre essa mensagem ao usuário e mantenha o formulário preenchido.

| Mensagem | Causa | O que fazer no frontend |
| --- | --- | --- |
| Nome é obrigatório | `p_name` vazio | Exigir o nome antes de enviar |
| É necessário aceitar o uso dos dados para enviar | `p_consent` diferente de `true` | Exigir o checkbox de aceite |
| Formato de respostas inválido | `p_answers` não é uma lista | Enviar um array de objetos |
| Nenhuma pergunta disponível no momento | Não há perguntas ativas | Mostrar aviso e bloquear o envio |
| Responda todas as perguntas com notas de 1 a 5 | Falta pergunta, nota fora de 1 a 5 ou pergunta repetida | Validar antes: todas respondidas e nota entre 1 e 5 |

Valide no frontend antes de chamar a função, para dar retorno mais rápido; a validação do banco continua valendo como garantia. Se a lista de perguntas mudar enquanto a pessoa preenche, recarregue com `get_questions` e peça para revisar.

## Admin: login

O admin entra com e-mail e senha pelo Supabase Auth. O usuário precisa existir em Authentication > Users e estar cadastrado na tabela `admins` (isso é feito no backend, uma única vez).

```js
const { error } = await supabase.auth.signInWithPassword({
  email: 'admin@suaigreja.com',
  password: 'senha'
})
```

Para saber se o usuário logado é admin, consulte a própria linha em `admins`:

```js
const { data } = await supabase.from('admins').select('user_id').maybeSingle()
const isAdmin = !!data
```

Quem estiver logado mas não for admin recebe listas vazias nas telas abaixo. Trate isso mostrando uma mensagem de acesso negado. Para sair, use `supabase.auth.signOut()`.

## Admin: gerenciar perguntas

Com o admin logado, a tabela `questions` aceita leitura, inclusão, edição e exclusão. Campos: `id`, `text`, `sort_order` (ordem de exibição, menor primeiro), `is_active` (ativa no formulário) e `created_at`.

```js
// Listar todas (ativas ou não)
const { data } = await supabase.from('questions').select('*').order('sort_order')

// Cadastrar
await supabase.from('questions').insert({ text: 'Nova pergunta', sort_order: 11 })

// Editar texto ou ordem
await supabase.from('questions').update({ text: 'Texto novo', sort_order: 3 }).eq('id', id)

// Desativar (some do formulário, mantém as respostas já dadas)
await supabase.from('questions').update({ is_active: false }).eq('id', id)
```

Perguntas que já têm respostas não podem ser excluídas: o banco bloqueia. Para retirá-las do formulário, desative com `is_active = false`. Evite reescrever o texto de uma pergunta já respondida, pois isso muda o sentido das respostas antigas; desative-a e crie uma nova.

## Admin: visualizar as respostas

A view `admin_answers_detail` traz uma linha por resposta, já com os dados de quem respondeu e o texto da pergunta.

| Coluna | Descrição |
| --- | --- |
| `submission_id` | Id do envio (agrupa as respostas de uma pessoa) |
| `submitted_at` | Data e hora do envio |
| `respondent_name` | Nome |
| `respondent_email` | E-mail (pode ser nulo) |
| `respondent_phone` | Telefone (pode ser nulo) |
| `question_order` | Ordem da pergunta |
| `question_text` | Texto da pergunta |
| `answer_value` | Nota de 1 a 5 |

```js
// Todas as respostas, envios mais recentes primeiro
const { data } = await supabase
  .from('admin_answers_detail')
  .select('*')
  .order('submitted_at', { ascending: false })

// Respostas de uma pessoa específica
const { data: pessoa } = await supabase
  .from('admin_answers_detail')
  .select('*')
  .eq('submission_id', submissionId)
  .order('question_order')
```

Para a lista de pessoas, agrupe as linhas por `submission_id` no frontend (uma linha por pessoa, com nome e data). O Supabase devolve até 1000 linhas por consulta por padrão: com muitos envios, pagine com `.range(0, 999)`, depois `.range(1000, 1999)` e assim por diante. Para exportar, gere um CSV no frontend a partir de `data`. Para apagar um envio de teste, use `supabase.from('submissions').delete().eq('id', id)`.

## Exemplo completo e checklist

Fluxo mínimo do formulário do membro: carregar as perguntas, montar as respostas e enviar.

```js
import { supabase } from './supabase.js'

async function carregarFormulario() {
  const { data: perguntas, error } = await supabase.rpc('get_questions')
  if (error) return mostrarErro('Não foi possível carregar as perguntas.')
  renderizar(perguntas) // cada pergunta com opções de 1 a 5
}

async function enviar(form, perguntas) {
  const respostas = perguntas.map(p => ({
    question_id: p.id,
    value: Number(form[`q_${p.id}`].value) // 1 a 5
  }))

  const { error } = await supabase.rpc('submit_answers', {
    p_name: form.nome.value.trim(),
    p_email: form.email.value.trim() || null,
    p_phone: form.telefone.value.trim() || null,
    p_consent: form.consentimento.checked,
    p_answers: respostas
  })

  if (error) return mostrarErro(error.message)
  mostrarAgradecimento()
}
```

Checklist antes de publicar:

- [ ] Usar só a chave pública (anon ou publishable) no frontend
- [ ] Bloquear o envio sem nome, sem aceite ou com pergunta sem resposta
- [ ] Desabilitar o botão durante o envio para evitar envio duplicado
- [ ] Mostrar só um agradecimento, sem resultado nem pontuação
- [ ] Proteger as telas de admin: sem login ou sem permissão, mostrar acesso negado
- [ ] Testar um envio de ponta a ponta e conferir em `admin_answers_detail`
