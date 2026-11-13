#!/usr/bin/env bash
# zen-lane — OpenCode 2.x compatible launcher.
#
# Why this changed for V2:
#   V2 is client + background server. Provider requests are made by the SERVER,
#   not by the TUI process. Pinning /etc/hosts inside the lane namespace only
#   affects processes in that namespace, so the lane must force a PRIVATE
#   server (--standalone). The private server is spawned as a child of the
#   TUI, inherits the mount namespace and therefore uses the pinned IPv6 edge.
#
# Everything else is the original trick:
#   - opencode.ai -> one random edge from the live AAAA pool (per launch)
#   - fresh random /etc/machine-id (cosmetic in V2, harmless)
#   - process dies -> namespace evaporates -> no trace on the host
set -u

REAL="${OUC_REAL_BIN:-$HOME/.opencode/bin/opencode}"
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"

# Resolve the real binary and never exec ourselves (reinstall safety).
pick_real() {
  local c r
  for c in "$REAL" "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode /usr/bin/opencode; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    r="$(readlink -f "$c" 2>/dev/null || echo "$c")"
    [ "$r" = "$SELF" ] && continue
    head -c 4096 "$r" 2>/dev/null | grep -q 'zen-lane' && continue
    REAL="$r"
    return 0
  done
  return 1
}
pick_real || { echo "opencode binary not found — set OUC_REAL_BIN or reinstall" >&2; exit 1; }

# ------------------------------------------------------------------ version
# V1 (1.x) does not understand --standalone; only inject it on V2.
VER="$("$REAL" --version 2>/dev/null | tr -d '\r' | awk '{print $NF}' | sed 's/^v//')"
MAJOR="${VER%%.*}"
case "$MAJOR" in ''|*[!0-9]*) MAJOR=1 ;; esac

STANDALONE=0
if [ "$MAJOR" -ge 2 ]; then
  # Default ON (TUI, a project directory, run/models/session/...) because the
  # provider call must happen inside this namespace. Only commands that manage
  # the installation itself, or that are servers/daemons, must stay OFF.
  case "${1:-}" in
    service|upgrade|uninstall|debug|pair|serve|acp|version|--version|-v) STANDALONE=0 ;;
    *) STANDALONE=1 ;;
  esac
fi

# Fail closed: without user namespaces we cannot pin anything.
if ! unshare -rm true 2>/dev/null; then
  echo "zen-lane: unshare -rm failed — refusing to run without the IPv6/hosts pin." >&2
  echo "          On Ubuntu 24.04 / Mint 22.x see: kernel.apparmor_restrict_unprivileged_userns" >&2
  exit 1
fi

# ------------------------------------------------------ random Cloudflare edge
# strict hex-colon regex: dig error lines also contain colons
AAAA_POOL=$(dig +short AAAA opencode.ai @1.1.1.1 2>/dev/null | grep -E '^[0-9A-Fa-f:]+$' | sort -u)
[ -z "$AAAA_POOL" ] && AAAA_POOL=$(python3 -c "
import socket
try:
    print('\n'.join(sorted({i[4][0] for i in socket.getaddrinfo('opencode.ai', 443, socket.AF_INET6)})))
except Exception:
    pass" 2>/dev/null)
# Last resort: Cloudflare anycast literals. SNI/Host is still opencode.ai, so
# any Cloudflare edge can serve it.
[ -z "$AAAA_POOL" ] && AAAA_POOL="2606:4700:10::ac42:ad95
2606:4700:10::ac42:ad96
2606:4700:10::6814:2011
2606:4700:4700::1111
2606:4700:4700::1001"
AAAA=$(printf '%s\n' "$AAAA_POOL" | shuf -n 1)

# ---------------------------------------------------------- namespace scratch
TD=$(mktemp -d /tmp/ouc-lane.XXXXXX 2>/dev/null) || {
  mkdir -p /tmp/opencode-unlimited 2>/dev/null
  TD=$(mktemp -d /tmp/opencode-unlimited/lane.XXXXXX 2>/dev/null) || {
    echo "zen-lane: cannot create a temporary directory" >&2
    exit 1
  }
}

# opencode.ai -> chosen edge, IPv6 only. If v6 to that edge fails, the request
# fails — a failure is better than a silent home-IP leak.
printf '%s opencode.ai\n%s www.opencode.ai\n%s api.opencode.ai\n' \
  "$AAAA" "$AAAA" "$AAAA" > "$TD/hosts" || { rm -rf "$TD"; exit 1; }

# Fresh machine-id (V2 does not use /etc/machine-id, kept for defence in depth)
tr -dc 'a-f0-9' < /dev/urandom | head -c 32 > "$TD/machine-id"

# --------------------------------------------------------------------- launch
# `--standalone` is a global V2 flag (declared on the root command and
# inherited by run/models/session/...), so it is valid in front of everything
# that accepts it. Commands that do not accept it are filtered out above.
ARGS=()
[ "$STANDALONE" = 1 ] && ARGS+=(--standalone)
ARGS+=("$@")

# Inner shell runs the binary as a child (not exec) so it can clean up the
# scratch dir inside the namespace. Ctrl+C/SIGWINCH reach the foreground group.
unshare -rm bash -c '
  td=$1; real=$2; shift 2
  mount --bind "$td/hosts" /etc/hosts || {
    echo "zen-lane: cannot bind /etc/hosts inside the namespace" >&2
    exit 97
  }
  if [ -f /etc/machine-id ]; then
    mount --bind "$td/machine-id" /etc/machine-id 2>/dev/null || true
  fi
  "$real" "$@"
  rc=$?
  rm -rf "$td"
  exit "$rc"
' bash "$TD" "$REAL" "${ARGS[@]}"
rc=$?

# backup cleanup if the inner shell was killed before its own rm
rm -rf "$TD"
exit "$rc"
