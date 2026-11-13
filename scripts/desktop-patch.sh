#!/usr/bin/env bash
# desktop-patch — let the OpenCode *desktop* app use the opencode-unlimited lane.
#
# Why this is needed
#   The desktop app never runs ~/.local/bin/opencode (the lane wrapper). At
#   startup it copies its own bundled CLI:
#
#       /opt/OpenCode/resources/opencode-cli
#          ->  <userData>/cli/<version>/opencode-cli
#
#   and then spawns *that* file as its background server ("serve --service").
#   So the lane is bypassed: opencode.ai is not pinned to a random Cloudflare
#   edge and IPv6 is not forced. The guard can still rotate the WARP /64, but
#   if the app keeps talking over IPv4 a new /64 does not give a new bucket.
#
# What it does
#   * keeps the real binary as  resources/opencode-cli.real
#   * replaces  resources/opencode-cli  with a 3-line wrapper that runs the real
#     binary through zen-lane.sh, and does the same for copies already staged in
#     <userData>/cli/<version>/  (the app reuses a staged copy if it exists)
#
#   The lane only creates a *mount* namespace (bind-mounted /etc/hosts), the
#   network namespace is shared, so the app can still reach its own server on
#   127.0.0.1 / the unix socket.
#
# Usage
#   ./desktop-patch.sh install     # after install.sh, and again after every app update
#   ./desktop-patch.sh undo        # back to the stock bundled CLI
#   ./desktop-patch.sh status      # is the patch active?
#
# Caveat
#   This is not supported by OpenCode. Installing/updating the desktop app puts
#   the original binary back, so run `install` again afterwards.
set -u

BRAND="opencode-unlimited"
LANE="$HOME/.local/share/$BRAND/scripts/zen-lane.sh"
APP_ROOT="${OUC_DESKTOP_ROOT:-/opt/OpenCode}"
SRC_CLI="$APP_ROOT/resources/opencode-cli"
REAL_CLI="$APP_ROOT/resources/opencode-cli.real"
MARK="opencode-unlimited: desktop wrapper"

say() { echo -e "  $*"; }
ok()  { echo -e "  \e[32m✓\e[0m $*"; }
bad() { echo -e "  \e[31m✗\e[0m $*"; }
die() { bad "$*"; exit 1; }

# /opt belongs to root; anything under $HOME does not.
root() { if [ -w "$APP_ROOT/resources" ]; then "$@"; else sudo "$@"; fi; }

is_ours() { [ -f "$1" ] && head -c 512 "$1" 2>/dev/null | grep -qF "$MARK"; }

# The userData folder name differs between builds (@opencode/desktop, OpenCode,
# ...), so do not guess it: the staged copies live at <userData>/cli/<ver>/
# opencode-cli.
staged_list() {
  find "$HOME/.config" "$HOME/.local/share" -type f -name opencode-cli \
       -path '*/cli/*' 2>/dev/null
}

write_wrapper() { # dest  app|user
  local dest="$1" where="$2" tmp
  tmp="$(mktemp 2>/dev/null)" || die "mktemp failed"
  cat > "$tmp" <<EOF
#!/usr/bin/env bash
# $MARK (managed by desktop-patch.sh — do not edit)
export OUC_REAL_BIN="$REAL_CLI"
exec /bin/bash "$LANE" "\$@"
EOF
  if [ "$where" = app ]; then
    root install -m 755 "$tmp" "$dest"
  else
    install -m 755 "$tmp" "$dest"
  fi
  local rc=$?
  rm -f "$tmp"
  [ "$rc" = 0 ] || die "cannot write $dest"
}

running() { command -v pgrep >/dev/null 2>&1 && pgrep -f 'opencode-cli' >/dev/null 2>&1; }

install_patch() {
  [ -f "$LANE" ] || die "lane not installed yet — run ./install.sh first"
  [ -x "$SRC_CLI" ] || die "OpenCode Desktop not found at $APP_ROOT (installed?)"
  running && die "OpenCode Desktop is running — quit it completely, then run me again"

  if is_ours "$SRC_CLI"; then
    ok "bundled CLI already wrapped"
  else
    root cp -a "$SRC_CLI" "$REAL_CLI" || die "cannot back up the bundled CLI"
    write_wrapper "$SRC_CLI" app
    ok "bundled CLI wrapped: $SRC_CLI"
  fi

  local n=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_ours "$f" && continue
    write_wrapper "$f" user
    n=$((n + 1))
  done < <(staged_list)
  [ "$n" -gt 0 ] && ok "wrapped $n already-staged copy/copies"

  echo ""
  say "start OpenCode Desktop now — its server should egress through WARP (v6)."
  say "watch the rotation:  tail -f ~/.local/share/$BRAND/guard/guard.log"
}

undo_patch() {
  if [ -f "$REAL_CLI" ]; then
    root install -m 755 "$REAL_CLI" "$SRC_CLI" || die "cannot restore the bundled CLI"
    root rm -f "$REAL_CLI"
    ok "bundled CLI restored"
  else
    say "! no backup at $REAL_CLI — reinstall the desktop app to be safe"
  fi

  local n=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_ours "$f" || continue
    rm -f "$f" && n=$((n + 1))
  done < <(staged_list)
  [ "$n" -gt 0 ] && ok "removed $n staged wrapper(s) — the app re-copies the real CLI"
  ok "done"
}

status_patch() {
  if [ ! -x "$SRC_CLI" ] && [ ! -f "$REAL_CLI" ]; then
    say "OpenCode Desktop not installed ($APP_ROOT)"
    return
  fi
  if is_ours "$SRC_CLI"; then
    ok "bundled CLI : wrapped (lane)"
  else
    bad "bundled CLI : original (lane bypassed)"
  fi
  [ -f "$REAL_CLI" ] && say "  real binary : $REAL_CLI"

  local any=0 f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if is_ours "$f"; then ok "staged      : $f"; else bad "staged      : $f (original)"; fi
    any=1
  done < <(staged_list)
  [ "$any" = 0 ] && say "  staged      : none yet (app has never started)"
  return 0
}

echo ""
echo "  Opencode Unlimited — desktop app patch"
echo "  --------------------------------------"

case "${1:-install}" in
  install|on)  install_patch ;;
  undo|off)    undo_patch ;;
  status)      status_patch ;;
  *)           say "usage: $0 [install|undo|status]"; exit 1 ;;
esac
echo ""
