#!/usr/bin/env bash
set -euo pipefail
IMAGE="${1:-guillotine-notifications:test}"
SHA="${GIT_SHA:-test-image-sha}"
docker build -q -t "$IMAGE" --build-arg GIT_SHA="$SHA" . >/dev/null
cid=$(docker create "$IMAGE"); trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
for path in /app/src/notifications_service /app/migrations/manifest.txt /app/migrations/20260920_notification_foundation.sql /app/scripts/import-quant-notifications.py; do docker cp "$cid:$path" /tmp/notification-contract-check >/dev/null; done
docker run -d --rm --name "${cid}-run" --network host -e NOTIFICATION_API_KEY=test "$IMAGE" >/dev/null
trap 'docker rm -f "${cid}-run" "$cid" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 30); do curl -sf http://127.0.0.1:8010/api/ready >/dev/null && break; sleep 1; done
actual=$(curl -sf http://127.0.0.1:8010/api/build-info | python3 -c 'import json,sys;print(json.load(sys.stdin)["source_sha"])')
test "$actual" = "$SHA"
echo IMAGE_APP_PACKAGE_PRESENT=yes IMAGE_MIGRATION_MANIFEST_PRESENT=yes IMAGE_FOUNDATION_MIGRATION_PRESENT=yes IMAGE_QUANT_IMPORTER_PRESENT=yes IMAGE_BUILD_INFO_SHA_MATCH=yes IMAGE_CONTENT_CONTRACT=pass
