# zabbix_arm32

Community-maintained `linux/arm/v7` Docker images for Zabbix components,
built from unmodified upstream [`zabbix-docker`](https://github.com/zabbix/zabbix-docker)
plus a small patch — not a fork. Tested on real MikroTik RouterOS hardware,
not just under emulation.

Upstream dropped `armv7` support in 2023 for CI-cost reasons that don't apply
to a small community project (see [`docs/roadmap.md`](docs/roadmap.md) for
the full investigation, including why it's safe to reintroduce).

## Images

| Component | Status | Image |
|---|---|---|
| proxy-sqlite3 | Validated on real hardware (build, run, PSK-encrypted server connection, SNMP) | `ghcr.io/artakami/zabbix-proxy-sqlite3` |
| agent2 | In progress — build pipeline exists, not yet validated on real hardware | `ghcr.io/artakami/zabbix-agent2` |

Tracked Zabbix branches: `7.0`, `7.4` (see [`docs/roadmap.md`](docs/roadmap.md)
for why not `7.2` or `6.0` yet).

Tags: `<branch>-armv7` (e.g. `7.4-armv7`) and `<full-version>-armv7` (e.g.
`7.4.12-armv7`).

## Quick start

```
docker pull ghcr.io/artakami/zabbix-proxy-sqlite3:7.4-armv7
```

For MikroTik RouterOS specifically (Container feature), see
[`docs/mikrotik-container.md`](docs/mikrotik-container.md) — it covers real
gotchas found during hardware validation (networking setup, storage
formatting, a RouterOS directory-creation trap, firewall/SNMP configuration)
that aren't obvious from RouterOS's own docs.

## Building it yourself

See [`docs/building.md`](docs/building.md).

## License

This repo's own tooling (patches, workflows, scripts, docs) is
[MIT-licensed](LICENSE). The resulting Docker images contain Zabbix itself,
which is [AGPL v3.0](https://github.com/zabbix/zabbix/blob/master/COPYING).
