#!/usr/bin/env bash
set -euo pipefail
image="${1:?image required}"
expected_sha="${2:?source SHA required}"
cid=$(docker create "$image"); trap 'docker rm "$cid" >/dev/null 2>&1 || true' EXIT
for path in /app/src/notifications_service /app/migrations/manifest.txt /app/migrations/20260920_notification_foundation.sql /app/scripts/import-quant-notifications.py; do docker cp "$cid:$path" /tmp/published-image-contract >/dev/null; done
name="published-notification-$RANDOM-$$"
docker run -d --rm --name "$name" --network host "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; docker rm "$cid" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:8010/api/ready >/dev/null && break; sleep 1; done
actual=$(curl -sf http://127.0.0.1:8010/api/build-info | python3 -c 'import json,sys;print(json.load(sys.stdin)["source_sha"])')
test "$actual" = "$expected_sha"
echo POST_PUSH_IMAGE_CONTENT_VERIFICATION=pass POST_PUSH_BUILD_INFO_VERIFICATION=pass
