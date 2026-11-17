# Conecta Dons — frontend ajustado para o backend Supabase

Este projeto não usa mais MongoDB, Express API, sessão `express-session` ou modelos Mongoose para dados da aplicação.

## Backend

Use o conteúdo de `../teste-de-dons-back-end-refactor/supabase` (migrations + Edge Function) no projeto Supabase.
Foi adicionada a migration `0017_public_questionnaire_questions.sql` porque o backend original, após a migration 0016, expunha o envio público mas não expunha as perguntas ao usuário anônimo.

## Configuração

Edite `public/supabase-config.js` se estiver usando outro projeto Supabase.
A chave usada no frontend deve ser apenas a publishable/anon key. Nunca coloque `service_role` no navegador.

## Rodar local

```bash
npm install
npm start
```

Abra `http://localhost:3000`.

## Fluxos ajustados

- Login de pastor/admin: Supabase Auth (`signInWithPassword`).
- Gestão de pastores: `profiles` + Edge Function `create-pastor`.
- Igrejas: RPC `my_churches` / `create_church`.
- Membros: tabela `members` sob RLS.
- Dons: `member_gift_scores` / `get_member_gift_profile`.
- Histórico pastoral: `pastoral_notes`.
- Questionário público: `list_campuses`, `get_questionnaire_questions` e `submit_questionnaire`.
- Senhas não são lidas, armazenadas ou exibidas pelo frontend.
