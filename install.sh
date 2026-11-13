#!/usr/bin/env bash
# Opencode Unlimited Usage — installer for OpenCode 2.x
#
# What this installs:
#   OpenCode 2.x (official V2 installer)
#   Cloudflare WARP + TUN mode
#   keeper (root service)  : tunnel up + kill-switch firewall
#   zen-guard (user service): detects the free-tier wall, rotates the /64
#   zen-lane (wrapper)      : per-launch random edge + /64 + private server
#   doctor / hop            : health check and manual rotation
#
# No credit injection: OpenCode V2 reads global instructions from
# ~/.config/opencode/AGENTS.md, not ~/.opencode/AGENTS.md. That feature is
# V1-only in practice and is intentionally dropped here.
set -u

BRAND="opencode-unlimited"
USER="${USER:-$(id -un)}"
DEST="$HOME/.local/share/$BRAND"
UNIT_KEEPER="/etc/systemd/system/${BRAND}-keeper.service"
UNIT_GUARD="$HOME/.config/systemd/user/${BRAND}-guard.service"
SHIM="$HOME/.local/bin/opencode"
SUDOERS_FILE="/etc/sudoers.d/$BRAND"
BACKUP_ROOT="$HOME/.local/share/opencode-unlimited-backups"

# Remote-server mode: `OUC_SERVER=1 ./install.sh`
#   - keeps the SSH session alive (explicit ACCEPT + direct route)
#   - allows DNS so apt/network tools still work
#   - keeps user services alive after logout
SERVER_MODE="${OUC_SERVER:-0}"
# SSH_CLIENT ("ip port port") is what sshd puts in the login shell env. The
# manual override exists for tmux/screen sessions started ages ago, or when
# you reconnect from a different address.
SSH_IP="${OUC_SSH_CLIENT_IP:-${SSH_CLIENT:-}}"; SSH_IP="${SSH_IP%% *}"
SSH_PORT="${OUC_SSH_PORT:-22}"

say() { echo -e "  $*"; }
ok()  { echo -e "  \e[32m✓\e[0m $*"; }
bad() { echo -e "  \e[31m✗\e[0m $*"; }
die() { bad "$*"; exit 1; }

# This bundle is meant to be run from the extracted folder: it needs ./scripts.
# (Fetching "the same script names" from the V1 repo would silently install V1
# code, so we refuse instead of guessing.)
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd)"
{ [ -n "$SRC" ] && [ -d "$SRC/scripts" ]; } \
  || die "run install.sh from the extracted folder (./scripts must sit next to it)"

echo ""
echo "  ================================="
echo "  Opencode Unlimited — OpenCode 2.x"
echo "  ================================="
echo ""

