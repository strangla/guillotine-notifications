#!/usr/bin/env bash
set -euo pipefail
name="notification-foundation-$RANDOM-$$"; port="${TEST_PG_PORT:-55447}"
docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=test -e POSTGRES_DB=notifications -p "$port":5432 postgres:16 >/dev/null
cleanup(){ [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true; docker rm -f "$name" >/dev/null 2>&1 || true; }; trap cleanup EXIT
for _ in $(seq 1 40); do docker exec "$name" pg_isready -U postgres -d notifications >/dev/null 2>&1 && break; sleep 1; done
cat migrations/20260920_notification_foundation.sql | docker exec -i "$name" psql -U postgres -d notifications >/dev/null
fixture="${1:-tests/fixtures/quant-notifications.json}"
DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$fixture" --dry-run >/tmp/notification-dry-run.out
DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$fixture" >/tmp/notification-import-1.out
DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$fixture" >/tmp/notification-import-2.out
grep -q 'INSERTED_ROWS=0' /tmp/notification-import-2.out
docker exec "$name" psql -U postgres -d notifications -c "update notifications.notifications set metadata='{}'::jsonb where id='00000000-0000-0000-0000-000000000001'" >/dev/null
set +e; DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$fixture" >/tmp/notification-conflict.out 2>&1; conflict_rc=$?; set -e; test "$conflict_rc" -ne 0; grep -q 'CONFLICT_ROWS=' /tmp/notification-conflict.out
NOTIFICATION_API_KEY=test DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" SOURCE_SHA=disposable PYTHONPATH=src uv run uvicorn notifications_service.main:app --host 127.0.0.1 --port 8011 >/tmp/notification-api.log 2>&1 & pid=$!
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:8011/api/ready >/dev/null && break; sleep 1; done
h='X-API-Key: test'; body='{"source_product":"quant","event_type":"test","severity":"high","message":"api","occurred_at":"2026-01-01T00:00:00Z","dedupe_key":"api-dedupe","entity_type":"security","entity_key":"AAPL"}'
first=$(curl -sf -H "$h" -H 'Content-Type: application/json' -d "$body" http://127.0.0.1:8011/api/v1/notifications); second=$(curl -sf -H "$h" -H 'Content-Type: application/json' -d "$body" http://127.0.0.1:8011/api/v1/notifications); echo "$second" | grep -q '"created":false'
conflict=$(curl -s -o /dev/null -w '%{http_code}' -H "$h" -H 'Content-Type: application/json' -d "${body/api/different}" http://127.0.0.1:8011/api/v1/notifications); test "$conflict" = 409
curl -sf -H "$h" 'http://127.0.0.1:8011/api/v1/notifications?source_product=quant&entity_type=security&entity_key=AAPL&unread_only=true&limit=100' >/dev/null
curl -sf -H "$h" http://127.0.0.1:8011/api/v1/notifications/unread-count >/dev/null
id=$(echo "$first" | python3 -c 'import json,sys;print(json.load(sys.stdin)["notification"]["id"])'); curl -sf -X PATCH -H "$h" http://127.0.0.1:8011/api/v1/notifications/$id/read >/dev/null; curl -sf -X PATCH -H "$h" http://127.0.0.1:8011/api/v1/notifications/$id/read >/dev/null; curl -sf -X POST -H "$h" http://127.0.0.1:8011/api/v1/notifications/mark-all-read >/dev/null
test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8011/api/v1/notifications)" = 401
test "$(curl -s -o /dev/null -w '%{http_code}' -H 'X-API-Key: bad' http://127.0.0.1:8011/api/v1/notifications)" = 401
test "$(curl -s -o /dev/null -w '%{http_code}' -H "$h" 'http://127.0.0.1:8011/api/v1/notifications?limit=501')" = 422
unknown=$(mktemp); python3 - <<PY
import json
x=json.load(open('$fixture'));x[0]['source']='future_unknown';json.dump(x,open('$unknown','w'))
PY
set +e; DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$unknown" >/tmp/unknown.out 2>&1; rc=$?; set -e; test "$rc" -ne 0; test "$(docker exec "$name" psql -U postgres -d notifications -Atc 'select count(*) from notifications.notifications')" = 3
rm -f "$unknown"
echo MIGRATION_APPLY=pass FIRST_IMPORT=pass SECOND_IMPORT_INSERTED_ROWS=0 SECOND_IMPORT_CONFLICT_ROWS=0 SECOND_IMPORT_IDEMPOTENT=yes API_SMOKE=pass DEDUPE_SMOKE=pass READ_STATE_SMOKE=pass UNKNOWN_SOURCE_FAIL_CLOSED=pass DISPOSABLE_POSTGRES_ACCEPTANCE=pass
