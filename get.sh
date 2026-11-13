#!/usr/bin/env bash
# One-command install / uninstall.
#
#   install   :  curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash
#   uninstall :  ... | bash -s -- --uninstall
#
# This repository is public, so no access code is needed. --token / OUC_TOKEN is
# still accepted for forks or private mirrors; the bundle is then fetched through
# the API with the bearer token instead of the anonymous mirrors.
#
# Why a bootstrap: install.sh needs ./scripts next to it. Piping a single file
# through bash would leave it without that folder, so this downloads the whole
# bundle into a temp directory, runs install.sh / uninstall.sh from there, and
# deletes the directory afterwards. Nothing else from the tarball is executed.
set -u

REPO="${OUC_REPO:-asgtey/opencode-unlimited-v2}"
REF="${OUC_REF:-main}"
TOKEN="${OUC_TOKEN:-}"

say() { printf '  %s\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
die() { bad "$*"; exit 1; }

ACTION="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall|-u|uninstall) ACTION="uninstall" ;;
    --install|install)        ACTION="install" ;;
    --token|--code|-t)        TOKEN="${2:-}"; shift ;;
    --token=*|--code=*)       TOKEN="${1#*=}" ;;
    -h|--help|help)           ACTION="help" ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done
# The token is optional; keep it in scope for the fetch helpers.
OUC_TOKEN="$TOKEN"; export OUC_TOKEN

if [ "$ACTION" = help ]; then
  cat <<EOF

  opencode-unlimited-v2 — one-command installer

    install    curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash
    uninstall  curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash -s -- --uninstall

  Environment:
    OUC_TOKEN   optional access code (forks / private mirrors only)
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

AUTH=""
if [ -n "$TOKEN" ]; then AUTH="Authorization: Bearer $TOKEN"; fi

if   command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL ${AUTH:+-H "$AUTH"} "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO- ${AUTH:+--header="$AUTH"} "$1"; }
else die "curl or wget is required"
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t ouc)" || die "mktemp failed"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

ROOT=""
say "downloading $REPO ($REF)…"

# With a code, go through the API: it accepts the bearer token directly and
# redirects to a signed URL, which is also what works for a private repo.
if [ -n "$TOKEN" ]; then
  if fetch "https://api.github.com/repos/$REPO/tarball/$REF" | tar xz -C "$TMP" 2>/dev/null; then
    ROOT="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
  fi
elif fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF" | tar xz -C "$TMP" 2>/dev/null; then
  ROOT="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
fi

# Fallback for refs that are not branches (tags) or when the first mirror fails.
if [ -z "$ROOT" ] && command -v git >/dev/null 2>&1; then
  say "direct download failed — trying git…"
  GIT_URL="https://github.com/$REPO.git"
  if [ -n "$TOKEN" ]; then
    if git clone --depth 1 --branch "$REF" \
         "https://x-access-token:$TOKEN@github.com/$REPO.git" "$TMP/src" >/dev/null 2>&1; then
      ROOT="$TMP/src"
    fi
  else
    if git clone --depth 1 --branch "$REF" "$GIT_URL" "$TMP/src" >/dev/null 2>&1; then
      ROOT="$TMP/src"
    fi
  fi
fi

if [ -z "$ROOT" ] || [ ! -f "$ROOT/install.sh" ]; then
  bad "could not download the bundle"
  if [ -n "$TOKEN" ]; then
    say "the access code was rejected (or expired) and the mirrors failed."
    say "without a code the public repository is used — try again without --token."
  else
    say "check your connection, then run the same command again."
    say "manual fallback:  git clone https://github.com/$REPO.git"
  fi
  exit 1
fi

chmod +x "$ROOT"/*.sh "$ROOT"/scripts/*.sh 2>/dev/null
ok "bundle ready"

SCRIPT="$ROOT/$ACTION.sh"
[ -f "$SCRIPT" ] || die "$ACTION.sh missing from the bundle"

# `curl | bash` consumes stdin. Give the real script a terminal when there is
# one, so sudo and any prompt can ask for input.
if [ -r /dev/tty ] && [ -t 1 ]; then
  bash "$SCRIPT" < /dev/tty
else
  bash "$SCRIPT" < /dev/null
fi
