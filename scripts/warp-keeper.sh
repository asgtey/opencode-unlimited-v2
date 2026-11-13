#!/bin/bash
# warp keeper — keeps the cloudflare warp tunnel in TUN mode and the
# kill-switch firewall installed. runs as a root systemd service.
#
# every tick (45s):
#   - forces warp TUN mode
#   - reconnects if the tunnel died (fresh registration if the old one is toast)
#   - re-installs the OUC_LEAKGUARD iptables chain (survives manual flushes)
#
# the kill-switch: only loopback, LAN, cloudflare's control ranges, the warp
# interface and established connections may leave the host. everything else
# gets dropped. tunnel down? the chain is still there → traffic goes nowhere
# instead of leaking from your home IP. that's the whole point.
set -u

# warp binary: service env (installer sets it) → PATH → common fallbacks.
# we probe with --accept-tos and without: some boxes shim warp-cli with the
# flag already inside, and passing it twice kills the CLI with an arg error.
WARP="${OUC_WARP_BIN:-}"
if [ -z "$WARP" ]; then
  if command -v warp-cli >/dev/null 2>&1; then WARP="$(command -v warp-cli)"
  elif [ -x /usr/bin/warp-cli ]; then WARP=/usr/bin/warp-cli
  elif [ -x "$HOME/.local/bin/warp-cli" ]; then WARP="$HOME/.local/bin/warp-cli"
  fi
fi
[ -n "$WARP" ] || { echo "warp-cli not found"; exit 1; }

w(){  "$WARP" --accept-tos "$@" >/dev/null 2>&1 && return 0; "$WARP" "$@" >/dev/null 2>&1; }
wo(){ "$WARP" --accept-tos "$@" 2>/dev/null && return 0; "$WARP" "$@" 2>/dev/null; }

IFACE=CloudflareWARP
TICK=45

# ------------------------------------------------------- server mode (opt-in)
# A remote server is not a desktop: TUN mode can route SSH replies into the
# tunnel and kill your session, and a strict kill-switch can lock you out.
# With OUC_SERVER_SAFE=1 we add explicit SSH/DNS allowances and keep a direct
# route to the SSH client. The desktop default stays strict.
SERVER_SAFE="${OUC_SERVER_SAFE:-0}"
SSH_PORT="${OUC_SSH_PORT:-22}"
SSH_CLIENT_IP="${OUC_SSH_CLIENT_IP:-}"      # informational only now
# gateway/device learned by the installer *before* WARP was connected. We must
# not re-derive them while the tunnel is up: `ip route get` then answers with
# the WARP interface and pinning SSH to that is exactly the lockout we avoid.
SSH_GW="${OUC_SSH_GW:-}"
SSH_DEV="${OUC_SSH_DEV:-}"
RT_TABLE="${OUC_ROUTE_TABLE:-111}"
SSH_MARK="${OUC_SSH_MARK:-0x100cf}"   # warp's own bypass mark

# first default route that does not belong to the tunnel
_phys_route(){
  ip $1 route show default 2>/dev/null | awk -v i="$IFACE" '
    { g=""; d="";
      for (j=1;j<=NF;j++) { if ($j=="via") g=$(j+1); if ($j=="dev") d=$(j+1) }
      if (d!="" && d!=i) { print g" "d; exit } }'
}

# warp-svc's routing rule is "not from all fwmark <mark> lookup 65743". Its
# priority changes between runs (4, 19, 49 were all observed), so we do not
# race it: we reuse its own mark instead, and its rule skips our packets no
# matter which number it picked.
_warp_mark(){
  ip rule list 2>/dev/null \
    | awk '/not from all fwmark/ {for(i=1;i<=NF;i++) if($i=="fwmark"){print $(i+1); exit}}'
}