# ---------------------------------------------------------------- platform
# Everything this project installs is per-user. Running the installer as root
# would put files in /root, bind the user service to the wrong systemd manager
# and leave the sudoers rules pointing at a user that never logs in.
#
# So when root runs it, we create (or reuse) a normal account, ask for the name
# and the password, and re-run this same script as that account. A temporary
# NOPASSWD entry covers the sudo calls of the second pass and is deleted before
# we exit.
if [ "$(id -u)" = 0 ]; then
  SELF="$SRC/install.sh"
  # `[ -r /dev/tty ]` lies when there is no controlling terminal; opening it is
  # the only reliable test.
  HAVE_TTY=0
  if { : < /dev/tty; } 2>/dev/null; then HAVE_TTY=1; fi

  # Read a line without echoing it (passwords). Falls back to plain read when
  # there is no tty at all — the caller decides what that means.
  read_secret() {
    printf "%s" "$1"
    SECRET=""
    if [ "$HAVE_TTY" = 1 ]; then
      STTY_SAVE="$(stty -g < /dev/tty 2>/dev/null || true)"
      stty -echo < /dev/tty 2>/dev/null || true
      read -r SECRET < /dev/tty 2>/dev/null || SECRET=""
      [ -n "$STTY_SAVE" ] && stty "$STTY_SAVE" < /dev/tty 2>/dev/null || true
      printf "\n"
    else
      read -r SECRET 2>/dev/null || SECRET=""
    fi
  }

  echo ""
  say "you are root. this project installs per user, so I will create a normal"
  say "account and continue as that account."
  echo ""

  printf "  username for the new account [opencode]: "
  NEWUSER=""
  if [ "$HAVE_TTY" = 1 ]; then
    read -r NEWUSER < /dev/tty 2>/dev/null || NEWUSER=""
  else
    read -r NEWUSER 2>/dev/null || NEWUSER=""
  fi
  NEWUSER="${NEWUSER:-opencode}"
  case "$NEWUSER" in
    ''|*[!a-z0-9_-]*) die "invalid username '$NEWUSER' — lowercase letters, digits, - and _ only" ;;
  esac
  case "$NEWUSER" in
    [0-9]*) die "username cannot start with a digit" ;;
  esac
  [ ${#NEWUSER} -le 32 ] || die "username too long (max 32)"
  [ "$NEWUSER" = root ] && die "pick a name other than root"

  NEWPW=""
  PW_SOURCE=""
  if id "$NEWUSER" >/dev/null 2>&1; then
    say "user '$NEWUSER' already exists — continuing as that user"
    say "  (its password is unchanged)"
    PW_SOURCE=existing
  else
    # The password is asked twice and never echoed. Unattended root installs
    # (cloud-init, docker, no tty) can pass OUC_PASSWORD instead.
    if [ -n "${OUC_PASSWORD:-}" ]; then
      NEWPW="$OUC_PASSWORD"
      case "$NEWPW" in
        *:*) die "OUC_PASSWORD cannot contain ':'" ;;
      esac
      PW_SOURCE=env
    elif [ "$HAVE_TTY" = 1 ]; then
      PW_TRIES=0
      while [ "$PW_TRIES" -lt 3 ]; do
        PW_TRIES=$((PW_TRIES + 1))
        read_secret "  password for '$NEWUSER': "
        NEWPW="$SECRET"
        if [ -z "$NEWPW" ]; then
          say "! empty password — try again"
          continue
        fi
        case "$NEWPW" in
          *:*) say "! a password cannot contain ':' — try again"; NEWPW=""; continue ;;
        esac
        if [ ${#NEWPW} -lt 6 ]; then
          say "! use at least 6 characters — try again"
          NEWPW=""
          continue
        fi
        read_secret "  repeat the password: "
        if [ "$NEWPW" != "$SECRET" ]; then
          say "! the two passwords do not match — try again"
          NEWPW=""
          continue
        fi
        break
      done
      [ -n "$NEWPW" ] || die "no usable password after 3 tries — nothing was created"
      PW_SOURCE=typed
    else
      NEWPW="$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 12)"
      [ -n "$NEWPW" ] || NEWPW="opencode$(date +%s | tail -c 5)"
      PW_SOURCE=generated
      say "no terminal to ask on — generated a password for '$NEWUSER'"
    fi

    CREATED=0
    if command -v adduser >/dev/null 2>&1 \
       && adduser --disabled-password --gecos "" "$NEWUSER" >/dev/null 2>&1; then
      CREATED=1
    elif command -v useradd >/dev/null 2>&1 \
       && useradd -m -s /bin/bash "$NEWUSER" >/dev/null 2>&1; then
      CREATED=1
    fi
    [ "$CREATED" = 1 ] || die "could not create user '$NEWUSER'"

    printf '%s:%s\n' "$NEWUSER" "$NEWPW" | chpasswd 2>/dev/null \
      || say "! could not set the password — set one later with: passwd $NEWUSER"

    SUDO_GROUP=""
    if getent group sudo >/dev/null 2>&1 || grep -q '^sudo:' /etc/group 2>/dev/null; then
      SUDO_GROUP=sudo
    elif getent group wheel >/dev/null 2>&1 || grep -q '^wheel:' /etc/group 2>/dev/null; then
      SUDO_GROUP=wheel
    fi
    if [ -n "$SUDO_GROUP" ]; then
      usermod -aG "$SUDO_GROUP" "$NEWUSER" || say "! could not add '$NEWUSER' to $SUDO_GROUP"
    fi
    ok "user '$NEWUSER' created${SUDO_GROUP:+ (group: $SUDO_GROUP)}"
  fi

  # The bundle lives in a root-only temp dir; the second pass reads it as $NEWUSER.
  chmod -R a+rX "$(dirname "$SRC")" 2>/dev/null
  loginctl enable-linger "$NEWUSER" >/dev/null 2>&1 \
    || say "! could not enable lingering for '$NEWUSER' (the guard needs it after reboot)"

  # The second pass needs that user's systemd manager (user@UID.service), and
  # `runuser -l` does not create one the way a real login does. enable-linger
  # usually starts it, but not instantly — so start it explicitly and wait for
  # /run/user/UID. Without this a fresh root install dies with
  # "user systemd is not running (are you inside a bare container?)".
  NEWUID="$(id -u "$NEWUSER" 2>/dev/null || true)"
  if [ -n "$NEWUID" ]; then
    systemctl start "user@$NEWUID.service" >/dev/null 2>&1 || true
    for i in $(seq 1 15); do
      [ -S "/run/user/$NEWUID/systemd/private" ] && break
      sleep 1
    done
  fi

  TMP_SUDO="/etc/sudoers.d/opencode-unlimited-install"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$NEWUSER" > "$TMP_SUDO"
  chmod 0440 "$TMP_SUDO"
  if ! visudo -cf "$TMP_SUDO" >/dev/null 2>&1; then
    rm -f "$TMP_SUDO"
    die "temporary sudoers file failed validation — aborting"
  fi
  cleanup_sudo() { rm -f "$TMP_SUDO"; }
  trap cleanup_sudo EXIT INT TERM

  # `runuser -l` / `su -` start a login shell, so every OUC_* set by the caller
  # is gone in the second pass. Forward the ones that change behaviour —
  # otherwise a root install silently ends up WITHOUT server mode.
  FORWARD=""
  for _v in OUC_SERVER OUC_PAIR OUC_SSH_CLIENT_IP OUC_SSH_PORT; do
    _val="$(printenv "$_v" 2>/dev/null || true)"
    [ -n "$_val" ] && FORWARD="$FORWARD $_v=$(printf '%q' "$_val")"
  done
  unset _v _val
  RUN="bash '$SELF'"
  [ -n "$FORWARD" ] && RUN="$FORWARD $RUN"

  echo ""
  say "starting the installer again as '$NEWUSER'…"
  [ "$SERVER_MODE" = 1 ] && say "  server mode is carried over (OUC_SERVER=1)"
  echo ""
  if command -v runuser >/dev/null 2>&1; then
    RUNNER="runuser -l $NEWUSER -c"
  else
    RUNNER="su - $NEWUSER -c"
  fi
  if [ "$HAVE_TTY" = 1 ]; then
    $RUNNER "$RUN" < /dev/tty
  else
    $RUNNER "$RUN" < /dev/null
  fi
  RC=$?

  cleanup_sudo
  trap - EXIT INT TERM
  chown -R "$NEWUSER": "/home/$NEWUSER" 2>/dev/null

  echo ""
  if [ "$RC" = 0 ]; then
    ok "installed for user '$NEWUSER'"
    say "  username : $NEWUSER"
    case "$PW_SOURCE" in
      generated) say "  password : $NEWPW   (generated — change it later: passwd)" ;;
      env)       say "  password : the one from OUC_PASSWORD" ;;
      existing)  : ;;
      *)         say "  password : the one you typed   (change it later: passwd)" ;;
    esac
    say "  log in as that user, then run:  opencode"
    say "  from another device:            opencode pair"
  else
    bad "install failed (exit $RC) — the messages above say why"
  fi
  exit "$RC"
