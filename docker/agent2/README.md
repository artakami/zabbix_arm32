# agent2 (ARMv7)

Community-maintained ARMv7 build of `zabbix/zabbix-agent2`.

Same approach as [`proxy-sqlite3`](../proxy-sqlite3/README.md): no forked
Dockerfile. Upstream's own Dockerfile/`Makefile`/`docker-bake.hcl` are used
unmodified, with the same `patches/<branch>/armv7-skip-java-gateway.patch`
applied at build time (it already covers `build-mysql`, which agent2 depends
on — verified before adding this component, no new patch was needed).

Built via [`build-agent2.yml`](../../.github/workflows/build-agent2.yml),
targeting upstream's `agent2-mysql` bake target
(`Dockerfiles/agent2/alpine`, depends on `build-mysql`).

See [`docs/building.md`](../../docs/building.md) for how to build and
smoke-test locally, and [`docs/mikrotik-container.md`](../../docs/mikrotik-container.md)
for deploying on MikroTik RouterOS (the same networking/storage/firewall
setup that applies to proxy-sqlite3 applies here too).
