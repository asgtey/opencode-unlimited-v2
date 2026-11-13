# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

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
- `uninstall.sh` re-enables the V2 shared service and removes the PATH block.

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

[2.0.0]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.0
