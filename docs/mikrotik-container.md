# Running on MikroTik RouterOS (Container feature)

This guide covers deploying `zabbix-proxy-sqlite3:alpine-*-armv7` on a MikroTik
RouterOS 7.x device using the built-in Container feature. It's written from a
real deployment on an L009UiGS-2HaxD-IN (IPQ-5018, 32-bit ARM), and includes
the non-obvious gotchas that cost real debugging time — not just the happy path.

## Prerequisites

- RouterOS 7.4+ with the `container` package installed.
- Container mode enabled (`/system/device-mode`) — requires physical access to
  confirm (button press or cold reboot).
- External storage (USB/SSD) attached. Internal flash is not recommended for
  container storage (limited write cycles/capacity).
- **Architecture check**: RouterOS containers support three families — `arm`,
  `arm64`, `x86`. This image targets 32-bit `arm` (`linux/arm/v7`). One known
  exception: devices with the **EN7562CT** chip (e.g. hEX Refresh) only
  support `arm32v5` images and cannot run this build. Check your device's CPU
  architecture (`/system/resource/print`) before starting.

## 1. Storage

Format the disk **using RouterOS itself**, not a drive pre-formatted by
another OS — RouterOS's ext4 driver can be picky about certain ext4
features/inode sizes from foreign formatting tools, which manifests as a
generic, unhelpful `status=error` on the container with no clear log entry.

```
/disk/print detail
```

If it's not already `fs=ext4` and mounted (`BM` flags), reformat it via
RouterOS's own disk tools first.

## 2. Networking

Give the container its **own dedicated bridge and subnet** — don't reuse a
bridge or subnet from an existing container setup. Reusing one (e.g. copying
an example that uses `172.17.0.0/24`) risks silently colliding with another
container's network, leaving your new interface with a gateway address it has
no bridge path to reach — every connection attempt fails immediately with
"Destination Host Unreachable" from the container's own kernel, not even
attempting to leave.

```
/interface/bridge/add name=zbx-proxy-br
/ip/address/add address=172.18.0.1/24 interface=zbx-proxy-br
/interface/veth/add name=veth3 address=172.18.0.2/24 gateway=172.18.0.1
/interface/bridge/port/add bridge=zbx-proxy-br interface=veth3
/ip/firewall/nat/add chain=srcnat src-address=172.18.0.0/24 action=masquerade
```

Pick a subnet (`172.18.0.0/24` here) that doesn't overlap anything else
already configured on the router.

**If you ever change an existing veth's `address`/`gateway` via
`/interface/veth/set`**, be aware that an already-created container may keep
using the *old* address internally even after being stopped/started or fully
recreated — some stale state can persist. If `ip addr show` inside the
container (`/container/shell`) doesn't match what `/interface/veth/print`
claims, don't debug further — just tear down and rebuild the veth object
fresh (remove the bridge port, remove the veth, re-add both) rather than
trying to reconcile the drift.

### If the router's own firewall blocks the container

By default, many RouterOS configs end their `input` chain with a catch-all
like:

```
chain=input action=drop in-interface-list=!LAN
```

A container's bridge is very likely **not** in that `LAN` interface-list.
This silently drops any traffic *to the router itself* originating from the
container — for example, if this proxy also polls the router's own SNMP
service. The fix is a narrow, explicit accept rule (don't add the whole
bridge to `LAN` — that can implicitly grant broader access via other
LAN-scoped rules):

```
/ip/firewall/filter/add chain=input action=accept protocol=udp \
    src-address=172.18.0.0/24 in-interface=zbx-proxy-br dst-port=161 \
    place-before=<number-of-the-catch-all-drop-rule> \
    comment="SNMP from Zabbix proxy container"
```

Symptom to recognize this by: `/tool/sniffer` on the container's bridge shows
the outbound query leaving the container, but **zero reply packets ever come
back** — the packet is arriving at the router and being silently dropped by
`input`, before the target service (e.g. RouterOS's own SNMP agent) ever
gets a chance to respond.

## 3. Registry and container setup

```
/container/config/set registry-url=https://ghcr.io tmpdir=usb1/tmp
```

Match `tmpdir` to your actual disk name — it defaults to referencing `disk1`
in most examples online, which won't exist if your disk is named `usb1` (or
anything else). A mismatch here causes the image pull to fail during
extraction with no obviously-related error message.

### Give the container its own folder — but let it create that folder itself

