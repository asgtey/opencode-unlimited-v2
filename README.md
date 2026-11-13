# OpenCode Unlimited — V2

Bypass OpenCode's free-tier limit on Linux. **One command to install.** When the
wall hits, your IPv6 identity is rotated automatically and you keep working.

[فارسی](README.fa.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [Pairing](docs/PAIRING.md) · [How it works](docs/ARCHITECTURE.md) · [Security](SECURITY.md)

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

### Running as root? It creates the user for you

Everything is installed per user (`~`), and the guard is a **user** systemd service,
so it cannot live in `/root`. If you run the installer as root, it asks for two
things — a username and a password (typed twice, not shown) — then creates that
account, adds it to `sudo`, and continues as that user. Nothing else to do. The
password you chose is the one you log in with; no random one is printed.

Do not wrap the command in `sudo` as a normal user; the installer asks for sudo only
when it needs it.

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

### Logs

If something looks wrong, the guard's last lines usually say why:

```bash
tail -n 20 ~/.local/share/opencode-unlimited/guard/guard.log
```

`opencode-unlimited-doctor` prints the same picture in one screen. The file grows
slowly, so `-n 20` is normally enough; use `-n 100` after a busy day.

## Project that lives on your Windows or macOS host

Linux in a VM, project on the host? Share the folder into the VM and run `opencode`
inside it. The lane does not care where the files are.

**1. Host (VMware):** power the VM off, then `VM → Settings → Options → Shared
Folders` → **Always enabled** → **Add…** (host path, name, *Read-only* off).

**2. VM:**

```bash
sudo apt install -y open-vm-tools open-vm-tools-desktop
sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,uid=$(id -u),gid=$(id -g)
```

The `uid`/`gid` part is the important one: without it the files belong to `root`
and OpenCode cannot save.

**3. Open it:**

```bash
cd /mnt/hgfs/my-project
opencode            # or: opencode /mnt/hgfs/my-project
```

Two `git` commands you will probably need, because the files arrive owned by
another user id and marked executable:

```bash
git config --global --add safe.directory /mnt/hgfs/my-project
git -C /mnt/hgfs/my-project config core.filemode false
```

Shared folders have no symlinks and no file-change notifications, and they are slow
for `node_modules`/`venv`. SMB, SSHFS, VirtualBox, and how pairing fits in:
[docs/HOST-SHARING.md](docs/HOST-SHARING.md).

## Pair with your phone or another computer

Pairing is already set up. Just run:

```bash
opencode pair
```

Open the printed link, or scan the QR. It works once and expires after 5 minutes.
Different network? `opencode pair --remote`, or forward the port:
`ssh -L 49374:127.0.0.1:49374 user@server` — see [docs/PAIRING.md](docs/PAIRING.md).

Paired sessions still go through WARP and still get `/64` rotation, but not the
random edge. If you never pair, turn the shared server off with
`opencode service set disabled true`.

## Why this fork

OpenCode 2 changed two things that break the V1 scripts:

1. **Requests moved to a background server.** The TUI is only a client. So the lane
   forces a private server (`--standalone`) on every launch, and that private server
   is what gets the pinned edge.
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

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash -s -- --uninstall
```

Your sessions, auth and backups are untouched.

## Docs

- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — every error and its fix
- [docs/PAIRING.md](docs/PAIRING.md) — connect from another device with `opencode pair`
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the namespace, DB check and firewall work
- [docs/V1-V2.md](docs/V1-V2.md) — line-by-line diff with the upstream V1 scripts
- [docs/HOST-SHARING.md](docs/HOST-SHARING.md) — edit a project that lives on your Windows/macOS host
- [CONTRIBUTING.md](CONTRIBUTING.md) · [CHANGELOG.md](CHANGELOG.md)

## Credits

Original project: [ElectronBreach/opencode-unlimited-usage](https://github.com/ElectronBreach/opencode-unlimited-usage) (MIT).
V2 adaptation: this repository. MIT — see [LICENSE](LICENSE).
