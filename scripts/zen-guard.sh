#!/usr/bin/env bash
# zen-guard — OpenCode 2.x compatible wall watcher.
#
# What changed for V2 (important):
#   V2 does not reliably write provider errors to opencode.log. Provider calls
#   happen in the background server, and a refused free-tier request is stored
#   in the session database instead:
#
#     ~/.local/share/opencode/opencode.db
#       table session_message.data (assistant message JSON)
#       -> "error":{"type":"provider.free-limit", ...
#                              "FreeUsageLimitError" ...
#                              "Free usage limit reached..."
#
#   So the PRIMARY detector is a read-only SQLite query. The old log-tail scan
#   stays as a fallback (V1, older builds, DB unavailable).
#
# Rotation behaviour is unchanged: blacklist the burned /64, pause the keeper,
# re-register WARP, verify, resume, retry up to 8 times. It now refuses to take
# the tunnel down if the kill-switch chain is missing.
set -u

STATE_DIR="$HOME/.local/share/opencode-unlimited/guard"
STATE="$STATE_DIR/state.json"
GUARD_LOG="$STATE_DIR/guard.log"
mkdir -p "$STATE_DIR" || exit 1

# --------------------------------------------------------------- real binary
# Never use our own wrapper here: a stale unit env from an older install may
# point OUC_REAL_BIN at ~/.local/bin/opencode (which is the lane).
REAL="${OUC_REAL_BIN:-}"
if [ -n "$REAL" ] && head -c 4096 "$REAL" 2>/dev/null | grep -q 'zen-lane'; then
  REAL=""
fi
if [ -z "$REAL" ] || [ ! -x "$REAL" ]; then
  for c in "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode /usr/bin/opencode; do
    [ -x "$c" ] || continue
    head -c 4096 "$c" 2>/dev/null | grep -q 'zen-lane' && continue
    REAL="$c"; break
  done
fi
[ -n "$REAL" ] && [ -x "$REAL" ] || { echo "opencode binary not found"; exit 1; }

VER="$("$REAL" --version 2>/dev/null | tr -d '\r' | awk '{print $NF}' | sed 's/^v//')"
MAJOR="${VER%%.*}"
case "$MAJOR" in ''|*[!0-9]*) MAJOR=1 ;; esac

# ------------------------------------------------------------------ paths
# `opencode debug paths` does not start a server and is V2-aware (XDG, channel,
# OPENCODE_DB). Fall back to the classic locations on V1/older builds.
oc_path() { "$REAL" debug paths "$1" 2>/dev/null | head -n 1; }

LOG_DIR="$(oc_path log)"
[ -n "$LOG_DIR" ] || LOG_DIR="$HOME/.local/share/opencode/log"
DB="$(oc_path db)"
[ -n "$DB" ] || DB="$HOME/.local/share/opencode/opencode.db"
[ -d "$DB" ] && DB="$DB/opencode.db"   # tolerate a directory answer

# ------------------------------------------------------------------ warp
WARP="${OUC_WARP_BIN:-}"
if [ -z "$WARP" ]; then
  if command -v warp-cli >/dev/null 2>&1; then WARP="$(command -v warp-cli)"
  elif [ -x /usr/bin/warp-cli ]; then WARP=/usr/bin/warp-cli
  elif [ -x "$HOME/.local/bin/warp-cli" ]; then WARP="$HOME/.local/bin/warp-cli"
  fi
fi
[ -n "$WARP" ] || { echo "warp-cli not found"; exit 1; }

KEEPER="${OUC_KEEPER_UNIT:-opencode-unlimited-keeper}"
SYSTEMCTL="${OUC_SYSTEMCTL:-$(command -v systemctl 2>/dev/null || echo /usr/bin/systemctl)}"
IPT="${OUC_IPTABLES:-$(command -v iptables 2>/dev/null || echo /usr/sbin/iptables)}"
IP6T="${OUC_IP6TABLES:-$(command -v ip6tables 2>/dev/null || echo /usr/sbin/ip6tables)}"