fi
command -v systemctl >/dev/null 2>&1 || die "systemd not found — linux+systemd only"
command -v python3 >/dev/null 2>&1 || die "python3 required (needed by guard/doctor)"
command -v curl    >/dev/null 2>&1 || die "curl required"
# The user manager can take a moment to appear after a fresh account is created.
USERD=0
for i in $(seq 1 15); do
  systemd-run --user --scope true >/dev/null 2>&1 && { USERD=1; break; }
  sleep 1
done
if [ "$USERD" = 0 ]; then
  bad "your user systemd manager (user@$(id -u).service) is not reachable"
  say "fix it, then run this again:"
  say "  sudo loginctl enable-linger $USER"
  say "  sudo systemctl start user@$(id -u).service"
  say "  log out and back in        # a console/su login starts it for real"
  say "if all three still fail, the VPS is a container (LXC) and cannot run TUN"
  exit 1
fi
[ -e /dev/net/tun ] || die "/dev/net/tun missing — enable TUN in your VM first"

# The lane cannot work without unprivileged user namespaces. Stop now instead
# of installing half a system (Ubuntu 24.04 / Mint 22.x restrict them by default).
if ! unshare -rm true 2>/dev/null; then
  bad "unprivileged user namespaces are blocked (unshare -rm fails)"
  say "run this, then re-run install.sh:"
  say "  echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/99-opencode-userns.conf"
  say "  sudo sysctl --system"
  exit 1
fi

# ---------------------------------------------------------------- sudo
if ! sudo -n true 2>/dev/null; then
  if bash -c 'sudo -v </dev/tty' 2>/dev/null; then
    ok "sudo authenticated"
  elif [ ! -t 0 ]; then
    sudo -S -v >/dev/null 2>&1 || die "sudo failed (password from stdin was wrong)"
    ok "sudo authenticated (stdin)"
  else
    die "sudo failed — run me from a real terminal"
  fi
fi

# Server mode: without lingering, the per-user systemd manager (and therefore
# zen-guard) stops as soon as you close the SSH session.
if [ "$SERVER_MODE" = 1 ]; then
  sudo loginctl enable-linger "$USER" >/dev/null 2>&1 \
    && ok "linger enabled (guard survives logout)" \
    || say "! run manually: sudo loginctl enable-linger $USER"
  if [ -z "$SSH_IP" ]; then
    say "! could not detect your SSH client IP — the session is NOT pinned."
    say "  abort now (Ctrl+C) if losing SSH is a risk, then run:"
    say "  OUC_SERVER=1 OUC_SSH_CLIENT_IP=<your.ip> ./install.sh"
  fi
fi

# ---------------------------------------------------------------- distro
PKR=""
command -v apt-get >/dev/null 2>&1 && PKR=apt
[ -z "$PKR" ] && command -v dnf    >/dev/null 2>&1 && PKR=dnf
[ -z "$PKR" ] && command -v pacman >/dev/null 2>&1 && PKR=pacman
[ -n "$PKR" ] || die "no apt/dnf/pacman — install cloudflare-warp yourself, then re-run"

# ---------------------------------------------------------------- helpers
# A previous install put our wrapper at ~/.local/bin/opencode. It must never
# be treated as the real binary (that is how the old installer recursed).
is_wrapper() {
  [ -f "$1" ] || return 1
  head -c 4096 "$1" 2>/dev/null | grep -q 'zen-lane'
}

