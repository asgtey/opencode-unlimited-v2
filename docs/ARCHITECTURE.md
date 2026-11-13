# Architecture

## Processes

```text
opencode (wrapper)  ── exec ──►  zen-lane.sh
                                  │  unshare -rm bash -c ...
                                  │    mount --bind hosts /etc/hosts
                                  │    mount --bind machine-id /etc/machine-id
                                  │    opencode --standalone
                                  ▼
                              private server (child, same mount ns)
                                  │  HTTPS to opencode.ai
                                  ▼
                              WARP TUN (host-wide)
```

The private server is the important part. In V2 a client normally discovers the
shared background server; that server lives in the host mount namespace and would
resolve `opencode.ai` with the host's `/etc/hosts`. `--standalone` makes the TUI
spawn its own `serve --stdio --port 0` child, which inherits the lane's namespace.

`opencode service set disabled true` makes private servers the default and stops
the shared one, so even subcommands that do not receive the flag stay private.

## Namespace contents

| File | Value |
|---|---|
| `/etc/hosts` | `opencode.ai`, `www.opencode.ai`, `api.opencode.ai` → one random AAAA from `dig` (or Python, or a built-in anycast list) |
| `/etc/machine-id` | 32 random hex chars (not used by V2; defence in depth) |

The bind mount is the only filesystem change inside the namespace. The scratch
directory is removed on exit; if the process is killed, the namespace disappears
with it and the host files are untouched.

## Wall detection

V2 refuses a free-tier request by storing an assistant message whose JSON contains:

```json
"error": {
  "type": "provider.free-limit",
  "data": { "message": "FreeUsageLimitError ... Free usage limit reached ..." }
}
```

in `session_message.data`. Go / workspace / budget limits use
`provider.go-limit` and `provider.budget-limit`; those are deliberately **not**
matched, because a new IP does not reset them.

The guard:

1. reads `MAX(time_updated)` for matching rows newer than the last seen wall;
2. falls back to tailing `*.log` with a byte offset if the DB is unavailable;
3. sets `pending=1`;
4. after the 75 s cooldown: blacklist the current `/64`, stop the keeper, delete the
   WARP registration, register a new one, reconnect, verify a non-empty IPv6, resume
   the keeper;
5. retries up to 8 times if Cloudflare returns a blacklisted `/64`.

## `/64` normalisation

`ipaddress.ip_network(addr + "/64", strict=False)` is used everywhere. The old
`":".join(addr.split(":")[:4])` approach corrupts compressed addresses such as
`2606:4700::1`.

## Kill-switch

`warp-keeper.sh` (unchanged from upstream) rebuilds two chains every 45 s:

```text
iptables  OUC_LEAKGUARD: lo, established, RFC1918, 162.159/16, 188.114/16, -o CloudflareWARP → DROP
ip6tables OUC_LEAKGUARD: lo, established, fe80::/10, 2606:4700::/32, -o CloudflareWARP → DROP
```

Both are inserted at the top of `OUTPUT`. If the tunnel dies, the DROP rules remain,
so traffic does not fall back to the physical interface.

## File map

| File | Role |
|---|---|
| `get.sh` | one-command bootstrap: fetch bundle → `install.sh` / `uninstall.sh` |
| `install.sh` | install/upgrade, services, sudoers, wrapper, PATH, verification |
| `uninstall.sh` | full removal, restores V2 defaults |
| `scripts/warp-keeper.sh` | root service: TUN mode + kill-switch |
| `scripts/zen-lane.sh` | per-launch namespace + edge pin + `--standalone` |
| `scripts/zen-guard.sh` | DB/log wall detector + automatic rotation |
| `scripts/zen-hop.sh` | manual rotation |
| `scripts/doctor.sh` | read-only diagnostics |

## State

`~/.local/share/opencode-unlimited/guard/state.json`

```json
{
  "blacklist": ["2a09:bac5:31cc:3773::/64"],
  "last_hop": 1794490453,
  "hops": 2,
  "current": "2a09:bac5:31cc:2864::406:49",
  "pending": 0,
  "last_wall_ms": 1794490452702
}
```

`last_wall_ms` is the high-water mark so historical walls are not replayed after a
restart. Log offsets live next to it as `off.<logfile>`.
