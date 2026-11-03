#!/usr/bin/env bash
# Runner de testes do backend Conecta Dons.
# Sobe o stack local, aplica migrations + seed e roda toda a suíte supabase/tests/*.sql.
# Uso:  bash supabase/tests/run.sh   (ou:  npm run test:backend)
# Sai com código != 0 se algum teste falhar (serve para rodar na mão e em CI).
set -euo pipefail

cd "$(dirname "$0")/../.."   # raiz do repositório

echo "==> Verificando Docker..."
if ! docker info >/dev/null 2>&1; then
  echo "ERRO: Docker não está rodando. Abra o Docker Desktop e tente de novo." >&2
  exit 1
fi

echo "==> Garantindo o stack Supabase local..."
if ! npx --yes supabase@latest status >/dev/null 2>&1; then
  npx --yes supabase@latest start
fi

echo "==> Aplicando migrations + seed (db reset)..."
npx --yes supabase@latest db reset >/dev/null

DB=$(docker ps --format '{{.Names}}' | grep -i 'supabase_db' | head -1)
if [ -z "$DB" ]; then
  echo "ERRO: container do Postgres não encontrado." >&2
  exit 1
fi
CONN="postgresql://postgres:postgres@127.0.0.1:5432/postgres"

fail=0
shopt -s nullglob
for f in supabase/tests/*.sql; do
  echo ""
  echo "==> Rodando $(basename "$f")"
  if docker exec -i "$DB" psql "$CONN" -v ON_ERROR_STOP=1 -q < "$f" > /tmp/conecta_test.out 2>&1; then
    grep -E 'NOTICE:|PASSARAM' /tmp/conecta_test.out | sed 's/^/   /' || true
    echo "   ✅ PASSOU: $(basename "$f")"
  else
    grep -E 'NOTICE:|ERROR|FALHOU' /tmp/conecta_test.out | sed 's/^/   /' || true
    echo "   ❌ FALHOU: $(basename "$f")"
    fail=1
  fi
done

echo ""
if [ "$fail" -eq 0 ]; then
  echo "==> TODOS OS TESTES PASSARAM ✅"
else
  echo "==> ALGUM TESTE FALHOU ❌" >&2
fi
exit $fail