detect_real() {
  local c r self
  self="$(readlink -f "$SHIM" 2>/dev/null || echo "$SHIM")"
  for c in "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode /usr/bin/opencode \
           "$(command -v opencode 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    r="$(readlink -f "$c" 2>/dev/null || echo "$c")"
    [ "$r" = "$self" ] && continue
    is_wrapper "$r" && continue
    printf '%s' "$r"
    return 0
  done
  return 1
}

oc_major() {
  "$1" --version 2>/dev/null | tr -d '\r' | awk '{print $NF}' \
    | sed 's/^v//' | cut -d. -f1
}

# ---------------------------------------------------------------- warp-cli
WARP=""
if command -v warp-cli >/dev/null 2>&1; then
  WARP="$(command -v warp-cli)"
elif [ -x "$HOME/.local/bin/warp-cli" ]; then
  WARP="$HOME/.local/bin/warp-cli"
fi
if [ -z "$WARP" ]; then
  say "warp-cli not found — installing cloudflare warp client"
  case "$PKR" in
    apt)
      sudo apt-get update -qq >/dev/null 2>&1
      sudo apt-get install -y -qq curl gpg lsb-release ca-certificates >/dev/null 2>&1
      # Linux Mint reports its own codename (zena, zara, xia, ...). Cloudflare's
      # repo only publishes Ubuntu codenames, so prefer UBUNTU_CODENAME.
      CODENAME="$(. /etc/os-release 2>/dev/null; printf '%s' "${UBUNTU_CODENAME:-}")"
      [ -n "$CODENAME" ] || CODENAME="$(lsb_release -cs 2>/dev/null)"
      [ -n "$CODENAME" ] || die "cannot detect the Ubuntu base codename for the WARP repo"
      curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | sudo gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg >/dev/null 2>&1
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $CODENAME main" \
        | sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
      sudo apt-get update -qq >/dev/null 2>&1
      sudo apt-get install -y -qq cloudflare-warp >/dev/null 2>&1
      ;;
    dnf)
      sudo dnf -y install gpg >/dev/null 2>&1
      REL=$(curl -fsSL https://api.github.com/repos/cloudflare-warp/cloudflare-warp-rpm/releases/latest 2>/dev/null \
        | python3 -c "import json,sys
try:
    a=json.load(sys.stdin)['assets']
    print(next(x['browser_download_url'] for x in a if 'x86_64.rpm' in x['name']))
except Exception:
    print('')" 2>/dev/null)
      if [ -n "$REL" ]; then
        curl -fsSL "$REL" -o /tmp/warp-install.rpm \
          && sudo dnf -y install /tmp/warp-install.rpm >/dev/null 2>&1 \
          && rm -f /tmp/warp-install.rpm
      else
        sudo dnf -y install cloudflare-warp >/dev/null 2>&1
      fi
      ;;
    pacman)
      if command -v yay >/dev/null 2>&1; then
        yay -S --noconfirm cloudflare-warp-bin >/dev/null 2>&1
      elif command -v paru >/dev/null 2>&1; then
        paru -S --noconfirm cloudflare-warp-bin >/dev/null 2>&1
      else
        die "arch needs yay or paru for cloudflare-warp-bin"
      fi
      ;;
  esac
  command -v warp-cli >/dev/null 2>&1 && WARP="$(command -v warp-cli)"
  [ -n "$WARP" ] || die "warp-cli install failed — see https://pkg.cloudflareclient.com/"
  ok "cloudflare warp installed"
else
  ok "warp-cli found: $WARP"
fi

# warp-cli wrappers: try with --accept-tos first, then without.
sw()  { sudo -n "$WARP" --accept-tos "$@" >/dev/null 2>&1 && return 0; sudo -n "$WARP" "$@" >/dev/null 2>&1; }
swo() { sudo -n "$WARP" --accept-tos "$@" 2>/dev/null && return 0; sudo -n "$WARP" "$@" 2>/dev/null; }

# ---------------------------------------------------------------- OpenCode 2.x
OC_REAL="$(detect_real || true)"
M=0
if [ -n "$OC_REAL" ]; then
  M="$(oc_major "$OC_REAL")"
  case "$M" in ''|*[!0-9]*) M=0 ;; esac
fi

if [ -n "$OC_REAL" ] && [ "$M" -ge 2 ]; then
  ok "opencode V2 already present: $("$OC_REAL" --version 2>/dev/null | tr -d '\r')"
else
  # V1 -> V2 migrates the database one way. Back up before touching anything,
  # as long as there is something to lose.
  if [ -e "$HOME/.local/share/opencode/opencode.db" ] || [ -d "$HOME/.config/opencode" ]; then
    [ -n "$OC_REAL" ] && say "opencode V1 detected ($("$OC_REAL" --version 2>/dev/null | tr -d '\r')) — upgrading to V2"
    ts="$(date +%Y%m%d-%H%M%S)"
    BK="$BACKUP_ROOT/$ts"
    mkdir -p "$BK/data" "$BK/config" || die "cannot create backup dir $BK"

    # Consistent SQLite copy (cp of a live DB + WAL is not reliable).
    if [ -e "$HOME/.local/share/opencode/opencode.db" ]; then
      python3 - "$HOME/.local/share/opencode/opencode.db" "$BK/data/opencode.db" <<'PY' \
        || cp -a "$HOME/.local/share/opencode/opencode.db" "$BK/data/" 2>/dev/null
import sqlite3, sys
src = sqlite3.connect(sys.argv[1])
dst = sqlite3.connect(sys.argv[2])
with dst:
    src.backup(dst)