COOLDOWN=75        # seconds between rotations (a rotation takes ~15s)
MAX_HOP_TRIES=8

# Free-tier wall only. Deliberately excludes Go / workspace / ChatGPT limits:
# rotating the IP does nothing for those and would only waste a fresh /64.
WALL_RE='FreeUsageLimitError|provider\.free-limit|Free usage limit reached'
[ "$MAJOR" -lt 2 ] && WALL_RE="$WALL_RE|QuotaExceeded"

glog() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$GUARD_LOG"; }

now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# ------------------------------------------------------------------ state
state_get() {
  python3 - "$STATE" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
v = d.get(sys.argv[2], "")
print("" if v is None else v)
PY
}

state_set() {
  python3 - "$STATE" "$1" "$2" <<'PY'
import json, sys
p, k, v = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d[k] = v
json.dump(d, open(p, "w"))
PY
}

# ------------------------------------------------------------------ SQLite
# Read-only, 3s busy timeout. Exit 1 means "DB unavailable" (V1, first launch,
# locked, missing table) so the caller can fall back to the log scan.
db_max_ts() {
  python3 - "$1" <<'PY'
import sqlite3, sys, urllib.parse
try:
    uri = "file:" + urllib.parse.quote(sys.argv[1]) + "?mode=ro"
    con = sqlite3.connect(uri, uri=True, timeout=3)
    con.execute("PRAGMA busy_timeout=3000")
    row = con.execute("SELECT COALESCE(MAX(time_updated), 0) FROM session_message").fetchone()
    print(int(row[0] or 0))
except Exception:
    sys.exit(1)
PY
}

db_wall_since() {
  python3 - "$1" "$2" <<'PY'
import sqlite3, sys, urllib.parse
db = sys.argv[1]
try:
    since = int(sys.argv[2] or 0)
except Exception:
    since = 0
# time_created has an index; look back 6h so a request that started before the
# last rotation is still found. time_updated is the actual failure time.
lower = max(0, since - 6 * 3600 * 1000)
try:
    uri = "file:" + urllib.parse.quote(db) + "?mode=ro"
    con = sqlite3.connect(uri, uri=True, timeout=3)
    con.execute("PRAGMA busy_timeout=3000")
    row = con.execute(
        """
        SELECT COALESCE(MAX(time_updated), 0) FROM session_message
        WHERE type = 'assistant' AND time_created >= ?
          AND (data LIKE '%FreeUsageLimitError%'
            OR data LIKE '%provider.free-limit%'
            OR data LIKE '%Free usage limit reached%')
        """,
        (lower,),
    ).fetchone()
    print(int(row[0] or 0))
except Exception:
    sys.exit(1)
PY
}

# ------------------------------------------------------------- blacklist
# /64-normalised. ipaddress handles compressed forms correctly (the old
# split(':')[:4] trick mis-normalises addresses containing '::').
blacklist_add() {
  python3 - "$STATE" "$1" <<'PY'
import ipaddress, json, sys

def m64(a):
    try:
        return str(ipaddress.ip_network(a.strip() + "/64", strict=False))
    except Exception:
        return ":".join(a.split(":")[:4])

p, addr = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    d = {}
bl = d.get("blacklist", [])
m = m64(addr)
bl = [x for x in bl if x and m64(x) != m] + ([m] if addr else [])
d["blacklist"] = bl[-200:]
json.dump(d, open(p, "w"))
PY
}

is_burnt() {
  python3 - "$STATE" "$1" <<'PY'
import ipaddress, json, sys

def m64(a):
    try:
        return str(ipaddress.ip_network(a.strip() + "/64", strict=False))
    except Exception:
        return ":".join(a.split(":")[:4])

try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
m = m64(sys.argv[2])
sys.exit(0 if any(x and m64(x) == m for x in d.get("blacklist", [])) else 1)
PY
}

