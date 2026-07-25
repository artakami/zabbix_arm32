# Changelog

## [Unreleased]

### Added
- `patches/7.0/` and `patches/7.4/` — branch-specific patches skipping the
  Java toolchain on `armv7` in `build-base`, `build-sqlite3`, and
  `build-mysql`, unblocking the one real incompatibility preventing upstream
  Dockerfiles from building for `linux/arm/v7`.
- `build-proxy.yml` (reusable) and `release.yml` (manual-dispatch entry
  point) — builds, smoke-tests, and publishes versioned
  `ghcr.io/artakami/zabbix-proxy-sqlite3` tags across the tracked version
  matrix.
- `scripts/build.sh`, `scripts/test-image.sh`, `scripts/update-upstream.sh`
  — local equivalents of what CI does, including a smoke test that catches
  architecture mismatches a successful build alone wouldn't.
- `docs/roadmap.md`, `docs/building.md`, `docs/development.md`,
  `docs/mikrotik-container.md` — real content, based on an actual
  investigation and a real hardware deployment (MikroTik L009UiGS-2HaxD-IN),
  not placeholders.
- proxy-sqlite3 validated end-to-end on real ARMv7 hardware: builds, starts,
  connects to a Zabbix server over PSK-encrypted TLS as an active proxy, and
  monitors the host router itself via SNMP.

### Removed
- `docker/proxy-sqlite3/Dockerfile`, `docker-entrypoint.sh`, and
  `patches/arm32.patch` — empty placeholders from an earlier "fork upstream's
  Dockerfile" plan that was superseded by the patch-against-upstream
  approach (see `docker/proxy-sqlite3/README.md` for why).
- `test-proxy-armv7.yml` — the original manual proof-of-concept workflow,
  superseded by `build-proxy.yml`/`release.yml`.
