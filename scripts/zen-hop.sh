#!/usr/bin/env bash
# zen-hop — manual identity rotation for OpenCode 2.x.
#
# What it does (same trick as V1):
#   delete the WARP registration -> register a fresh one -> reconnect.
#   Cloudflare hands out a new IPv6 /64, which is a new free-tier bucket.
#
# What changed for V2:
#   - /64 comparison uses Python's ipaddress module, so compressed forms
#     (2606:4700::1) and full forms compare correctly.
#   - It refuses to take the tunnel down when the kill-switch chain is
#     missing (fail closed, same rule as zen-guard).
#   - systemctl stop/start of the keeper uses `sudo -n`; the installer writes
#     the exact NOPASSWD entries for it.
set -u

BRAND="opencode-unlimited"
STATE_DIR="$HOME/.local/share/$BRAND/guard"
STATE="$STATE_DIR/state.json"

# ------------------------------------------------------------------ binaries
WARP="${OUC_WARP_BIN:-}"
if [ -z "$WARP" ]; then
  if command -v warp-cli >/dev/null 2>&1; then WARP="$(command -v warp-cli)"
  elif [ -x /usr/bin/warp-cli ]; then WARP=/usr/bin/warp-cli
  elif [ -x "$HOME/.local/bin/warp-cli" ]; then WARP="$HOME/.local/bin/warp-cli"
  fi
fi
[ -n "$WARP" ] || { echo "warp-cli not found" >&2; exit 1; }

KEEPER="${OUC_KEEPER_UNIT:-opencode-unlimited-keeper}"
SYSTEMCTL="${OUC_SYSTEMCTL:-$(command -v systemctl 2>/dev/null || echo /usr/bin/systemctl)}"
IPT="${OUC_IPTABLES:-$(command -v iptables 2>/dev/null || echo /usr/sbin/iptables)}"
IP6T="${OUC_IP6TABLES:-$(command -v ip6tables 2>/dev/null || echo /usr/sbin/ip6tables)}"

# some boxes shim warp-cli with --accept-tos already inside the shim;
# passing it twice makes the CLI die. try with it, then without.
w()  { sudo -n "$WARP" --accept-tos "$@" >/dev/null 2>&1 && return 0; sudo -n "$WARP" "$@" >/dev/null 2>&1; }
wo() { sudo -n "$WARP" --accept-tos "$@" 2>/dev/null && return 0; sudo -n "$WARP" "$@" 2>/dev/null; }

mkdir -p "$STATE_DIR" 2>/dev/null || { echo "cannot create $STATE_DIR" >&2; exit 1; }
glog() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$STATE_DIR/hop.log"; }

svc() { sudo -n "$SYSTEMCTL" "$@" >/dev/null 2>&1 || sudo "$SYSTEMCTL" "$@" >/dev/null 2>&1; }

# --------------------------------------------------------------- normalise
# Always compare /64 prefixes, never raw strings.
m64() { python3 -c 'import ipaddress,sys
try: print(ipaddress.ip_network(sys.argv[1].strip()+"/64", strict=False))
except Exception: print("")' "$1" 2>/dev/null; }

# ---------------------------------------------------------------- egress
# -6 is mandatory: without it curl may silently report the home IPv4.
cur_v6() {
  local v
  v=$(timeout 10 curl -6 -s -m 8 https://api64.ipify.org 2>/dev/null)
  case "$v" in *:*) printf '%s' "$v"; return ;; esac
  v=$(timeout 10 curl -6 -s -m 8 https://ipv6.icanhazip.com 2>/dev/null)
  case "$v" in *:*) printf '%s' "$v"; return ;; esac
  printf ''
}

# The kill-switch is what makes a manual rotation safe. If the chain is gone,
# pulling the tunnel down would expose the real IPv6 address.
leakguard_ok() {
  sudo -n "$IPT"  -nL OUC_LEAKGUARD >/dev/null 2>&1 || return 1
  sudo -n "$IP6T" -nL OUC_LEAKGUARD >/dev/null 2>&1 || return 1
  return 0
}

# Remember the burned /64 so the guard does not rotate back onto it.
blacklist_add() {
  [ -n "${1:-}" ] || return 0
  python3 - "$STATE" "$1" <<'PY'
import ipaddress, json, sys

def m64(a):
    try:
        return str(ipaddress.ip_network(a.strip() + "/64", strict=False))
    except Exception:
        return ""

p, addr = sys.argv[1], sys.argv[2]
m = m64(addr)
if not m:
    raise SystemExit(0)
try:
    d = json.load(open(p))
except Exception:
    d = {}
bl = [x for x in d.get("blacklist", []) if m64(x) != m]
bl.append(m)
d["blacklist"] = bl[-200:]
json.dump(d, open(p, "w"))
PY
}

# Make sure the keeper comes back even if we are interrupted mid-rotation.
SYSTEMCTL_STATE=unknown
restore() {
  if [ "$SYSTEMCTL_STATE" = stopped ]; then
    svc start "$KEEPER" && glog "keeper resumed"
  fi
}
trap restore EXIT INT TERM

echo ""
echo "  Opencode Unlimited — manual hop"
echo "  --------------------------------"

# ------------------------------------------------------------ safety gate
if ! leakguard_ok; then
  echo "  ✗ kill-switch chain OUC_LEAKGUARD is missing." >&2
  echo "    Refusing to drop the tunnel: that would leak your real IPv6." >&2
  echo "    Fix first:  sudo systemctl restart ${BRAND}-keeper" >&2
  exit 1
fi

OLD="$(cur_v6)"
if [ -z "$OLD" ]; then
  echo "  ✗ no IPv6 egress right now — the tunnel is down." >&2
  echo "    Refusing to rotate. Fix first: sudo systemctl restart ${BRAND}-keeper" >&2
  exit 1
fi
echo "  old: $OLD  ($(m64 "$OLD"))"

# ------------------------------------------------------------ rotation
svc stop "$KEEPER"
SYSTEMCTL_STATE=stopped
echo "  -- keeper paused --"

w disconnect
w registration delete

OK=0
for i in 1 2 3 4 5; do
  w registration new && { OK=1; break; }
  echo "     registration attempt $i failed"
  sleep 8
done
if [ "$OK" != 1 ]; then
  echo "  ✗ could not register a new WARP identity." >&2
  echo "    The keeper will keep retrying; run me again in a minute." >&2
  exit 1
fi

w mode warp
# Restart the keeper right here, not from the EXIT trap: in server mode the
# keeper raises the tunnel together with the SSH route pin and the firewall
# holes. Leaving it stopped for the whole polling loop means the tunnel comes
# up with no SSH holes — that is how a remote session gets lost.
svc start "$KEEPER" && SYSTEMCTL_STATE=started

for i in $(seq 1 20); do
  sleep 3
  wo status | head -1 | grep -q Connected && break
done

NEW="$(cur_v6)"
if [ -z "$NEW" ]; then
  echo "  ✗ tunnel came up but has no IPv6 yet — try again in a minute." >&2
  exit 1
fi

echo "  new: $NEW  ($(m64 "$NEW"))"

if [ "$(m64 "$NEW")" != "$(m64 "$OLD")" ]; then
  blacklist_add "$OLD"
  glog "manual hop: ${OLD} -> ${NEW}"
  echo "  ✓ fresh /64 — re-send your message"
  exit 0
fi

echo "  ! Cloudflare handed back the same /64 — run me again" >&2
exit 1
