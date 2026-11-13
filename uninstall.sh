#!/usr/bin/env bash
# Clean removal for the OpenCode 2.x build.
# Removes services, firewall chains, sudoers entry, wrapper, PATH tools and
# state. Your OpenCode data, sessions and auth are untouched (and the V1
# backup kept by install.sh is never deleted).
set -u

BRAND="opencode-unlimited"
DEST="$HOME/.local/share/$BRAND"
SHIM="$HOME/.local/bin/opencode"

# `su - user` from a root console does not export the session bus, and every
# `systemctl --user` call would then fail silently.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

ok()  { echo -e "  \e[32m✓\e[0m $*"; }
say() { echo -e "  $*"; }

echo ""
echo "  removing Opencode Unlimited Usage…"
echo ""

WARP="${OUC_WARP_BIN:-}"
if [ -z "$WARP" ]; then
  if command -v warp-cli >/dev/null 2>&1; then WARP="$(command -v warp-cli)"
  elif [ -x /usr/bin/warp-cli ]; then WARP=/usr/bin/warp-cli
  elif [ -x "$HOME/.local/bin/warp-cli" ]; then WARP="$HOME/.local/bin/warp-cli"
  fi
fi
IPT="${OUC_IPTABLES:-$(command -v iptables 2>/dev/null || echo /usr/sbin/iptables)}"
IP6T="${OUC_IP6TABLES:-$(command -v ip6tables 2>/dev/null || echo /usr/sbin/ip6tables)}"

# ---------------------------------------------------------------- services
systemctl --user disable --now "${BRAND}-guard.service" >/dev/null 2>&1 && ok "zen-guard stopped"
rm -f "$HOME/.config/systemd/user/${BRAND}-guard.service"
systemctl --user daemon-reload >/dev/null 2>&1

sudo systemctl disable --now "${BRAND}-keeper.service" >/dev/null 2>&1 && ok "keeper stopped"
sudo rm -f "/etc/systemd/system/${BRAND}-keeper.service" "/usr/local/bin/${BRAND}-keeper"
sudo systemctl daemon-reload >/dev/null 2>&1

# ---------------------------------------------------------------- firewall
sudo "$IPT"  -D OUTPUT -j OUC_LEAKGUARD 2>/dev/null
sudo "$IPT"  -F OUC_LEAKGUARD 2>/dev/null
sudo "$IPT"  -X OUC_LEAKGUARD 2>/dev/null
sudo "$IP6T" -D OUTPUT -j OUC_LEAKGUARD 2>/dev/null
sudo "$IP6T" -F OUC_LEAKGUARD 2>/dev/null
sudo "$IP6T" -X OUC_LEAKGUARD 2>/dev/null
ok "kill-switch removed (traffic can leave normally again)"

# ---------------------------------------------------------------- route pin
# server mode only: mark chain, nft holes, private table and its rule
for fam in "" "-6"; do
  sudo ip $fam rule list 2>/dev/null | grep -F 'lookup 111' \
    | sed 's/:.*//' | while read -r p; do sudo ip $fam rule del priority "$p" 2>/dev/null; done
  sudo ip $fam route flush table 111 2>/dev/null
done
for t in iptables ip6tables; do
  sudo $t -t mangle -D OUTPUT -j OUC_SSHOUT 2>/dev/null
  sudo $t -t mangle -F OUC_SSHOUT 2>/dev/null
  sudo $t -t mangle -X OUC_SSHOUT 2>/dev/null
done
if command -v nft >/dev/null 2>&1; then
  for chain in input output; do
    nft -a list chain inet cloudflare-warp "$chain" 2>/dev/null \
      | grep -E 'tcp (sport|dport) (22|[0-9]+) accept' \
      | sed -n 's/.*# handle \([0-9]*\).*/\1/p' \
      | while read -r h; do sudo nft delete rule inet cloudflare-warp "$chain" handle "$h" 2>/dev/null; done
  done
fi

# ---------------------------------------------------------------- sudoers
sudo rm -f "/etc/sudoers.d/$BRAND" && ok "sudoers entry removed"

# ---------------------------------------------------------------- V2 service
# V2's shared background server is what `opencode pair` talks to. Put it back to
# the default (enabled) so pairing keeps working after the uninstall.
REAL=""
for c in "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode /usr/bin/opencode; do
  [ -x "$c" ] || continue
  head -c 4096 "$c" 2>/dev/null | grep -q 'zen-lane' && continue
  REAL="$c"; break
done
if [ -n "$REAL" ]; then
  "$REAL" service unset disabled >/dev/null 2>&1 \
    && ok "V2 background service re-enabled" \
    || say "! re-enable manually if you want the shared server: $REAL service unset disabled"
fi

# ---------------------------------------------------------------- wrapper
# rm first: the shim may be a symlink to the real binary.
rm -f "$SHIM"
if [ -n "$REAL" ]; then
  printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$REAL" > "$SHIM"
  chmod +x "$SHIM"
  ok "opencode entry → back to the stock binary"
fi

# ---------------------------------------------------------------- PATH block
RC=""
case "$(basename "${SHELL:-bash}")" in
  zsh)          RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash|sh|dash) RC="$HOME/.bashrc" ;;
esac
if [ -n "$RC" ] && [ -f "$RC" ]; then
  grep -vF '# opencode-unlimited PATH' "$RC" \
    | grep -vF 'opencode-unlimited/path.sh' > "$RC.ouc.tmp" \
    && mv "$RC.ouc.tmp" "$RC"
fi
rm -f "$HOME/.config/opencode-unlimited/path.sh"
rmdir "$HOME/.config/opencode-unlimited" 2>/dev/null
ok "PATH block removed (reopen the terminal)"

# ---------------------------------------------------------------- credit file
# Only remove ours; a user-written AGENTS.md survives.
if [ -f "$HOME/.opencode/AGENTS.md" ] && grep -q "ElectronCursed" "$HOME/.opencode/AGENTS.md"; then
  rm -f "$HOME/.opencode/AGENTS.md"
  ok "legacy credit file removed"
fi

# ---------------------------------------------------------------- state
rm -f "$HOME/.local/bin/${BRAND}-hop" "$HOME/.local/bin/${BRAND}-doctor" \
      "$HOME/.local/bin/${BRAND}-share" "$HOME/.local/bin/${BRAND}-uninstall"
rm -rf "$DEST" && ok "scripts + guard state removed"
say "V1 backups kept in: $HOME/.local/share/opencode-unlimited-backups"

# Leave the warp package installed (it is a normal system package now) but
# drop the tunnel so normal networking resumes.
if [ -n "$WARP" ] && [ -x "$WARP" ]; then
  sudo "$WARP" --accept-tos disconnect >/dev/null 2>&1 \
    && ok "warp tunnel disconnected (package left installed)"
fi

echo ""
ok "gone. opencode itself + your sessions are untouched."
echo ""