dst.close(); src.close()
PY
    fi
    for f in auth.json; do
      [ -e "$HOME/.local/share/opencode/$f" ] \
        && cp -a "$HOME/.local/share/opencode/$f" "$BK/data/" 2>/dev/null
    done
    # V1 kept session history as JSON files, not in a DB.
    [ -d "$HOME/.local/share/opencode/storage" ] \
      && cp -a "$HOME/.local/share/opencode/storage" "$BK/data/" 2>/dev/null
    [ -d "$HOME/.config/opencode" ] \
      && cp -a "$HOME/.config/opencode/." "$BK/config/" 2>/dev/null
    ok "pre-upgrade backup: $BK"
  fi

  say "installing OpenCode V2 (official installer)…"
  curl -fsSL https://opencode.ai/v2/install | bash >/dev/null 2>&1 || true

  OC_REAL="$(detect_real || true)"
  [ -n "$OC_REAL" ] || die "OpenCode V2 install failed — see https://opencode.ai/v2/install"
  M="$(oc_major "$OC_REAL")"
  case "$M" in ''|*[!0-9]*) M=0 ;; esac
  [ "$M" -ge 2 ] || die "installer produced V1 ($("$OC_REAL" --version 2>/dev/null)) — aborting"
  ok "OpenCode V2 installed: $("$OC_REAL" --version 2>/dev/null | tr -d '\r')"
fi

# V2 runs a shared background server. Pairing (`opencode pair`) needs it, and
# the terminal does not: zen-lane always adds --standalone, so the TUI gets its
# own private server inside the lane either way.
#
# Default: leave the shared server available, so `opencode pair` works with no
# extra steps. Strict mode (OUC_PAIR=0) disables it and forces private servers.
PAIR_MODE="${OUC_PAIR:-1}"
if [ "$PAIR_MODE" = 0 ]; then
  if "$OC_REAL" service set disabled true >/dev/null 2>&1; then
    ok "V2 background service disabled (private server per launch)"
  else
    say "! could not disable the V2 background service automatically"
    say "  run once:  $OC_REAL service set disabled true"
  fi
else
  "$OC_REAL" service unset disabled >/dev/null 2>&1
  if "$OC_REAL" service start >/dev/null 2>&1; then
    ok "pairing ready — shared service running ('opencode pair' works as-is)"
  else
    say "! shared service did not start; try:  $OC_REAL service start"
  fi
fi

# ---------------------------------------------------------------- scripts
mkdir -p "$DEST/scripts" "$HOME/.local/bin"
cp "$SRC/scripts/"*.sh "$DEST/scripts/" || die "could not copy scripts"
chmod +x "$DEST/scripts/"*.sh
# keep the uninstaller too: people delete the extracted folder
cp "$SRC/uninstall.sh" "$DEST/uninstall.sh" 2>/dev/null && chmod +x "$DEST/uninstall.sh"
ln -sf "$DEST/scripts/zen-hop.sh" "$HOME/.local/bin/${BRAND}-hop"
ln -sf "$DEST/scripts/doctor.sh"  "$HOME/.local/bin/${BRAND}-doctor"
[ -f "$DEST/uninstall.sh" ] && ln -sf "$DEST/uninstall.sh" "$HOME/.local/bin/${BRAND}-uninstall"
ok "scripts in $DEST"

# ---------------------------------------------------------------- tool paths
SYSTEMCTL="$(command -v systemctl 2>/dev/null || echo /usr/bin/systemctl)"
IPT="$(command -v iptables 2>/dev/null || echo /usr/sbin/iptables)"
IP6T="$(command -v ip6tables 2>/dev/null || echo /usr/sbin/ip6tables)"

# ---------------------------------------------------------------- sudoers
# Exact commands only:
#   - warp-cli (any args): guard/hop must register a new identity unattended
#   - read-only chain checks for guard/doctor
#   - keeper stop/start so guard/hop can pause it without a password prompt
SUDOERS_NEED="$USER ALL=(root) NOPASSWD: $WARP, $IPT -nL OUC_LEAKGUARD, $IP6T -nL OUC_LEAKGUARD, $SYSTEMCTL stop ${BRAND}-keeper, $SYSTEMCTL start ${BRAND}-keeper"
SUDOERS_NOW="$(sudo -n cat "$SUDOERS_FILE" 2>/dev/null || echo '')"
if [ "$SUDOERS_NOW" != "$SUDOERS_NEED" ]; then
  say "sudoers: passwordless warp-cli + keeper pause + read-only chain check"
  printf '%s\n' "$SUDOERS_NEED" | sudo tee "$SUDOERS_FILE" >/dev/null
  sudo chmod 440 "$SUDOERS_FILE"
  sudo visudo -c >/dev/null 2>&1 || { sudo rm -f "$SUDOERS_FILE"; die "sudoers rejected the generated file"; }
fi
sw status || die "passwordless warp-cli did not work — check $SUDOERS_FILE"
ok "passwordless helpers installed"

# ---------------------------------------------------------------- warp up
say "registering warp + bringing the tunnel up"
sw registration new >/dev/null 2>&1   # already-registered boxes just error, fine