Don't pre-create the `root-dir` path yourself (e.g. via the
`/file/add name=path/.keep` trick some guides suggest for working around
RouterOS's lack of a native `mkdir` before v7.15). A directory created that
way can end up with attributes the container engine's own extraction/pivot
logic doesn't handle correctly — the container will import successfully, show
`status=running` for a moment, then silently flip back to `stopped` with
**zero log output at any topic**, which is a very hard failure mode to
diagnose because every other layer (image pull, network, firewall) checks out
fine.

Instead, just point `root-dir` at a path that **doesn't exist yet** and let
`/container/add` create it as part of the pull:

```
/container/add remote-image=ghcr.io/artakami/zabbix-proxy-sqlite3:alpine-7.4-armv7 \
    interface=veth3 \
    root-dir=usb1/zbxproxy \
    envlist=zbx-proxy-env \
    logging=yes
```

Keeping each container in its own named subfolder (rather than dumping
straight onto the disk root) matters once you run more than one container on
the same disk — the disk root otherwise fills up with a loose, unlabeled copy
of every container's entire filesystem (`bin/`, `etc/`, `usr/`, `var/`...).

Give the pull time to fully finish before checking status or starting it —
checking `/container/print detail` too early mid-pull can make it look like
nothing happened.

```
/container/print detail
/container/start [find tag~"zabbix-proxy-sqlite3"]
```

## 4. Configuration via environment variables (PSK-encrypted, active proxy)

The image reads `ZBX_*` variables directly — Zabbix 7.4 added native
`${ZBX_VAR}` substitution inside the config parser itself, so nothing in the
entrypoint needs to rewrite the config file for these. Set them as a RouterOS
env-list (never hardcode server address, proxy name, or the PSK key into
anything that goes in git — this is a public repo):

```
/container/envs/add name=zbx-proxy-env key=ZBX_HOSTNAME value="<proxy-name>"
/container/envs/add name=zbx-proxy-env key=ZBX_SERVER_HOST value="<server-address>"
/container/envs/add name=zbx-proxy-env key=ZBX_TLSCONNECT value="psk"
/container/envs/add name=zbx-proxy-env key=ZBX_TLSPSKIDENTITY value="<psk-identity>"
/container/envs/add name=zbx-proxy-env key=ZBX_TLSPSK value="<psk-hex-key>"
```

Generate the key yourself (`openssl rand -hex 32`), and configure the
matching PSK identity/value on the Zabbix server side under
**Data collection → Proxies → (your proxy) → Encryption →
Connections from proxy: PSK**.

Attach the env-list and (re)start:

```
/container/set [find tag~"zabbix-proxy-sqlite3"] envlist=zbx-proxy-env
/container/stop [find tag~"zabbix-proxy-sqlite3"]
/container/start [find tag~"zabbix-proxy-sqlite3"]
```

Success looks like, in `/log/print where topics~"container"`:

```
received configuration data from server at "<server-address>", datalen ...
```

Proxy mode (active/passive) only affects how the proxy talks to the
**server** — it has no effect on how the proxy polls monitored hosts (SNMP,
agent, etc.), which always happens the same way regardless.

## 5. Monitoring the router itself via SNMP through this proxy

A common setup: this proxy also monitors the host router's own health (CPU,
interfaces, temperature) via SNMP. That means traffic flows in the opposite
direction from everything above — *from* the container *to* the router
itself — which hits RouterOS's own firewall and SNMP access control, not
just the proxy's network path.

### Enable SNMP and create credentials

```
/snmp/set enabled=yes
```

RouterOS's "SNMP Community" dialog (`/snmp/community`) is overloaded: when
it shows Authentication Protocol / Encryption Protocol fields and a
`security` setting, it's actually configuring an **SNMPv3 USM user**, not a
plain v1/v2c community string, despite the label. Create one for Zabbix to
use — start with just the server's own address; the container's subnet gets
added next:

```
/snmp/community/add name=zabbix addresses=<zabbix-server-ip>/32 \
    security=private read-access=yes \
    authentication-protocol=MD5 authentication-password=<auth-passphrase> \
    encryption-protocol=AES encryption-password=<priv-passphrase>
```

### Allow the container's subnet to query it too

Once the *proxy* is responsible for polling this host instead of the server
polling it directly, queries arrive from the container's subnet, not the
server's IP. Add it to the same community's allow-list rather than creating
a second one:

```
/snmp/community/set [find name=zabbix] \
    addresses=<zabbix-server-ip>/32,172.18.0.0/24
```

### Open the firewall for it