# ------------------------------------------------------------------ helpers
svc() { sudo -n "$SYSTEMCTL" "$@" >/dev/null 2>&1 || sudo "$SYSTEMCTL" "$@" >/dev/null 2>&1; }
w()  { sudo -n "$WARP" --accept-tos "$@" >/dev/null 2>&1 && return 0; sudo -n "$WARP" "$@" >/dev/null 2>&1; }
wo() { sudo -n "$WARP" --accept-tos "$@" 2>/dev/null && return 0; sudo -n "$WARP" "$@" 2>/dev/null; }

# Force IPv6: the whole scheme is a /64 rotation. If this returns empty, there
# is no v6 path and rotating would be pointless (and risky).
cur_v6() {
  local v
  v=$(timeout 10 curl -6 -s -m 8 https://api64.ipify.org 2>/dev/null)
  case "$v" in *:*) printf '%s' "$v"; return ;; esac
  v=$(timeout 10 curl -6 -s -m 8 https://ipv6.icanhazip.com 2>/dev/null)
  case "$v" in *:*) printf '%s' "$v"; return ;; esac
  printf ''
}

# The kill-switch is what makes rotation safe. If the chain is gone, do not
# take WARP down: keeper reinstalls it within 45s and we retry next tick.
leakguard_ok() {
  sudo -n "$IPT"  -nL OUC_LEAKGUARD >/dev/null 2>&1 || return 1
  sudo -n "$IP6T" -nL OUC_LEAKGUARD >/dev/null 2>&1 || return 1
  return 0
}

# One keeper-safe registration cycle. Prints the new IPv6 or empty.
hop_once() {
  if ! leakguard_ok; then
    glog "ABORT rotation: kill-switch chain missing — refusing to take the tunnel down"
    printf ''
    return
  fi

  svc stop "$KEEPER"
  w disconnect
  w registration delete

  local ok=0 i
  for i in 1 2 3; do
    w registration new && { ok=1; break; }
    sleep 6
  done
  w mode warp
  # Let the keeper raise the tunnel instead of connecting here: it pins the SSH
  # route and opens the SSH port inside warp's own firewall in the same tick.
  # Connecting directly left a window with no firewall holes — on a remote box
  # that window is a lost SSH session.
  svc start "$KEEPER"
  local up=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 2
    ip -br addr show "${OUC_WARP_IFACE:-CloudflareWARP}" 2>/dev/null | grep -q ' UP ' && { up=1; break; }
  done
  [ "$up" = 1 ] || w connect
  [ "$ok" = 1 ] || { printf ''; return; }

  local V=""
  for i in $(seq 1 12); do
    sleep 3
    V=$(cur_v6)
    [ -n "$V" ] && break
    V=""
  done
  printf '%s' "$V"
}

