# Work on a project that lives on the host

You run Linux in a VM (VMware, VirtualBox) and the project lives on the host —
Windows or macOS. You want the `opencode` in the VM to edit those files.

The lane does not care where a project is: it only needs the directory and the
network. So the whole job is "make the host folder visible in the VM", then
`cd` into it and run `opencode` as usual.

```bash
cd /mnt/hgfs/my-project
opencode
```

Three ways to get the folder there, easiest first.

---

## 1. VMware Shared Folders (recommended)

**On the host (VMware Workstation / Player):**

1. Shut the VM down (or suspend it).
2. *VM → Settings → Options → Shared Folders* → **Always enabled**.
3. **Add…** → *Host path* = the project folder (e.g. `C:\Users\you\project`),
   *Name* = `project`, leave *Read-only* **off**.
4. Start the VM.

**In the VM:**

```bash
sudo apt install -y open-vm-tools open-vm-tools-desktop
vmware-hgfsclient                    # lists the share names, e.g. "project"
sudo mkdir -p /mnt/hgfs
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,uid=$(id -u),gid=$(id -g)
ls /mnt/hgfs
```

`uid`/`gid` are the important part: without them everything belongs to `root`
and OpenCode cannot save.

Make it permanent (survives reboot):

```bash
echo '.host:/ /mnt/hgfs fuse.vmhgfs-fuse allow_other,uid='"$(id -u)"',gid='"$(id -g)"',defaults 0 0' \
  | sudo tee -a /etc/fstab
sudo mount -a
```

Then:

```bash
cd /mnt/hgfs/project
opencode-unlimited-share      # check first (see below)
opencode
```

Git will complain the first time, because the files are owned by a different
user id on the host side:

```bash
git config --global --add safe.directory /mnt/hgfs/project
git -C /mnt/hgfs/project config core.filemode false
```

That second line matters on every share: all files arrive with the executable
bit set, so `git status` would show endless mode changes.

---

## 2. SMB share (faster than hgfs, more setup)

**On Windows:** right-click the folder → *Properties → Sharing → Advanced
Sharing → Share this folder*. Give your Windows user read/write. Allow
"File and Printer Sharing" through the firewall.

**In the VM:**

```bash
sudo apt install -y cifs-utils
sudo mkdir -p /mnt/project
sudo mount -t cifs //HOST-IP/project /mnt/project \
  -o username=YOUR-WINDOWS-USER,uid=$(id -u),gid=$(id -g),vers=3.0
```

Add to `/etc/fstab` with a credentials file (`chmod 600`) if you want it
permanent. Replace `HOST-IP` with the host's LAN address (`ipconfig` on
Windows).

---

## 3. SSHFS (no VM settings needed)

**On Windows:** *Settings → System → Optional features → Add → OpenSSH
Server*, then:

```powershell
Start-Service sshd
Set-Service sshd -StartupType Automatic
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH' -Enabled True `
  -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

**In the VM:**

```bash
sudo apt install -y sshfs
mkdir -p ~/host-project
sshfs YOU@HOST-IP:C:/Users/you/project ~/host-project
cd ~/host-project && opencode
```

---

## Check the folder before you start

```bash
opencode-unlimited-share /mnt/hgfs/project
```

It reports the filesystem, whether the folder is writable, whether git blocks
it, and the exact command for each problem it finds.

---

## Limits you should know about

| Thing | Shared folder | Local disk |
|---|---|---|
| Plain source files | fine | fine |
| Write speed | 3–10× slower | baseline |
| File-change notifications (inotify) | **no** — tools poll or miss changes | yes |
| Symlinks | **no** (hgfs/vboxsf) | yes |
| `node_modules`, `vendor/`, `.venv` | slow, often breaks | fine |
| `git status` mode noise | need `core.filemode false` | none |

If the project is JavaScript/Python with a big dependency tree, the honest
answer is: **keep the project on the VM disk and sync it**, instead of running
the toolchain on the share.

```bash
# one-time: copy the project into the VM
rsync -a --exclude node_modules --exclude .git \
  /mnt/hgfs/project/ ~/work/project/

# after that, keep the two in sync with git
cd ~/work/project && git fetch && git status
```

You can still edit files on the share with `opencode` — it works — but run
`npm test`, `cargo build`, etc. on the VM copy.

---

## What does *not* change

- The kill-switch, WARP, `/64` rotation and the random edge are independent of
  where the project sits.
- The lane still starts a private server (`--standalone`) for the TUI, so the
  pinned edge applies to requests from any directory.
- Files in the share are only touched by OpenCode; the installer never uploads
  or copies them anywhere.
