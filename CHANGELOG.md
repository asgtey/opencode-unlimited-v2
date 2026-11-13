# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [SemVer](https://semver.org/).

## [2.0.7] — 2026-11-13

The repository is public again: one command, no access code.

### Changed

- `asgtey/opencode-unlimited-v2` is public. Install and uninstall go back to the
  plain one-liners on this repository's own `get.sh`.
- `get.sh` no longer requires a code. `--token` / `OUC_TOKEN` is still accepted (and
  silently used) for forks and private mirrors; without it the public mirrors
  (codeload, then `git clone`) are used.
- `docs/ACCESS.md` now says access is open, and keeps the note for anyone who still
  has an old code.

### Removed

- The "private repository / access code required" wording from both READMEs,
  `docs/TROUBLESHOOTING.md` and `docs/ARCHITECTURE.md`.

## [2.0.6] — 2026-11-13

### Changed

- The guard log command —
  `tail -n 20 ~/.local/share/opencode-unlimited/guard/guard.log` — is now in both
  READMEs, `docs/TROUBLESHOOTING.md`, the installer's closing hints, and the last
  line of `doctor.sh`. It was already buried in the bug-report section.

## [2.0.5] — 2026-11-13

Access is now controlled: the repo is private and installs need a personal code.
The root install also asks for the password instead of generating one.

### Added

- **Access codes.** The bundle lives in a private repository and is fetched through
  the public launcher `asgtey/ou-start`. Each person gets their own fine-grained
  token (Contents: read-only, one repo, expiring); deleting it cuts that person off
  without touching anyone else. See `docs/ACCESS.md`.
- `get.sh` accepts `--token` / `--code` / `OUC_TOKEN`, sends it to the GitHub API
  tarball endpoint, and explains a 404 as "code rejected or expired" instead of a
  generic download failure.
- `OUC_PASSWORD` for unattended root installs (cloud-init, CI, no tty).

### Changed

- `install.sh` as root now asks for the **password too** (typed twice, hidden,
  minimum 6 characters, `:` rejected) and sets exactly that password. A generated
  password is only used when there is no terminal, and it is printed in that case.
- Install and uninstall commands point at `asgtey/ou-start`.

## [2.0.4] — 2026-11-13

Installing as root now creates the account for you, and pairing works without any
setup.

### Added

- `install.sh` run as root asks only for a **username**, creates that account (with
  a generated password printed at the end), adds it to `sudo`/`wheel`, enables
  lingering, and re-runs the installer as that user through `runuser`. A temporary
  `NOPASSWD` sudoers entry covers the second pass and is deleted before exit.
- `OUC_PAIR=0` installs in the old private-only mode.

### Changed

- The shared background server now stays enabled by default, so `opencode pair`
  works immediately. The terminal is unaffected: the lane always passes
  `--standalone`, so the TUI still gets a private server with the pinned edge.
- `doctor.sh` reports "pairing ready" instead of flagging the shared service as a
  problem, and prints the command for the other mode.
- `docs/PAIRING.md` is now one command plus the network edge cases.
- `get.sh` allows a root install (only a root uninstall is still refused).

## [2.0.3] — 2026-11-13

### Changed

- `docs/PAIRING.md` rewritten in plain language: one "what it is" paragraph, three
  numbered steps, and the edge cases (LAN, `--remote`, SSH) in a short section.
- The pairing section of both READMEs is now the same three commands, no
  explanation up front.

## [2.0.2] — 2026-11-13

Root-user guidance and `opencode pair`. Desktop app support removed.

### Added

- `docs/PAIRING.md`: connect from another machine with `opencode pair` — same LAN,
  SSH port forward, and `--remote` through OpenTunnel, including the
  enable → pair → disable cycle around the shared service.
- `README.md` / `README.fa.md` explain why the installer refuses to run as root,
  with `adduser` / `usermod` steps for VPS and container users.
- `install.sh` prints those same steps instead of a one-line error when it is
  started as root.

### Removed

- `scripts/desktop-patch.sh` and every reference to the OpenCode desktop app. The
  project targets the terminal TUI only.

### Changed

- `doctor.sh` reminds you to re-disable the shared service after pairing.
- The "pairing does not work" troubleshooting entry now points at the real
  procedure instead of calling it unsupported.
- `docs/V1-V2.md` and `SECURITY.md` no longer describe the desktop app.

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

[2.0.7]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.7
[2.0.6]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.6
[2.0.5]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.5
[2.0.4]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.4
[2.0.3]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.3
[2.0.2]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.2
[2.0.1]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.1
[2.0.0]: https://github.com/asgtey/opencode-unlimited-v2/releases/tag/v2.0.0
