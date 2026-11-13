#!/usr/bin/env bash
# One-command install / uninstall.
#
#   install   :  curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash
#   uninstall :  curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash -s -- --uninstall
#
# Why a bootstrap: install.sh needs ./scripts next to it. Piping a single file
# through bash would leave it without that folder, so this downloads the whole
# bundle into a temp directory, runs install.sh / uninstall.sh from there, and
# deletes the directory afterwards. Nothing else from the tarball is executed.
set -u

REPO="${OUC_REPO:-asgtey/opencode-unlimited-v2}"
REF="${OUC_REF:-main}"

say() { printf '  %s\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
die() { bad "$*"; exit 1; }

ACTION="install"
for a in "$@"; do
  case "$a" in
    --uninstall|-u|uninstall) ACTION="uninstall" ;;
    --install|install)        ACTION="install" ;;
    -h|--help|help)           ACTION="help" ;;
    *) die "unknown option: $a (try --help)" ;;
  esac
done

if [ "$ACTION" = help ]; then
  cat <<EOF

  opencode-unlimited-v2 — one-command installer

    install    curl -fsSL https://raw.githubusercontent.com/$REPO/main/get.sh | bash
    uninstall  curl -fsSL https://raw.githubusercontent.com/$REPO/main/get.sh | bash -s -- --uninstall

  Environment:
    OUC_REF     git ref to use (default: main)
    OUC_REPO    owner/name override (for forks)

EOF
  exit 0
fi

echo ""
echo "  ==============================="
echo "  Opencode Unlimited — OpenCode 2.x"
echo "  ==============================="
echo ""

command -v tar >/dev/null 2>&1 || die "tar is required"

# Everything is per-user. install.sh knows how to create an account when it is
# started as root; uninstalling as root is ambiguous, so that one is refused.
if [ "$(id -u)" = 0 ] && [ "$ACTION" = uninstall ]; then
  bad "uninstall as the user that installed it, not as root"
  say "log in as that user and run the same command again."
  exit 1
fi

if   command -v curl >/dev/null 2>&1; then fetch() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then fetch() { wget -qO- "$1"; }
else die "curl or wget is required"
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t ouc)" || die "mktemp failed"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

ROOT=""
say "downloading $REPO ($REF)…"

if fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" | tar xz -C "$TMP" 2>/dev/null; then
  ROOT="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
fi

# Fallback for refs that are not branches (tags) or when codeload is blocked.
if [ -z "$ROOT" ] && command -v git >/dev/null 2>&1; then
  say "codeload failed — trying git clone…"
  if git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$TMP/src" >/dev/null 2>&1; then
    ROOT="$TMP/src"
  fi
fi

{ [ -n "$ROOT" ] && [ -f "$ROOT/install.sh" ]; } \
  || die "could not download the bundle — check your connection, then retry"

chmod +x "$ROOT"/*.sh "$ROOT"/scripts/*.sh 2>/dev/null
ok "bundle ready"

SCRIPT="$ROOT/$ACTION.sh"
[ -f "$SCRIPT" ] || die "$ACTION.sh missing from the bundle"

# `curl | bash` consumes stdin. Give the real script a terminal when there is
# one, so sudo can ask for a password.
if [ -r /dev/tty ] && [ -t 1 ]; then
  bash "$SCRIPT" < /dev/tty
else
  bash "$SCRIPT" < /dev/null
fi
