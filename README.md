# OpenCode Unlimited — V2

Unofficial **OpenCode 2.x** port of [`opencode-unlimited-usage`](https://github.com/ElectronBreach/opencode-unlimited-usage):
a per-launch random Cloudflare edge + a rotating WARP IPv6 `/64`, behind a fail-closed
kill-switch, with automatic free-tier wall detection.

[فارسی](README.fa.md) · [Architecture](docs/ARCHITECTURE.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [V1 vs V2](docs/V1-V2.md) · [Security](SECURITY.md)

> [!WARNING]
> This is an unofficial community project, not affiliated with OpenCode or Cloudflare.
> Rotating network identity to extend a free tier may violate the provider's terms of
> service and can get your account limited. Use at your own risk.

---

## Why this fork exists

OpenCode 2 changed two things that break the original V1 scripts:

1. **Requests moved to a background server.** V2 has one shared server per user. The
   TUI is only a client. Pinning `/etc/hosts` inside a namespace does nothing if the
   server making the request lives outside it. The lane therefore forces a **private
   server** (`--standalone`) and the installer disables the shared one
   (`opencode service set disabled true`).
2. **The free-tier wall moved to SQLite.** V2 does not reliably write
   `provider.free-limit` to `opencode.log`. It stores the error in
   `session_message.data` inside `~/.local/share/opencode/opencode.db`. The guard now
   reads that database (read-only) and keeps the log scan as a fallback.

Everything else — WARP TUN mode, `/64` rotation, `OUC_LEAKGUARD` kill-switch, keeper —
is the original design.

---

## How it works

```text
            ┌──────────────────────────── opencode (wrapper) ───────────────────────────┐
            │  zen-lane.sh                                                             │
            │    unshare -rm  ──►  private mount namespace                             │
            │      /etc/hosts  ──►  opencode.ai = one random Cloudflare AAAA edge      │
            │      /etc/machine-id ──► fresh random                                    │
            │    exec opencode --standalone  ──► private server (same namespace)       │
            └───────────────────────────────────┬──────────────────────────────────────┘
                                                │ HTTPS via WARP TUN
                                                ▼
             Cloudflare WARP  ──►  a fresh IPv6 /64 per registration

  keeper (root service)          zen-guard (user service)
  ├─ force TUN mode              ├─ read session_message for provider.free-limit
  ├─ reconnect when down         ├─ on wall: blacklist /64, pause keeper
  └─ rebuild OUC_LEAKGUARD       ├─ re-register WARP, verify new /64
     (v4 + v6, fail closed)      └─ resume keeper, retry up to 8×

  zen-hop  = manual rotation      doctor = read-only health report
```

A free-tier wall no longer needs a restart: the guard changes the host's WARP
registration, so the next request from the running TUI leaves from a new `/64`.
Re-send the message after the rotation.

---

## Requirements

- Linux with systemd (tested on **Linux Mint 22.3** and **Ubuntu 24.04**)
- Python 3.10+, `curl`, `iptables`/`ip6tables`, `/dev/net/tun`
- Unprivileged user namespaces (`unshare -rm`)
- A network where Cloudflare WARP can connect
- `~/.local/bin` **before** `~/.opencode/bin` in `PATH` (the installer adds a
  removable block for this)

## Install

```bash
git clone https://github.com/asgtey/opencode-unlimited-v2.git
cd opencode-unlimited-v2
chmod +x install.sh uninstall.sh scripts/*.sh
./install.sh
exec $SHELL
opencode
```

The installer:

1. checks systemd, Python, curl, TUN and `unshare`;
2. installs/upgrades to OpenCode 2.x — **backing up V1 data first**;
3. runs `opencode service set disabled true`;
4. installs WARP (using the Ubuntu base codename, so Mint works);
5. installs the root `opencode-unlimited-keeper` service;
6. installs the user `opencode-unlimited-guard` service;
7. writes `~/.local/bin/opencode` → lane and a PATH block;
8. verifies IPv6 egress.

> Do **not** run it with `sudo`. It asks for sudo when needed.

## Verify

```bash
opencode --version                  # 2.x
opencode-unlimited-doctor           # all green (or a fix next to each red line)
opencode debug paths db             # session database actually in use
curl -6 -s https://api64.ipify.org  # 2606:... or 2a09:...
```

## Daily use

- When the free wall appears, **wait ~15–90 s** and **re-send** the message. The guard
  rotates automatically.
- Manual rotation: `opencode-unlimited-hop` (prints old/new `/64`; run again if
  Cloudflare returns the same block).
- Health: `opencode-unlimited-doctor`.
- Logs: `~/.local/share/opencode-unlimited/guard/guard.log` and
  `journalctl --user -u opencode-unlimited-guard -f`.

## Configuration

The installer writes these into the guard unit; all are optional overrides:

| Variable | Meaning |
|---|---|
| `OUC_REAL_BIN` | real OpenCode binary (never the wrapper) |
| `OUC_WARP_BIN` | `warp-cli` path |
| `OUC_KEEPER_UNIT` | keeper unit name (default `opencode-unlimited-keeper`) |
| `OUC_IPTABLES` / `OUC_IP6TABLES` | firewall binaries |
| `OUC_SYSTEMCTL` | `systemctl` path |

Paths used at runtime:

| Path | Purpose |
|---|---|
| `~/.local/share/opencode-unlimited/scripts/` | installed scripts |
| `~/.local/share/opencode-unlimited/guard/state.json` | blacklist + counters |
| `~/.local/share/opencode/opencode.db` | V2 session DB (read-only) |
| `~/.local/share/opencode/log/` | log fallback |
| `~/.local/share/opencode-unlimited-backups/` | V1 backup before upgrade |

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The five most common:

| Symptom | Fix |
|---|---|
| `unshare -rm` fails | enable `kernel.apparmor_restrict_unprivileged_userns=0` |
| `apt` rejects the WARP repo (`zena`) | repo line must use `noble` (installer handles it) |
| `opencode` bypasses the lane | `source ~/.config/opencode-unlimited/path.sh` |
| no IPv6 egress | WARP is not connected; check `warp-cli status` |
| internet dead after install | WARP unreachable → use the escape hatch in [SECURITY.md](SECURITY.md#emergency-exit) |

## Uninstall

```bash
cd opencode-unlimited-v2
./uninstall.sh
```

It stops and removes both services, flushes `OUC_LEAKGUARD`, removes the sudoers
file and the PATH block, restores `~/.local/bin/opencode`, and re-enables the V2
shared service. Your OpenCode data, sessions, auth and the V1 backup are untouched.

## Security model (short version)

- The kill-switch allows only loopback, LAN, established connections, WARP control
  ranges and the WARP interface. If the tunnel is down, traffic goes **nowhere**.
- The lane fails closed if `unshare` or the `/etc/hosts` bind fails.
- The guard/hop refuse to drop the tunnel when `OUC_LEAKGUARD` is missing.
- Residual risk: the IPv6 allow rule for `2606:4700::/32` is broad because WARP's
  control plane needs it. See [SECURITY.md](SECURITY.md) for hardening.
- `NOPASSWD` for `warp-cli` is required for unattended rotation; this is a
  single-user-desktop assumption.

## Compatibility

- OpenCode **2.x** (developed against 2.2.7). V1 has a partial fallback (log-based
  detection, no `--standalone`) but the installer targets V2.
- **Desktop app / IDE integrations bypass the wrapper** and therefore the per-launch
  edge pin. Only the terminal `opencode` goes through the lane.
- Pairing is unavailable while the shared service is disabled (V2 behaviour).

## Credits

- Original project: [ElectronBreach/opencode-unlimited-usage](https://github.com/ElectronBreach/opencode-unlimited-usage) (MIT).
- V2 adaptation: this repository.
- Not affiliated with OpenCode or Cloudflare.

## License

MIT — see [LICENSE](LICENSE). The original copyright notice is retained.
