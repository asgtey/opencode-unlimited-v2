#!/usr/bin/env bash
# doctor — read-only health report for OpenCode 2.x + WARP rotation.
# It changes nothing; it only tells you the truth. Run it when something
# feels wrong, and after every OpenCode upgrade.
set -u

BRAND="opencode-unlimited"
DEST="$HOME/.local/share/$BRAND"
SHIM="$HOME/.local/bin/opencode"

# ---------------------------------------------------------------- binaries
WARP="${OUC_WARP_BIN:-}"
if [ -z "$WARP" ]; then
  if command -v warp-cli >/dev/null 2>&1; then WARP="$(command -v warp-cli)"
  elif [ -x /usr/bin/warp-cli ]; then WARP=/usr/bin/warp-cli
  elif [ -x "$HOME/.local/bin/warp-cli" ]; then WARP="$HOME/.local/bin/warp-cli"
  fi
fi
wo() { [ -n "$WARP" ] || return 1; sudo -n "$WARP" --accept-tos "$@" 2>/dev/null && return 0; sudo -n "$WARP" "$@" 2>/dev/null; }

SYSTEMCTL="${OUC_SYSTEMCTL:-$(command -v systemctl 2>/dev/null || echo /usr/bin/systemctl)}"
IPT="${OUC_IPTABLES:-$(command -v iptables 2>/dev/null || echo /usr/sbin/iptables)}"
IP6T="${OUC_IP6TABLES:-$(command -v ip6tables 2>/dev/null || echo /usr/sbin/ip6tables)}"

# `su - user` and some consoles do not export the session bus, and then every
# `systemctl --user` call fails — which looks exactly like "guard is down".
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
USER_BUS=1
[ -S "$XDG_RUNTIME_DIR/bus" ] || USER_BUS=0

ok()   { echo -e "  \e[32m✓\e[0m $*"; }
warn() { echo -e "  \e[33m!\e[0m $*"; }
bad()  { echo -e "  \e[31m✗\e[0m $*"; }

echo ""
echo "  ============================="
echo "  Opencode Unlimited — doctor"
echo "  ============================="
echo ""

# ------------------------------------------------------------ real binary
# Never resolve to our own wrapper (that is a loop, not a binary).
REAL=""
for c in "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode /usr/bin/opencode "$(command -v opencode 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] || continue
  r="$(readlink -f "$c" 2>/dev/null || echo "$c")"
  [ "$r" = "$(readlink -f "$SHIM" 2>/dev/null)" ] && continue
  head -c 4096 "$r" 2>/dev/null | grep -q 'zen-lane' && continue
  REAL="$r"; break
done

VER=""
if [ -n "$REAL" ]; then
  VER="$("$REAL" --version 2>/dev/null | tr -d '\r' | awk '{print $NF}' | sed 's/^v//')"
fi
MAJOR="${VER%%.*}"
case "$MAJOR" in ''|*[!0-9]*) MAJOR=0 ;; esac

# ------------------------------------------------------------ OpenCode V2
if [ -z "$REAL" ]; then
  bad "opencode binary not found — run install.sh"
elif [ "$MAJOR" -ge 2 ]; then
  ok "opencode V2: $VER ($REAL)"
elif [ "$MAJOR" -eq 1 ]; then
  bad "opencode V1 detected ($VER) — these scripts target 2.x; re-run install.sh"
else
  warn "could not read opencode version (got: '${VER}') — check: $REAL --version"
fi

# ----------------------------------------------------- user namespaces
# The lane cannot pin /etc/hosts without them; it fails closed instead.
if unshare -rm true 2>/dev/null; then
  ok "unprivileged user namespaces work (unshare -rm)"
else
  bad "unshare -rm fails — the lane will refuse to start"
  echo "     fix:  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0"
fi

# ----------------------------------------------------- V2 private server
# V2 has a shared background server by default. The lane needs a private one
# per launch, otherwise the server (outside the namespace) makes the request.
CFG=""
if [ -n "$REAL" ] && [ "$MAJOR" -ge 2 ]; then
  CFG="$("$REAL" debug paths config 2>/dev/null | head -n 1)"
fi
[ -n "$CFG" ] || CFG="$HOME/.config/opencode"
SVC_JSON="$CFG/service.json"
if [ -f "$SVC_JSON" ]; then
  if python3 - "$SVC_JSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)

