#!/usr/bin/env bash
# host-share-check — is this folder a good place to run the lane?
#
#   opencode-unlimited-share [directory]
#
# Used when the project lives on the host (Windows/macOS) and is shared into a
# Linux VM: VMware Shared Folders, VirtualBox, SMB, SSHFS. The checks are
# read-only apart from one write test, and every problem comes with the exact
# command that fixes it.
set -u

DIR="${1:-$PWD}"
[ -d "$DIR" ] || { echo "not a directory: $DIR" >&2; exit 2; }
DIR="$(cd "$DIR" && pwd -P)"

printf '\n'
printf '  path       : %s\n' "$DIR"
printf '  user       : %s (uid %s)\n' "$(id -un)" "$(id -u)"

FSTYPE="$(stat -f -c %T "$DIR" 2>/dev/null || echo unknown)"
MOUNT="$(df -P "$DIR" 2>/dev/null | awk 'NR==2 {print $6}')"
printf '  filesystem : %s  (mounted from %s)\n' "$FSTYPE" "${MOUNT:-?}"

SHARED=0
case "$FSTYPE" in
  *vmhgfs*)  printf '  verdict    : VMware shared folder\n'; SHARED=1 ;;
  vboxsf)    printf '  verdict    : VirtualBox shared folder\n'; SHARED=1 ;;
  cifs|smb3) printf '  verdict    : SMB/CIFS share\n'; SHARED=1 ;;
  *sshfs*)   printf '  verdict    : SSHFS\n'; SHARED=1 ;;
  9p)        printf '  verdict    : 9p share\n'; SHARED=1 ;;
  ext2/ext3|ext4|xfs|btrfs|zfs|overlay|tmpfs)
             printf '  verdict    : local disk — fastest, nothing to fix\n' ;;
  *)         printf '  verdict    : %s\n' "$FSTYPE" ;;
esac

printf '\n'

# --------------------------------------------------------------- write test
if W="$(mktemp "$DIR/.ouc-write.XXXXXX" 2>/dev/null)"; then
  rm -f "$W"
  printf '  \033[32m✓\033[0m writable by %s\n' "$(id -un)"
else
  printf '  \033[31m✗\033[0m NOT writable — opencode cannot save edits here\n'
  printf '     remount with your own ids:\n'
  printf '     sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,uid=%s,gid=%s\n' \
         "$(id -u)" "$(id -g)"
fi

# ------------------------------------------------------------------ git
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  printf '  \033[32m✓\033[0m git repository\n'
  ERR="$(git -C "$DIR" status --porcelain 2>&1 >/dev/null)"
  case "$ERR" in
    *"dubious ownership"*)
      printf '  \033[31m✗\033[0m git blocks this path (owner mismatch)\n'
      printf '     git config --global --add safe.directory "%s"\n' "$DIR" ;;
    *) printf '  \033[32m✓\033[0m git status works\n' ;;
  esac
  if [ "$SHARED" = 1 ] \
     && [ "$(git -C "$DIR" config --bool core.filemode 2>/dev/null || echo true)" != false ]; then
    printf '  \033[33m!\033[0m every file looks executable on a share — git reports mode changes\n'
    printf '     git -C "%s" config core.filemode false\n' "$DIR"
  fi
else
  printf '  - no .git here (nothing to check)\n'
fi

# -------------------------------------------------------- share limitations
if [ "$SHARED" = 1 ]; then
  printf '\n'
  printf '  note: shares have no symlinks and no file-change notifications.\n'
  printf '        Fine for source files. If the project needs node_modules,\n'
  printf '        vendor/ or a symlinked toolchain, keep those on the VM disk.\n'
fi

printf '\n  next:  cd "%s" && opencode\n\n' "$DIR"
