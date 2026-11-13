# OpenCode Unlimited — V2

Bypass OpenCode's free-tier limit on Linux. **One command to install.** When the
wall hits, your IPv6 identity is rotated automatically and you keep working.

[فارسی](README.fa.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [How it works](docs/ARCHITECTURE.md) · [Security](SECURITY.md)

> **Unofficial.** Not affiliated with OpenCode or Cloudflare. Rotating identity to
> extend a free tier may break the provider's terms. Use at your own risk.

---

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash
```

Then close and reopen your terminal, and run `opencode` like always.

The command downloads this repo to a temp folder, runs `install.sh` (it asks for
sudo), and deletes the folder afterwards. No `git` needed.

**Requirements:** Linux with systemd, `sudo`, `python3`, and a network where
Cloudflare WARP can connect. Tested on Linux Mint 22.3 and Ubuntu 24.04.

If unprivileged user namespaces are blocked (Ubuntu 24.04 and Mint 22.x do this by
default), the installer stops and prints the one-line `sysctl` fix. Run it, then run
the install command again.

## When the limit hits

1. Do nothing.
2. Wait 15–90 seconds (`zen-guard` is rotating your `/64`).
3. Re-send the message.

Manual rotation, if you want a new identity right now:

```bash
opencode-unlimited-hop
```

Health check:

```bash
opencode-unlimited-doctor
```

## What it installs

| Piece | Job |
|---|---|
| `zen-lane` | runs `opencode` with a random Cloudflare edge and a private server |
| `zen-guard` | watches for the limit error, rotates WARP to a fresh `/64` |
| `warp-keeper` | root service: keeps WARP up and keeps the kill-switch installed |
| `zen-hop` | manual "give me a new `/64`" |
| `doctor` | read-only health report |

Everything lives in `~/.local/share/opencode-unlimited/`. System touches are two
systemd units, one sudoers file and one firewall chain — all removed by
`uninstall.sh`.

## Why this fork

OpenCode 2 changed two things that break the V1 scripts:

1. **Requests moved to a background server.** The TUI is only a client. So the
   lane forces a private server (`--standalone`) and the installer disables the
   shared one (`opencode service set disabled true`).
2. **The limit error moved to SQLite.** V2 stores it in
   `~/.local/share/opencode/opencode.db`, not in the log. The guard reads that
   database (read-only) and keeps the log as a fallback.

The WARP trick itself, the `/64` rotation and the kill-switch are unchanged.

## Safety

- Kill-switch is **fail-closed**: tunnel down → traffic goes nowhere, never out of
  your real IP.
- The lane refuses to start if the namespace or the `/etc/hosts` pin fails.
- Rotation is refused if the kill-switch chain is missing.
- Emergency exit and residual risks: [SECURITY.md](SECURITY.md).

## Desktop app

The desktop app runs its own bundled CLI, so it skips the lane. Optional fix:

```bash
~/.local/share/opencode-unlimited/scripts/desktop-patch.sh install
```

Run it again after every app update. `undo` puts the original back.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash -s -- --uninstall
```

Your sessions, auth and backups are untouched.

## Docs

- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — every error and its fix
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the namespace, DB check and firewall work
- [docs/V1-V2.md](docs/V1-V2.md) — line-by-line diff with the upstream V1 scripts
- [CONTRIBUTING.md](CONTRIBUTING.md) · [CHANGELOG.md](CHANGELOG.md)

## Credits

Original project: [ElectronBreach/opencode-unlimited-usage](https://github.com/ElectronBreach/opencode-unlimited-usage) (MIT).
V2 adaptation: this repository. MIT — see [LICENSE](LICENSE).
