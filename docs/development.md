# Development

## Project structure

```
docker/<component>/README.md   -- why this component needs (or doesn't need) a patch
patches/<branch>/*.patch        -- Dockerfile-level patches against upstream, per branch
scripts/                        -- local build/test/maintenance helpers, mirrors CI
.github/workflows/
  build-<component>.yml         -- reusable: build + smoke-test + push, one branch
  release.yml                   -- manual-dispatch entry point, fans out to build-*.yml
docs/                           -- this directory
```

There is deliberately no forked copy of any upstream Dockerfile in this
repo. See [`docker/proxy-sqlite3/README.md`](../docker/proxy-sqlite3/README.md)
for why — the guiding principle for this whole project is **minimum diff
against upstream**, so every other upstream change (security fixes,
dependency bumps, new features) is inherited automatically instead of having
to be manually re-ported into a fork.

## Relationship to upstream

Upstream (`zabbix/zabbix-docker`) dropped `linux/arm/v7` from its build
matrix in 2023 for CI-cost reasons that don't apply to a small,
MikroTik-focused community project — not because of a technical
incompatibility. The one real blocker (an unconditional JDK install that
Alpine doesn't ship for `armhf`) is fixed by a small patch; see
[`docs/roadmap.md`](roadmap.md) for the full investigation.

This means the patches in `patches/` are the entire surface area this
project actively maintains. When upstream changes something that breaks a
patch, `scripts/update-upstream.sh` catches it (see
[`docs/building.md`](building.md)) — regenerate the patch the same way the
original was made: edit a fresh upstream checkout by hand, then
`git diff` to capture the new patch.

## Adding a new tracked component (e.g. agent2)

The proxy-sqlite3 setup is the template. Repeat the same steps:

1. Confirm which upstream Dockerfile(s) the component depends on (check
   `docker-bake.hcl`'s `depends_on`/`context` for the target — agent2 uses
   `build-mysql`, not `build-sqlite3`).
2. Check whether the existing patches already cover that dependency (the
   `armv7-skip-java-gateway` patches already touch `build-mysql`, so agent2
   may need no new patch at all — verify with `scripts/build.sh` before
   assuming).
3. Add a `build-<component>.yml` reusable workflow mirroring
   `build-proxy.yml`, and extend `release.yml`'s matrix/inputs.
4. Validate on real hardware before calling it done — a successful CI build
   does not guarantee the binary behaves correctly on real ARMv7 silicon
   (see [`docs/mikrotik-container.md`](mikrotik-container.md) for what real
   hardware validation actually surfaced for proxy-sqlite3: networking,
   storage, and firewall issues that a build-only check would never catch).

## Adding a new tracked Zabbix branch

Only branches that actually exist upstream can be tracked — verify with
`git ls-remote --heads https://github.com/zabbix/zabbix-docker.git` before
assuming a version (e.g. non-LTS releases like 7.2 don't get a persistent
branch). To add one:

1. `scripts/update-upstream.sh` will tell you if an *existing* patch happens
   to apply cleanly to the new branch — it usually won't, since JDK
   versions and `case` statement branches drift between releases.
2. If it doesn't apply cleanly, create `patches/<branch>/` with a
   branch-specific patch (same process as adding any patch — see
   [`docs/building.md`](building.md)).
3. Add the branch to the `BRANCHES` array in `scripts/update-upstream.sh`,
   and to the `options`/matrix logic in `release.yml`.

## Testing expectations

- Every build is smoke-tested (`scripts/test-image.sh`) before being pushed
  to GHCR — confirms the binary executes under emulation and the container
  doesn't crash-loop.
- That is necessary but not sufficient. A build that passes the smoke test
  can still fail on real hardware for reasons emulation can't catch
  (hardware-specific networking, storage driver quirks, etc.) — see
  [`docs/mikrotik-container.md`](mikrotik-container.md) for the real issues
  found this way. Validate on actual MikroTik hardware before trusting a new
  version or component.
