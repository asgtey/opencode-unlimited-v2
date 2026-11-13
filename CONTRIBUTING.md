# Contributing

Thanks for helping. This project is small on purpose: five bash scripts, no build
system, no dependencies beyond Python 3 and the system tools.

## Ground rules

1. **Do not weaken the kill-switch.** A change that makes rotation possible while
   `OUC_LEAKGUARD` is missing will be rejected.
2. **Keep it fail-closed.** If a safety check cannot run, the answer is "stop", not
   "continue".
3. **Stay V2-aware.** Anything that reads provider errors must consider both the
   session DB (primary) and the log (fallback).
4. **Do not add data collection.** No telemetry, no analytics, no network calls other
   than the ones already required (opencode.ai, Cloudflare, ipify for egress tests).

## Development

```bash
git clone https://github.com/asgtey/opencode-unlimited-v2.git
cd opencode-unlimited-v2

# syntax check (required before every commit)
make check

# optional: shellcheck
shellcheck -S warning get.sh install.sh uninstall.sh scripts/*.sh
```

Test on a **disposable VM** running Ubuntu 24.04 or Linux Mint 22.x. The installer
changes firewall rules, systemd units and a sudoers file.

## Style

- `#!/usr/bin/env bash`, `set -u`, no `set -e` (the scripts handle failures explicitly).
- Quote variables unless word splitting is intentional.
- Prefer `python3` for JSON/SQLite/IPv6 work; do not add `jq` or `sqlite3` as hard
  dependencies.
- Comments explain *why*, not *what*.
- Keep user-facing messages short and actionable.
- Persian and English docs are both maintained; update both when behaviour changes.
- `README.fa.md` is raw HTML (`dir="rtl"`), because GitHub markdown has no RTL
  switch. Keep its structure consistent (one `<h2>` per section, `<ul>`/`<ol>` for
  lists, `<pre dir="ltr">` for commands) rather than mixing markdown back in.

## Pull requests

- One logical change per PR.
- Include the output of `bash -n` and, when relevant, `opencode-unlimited-doctor`.
- Describe the failure mode you fixed and how you reproduced it.
- Do not bump the version in `CHANGELOG.md` yourself; the maintainer does that on
  release.

## Reporting bugs

Use the bug report template and include:

```bash
opencode --version
cat /etc/os-release
opencode-unlimited-doctor
tail -n 50 ~/.local/share/opencode-unlimited/guard/guard.log
```

Redact IP addresses and tokens.