The community's address list alone isn't enough — RouterOS's `input` chain
(see the catch-all `drop` note in section 2) will silently drop the query
before the SNMP service ever evaluates it. Find where that catch-all rule
sits:

```
/ip/firewall/filter/print where chain=input
```

Note the `#` of the final `drop`-everything rule (commonly something like
`action=drop in-interface-list=!LAN`), then insert an explicit accept
*before* it — don't add the whole bridge to `LAN` instead, that can
implicitly grant broader access via other LAN-scoped rules:

```
/ip/firewall/filter/add chain=input action=accept protocol=udp \
    src-address=172.18.0.0/24 in-interface=zbx-proxy-br dst-port=161 \
    place-before=<number-of-the-catch-all-drop-rule-from-above> \
    comment="SNMP from Zabbix proxy container"
```

**`in-interface=zbx-proxy-br` is load-bearing, not incidental** — it scopes
this accept rule to traffic arriving specifically via the container's own
internal bridge. Port 161 is never opened on the WAN/internet-facing
interface by this rule; a request claiming to be from `172.18.0.0/24` but
arriving on any other interface (including WAN) still gets caught by the
catch-all drop, exactly as before. Never broaden this to
`in-interface-list=LAN` or drop the `in-interface` match entirely just to
make it work faster — if it's still failing, the fix is finding the real
cause (see the verification step below), not widening the rule. This is a
separate, internal-only accept, unrelated to whatever rule you may already
have allowing SNMP from `in-interface-list=WAN` for the Zabbix *server*
polling the router directly (if you have one) — don't reuse or widen that
one for the container either.

### Configure the matching SNMP interface on the Zabbix host

On the host object being monitored (the router itself), the SNMP interface
must match exactly what you just created — this is the part that's easy to
get subtly wrong, since RouterOS's terminology doesn't map obviously onto
Zabbix's UI fields:

| Zabbix field | Value |
|---|---|
| SNMP version | **v3** |
| Security name | the community `name=` above (`zabbix`) |
| Security level | **authPriv** — RouterOS's `security=private` means both authentication *and* privacy/encryption |
| Authentication protocol / passphrase | matches `authentication-protocol` / `authentication-password` |
| Privacy protocol / passphrase | matches `encryption-protocol` / `encryption-password` |

A mismatch here (e.g. Zabbix configured for v2c, or `authNoPriv` instead of
`authPriv`) fails as a plain timeout, with no "wrong credentials" error —
indistinguishable from the firewall dropping it, which is why the next step
matters.

### Verify it actually works end to end

```
/tool/sniffer quick interface=zbx-proxy-br ip-address=<router-ip>/32 port=161
```

Trigger a check from Zabbix (**Monitoring → Latest data** → the item →
**Execute now**) while the sniffer runs. This works even with an active
proxy — the server queues the request and the proxy picks it up on its own
next check-in, not instantly, but there's no need to wait for a full polling
interval. Then read the result:

- **No packets captured at all** — the query isn't reaching this interface;
  recheck the container's own networking (section 2), not the SNMP config.
- **Query goes out, no reply comes back** — it's reaching the router but
  getting dropped before the SNMP service responds. Almost always the
  firewall `input` chain — double-check the accept rule above is genuinely
  placed *before* the catch-all drop, not after it.
- **Query and reply both appear** — it's working; Zabbix's cached
  "Not available" status on the host just hasn't refreshed yet.

## Troubleshooting checklist

When something isn't working, check in this order — it's the order that
actually narrows things down fastest, since each check rules out an entire
layer:

1. `/container/print detail` — status, and whether `arch` populated (blank
   `arch=""` means it never even got as far as reading the image manifest —
   almost always a network/registry-reachability problem, not an image
   problem).
2. `/log/print` — **unfiltered**, not just `where topics~"container"`. Some
   failures log under different topics, and filtering too early can hide the
   one line that matters.
3. `/container/shell [find tag~"..."]` — if it's running, test connectivity
   directly from inside: `ping`, `traceroute`. Confirms whether the container
   itself has a working network path before blaming anything downstream.
4. `/tool/sniffer quick interface=<bridge> ip-address=<target>/32 port=<port>`
   — ground truth for whether packets are actually leaving/arriving, versus
   inferring from symptoms.
5. `/ip/firewall/filter/print where chain=input` and
   `where chain=forward` — check both. `input` governs traffic *to the
   router itself* (e.g. SNMP queries the container sends to the router);
   `forward` governs traffic passing *through* the router to somewhere else.
   They're evaluated differently and a fix in one won't help a problem in the
   other.