# sshd's replies: marked by source port (works for any client address, since
# home IPs move) and routed through a table DHCP reconfiguration never touches.
pin_ssh_route(){
  local g="$SSH_GW" d="$SSH_DEV" line g6 d6 m
  m="$(_warp_mark)"; [ -n "$m" ] && SSH_MARK="$m"

  if [ -z "$d" ]; then
    line="$(_phys_route "")"; g="${line%% *}"; d="${line##* }"
  fi
  [ -n "$d" ] || return 1
  if [ -n "$g" ]; then
    ip route replace default via "$g" dev "$d" table "$RT_TABLE" 2>/dev/null || return 1
  else
    ip route replace default dev "$d" table "$RT_TABLE" 2>/dev/null || return 1
  fi

  # rebuild the mark chain only when the mark value actually changed
  iptables -t mangle -N OUC_SSHOUT 2>/dev/null
  iptables -t mangle -C OUTPUT -j OUC_SSHOUT 2>/dev/null \
    || iptables -t mangle -I OUTPUT -j OUC_SSHOUT 2>/dev/null
  if ! iptables -t mangle -S OUC_SSHOUT 2>/dev/null | grep -qF "set-xmark ${SSH_MARK}/"; then
    iptables -t mangle -F OUC_SSHOUT 2>/dev/null
    iptables -t mangle -A OUC_SSHOUT -p tcp --sport "$SSH_PORT" -j MARK --set-mark "$SSH_MARK" 2>/dev/null
  fi
  ip rule list 2>/dev/null | grep -q "fwmark $SSH_MARK lookup $RT_TABLE" \
    || ip rule add fwmark "$SSH_MARK" lookup "$RT_TABLE" priority 1 2>/dev/null

  # v6 mirror, but only when the box really has a v6 default route
  line="$(_phys_route -6)"; g6="${line%% *}"; d6="${line##* }"
  if [ -n "$d6" ]; then
    if [ -n "$g6" ]; then
      ip -6 route replace default via "$g6" dev "$d6" table "$RT_TABLE" 2>/dev/null
    else
      ip -6 route replace default dev "$d6" table "$RT_TABLE" 2>/dev/null
    fi
    ip6tables -t mangle -N OUC_SSHOUT 2>/dev/null
    ip6tables -t mangle -C OUTPUT -j OUC_SSHOUT 2>/dev/null \
      || ip6tables -t mangle -I OUTPUT -j OUC_SSHOUT 2>/dev/null
    if ! ip6tables -t mangle -S OUC_SSHOUT 2>/dev/null | grep -qF "set-xmark ${SSH_MARK}/"; then
      ip6tables -t mangle -F OUC_SSHOUT 2>/dev/null
      ip6tables -t mangle -A OUC_SSHOUT -p tcp --sport "$SSH_PORT" -j MARK --set-mark "$SSH_MARK" 2>/dev/null
    fi
    ip -6 rule list 2>/dev/null | grep -q "fwmark $SSH_MARK lookup $RT_TABLE" \
      || ip -6 rule add fwmark "$SSH_MARK" lookup "$RT_TABLE" priority 1 2>/dev/null
  fi
  return 0
}

# warp-svc also loads "inet cloudflare-warp" with input/output chains set to
# "policy drop". Routing is not enough: without these holes SSH is discarded in
# both directions. warp rebuilds the table on every connect, hence every tick.
nft_ssh_holes(){
  command -v nft >/dev/null 2>&1 || return 0
  nft list table inet cloudflare-warp >/dev/null 2>&1 || return 0
  nft list chain inet cloudflare-warp input 2>/dev/null | grep -q "tcp dport $SSH_PORT accept" \
    || nft insert rule inet cloudflare-warp input tcp dport "$SSH_PORT" accept 2>/dev/null
  nft list chain inet cloudflare-warp output 2>/dev/null | grep -q "tcp sport $SSH_PORT accept" \
    || nft insert rule inet cloudflare-warp output tcp sport "$SSH_PORT" accept 2>/dev/null
  return 0
}

