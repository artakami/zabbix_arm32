# Roadmap

## Background: why this project exists

Upstream `zabbix-docker` shipped working `linux/arm/v7` Alpine images through
Zabbix 6.4. Support was explicitly removed in September 2023
([commit `1b2b0f5cf`](https://github.com/zabbix/zabbix-docker/commit/1b2b0f5cf60d34da047049ddb7fadbc14cc6e9ee)),
confirmed by a Zabbix collaborator in
[issue #1427](https://github.com/zabbix/zabbix-docker/issues/1427) as a
CI-cost decision ("significantly increases building time... no real profit"),
not a technical wall — the Dockerfiles have no architecture-specific logic
blocking armv7. That tradeoff makes sense for Zabbix's release cadence and
scale; it doesn't apply to a small community project targeting MikroTik
RouterOS devices specifically.

The one real incompatibility found: `build-base` unconditionally installs a
JDK version (21, then 17 on the 7.0 branch) that Alpine doesn't ship for
`armhf` — blocking every downstream component, including ones like the proxy
that don't use Java at all. Fixed with a small patch that skips the Java
toolchain on `armv7` (see [`docs/building.md`](building.md)).

## Status

**proxy-sqlite3: validated end-to-end on real hardware.**

- Builds cleanly for `linux/arm/v7` on both tracked branches (7.0, 7.4) via
  a small, version-specific patch against upstream's `build-base`,
  `build-sqlite3`, and `build-mysql` Dockerfiles.
- Confirmed running on a real MikroTik L009UiGS-2HaxD-IN (IPQ-5018, 32-bit
  ARM) — not just under QEMU emulation.
- Confirmed connecting to a real Zabbix server over PSK-encrypted TLS as an
  active proxy, receiving and applying its configuration.
- Confirmed monitoring the router itself via SNMP through that proxy.
- Real-hardware validation surfaced several deployment issues that a CI
  build alone would never catch — see
  [`docs/mikrotik-container.md`](mikrotik-container.md) for all of them
  (networking/bridge setup, USB formatting, a RouterOS directory-creation
  trap, a firewall rule blocking the proxy from reaching the router's own
  SNMP service, an SNMP ACL restriction). None were image or patch bugs.
- Automated: `build-proxy.yml` (reusable, one branch) + `release.yml`
  (manual-dispatch, fans out across the version matrix), pushing versioned
  tags (`<branch>-armv7` and `<full-version>-armv7`) to
  `ghcr.io/artakami/zabbix-proxy-sqlite3`, with a smoke test gating the push.

**agent2: not yet started.** Uses the `build-mysql` path (already covered by
the existing patches), but has never been built, run, or connectivity-tested.
This is the next real gap — see [`docs/development.md`](development.md) for
the process to follow (it's largely a repeat of the proxy-sqlite3 work).

## Tracked versions

Only `7.0` and `7.4` — the branches that actually exist upstream. `7.2` was
considered but doesn't have a persistent branch in `zabbix/zabbix-docker`
(confirmed directly against the live repo, not a caching artifact) — Zabbix
appears to only maintain docker branches for LTS releases (6.0, 7.0) plus
the current release (7.4). `6.0` isn't tracked yet; its Dockerfile predates
some of the restructuring 7.0/7.4 share, so it would likely need its own
separate patch rather than reusing an existing one.

## Release automation

Manual-dispatch only, deliberately, while the pipeline itself is still new
and unproven at scale. Candidates for later, once this has run enough times
to be trusted:
- Scheduled rebuilds (to pick up new Zabbix point releases without manual
  triggering) — public repos get unlimited free GitHub Actions minutes, so
  this isn't a cost concern, just a "how much unattended automation do we
  trust yet" one.
- A `latest-armv7` tag alongside the versioned ones.

## Not yet done

- agent2 (see above — the immediate next real gap).
- Any component beyond proxy-sqlite3 and agent2 (server, web, java-gateway,
  snmptraps) — out of scope until the current two are solid.
- 6.0 branch support.
- Automated release triggers (see above).
