#!/usr/bin/env bash
set -euo pipefail

# Refreshes the local upstream/ checkout and verifies our armv7 patches still
# apply cleanly against every tracked branch. Run this before cutting a
# release, or whenever upstream might have changed -- catches a patch that
# needs updating before CI does.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"
BRANCHES=(7.0 7.4)

if [ ! -d "${UPSTREAM_DIR}/.git" ]; then
    git clone https://github.com/zabbix/zabbix-docker.git "$UPSTREAM_DIR"
fi

FAILED=0
for branch in "${BRANCHES[@]}"; do
    echo "==> Checking ${branch}"
    git -C "$UPSTREAM_DIR" fetch origin "$branch" --depth 1
    git -C "$UPSTREAM_DIR" checkout -f "origin/${branch}"

    PATCH_FILE="${REPO_ROOT}/patches/${branch}/armv7-skip-java-gateway.patch"
    if [ ! -f "$PATCH_FILE" ]; then
        echo "  no patch tracked for ${branch}, skipping"
        continue
    fi

    if (cd "$UPSTREAM_DIR" && patch -p1 --dry-run < "$PATCH_FILE" > /dev/null 2>&1); then
        echo "  OK: patch still applies cleanly"
    else
        echo "  FAILED: patch no longer applies cleanly against ${branch} -- needs updating" >&2
        FAILED=1
    fi
done

exit "$FAILED"