ensure_connected(){
  wo status | head -1 | grep -q Connected && return 0
  w connect; sleep 4
  wo status | head -1 | grep -q Connected && return 0
  # old registration is probably dead — burn it and make a new one
  w disconnect
  w registration delete
  w registration new || return 1
  w mode warp
  w connect
  sleep 5
  wo status | head -1 | grep -q Connected
}

ensure_guard(){
  # ---- v4
  iptables  -N OUC_LEAKGUARD 2>/dev/null
  iptables  -F OUC_LEAKGUARD
  iptables  -A OUC_LEAKGUARD -o lo              -j ACCEPT
  iptables  -A OUC_LEAKGUARD -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables  -A OUC_LEAKGUARD -d 10.0.0.0/8      -j ACCEPT
  iptables  -A OUC_LEAKGUARD -d 172.16.0.0/12   -j ACCEPT
  iptables  -A OUC_LEAKGUARD -d 192.168.0.0/16  -j ACCEPT
  # cloudflare warp control/engage ranges (warp-cli needs these to talk home)
  iptables  -A OUC_LEAKGUARD -d 162.159.0.0/16  -j ACCEPT
  iptables  -A OUC_LEAKGUARD -d 188.114.0.0/16  -j ACCEPT
  iptables  -A OUC_LEAKGUARD -o $IFACE          -j ACCEPT
  if [ "$SERVER_SAFE" = 1 ]; then
    iptables  -A OUC_LEAKGUARD -p tcp --sport "$SSH_PORT" -j ACCEPT
    iptables  -A OUC_LEAKGUARD -p udp --dport 53 -j ACCEPT
    iptables  -A OUC_LEAKGUARD -p tcp --dport 53 -j ACCEPT
  fi
  iptables  -A OUC_LEAKGUARD -j DROP
  iptables  -C OUTPUT -j OUC_LEAKGUARD 2>/dev/null || iptables -I OUTPUT -j OUC_LEAKGUARD
  # ---- v6 (same idea)
  ip6tables -N OUC_LEAKGUARD 2>/dev/null
  ip6tables -F OUC_LEAKGUARD
  ip6tables -A OUC_LEAKGUARD -o lo   -j ACCEPT
  ip6tables -A OUC_LEAKGUARD -m state --state ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A OUC_LEAKGUARD -d fe80::/10      -j ACCEPT
  ip6tables -A OUC_LEAKGUARD -d 2606:4700::/32 -j ACCEPT
  ip6tables -A OUC_LEAKGUARD -o $IFACE         -j ACCEPT
  if [ "$SERVER_SAFE" = 1 ]; then
    ip6tables -A OUC_LEAKGUARD -p tcp --sport "$SSH_PORT" -j ACCEPT
    ip6tables -A OUC_LEAKGUARD -p udp --dport 53 -j ACCEPT
    ip6tables -A OUC_LEAKGUARD -p tcp --dport 53 -j ACCEPT
  fi
  ip6tables -A OUC_LEAKGUARD -j DROP
  ip6tables -C OUTPUT -j OUC_LEAKGUARD 2>/dev/null || ip6tables -I OUTPUT -j OUC_LEAKGUARD
}

# on very first boot the unit may start before network is up — be patient
for i in 1 2 3 4 5 6; do
  w status >/dev/null 2>&1 && break
  sleep 10
done

while true; do
  if [ "$SERVER_SAFE" = 1 ]; then
    # Pin first, tunnel second — and never raise the tunnel if the pin failed.
    # A wrong pin is exactly how a remote box loses its SSH session.
    if pin_ssh_route; then
      w mode warp
      ensure_connected || true
      nft_ssh_holes          # warp recreates its firewall on every connect
      ensure_guard
    else
      echo "cannot pin sshd replies to the physical link — refusing to raise the tunnel"
    fi
  else
    w mode warp
    ensure_connected || true
    ensure_guard
  fi
  sleep $TICK
done