# Server mode: two independent things kill SSH when WARP comes up, and both
# must be handled before the tunnel is raised.
#
#  1. ROUTING. warp-svc installs "<n>: not from all fwmark 0x100cf lookup 65743"
#     which sends EVERY packet into the tunnel. Its priority is not fixed (we
#     measured 4, 19 and 49 on the same box), so racing it with our own
#     priority is fragile. Instead sshd's replies get WARP's own "do not tunnel
#     me" mark: that rule skips them whatever number it picked. A dedicated
#     route table then sends them out of the physical interface.
#
#  2. FILTERING. warp-svc also loads an nftables table "inet cloudflare-warp"
#     whose input and output chains are "policy drop". Routing alone is not
#     enough — every SSH packet is discarded in both directions. Holes for the
#     SSH port are punched after the tunnel is up (see nft_ssh_holes below).
RT_TABLE=111
SSH_MARK=0x100cf        # warp's own bypass mark
SSH_GW=""; SSH_DEV=""
IFACE_NAME="CloudflareWARP"

nft_ssh_holes(){
  command -v nft >/dev/null 2>&1 || { bad "nft not found — cannot open SSH in warp's firewall"; return 1; }
  # note: nft needs root even to list; as a plain user this would look like
  # "table does not exist" and silently skip the holes (that is how the box
  # got locked out once). Always go through sudo.
  sudo nft list table inet cloudflare-warp >/dev/null 2>&1 || return 0   # tunnel not up yet
  sudo nft list chain inet cloudflare-warp input 2>/dev/null | grep -q "tcp dport $SSH_PORT accept" \
    || sudo nft insert rule inet cloudflare-warp input tcp dport "$SSH_PORT" accept 2>/dev/null
  sudo nft list chain inet cloudflare-warp output 2>/dev/null | grep -q "tcp sport $SSH_PORT accept" \
    || sudo nft insert rule inet cloudflare-warp output tcp sport "$SSH_PORT" accept 2>/dev/null
  sudo nft list chain inet cloudflare-warp input 2>/dev/null | grep -q "tcp dport $SSH_PORT accept" || return 1
  sudo nft list chain inet cloudflare-warp output 2>/dev/null | grep -q "tcp sport $SSH_PORT accept" || return 1
  return 0
}

if [ "$SERVER_MODE" = 1 ]; then
  # Pick the physical default route, never the tunnel: if WARP happens to be
  # already connected, "ip route get 1.1.1.1" answers with CloudflareWARP and
  # pinning SSH to that is an instant lockout.
  SSH_DEV="$(ip route show default 2>/dev/null | awk -v w="$IFACE_NAME" '
    { d=""; for (j=1;j<=NF;j++) if ($j=="dev") d=$(j+1)
      if (d!="" && d!=w) { print d; exit } }')"
  SSH_GW="$(ip route show default 2>/dev/null | awk -v w="$IFACE_NAME" '
    { d=""; g=""; for (j=1;j<=NF;j++) { if ($j=="via") g=$(j+1); if ($j=="dev") d=$(j+1) }
      if (d!="" && d!=w) { print g; exit } }')"
  if [ -n "$SSH_DEV" ]; then
    if [ -n "$SSH_GW" ]; then
      sudo ip route replace default via "$SSH_GW" dev "$SSH_DEV" table "$RT_TABLE" 2>/dev/null
    else
      sudo ip route replace default dev "$SSH_DEV" table "$RT_TABLE" 2>/dev/null
    fi
    sudo iptables -t mangle -N OUC_SSHOUT 2>/dev/null
    sudo iptables -t mangle -C OUTPUT -j OUC_SSHOUT 2>/dev/null \
      || sudo iptables -t mangle -I OUTPUT -j OUC_SSHOUT 2>/dev/null
    sudo iptables -t mangle -F OUC_SSHOUT 2>/dev/null
    sudo iptables -t mangle -A OUC_SSHOUT -p tcp --sport "$SSH_PORT" -j MARK --set-mark "$SSH_MARK" 2>/dev/null
    sudo ip rule list 2>/dev/null | grep -q "fwmark $SSH_MARK lookup $RT_TABLE" \
      || sudo ip rule add fwmark "$SSH_MARK" lookup "$RT_TABLE" priority 1 2>/dev/null
    ok "SSH replies pinned to $SSH_DEV (mark $SSH_MARK, port $SSH_PORT)"
  else
    bad "no physical default route found — SSH is NOT protected"
  fi
  # IPv6 mirror, only if this box actually has a v6 default route
  V6GW="$(ip -6 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')"
  V6DEV="$(ip -6 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  if [ -n "$V6DEV" ]; then
    if [ -n "$V6GW" ]; then
      sudo ip -6 route replace default via "$V6GW" dev "$V6DEV" table "$RT_TABLE" 2>/dev/null
    else
      sudo ip -6 route replace default dev "$V6DEV" table "$RT_TABLE" 2>/dev/null
    fi
    sudo ip6tables -t mangle -N OUC_SSHOUT 2>/dev/null
    sudo ip6tables -t mangle -C OUTPUT -j OUC_SSHOUT 2>/dev/null \
      || sudo ip6tables -t mangle -I OUTPUT -j OUC_SSHOUT 2>/dev/null
    sudo ip6tables -t mangle -F OUC_SSHOUT 2>/dev/null
    sudo ip6tables -t mangle -A OUC_SSHOUT -p tcp --sport "$SSH_PORT" -j MARK --set-mark "$SSH_MARK" 2>/dev/null
    sudo ip -6 rule list 2>/dev/null | grep -q "fwmark $SSH_MARK lookup $RT_TABLE" \
      || sudo ip -6 rule add fwmark "$SSH_MARK" lookup "$RT_TABLE" priority 1 2>/dev/null
    ok "SSH v6 replies pinned too ($V6DEV)"
  fi
