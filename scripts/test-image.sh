#!/usr/bin/env bash
set -euo pipefail

# Smoke-tests an armv7 image: confirms the binary actually executes under
# emulation (catches architecture mismatches that a successful build can
# still hide) and that the container stays running rather than crash-looping.
#
# Usage: scripts/test-image.sh <image:tag> [binary]
# Example: scripts/test-image.sh ghcr.io/artakami/zabbix-proxy-sqlite3:alpine-7.4-armv7 zabbix_proxy
#
# Requires: docker buildx with QEMU registered for arm/v7
# (docker run --privileged --rm tonistiigi/binfmt --install arm)

IMAGE="${1:?Usage: $0 <image:tag> [binary]}"
BINARY="${2:-zabbix_proxy}"

echo "==> Checking ${BINARY} -V runs under emulation"
docker run --rm --platform linux/arm/v7 "$IMAGE" "$BINARY" -V

echo "==> Checking the container stays running (not crash-looping)"
CID="$(docker run -d --platform linux/arm/v7 "$IMAGE")"
trap 'docker rm -f "$CID" > /dev/null 2>&1 || true' EXIT

sleep 5

if ! docker ps --filter "id=${CID}" --filter status=running --format '{{.ID}}' | grep -q "$CID"; then
    echo "FAIL: container exited within 5 seconds" >&2
    docker logs "$CID" >&2 || true
    exit 1
fi

echo "PASS: ${IMAGE} started and stayed running"
echo "---- last 20 log lines ----"
docker logs --tail 20 "$CID"
