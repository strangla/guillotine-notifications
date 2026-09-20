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
# End-to-end rollback export on the clean imported database, including a native-style row.
docker exec "$name" psql -U postgres -d notifications -c "INSERT INTO notifications.notifications (id,source_product,event_type,entity_type,entity_key,severity,message,occurred_at,metadata) VALUES ('00000000-0000-0000-0000-000000000099','quant','native','security','NVDA','low','native','2026-01-03T00:00:00Z','{\"quant_alert_id\":\"native-1\",\"quant_source\":\"auto_scan\"}')" >/dev/null
DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/export-quant-compatible-notifications.py /tmp/quant-rollback.json >/dev/null
python3 - <<PY
import json
src={x['id']:x for x in json.load(open('$fixture'))}; out={x['id']:x for x in json.load(open('/tmp/quant-rollback.json'))}
assert set(src) <= set(out)
for i,x in src.items():
 for k in ('id','alert_id','symbol','message','read','priority','source','legacy_id','legacy_position'): assert out[i][k]==x[k], (i,k)
 assert out[i]['triggered_at'].replace('+00:00','Z') == x['triggered_at']
assert out['00000000-0000-0000-0000-000000000099']['legacy_id'] is None
print('HISTORICAL_ROLLBACK_EXPORT_SCRIPT=pass HISTORICAL_ROLLBACK_FIELD_MISMATCHES=0 HISTORICAL_ROLLBACK_ROUNDTRIP=pass NATIVE_QUANT_ROLLBACK_EXPORT_SCRIPT=pass NATIVE_QUANT_ROLLBACK_EXPORT=pass ROLLBACK_ID_REWRITE=no')
PY
docker exec "$name" psql -U postgres -d notifications -c "update notifications.notifications set metadata='{}'::jsonb where id='00000000-0000-0000-0000-000000000001'" >/dev/null
set +e; DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$fixture" >/tmp/notification-conflict.out 2>&1; conflict_rc=$?; set -e; test "$conflict_rc" -ne 0; grep -q 'CONFLICT_ROWS=' /tmp/notification-conflict.out
docker exec "$name" psql -U postgres -d notifications -c "INSERT INTO notifications.notifications (id,source_product,event_type,entity_type,entity_key,severity,message,occurred_at,metadata) SELECT gen_random_uuid(), CASE WHEN g%3=0 THEN 'quant' WHEN g%3=1 THEN 'qual' ELSE 'analysis' END, 'page', 'security', 'SYM'||g, 'low', 'page-'||g, CASE WHEN g <= 60 THEN '2026-01-10T00:00:00Z'::timestamptz ELSE now() - (g||' seconds')::interval END, '{}'::jsonb FROM generate_series(1,1200) g" >/dev/null
NOTIFICATION_API_KEY=test DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" SOURCE_SHA=disposable PYTHONPATH=src uv run uvicorn notifications_service.main:app --host 127.0.0.1 --port 8011 >/tmp/notification-api.log 2>&1 & pid=$!
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:8011/api/ready >/dev/null && break; sleep 1; done
h='X-API-Key: test'; body='{"source_product":"quant","event_type":"test","severity":"high","message":"api","occurred_at":"2026-01-01T00:00:00Z","dedupe_key":"api-dedupe","entity_type":"security","entity_key":"AAPL"}'
first=$(curl -sf -H "$h" -H 'Content-Type: application/json' -d "$body" http://127.0.0.1:8011/api/v1/notifications); second=$(curl -sf -H "$h" -H 'Content-Type: application/json' -d "$body" http://127.0.0.1:8011/api/v1/notifications); echo "$second" | grep -q '"created":false'
conflict=$(curl -s -o /dev/null -w '%{http_code}' -H "$h" -H 'Content-Type: application/json' -d "${body/api/different}" http://127.0.0.1:8011/api/v1/notifications); test "$conflict" = 409
curl -sf -H "$h" 'http://127.0.0.1:8011/api/v1/notifications?source_product=quant&entity_type=security&entity_key=AAPL&unread_only=true&limit=100' >/dev/null
docker exec "$name" psql -U postgres -d notifications -Atc "select id from notifications.notifications order by occurred_at desc,id desc" > /tmp/expected_ids
python3 - <<'PY'
import json,urllib.request
h={'X-API-Key':'test'}; cur=None; rows=[]
while True:
 u='http://127.0.0.1:8011/api/v1/notifications?limit=100'+(('&cursor='+cur) if cur else '')
 data=json.load(urllib.request.urlopen(urllib.request.Request(u,headers=h))); rows += data['items']; cur=data.get('next_cursor')
 if not cur: break
expected=[x.strip() for x in open('/tmp/expected_ids') if x.strip()]
assert [x['id'] for x in rows] == expected
for a,b in zip(rows,rows[1:]): assert (a['occurred_at'],a['id']) >= (b['occurred_at'],b['id'])
ties=[x for x in rows if x['occurred_at'].startswith('2026-01-10T00:00:00')]
assert len(ties)==60 and [x['id'] for x in ties] == sorted((x['id'] for x in ties),reverse=True)
print(f'PAGINATION_EXPECTED_ROWS={len(expected)} PAGINATION_RETURNED_ROWS={len(rows)} PAGINATION_DUPLICATE_IDS=0 PAGINATION_MISSING_IDS=0 PAGINATION_EXTRA_IDS=0 PAGINATION_ORDER_STABLE=yes TIE_TIMESTAMP_ROWS={len(ties)} TIE_TIMESTAMP_DUPLICATES=0 TIE_TIMESTAMP_MISSING=0 TIE_BREAK_ID_DESC=pass CURSOR_PAGINATION=pass')
PY
# Exact multi-page filtered proof.
docker exec "$name" psql -U postgres -d notifications -Atc "select id from notifications.notifications where source_product='quant' and is_read=false order by occurred_at desc,id desc" > /tmp/expected_quant_ids
python3 - <<'PY'
import json,urllib.request
h={'X-API-Key':'test'}; cur=None; rows=[]; pages=0
while True:
 u='http://127.0.0.1:8011/api/v1/notifications?limit=100&source_product=quant&unread_only=true'+(('&cursor='+cur) if cur else '')
 d=json.load(urllib.request.urlopen(urllib.request.Request(u,headers=h))); rows += d['items']; pages+=1; cur=d.get('next_cursor')
 if not cur: break
expected=[x.strip() for x in open('/tmp/expected_quant_ids') if x.strip()]
assert pages>=3 and [x['id'] for x in rows]==expected
print(f'FILTERED_PAGE_COUNT={pages} FILTERED_MISSING_IDS=0 FILTERED_EXTRA_IDS=0 FILTERED_CURSOR_PAGINATION=pass')
PY
test "$(curl -sf -H "$h" http://127.0.0.1:8011/api/v1/notifications/unread-count | python3 -c 'import json,sys;print(json.load(sys.stdin)["count"])')" -gt 0
test "$(curl -sf -H "$h" 'http://127.0.0.1:8011/api/v1/notifications/unread-count?source_product=quant' | python3 -c 'import json,sys;print(json.load(sys.stdin)["count"])')" -gt 0
curl -sf -X POST -H "$h" 'http://127.0.0.1:8011/api/v1/notifications/mark-all-read?source_product=quant' >/dev/null
test "$(curl -sf -H "$h" 'http://127.0.0.1:8011/api/v1/notifications/unread-count?source_product=quant' | python3 -c 'import json,sys;print(json.load(sys.stdin)["count"])')" = 0
test "$(curl -sf -H "$h" 'http://127.0.0.1:8011/api/v1/notifications/unread-count?source_product=qual' | python3 -c 'import json,sys;print(json.load(sys.stdin)["count"])')" -gt 0
test "$(curl -sf -H "$h" 'http://127.0.0.1:8011/api/v1/notifications/unread-count?source_product=analysis' | python3 -c 'import json,sys;print(json.load(sys.stdin)["count"])')" -gt 0
id=$(echo "$first" | python3 -c 'import json,sys;print(json.load(sys.stdin)["notification"]["id"])'); curl -sf -X PATCH -H "$h" http://127.0.0.1:8011/api/v1/notifications/$id/read >/dev/null; curl -sf -X PATCH -H "$h" http://127.0.0.1:8011/api/v1/notifications/$id/read >/dev/null; curl -sf -X POST -H "$h" http://127.0.0.1:8011/api/v1/notifications/mark-all-read >/dev/null
curl -sf -X DELETE -H "$h" 'http://127.0.0.1:8011/api/v1/notifications?source_product=quant' >/dev/null
q=$(docker exec "$name" psql -U postgres -d notifications -Atc "select count(*) from notifications.notifications where source_product='quant'"); test "$q" = 0
q=$(docker exec "$name" psql -U postgres -d notifications -Atc "select count(*) from notifications.notifications where source_product in ('qual','analysis')"); test "$q" = 800
echo READ_STATE_PRODUCT_ISOLATION=pass
curl -sf -X DELETE -H "$h" 'http://127.0.0.1:8011/api/v1/notifications' >/dev/null
test "$(docker exec "$name" psql -U postgres -d notifications -Atc 'select count(*) from notifications.notifications')" = 0
echo CLEAR_BY_SOURCE_TEST=pass GLOBAL_CLEAR_TEST=pass
test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8011/api/v1/notifications)" = 401
test "$(curl -s -o /dev/null -w '%{http_code}' -H 'X-API-Key: bad' http://127.0.0.1:8011/api/v1/notifications)" = 401
test "$(curl -s -o /dev/null -w '%{http_code}' -H "$h" 'http://127.0.0.1:8011/api/v1/notifications?limit=501')" = 422
unknown=$(mktemp); python3 - <<PY
import json
x=json.load(open('$fixture'));x[0]['source']='future_unknown';json.dump(x,open('$unknown','w'))
PY
set +e; DATABASE_URL="postgresql+asyncpg://postgres:test@127.0.0.1:$port/notifications" uv run python scripts/import-quant-notifications.py "$unknown" >/tmp/unknown.out 2>&1; rc=$?; set -e; test "$rc" -ne 0; test "$(docker exec "$name" psql -U postgres -d notifications -Atc 'select count(*) from notifications.notifications')" = 0
rm -f "$unknown"
echo MIGRATION_APPLY=pass FIRST_IMPORT=pass SECOND_IMPORT_INSERTED_ROWS=0 SECOND_IMPORT_CONFLICT_ROWS=0 SECOND_IMPORT_IDEMPOTENT=yes API_SMOKE=pass DEDUPE_SMOKE=pass READ_STATE_SMOKE=pass UNKNOWN_SOURCE_FAIL_CLOSED=pass DISPOSABLE_POSTGRES_ACCEPTANCE=pass
