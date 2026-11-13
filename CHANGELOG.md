# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [2.0.1] — 2026-11-13

Documentation and packaging pass: install with a single command, simpler docs,
right-to-left Persian README.

### Added

- `get.sh` — one-command bootstrap:
  `curl -fsSL .../main/get.sh | bash`. It downloads the bundle to a temp directory,
  runs `install.sh` (or `uninstall.sh` with `--uninstall`) with `/dev/tty` on stdin
  so sudo can prompt, then deletes the directory. Falls back to `git clone` if
  `codeload` is unreachable, and honours `OUC_REF` / `OUC_REPO` for forks and tags.
- One-command uninstall in the docs.

### Changed

- `README.md` rewritten: shorter, plain language, one-command install first.
- `README.fa.md` rewritten as right-to-left HTML so Persian renders justified and
  tidy on GitHub, with lists instead of tables.
- `uninstall.sh` restores the desktop app's bundled CLI before deleting the scripts
  it points at.
- `Makefile` and CI also syntax-check `get.sh`.

## [2.0.0] — 2026-11-13

First public release of the OpenCode 2.x port.

### Added

- `zen-lane.sh` forces a private V2 server (`--standalone`) so provider requests are
  made inside the namespace that pins `opencode.ai`.
- `zen-guard.sh` reads the free-tier wall from `session_message` in the V2 session
  database (read-only) and keeps the log tail as a fallback.
- `doctor.sh` reports V2 version, `unshare -rm`, `service.json`, DB readability,
  kill-switch chains, IPv6 egress and wrapper/PATH resolution.
- `zen-hop.sh` manual rotation with kill-switch gate and `/64`-aware comparison.
- `desktop-patch.sh` wraps the desktop app's bundled CLI (`resources/opencode-cli`)
  so its private server runs through the lane; supports `install`, `undo`, `status`.
- `install.sh` backs up V1 data (`opencode.db`, `auth.json`, `storage/`, config)
  before the one-way V2 migration.
- `install.sh` detects the real binary without selecting its own wrapper.
- `install.sh` writes sudoers rules for `systemctl stop/start` of the keeper.
- `install.sh` adds a removable `PATH` block so `~/.local/bin` wins.
- Docs: architecture, V1→V2 diff, troubleshooting, security model, Persian README.

### Changed

- WARP apt repository uses `UBUNTU_CODENAME` (Linux Mint reports `zena`, not
  `noble`).
- `/64` blacklist normalisation uses Python `ipaddress` instead of string slicing.
- Guard and hop refuse to take the tunnel down when `OUC_LEAKGUARD` is missing.
- Log fallback accepts both a log directory and a log file.
- `uninstall.sh` re-enables the V2 shared service, removes the PATH block and
  restores the desktop app's bundled CLI if it was patched.

### Removed

- Credit/`AGENTS.md` injection. V2 reads global instructions from
  `~/.config/opencode/AGENTS.md`; the feature was unrelated to IP rotation.

### Fixed

- Wrapper recursion when re-running the installer.
- `$HOME`-relative sudoers paths that broke on distributions with `/usr/sbin` only.
- `exec` in the lane skipping scratch-directory cleanup.
- `cur_v6` could report IPv4; both guard and hop now force `curl -6`.

### Security

- Lane fails closed on `unshare -rm` or `/etc/hosts` bind failure.
- Guard/hop abort rotation if the kill-switch chain is missing.
- Broad `2606:4700::/32` allow rule documented with an owner-scoped hardening
  variant.

[2.0.1]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.1
[2.0.0]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.0