def find(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "disabled" and v is True:
                return True
            if find(v):
                return True
    elif isinstance(o, list):
        return any(find(v) for v in o)
    return False

sys.exit(0 if find(d) else 1)
PY
  then
    ok "private servers only (pairing off)"
    echo "     pairing:  $REAL service unset disabled && $REAL service start"
  else
    ok "pairing ready (shared service on; terminal still uses --standalone)"
    echo "     strict:   $REAL service set disabled true"
  fi
else
  warn "service.json not found — check: $REAL service status"
fi

# ------------------------------------------------------------ paths (V2)
LOG_DIR=""
DB=""
if [ -n "$REAL" ]; then
  LOG_DIR="$("$REAL" debug paths log 2>/dev/null | head -n 1)"
  DB="$("$REAL" debug paths db 2>/dev/null | head -n 1)"
fi
[ -n "$LOG_DIR" ] || LOG_DIR="$HOME/.local/share/opencode/log"
[ -n "$DB" ] || DB="$HOME/.local/share/opencode/opencode.db"
[ -d "$DB" ] && DB="$DB/opencode.db"

if [ -d "$LOG_DIR" ]; then
  ok "log dir: $LOG_DIR"
elif [ -f "$LOG_DIR" ]; then
  ok "log file: $LOG_DIR"
else
  warn "log path missing: $LOG_DIR (created on first launch)"
fi

# ------------------------------------------------------------ free walls
# Primary V2 signal lives in the session DB, not in the log. Count only the
# free-tier wall; Go / workspace / budget limits must NOT trigger rotation.
if [ -f "$DB" ]; then
  WALLS="$(python3 - "$DB" <<'PY'
import sqlite3, sys, urllib.parse
try:
    uri = "file:" + urllib.parse.quote(sys.argv[1]) + "?mode=ro"
    con = sqlite3.connect(uri, uri=True, timeout=3)
    con.execute("PRAGMA busy_timeout=3000")
    row = con.execute(
        """
        SELECT COUNT(*) FROM session_message
        WHERE data LIKE '%FreeUsageLimitError%'
           OR data LIKE '%provider.free-limit%'
           OR data LIKE '%Free usage limit reached%'
        """
    ).fetchone()
    print(int(row[0] or 0))
except Exception:
    sys.exit(1)
PY
)"
  case "$WALLS" in
    ''|*[!0-9]*) warn "session DB present but not readable: $DB" ;;
    *) ok "session DB readable ($WALLS free-tier wall(s) recorded)" ;;
  esac
else
  warn "session DB not found yet: $DB (normal before the first session)"
fi

# ------------------------------------------------------------ keeper
"$SYSTEMCTL" is-active ${BRAND}-keeper >/dev/null 2>&1 \
  && ok "keeper service (root)" \
  || bad "keeper down — sudo systemctl restart ${BRAND}-keeper"

# ------------------------------------------------------------ warp tunnel
ST="$(wo status | head -1)"
echo "$ST" | grep -q Connected \
  && ok "warp tunnel: connected" \
  || bad "warp not connected — sudo systemctl restart ${BRAND}-keeper"

# ------------------------------------------------------------ kill-switch
sudo -n "$IPT"  -nL OUC_LEAKGUARD >/dev/null 2>&1 \
  && ok "kill-switch v4 installed" \
  || bad "kill-switch v4 missing — keeper reinstalls it every 45s"
sudo -n "$IP6T" -nL OUC_LEAKGUARD >/dev/null 2>&1 \
  && ok "kill-switch v6 installed" \
  || bad "kill-switch v6 missing — keeper reinstalls it every 45s"

# ------------------------------------------------------------ egress
# -6: if this returns nothing we are either fully blocked (kill-switch doing
# its job) or the tunnel is down. A private IPv4 answer would prove a leak.
V6="$(timeout 12 curl -6 -s -m 10 https://api64.ipify.org 2>/dev/null)"
if [ -n "$V6" ]; then
  FIRST="$(echo "$V6" | cut -d: -f1-4)"
  case "$V6" in
    2606:*|2a09:*) ok "egress is cloudflare (warp): ${FIRST}::/64" ;;
    *) bad "egress is NOT warp ($V6) — restart the keeper" ;;
  esac
else
  V4="$(timeout 8 curl -4 -s -m 6 https://api.ipify.org 2>/dev/null)"
  if [ -n "$V4" ]; then
    bad "IPv4 still leaves the host ($V4) — kill-switch is not blocking; restart keeper"
  else
    warn "no egress at all — tunnel down and kill-switch blocking (safe, but rotate nothing)"
  fi
fi

# ------------------------------------------------------------ guard
if [ "$USER_BUS" = 0 ]; then
  warn "cannot reach the user session bus ($XDG_RUNTIME_DIR/bus) — guard state unknown"
  warn "run this from a normal login/SSH shell, not from 'su' inside a root console"
elif systemctl --user is-active ${BRAND}-guard >/dev/null 2>&1; then
  ok "zen-guard service (user)"
else
  bad "zen-guard down — systemctl --user start ${BRAND}-guard"
fi

if [ -f "$DEST/guard/state.json" ]; then
  python3 - "$DEST/guard/state.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(f"    rotations: {d.get('hops', 0)} · blacklisted /64s: "
          f"{len([x for x in d.get('blacklist', []) if x])}")
except Exception as e:
    print(f"    guard state unreadable: {e}")
PY
fi

# ------------------------------------------------------------ wrapper
if [ -f "$SHIM" ] && grep -q 'zen-lane' "$SHIM" 2>/dev/null; then
  ok "opencode entry → lane ($SHIM)"
  # ~/.opencode/bin must not shadow ~/.local/bin, or the lane is skipped.
  WHICH="$(command -v opencode 2>/dev/null)"
  [ "$(readlink -f "$WHICH" 2>/dev/null)" = "$(readlink -f "$SHIM" 2>/dev/null)" ] \
    && ok "PATH resolves 'opencode' to the lane" \
    || warn "PATH resolves 'opencode' to $WHICH — put ~/.local/bin first in PATH"
else
  warn "opencode entry does not point at the lane — re-run install.sh"
fi

# ------------------------------------------------------------ sudoers
[ -f "/etc/sudoers.d/$BRAND" ] \
  && ok "sudoers helper entries present" \
  || warn "sudoers entries missing — guard/hop cannot pause the keeper"

echo ""
echo "  all green = work. red = run the fix printed next to it."
echo ""