fi

sw mode warp
# Server mode: sample the routing state while the tunnel comes up. If SSH dies,
# this file is the only witness — read it right after the gate reverts WARP.
NETLOG="$DEST/server-net.log"
if [ "$SERVER_MODE" = 1 ]; then
  ( for _i in $(seq 1 60); do
      echo "== $(date +%T)"
      ip -br addr show 2>/dev/null | sed 's/^/  addr /'
      ip rule show 2>/dev/null | sed 's/^/  rule /'
      ip route show table "$RT_TABLE" 2>/dev/null | sed 's/^/  t111 /'
      ip route show default 2>/dev/null | sed 's/^/  def  /'
      sleep 1
    done ) > "$NETLOG" 2>&1 &
fi
sw connect
CONNECTED=0
for i in $(seq 1 12); do
  sleep 2
  # warp's nft firewall exists from the first second of the tunnel and drops
  # everything else, so open the SSH port immediately — not after the status
  # polling below, which can take 20+ seconds and costs you the session.
  [ "$SERVER_MODE" = 1 ] && nft_ssh_holes >/dev/null 2>&1
  swo status | head -1 | grep -q Connected && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] \
  && ok "warp tunnel: connected (TUN mode)" \
  || say "! warp not up yet — the keeper retries every 45s"

# warp's firewall is up from this moment: open the SSH port in it, or the
# session dies even though routing is correct.
if [ "$SERVER_MODE" = 1 ] && [ "$CONNECTED" = 1 ]; then
  nft_ssh_holes && ok "SSH opened in warp's own firewall" \
    || bad "could not open SSH in warp's firewall — the gate below will revert"
fi

# ---------------------------------------------------------- server ssh gate
# WARP can still break SSH on some hosts (provider NAT, MTU, DHCP reapply), and
# losing the box mid-install is the worst possible outcome. So we stop here and
# ask for proof that the session survived. No proof within 180s → disconnect
# WARP and leave the machine exactly as it was found.
if [ "$SERVER_MODE" = 1 ]; then
  GATE="$HOME/.cache/ouc-warp-ok"
  mkdir -p "$(dirname "$GATE")"; rm -f "$GATE"
  echo ""
  say "warp is up. you now have 180s to prove SSH still works:"
  say "  open a SECOND terminal and run:  touch $GATE"
  say "  (or just copy-paste it here — the current session counts too)"
  OKGATE=0
  for i in $(seq 1 180); do
    [ -e "$GATE" ] && { OKGATE=1; break; }
    sleep 1
  done
  if [ "$OKGATE" = 1 ]; then
    rm -f "$GATE"
    ok "session survived the tunnel — continuing"
  else
    say "! no confirmation in 180s — disconnecting WARP to give you the box back"
    say "  routing sample saved to: $NETLOG"
    sw disconnect >/dev/null 2>&1
    sudo iptables   -t mangle -D OUTPUT -j OUC_SSHOUT 2>/dev/null
    sudo ip6tables  -t mangle -D OUTPUT -j OUC_SSHOUT 2>/dev/null
    sudo iptables   -t mangle -F OUC_SSHOUT 2>/dev/null; sudo iptables  -t mangle -X OUC_SSHOUT 2>/dev/null
    sudo ip6tables  -t mangle -F OUC_SSHOUT 2>/dev/null; sudo ip6tables -t mangle -X OUC_SSHOUT 2>/dev/null
    sudo ip     rule  del fwmark "$SSH_MARK" lookup "$RT_TABLE" 2>/dev/null
    sudo ip -6  rule  del fwmark "$SSH_MARK" lookup "$RT_TABLE" 2>/dev/null
    sudo ip     route flush table "$RT_TABLE" 2>/dev/null
    sudo ip -6  route flush table "$RT_TABLE" 2>/dev/null
    die "reverted; nothing was installed. see README (server mode)"
  fi
fi

# ---------------------------------------------------------------- keeper
KEEPER_ENV=""
if [ "$SERVER_MODE" = 1 ]; then
  KEEPER_ENV="Environment=\"OUC_SERVER_SAFE=1\"
Environment=\"OUC_SSH_PORT=${SSH_PORT}\"
Environment=\"OUC_SSH_CLIENT_IP=${SSH_IP}\"
Environment=\"OUC_SSH_GW=${SSH_GW}\"
Environment=\"OUC_SSH_DEV=${SSH_DEV}\"
Environment=\"OUC_ROUTE_TABLE=${RT_TABLE}\"
Environment=\"OUC_SSH_MARK=${SSH_MARK}\""
fi

cat > /tmp/ouc-keeper-unit <<EOF
[Unit]
Description=Opencode Unlimited — warp keeper (tunnel + kill-switch)
After=network-online.target
Wants=network-online.target

