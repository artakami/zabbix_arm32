# proxy-sqlite3 (ARMv7)

Community-maintained ARMv7 build of `zabbix/zabbix-proxy-sqlite3`.

## Why this doesn't contain a Dockerfile

Upstream `zabbix-docker` dropped `linux/arm/v7` from its build matrix in 2023
(CI cost, not a technical blocker — see
[`docs/roadmap.md`](../../docs/roadmap.md)). Its Dockerfiles have no
architecture-specific logic blocking armv7 — the one real incompatibility is
that `build-base` unconditionally installs a JDK version Alpine doesn't ship
for `armhf`, which every downstream component (including this one) inherits
even though a Zabbix proxy doesn't use Java at all.

Rather than fork and maintain a full copy of upstream's Dockerfile, this
component works by:

1. Checking out the upstream `zabbix-docker` repo fresh at build time (see
   [`.github/workflows/build-proxy.yml`](../../.github/workflows/build-proxy.yml)).
2. Applying a small patch from [`patches/<branch>/`](../../patches/) that
   skips the Java toolchain specifically on `armv7` in `build-base`,
   `build-sqlite3`, and `build-mysql`.
3. Running upstream's own `Makefile`/`docker-bake.hcl` unmodified for
   `linux/arm/v7`.

This keeps the diff against upstream minimal and automatically picks up
every other upstream change (security fixes, dependency bumps, new plugins)
without us having to track or re-port them into a forked Dockerfile.

See [`docs/building.md`](../../docs/building.md) for how to reproduce a build
locally, and [`docs/mikrotik-container.md`](../../docs/mikrotik-container.md)
for deploying the resulting image on MikroTik RouterOS.