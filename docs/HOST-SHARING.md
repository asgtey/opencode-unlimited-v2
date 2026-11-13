# Share a host folder with the VM

Your project lives on the host (Windows or macOS), and OpenCode runs inside a
Linux VM. You want OpenCode to edit those files directly.

Nothing in this project depends on where a project sits: point it at a directory
and it works. So the only job is making the host folder visible inside the VM.

---

## 1. VMware: share the folder

Shut the VM down (**Power off**, not Suspend).

1. `VM → Settings → Options → Shared Folders`
2. Choose **Always enabled**.
3. **Add…**
   - *Host path*: the project folder, e.g. `C:\Users\you\my-project`
   - *Name*: `my-project`
   - Leave *Read-only* **off**.
4. OK, then start the VM.

---

## 2. Inside the VM: mount it

```bash
sudo apt install -y open-vm-tools open-vm-tools-desktop
vmware-hgfsclient
```

`vmware-hgfsclient` prints the share names — if you see `my-project`, the share
is there. Mount all of them with your own user id:

```bash
sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,uid=$(id -u),gid=$(id -g)
ls /mnt/hgfs
```

The `uid`/`gid` part matters: without it everything belongs to `root` and
OpenCode cannot save your edits.

To keep it after a reboot:

```bash
echo '.host:/ /mnt/hgfs fuse.vmhgfs-fuse allow_other,uid='"$(id -u)"',gid='"$(id -g)"',defaults 0 0' \
  | sudo tee -a /etc/fstab
sudo mount -a
```

If `/mnt/hgfs` is empty, power the VM off and on again (Suspend/Resume often
skips the share), and check that `open-vm-tools` is installed.

---

## 3. Open it in OpenCode

Either go into the folder first:

```bash
cd /mnt/hgfs/my-project
opencode
```

or pass the path straight to it:

```bash
opencode /mnt/hgfs/my-project
```

OpenCode then works on the host files — saves go straight back to Windows.

---

## Two fixes you will probably need

Git refuses paths owned by another uid:

```bash
git config --global --add safe.directory /mnt/hgfs/my-project
```

A share reports every file as executable, so git would show endless mode
changes:

```bash
git -C /mnt/hgfs/my-project config core.filemode false
```

---

## What a shared folder cannot do

| Thing | Effect |
|---|---|
| symlinks | not supported by `vmhgfs` / `vboxsf` |
| file-change notifications | none — editors fall back to polling |
| speed | 3–10× slower than the VM disk |
| `node_modules`, `venv`, `vendor/` | slow, and often break |

Fine for source files, scripts, configs and markdown. If the project has a big
dependency tree, keep the real copy on the VM disk and sync with git.

---

## Alternatives

**SMB (Windows share, faster):**

```bash
sudo apt install -y cifs-utils
sudo mount -t cifs //HOST-IP/my-project /mnt/project \
  -o username=YOUR-WINDOWS-USER,uid=$(id -u),gid=$(id -g),vers=3.0
```

**SSHFS (needs OpenSSH Server on the host):**

```bash
sudo apt install -y sshfs
sshfs you@HOST-IP:C:/Users/you/my-project ~/host-project
cd ~/host-project && opencode
```

**VirtualBox:** *Settings → Shared Folders → Add*, install
`virtualbox-guest-utils`, then
`sudo mount -t vboxsf -o uid=$(id -u),gid=$(id -g) my-project /mnt/project`.
