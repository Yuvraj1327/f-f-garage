#!/usr/bin/env bash
# Validates the SQL migrations on a LOCAL, throwaway PostgreSQL database.
#
#   1. creates a fresh scratch database
#   2. loads the Supabase shim (supabase/tests/00_supabase_shim.sql)
#   3. applies every file in supabase/migrations/ in order, each in one transaction
#   4. runs the RLS / constraint tests (supabase/tests/01_rls_and_constraints_test.sql)
#   5. drops the scratch database
#
# Connection settings come from the standard libpq variables (PGHOST, PGPORT,
# PGUSER, PGPASSWORD). The server must be local: the shim creates an `auth`
# schema and roles, which must never be created on a real Supabase project.
#
#   PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres supabase/tests/run_migration_tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${PGHOST:-localhost}"

case "$HOST" in
  localhost | 127.0.0.1 | ::1 | /*) ;;
  *)
    echo "Refusing to run: PGHOST='$HOST' is not a local server." >&2
    exit 2
    ;;
esac

DB="ff_garage_migration_test_$$"
cleanup() { psql -X -q -d postgres -c "drop database if exists \"$DB\"" >/dev/null 2>&1 || true; }
trap cleanup EXIT

psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "create database \"$DB\""

echo "== Shim"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -1 -f "$ROOT/supabase/tests/00_supabase_shim.sql"

echo "== Migrations"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "   applying $(basename "$f")"
  psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -1 -f "$f"
done

echo "== Tests"
LOG="$(mktemp)"
# Test files share fixtures, so they run in filename order against one database.
for t in "$ROOT"/supabase/tests/0[1-9]_*.sql; do
  echo "-- $(basename "$t")"
  psql -X -v ON_ERROR_STOP=1 -d "$DB" -f "$t" 2>&1 | tee -a "$LOG"
done
PASSES="$(grep -c 'PASS:' "$LOG" || true)"
FAILS="$(grep -c 'FAIL:' "$LOG" || true)"
rm -f "$LOG"
echo
echo "Result: $PASSES checks passed, $FAILS failed."
[ "$FAILS" -eq 0 ]
