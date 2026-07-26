# Building

## How a build works

Each component is built by checking out upstream
[`zabbix/zabbix-docker`](https://github.com/zabbix/zabbix-docker) fresh at
the target branch, applying a small patch, then running upstream's own
`Makefile`/`docker-bake.hcl` unmodified for `linux/arm/v7`. There is no
forked Dockerfile to keep in sync — see
[`docker/proxy-sqlite3/README.md`](../docker/proxy-sqlite3/README.md) for why.

Patches live under `patches/<branch>/` (e.g. `patches/7.4/`) because the
exact file content they target differs enough between branches (different
default JDK version, different `case` statement branches) that one patch
can't cleanly apply to all of them — verified by hand when 7.0 was added.

## Prerequisites

- Docker with Buildx.
- QEMU registered for `arm` emulation:
  ```
  docker run --privileged --rm tonistiigi/binfmt --install arm
  ```
- `patch` and `make` (present on any Linux/macOS shell; use WSL or Git Bash
  on Windows).

## Building locally

```
scripts/build.sh 7.4 proxy-sqlite3
```

This clones upstream into `upstream/` (gitignored — safe to delete and
re-run), applies `patches/7.4/armv7-skip-java-gateway.patch`, and produces a
local image tagged `zabbix-proxy-sqlite3:alpine-7.4-armv7`.

First argument is the upstream branch (`7.0` or `7.4` currently tracked —
see [`docs/roadmap.md`](roadmap.md) for why not others). Second argument is
the bake target; defaults to `proxy-sqlite3`. For agent2:

```
scripts/build.sh 7.4 agent2-mysql
```

(Note the bake *target* name is `agent2-mysql` — it depends on `build-mysql`
rather than `build-sqlite3` — but the resulting local image tag is
`zabbix-agent2:alpine-7.4-armv7`, matching upstream's own `tags=` in
`docker-bake.hcl`.)

## Smoke-testing a built image

```
scripts/test-image.sh zabbix-proxy-sqlite3:alpine-7.4-armv7 zabbix_proxy
scripts/test-image.sh zabbix-agent2:alpine-7.4-armv7 zabbix_agent2
```

Confirms the binary actually executes under emulation and the container
stays running rather than crash-looping — a build that succeeds doesn't
guarantee the resulting binary is actually correct for the target
architecture (QEMU can produce a binary that links fine but misbehaves).
This is the same check the CI release workflow runs before pushing to GHCR.

## Checking a patch still applies before it breaks CI

```
scripts/update-upstream.sh
```

Refreshes the local upstream checkout and dry-run checks every tracked
branch's patch. Run this before cutting a release, or whenever you suspect
upstream has changed something relevant (a new Zabbix point release, a
Dockerfile restructuring). A patch that stops applying cleanly needs to be
regenerated the same way the original ones were: edit a fresh checkout of
the affected Dockerfile(s) by hand, then `git diff` to capture the new patch
(see the commit history of `patches/` for the exact process used for 7.0 and
7.4).

## CI build/release pipeline

- [`build-proxy.yml`](../.github/workflows/build-proxy.yml) is a reusable
  workflow that builds, smoke-tests, and pushes one branch's proxy-sqlite3
  image to GHCR.
- [`release.yml`](../.github/workflows/release.yml) is the manual-dispatch
  entry point — pick a branch (or `all`) and it fans out to `build-proxy.yml`
  per branch. Images are pushed as `ghcr.io/artakami/zabbix-proxy-sqlite3:
  <branch>-armv7` (e.g. `7.4-armv7`) and `:<full-version>-armv7` (e.g.
  `7.4.12-armv7`).

Currently manual-dispatch only, by design, while the pipeline itself is
still new — see [`docs/roadmap.md`](roadmap.md) for the reasoning and what
might change later (e.g. scheduled rebuilds to catch new Zabbix point
releases automatically).
