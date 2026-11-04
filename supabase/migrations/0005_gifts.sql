-- 0005_gifts.sql
-- Teste de Dons (RF07) com estrutura MOCK flexível (RF08).
-- gifts = matriz oficial IPB (16 semeados, extensível). gift_questions = perguntas mock
-- com peso por dom. Submissões vinculadas ao membro (necessário p/ matching RF14).

create table public.gifts (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  name        text not null,
  description text,
  sort_order  int  not null default 0
);
comment on table public.gifts is 'Dons oficiais IPB (RF07). Extensível: o 17º dom pode ser inserido depois.';

create table public.gift_questions (
  id         uuid primary key default gen_random_uuid(),
  text       text not null,
  gift_id    uuid not null references public.gifts(id),
  -- peso da pergunta no dom (RF08 — chave de pontuação, nunca exposta ao respondente)
  weight     numeric not null default 1 check (weight >= 0),
  is_active  boolean not null default true,
  -- versão do questionário: quando o pastor entregar o definitivo, incrementa-se a versão
  -- em vez de reescrever perguntas já respondidas (preserva o sentido das respostas antigas).
  version    int not null default 1,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index gift_questions_active_idx on public.gift_questions (is_active, sort_order);

create table public.gift_submissions (
  id         uuid primary key default gen_random_uuid(),
  member_id  uuid not null references public.members(id) on delete cascade,
  -- church_id é derivado do membro no RPC submit_gift_test (nunca vem do cliente).
  -- Mantido denormalizado p/ performance de RLS e p/ histórico (migra no aceite de transferência).
  church_id  uuid not null references public.churches(id),
  created_at timestamptz not null default now()
);
-- uma submissão por membro (impede flood de respostas falsas num mesmo membro)
create unique index gift_submissions_member_uniq on public.gift_submissions (member_id);
create index gift_submissions_church_idx on public.gift_submissions (church_id);

create table public.gift_answers (
  submission_id uuid not null references public.gift_submissions(id) on delete cascade,
  question_id   uuid not null references public.gift_questions(id) on delete restrict,
  value         int  not null check (value between 1 and 5),
  primary key (submission_id, question_id)
);
comment on table public.gift_answers is 'Nota 1..5 por pergunta. Perguntas respondidas não podem ser apagadas (on delete restrict).';
