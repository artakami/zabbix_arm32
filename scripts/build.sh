#!/usr/bin/env bash
set -euo pipefail

# Builds a component for linux/arm/v7 by checking out upstream zabbix-docker
# at the given branch, applying the matching patch from patches/<branch>/,
# and running upstream's own Makefile unmodified.
#
# Usage: scripts/build.sh <zbx-branch> [target]
# Example: scripts/build.sh 7.4 proxy-sqlite3
#          scripts/build.sh 7.4 agent2-mysql
#
# Requires: docker buildx with QEMU registered for arm/v7
# (docker run --privileged --rm tonistiigi/binfmt --install arm)

ZBX_BRANCH="${1:?Usage: $0 <zbx-branch: 7.0|7.4> [target]}"
TARGET="${2:-proxy-sqlite3}"

# DB backend is the target's suffix after the last hyphen (proxy-sqlite3 ->
# sqlite3, agent2-mysql -> mysql) -- matches upstream's own bake target
# naming convention.
DB="${TARGET##*-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"
PATCH_FILE="${REPO_ROOT}/patches/${ZBX_BRANCH}/armv7-skip-java-gateway.patch"

if [ ! -f "$PATCH_FILE" ]; then
    echo "No patch tracked for branch '${ZBX_BRANCH}' (expected ${PATCH_FILE})" >&2
    exit 1
fi

if [ ! -d "${UPSTREAM_DIR}/.git" ]; then
    git clone --branch "$ZBX_BRANCH" --depth 1 https://github.com/zabbix/zabbix-docker.git "$UPSTREAM_DIR"
else
    git -C "$UPSTREAM_DIR" fetch origin "$ZBX_BRANCH" --depth 1
    git -C "$UPSTREAM_DIR" checkout -f "origin/${ZBX_BRANCH}"
fi

if (cd "$UPSTREAM_DIR" && patch -p1 --dry-run < "$PATCH_FILE" > /dev/null 2>&1); then
    (cd "$UPSTREAM_DIR" && patch -p1 < "$PATCH_FILE")
else
    echo "Patch does not apply cleanly against ${ZBX_BRANCH} -- run scripts/update-upstream.sh to confirm" >&2
    exit 1
fi

LOCAL_TAG="alpine-${ZBX_BRANCH}-armv7"

cd "$UPSTREAM_DIR"
make base OS=alpine PLATFORMS=linux/arm/v7 LOCAL_ZBX_TAG="$LOCAL_TAG"
make "builders-${DB}" OS=alpine DB="$DB" PLATFORMS=linux/arm/v7 LOCAL_ZBX_TAG="$LOCAL_TAG"
make bake-target TARGET="$TARGET" OS=alpine DB="$DB" PLATFORMS=linux/arm/v7 LOCAL_ZBX_TAG="$LOCAL_TAG"

echo "Build complete -- run 'docker images' to see the resulting zabbix-*:${LOCAL_TAG} image"
echo "(upstream's own docker-bake.hcl decides the exact image name per target, e.g."
echo " 'proxy-sqlite3' keeps its DB suffix but 'agent2-mysql' produces 'zabbix-agent2')"