[Service]
$KEEPER_ENV
ExecStart=/bin/bash "$DEST/scripts/warp-keeper.sh"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
sudo install -m 755 "$DEST/scripts/warp-keeper.sh" "/usr/local/bin/${BRAND}-keeper"
sudo install -m 644 /tmp/ouc-keeper-unit "$UNIT_KEEPER"
rm -f /tmp/ouc-keeper-unit
sudo systemctl daemon-reload
sudo systemctl enable --now "${BRAND}-keeper" >/dev/null 2>&1
systemctl is-active "${BRAND}-keeper" 2>/dev/null | grep -q active \
  && ok "keeper service (root): running" \
  || die "keeper did not start — check: systemctl status ${BRAND}-keeper"

# ---------------------------------------------------------------- guard
mkdir -p "$HOME/.config/systemd/user"
cat > "$UNIT_GUARD" <<EOF
[Unit]
Description=Opencode Unlimited — zen guard (wall watcher, /64 rotation)
After=network-online.target

[Service]
Environment="OUC_KEEPER_UNIT=${BRAND}-keeper"
Environment="OUC_WARP_BIN=$WARP"
Environment="OUC_REAL_BIN=$OC_REAL"
Environment="OUC_IPTABLES=$IPT"
Environment="OUC_IP6TABLES=$IP6T"
Environment="OUC_SYSTEMCTL=$SYSTEMCTL"
ExecStart=/bin/bash "$DEST/scripts/zen-guard.sh"
Restart=always
RestartSec=15

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now "${BRAND}-guard" >/dev/null 2>&1
systemctl --user is-active "${BRAND}-guard" 2>/dev/null | grep -q active \
  && ok "zen-guard service (user): running" \
  || die "guard did not start — check: systemctl --user status ${BRAND}-guard"

# ---------------------------------------------------------------- wrapper
# rm first: if ~/.local/bin/opencode is a symlink to the real binary, writing
# through it would overwrite the real binary with this wrapper.
rm -f "$SHIM"
printf '#!/usr/bin/env bash\nexport OUC_REAL_BIN=%q\nexec bash %q "$@"\n' \
  "$OC_REAL" "$DEST/scripts/zen-lane.sh" > "$SHIM"
chmod +x "$SHIM"
ok "opencode entry → lane (fresh edge + /64 per launch)"

# The official V2 installer prepends ~/.opencode/bin to PATH. The lane is only
# reached if ~/.local/bin comes first, so add one small, uninstallable block.
RC=""
case "$(basename "${SHELL:-bash}")" in
  zsh)          RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
  bash|sh|dash) RC="$HOME/.bashrc" ;;
esac
PATHFILE="$HOME/.config/opencode-unlimited/path.sh"
if [ -n "$RC" ] && [ -f "$RC" ]; then
  mkdir -p "$(dirname "$PATHFILE")"
  printf 'export PATH="$HOME/.local/bin:$PATH"\n' > "$PATHFILE"
  if ! grep -qF 'opencode-unlimited PATH' "$RC" 2>/dev/null; then
    printf '\n# opencode-unlimited PATH (removed by uninstall.sh)\n. %q\n' "$PATHFILE" >> "$RC"
  fi
  ok "PATH block added to $RC (lane wins after the terminal is reopened)"
else
  say "! add manually to your shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ---------------------------------------------------------------- verify
say "verifying egress (IPv6 only)…"
V6="$(timeout 12 curl -6 -s -m 10 https://api64.ipify.org 2>/dev/null)"
case "$V6" in
  2606:*|2a09:*) ok "egress is cloudflare warp: $(echo "$V6" | cut -d: -f1-4)::/64" ;;
  '') bad "no IPv6 egress yet — keeper may still be setting up; re-check with ${BRAND}-doctor" ;;
  *)  bad "egress is not warp ($V6) — re-check with ${BRAND}-doctor" ;;
esac

# The wrapper only wins if ~/.local/bin is before ~/.opencode/bin.
RESOLVED="$(command -v opencode 2>/dev/null || true)"
if [ -n "$RESOLVED" ] && [ "$(readlink -f "$RESOLVED" 2>/dev/null)" = "$(readlink -f "$SHIM" 2>/dev/null)" ]; then
  ok "PATH already resolves 'opencode' to the lane"
else
  ok "wrapper ready — reopen the terminal so ~/.local/bin wins over ~/.opencode/bin"
fi

echo ""
ok "DONE. close & reopen your terminal, then run:  opencode"
say "first launch: sign in once to the free tier if asked."
say "wall hit? zen-guard rotates automatically — wait ~15s, re-send."
say "checks:  ${BRAND}-doctor      manual new identity:  ${BRAND}-hop"
say "if something looks wrong:  tail -n 20 ~/.local/share/$BRAND/guard/guard.log"
if [ "$PAIR_MODE" = 0 ]; then
  say "pairing is off (strict mode). enable it:  $OC_REAL service unset disabled && $OC_REAL service start"
else
  say "from another device:  opencode pair"
fi
if [ -d "$BACKUP_ROOT" ]; then
  say "V1 backup (one-way V2 migration): $BACKUP_ROOT"
fi
if [ "$SERVER_MODE" = 1 ]; then
  echo ""
  say "server mode: keep a provider console/VNC open. If SSH freezes:"
  say "  sudo systemctl stop ${BRAND}-keeper"
  say "  sudo iptables -D OUTPUT -j OUC_LEAKGUARD 2>/dev/null"
  say "  sudo ip6tables -D OUTPUT -j OUC_LEAKGUARD 2>/dev/null"
fi
echo ""