# ------------------------------------------------------------------ log scan
scan_logs() {
  local f base off_file size off newbytes files=()
  shopt -s nullglob
  # `debug paths log` may return a directory (stable) or a file (channel
  # builds). Handle both instead of silently disabling the fallback.
  if [ -f "$LOG_DIR" ]; then
    files=("$LOG_DIR")
  else
    files=("$LOG_DIR"/*.log)
  fi
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    off_file="$STATE_DIR/off.$base"
    size="$(wc -c < "$f" 2>/dev/null)" || continue
    case "$size" in ''|*[!0-9]*) continue ;; esac

    # First sight: start at EOF, never replay history.
    if [ ! -f "$off_file" ]; then
      printf '%s\n' "$size" > "$off_file"
      continue
    fi

    off="$(cat "$off_file" 2>/dev/null)"
    case "$off" in ''|*[!0-9]*) off=0 ;; esac
    [ "$size" -lt "$off" ] && off=0          # log was trimmed in place
    [ "$size" -le "$off" ] && continue
    newbytes=$((size - off))

    # A huge jump is a reopened/trimmed file, not new wall spam.
    if [ "$newbytes" -lt 50000000 ]; then
      if tail -c +"$((off + 1))" "$f" 2>/dev/null | grep -aqE "$WALL_RE"; then
        state_set pending 1
        glog "wall pattern in log/$base"
      fi
    fi
    printf '%s\n' "$size" > "$off_file"
  done
}

# ------------------------------------------------------------------ bootstrap
if [ ! -f "$STATE" ]; then
  printf '{"blacklist":[],"last_hop":0,"hops":0,"current":"","pending":0}' > "$STATE"
fi

# Baseline: ignore walls that happened before the guard started. If the DB is
# available, use its newest timestamp; otherwise use now (rows are older).
LAST_WALL="$(state_get last_wall_ms)"
if [ -z "$LAST_WALL" ]; then
  base="$(db_max_ts "$DB" 2>/dev/null || true)"
  case "$base" in ''|*[!0-9]*) base=0 ;; esac
  [ "$base" -gt 0 ] 2>/dev/null || base="$(now_ms)"
  state_set last_wall_ms "$base"
  LAST_WALL="$base"
fi

if [ "$MAJOR" -ge 2 ]; then
  glog "zen-guard up (V2: db+log, cooldown ${COOLDOWN}s, db=$DB)"
else
  glog "zen-guard up (V1: log only, cooldown ${COOLDOWN}s, log=$LOG_DIR)"
fi

while true; do
  sleep 20

  # ---- primary: session DB (V2) ----
  LAST_WALL="$(state_get last_wall_ms)"; LAST_WALL="${LAST_WALL:-0}"
  TS="$(db_wall_since "$DB" "$LAST_WALL" 2>/dev/null || true)"
  if [ -n "$TS" ] && [ "$TS" -gt "$LAST_WALL" ] 2>/dev/null; then
    state_set last_wall_ms "$TS"
    state_set pending 1
    glog "wall in session DB (ts=$TS)"
  fi

  # ---- fallback: log tail ----
  scan_logs

  # ---- rotate ----
  PENDING="$(state_get pending)"; PENDING="${PENDING:-0}"
  NOW="$(date +%s)"
  LASTHOP="$(state_get last_hop)"; LASTHOP="${LASTHOP:-0}"
  AGE=$((NOW - LASTHOP))

  if [ "$PENDING" = 1 ] && [ "$AGE" -ge "$COOLDOWN" ]; then
    OLD="$(cur_v6)"
    glog "wall pending — rotating (was: ${OLD:-?})"
    [ -n "$OLD" ] && blacklist_add "$OLD"

    NEW=""
    TRY=0
    while [ "$TRY" -lt "$MAX_HOP_TRIES" ]; do
      TRY=$((TRY + 1))
      V="$(hop_once)"
      if [ -z "$V" ]; then
        glog "try $TRY: tunnel repair failed"
        continue
      fi
      if is_burnt "$V"; then
        glog "try $TRY: cloudflare returned a blacklisted /64 ($V) — again"
        continue
      fi
      NEW="$V"
      break
    done

    # Every block burned -> recycle the oldest (buckets reset around midnight).
    if [ -z "$NEW" ]; then
      glog "everything blacklisted — recycling oldest block"
      V="$(hop_once)"
      [ -n "$V" ] && NEW="$V"
    fi

    if [ -n "$NEW" ]; then
      state_set last_hop "$NOW"
      state_set current "$NEW"
      state_set pending 0
      H="$(state_get hops)"; H="${H:-0}"; H=$((H + 1))
      state_set hops "$H"
      glog "rotated #$H: ${OLD:-?} → $NEW ✓"
    else
      state_set last_hop "$NOW"
      glog "rotation failed — pending stays 1, retry after cooldown"
    fi
  elif [ "$PENDING" = 1 ]; then
    glog "wall pending but in cooldown (${AGE}s < ${COOLDOWN}s)"
  fi
done
