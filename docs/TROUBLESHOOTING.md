# Troubleshooting

Run `opencode-unlimited-doctor` first. Every red line has a fix printed next to it.
If you want the raw story instead, the guard's log is at
`~/.local/share/opencode-unlimited/guard/guard.log`
(`tail -n 20 ~/.local/share/opencode-unlimited/guard/guard.log`).

---

## Install-time

### `run me as your normal user, not root` (older versions)

Current installers do not stop: they ask for a username and a password, create the
account, and continue as that user. If you see this message you are on an older
copy — update, or create the user yourself:

```bash
adduser asghar
usermod -aG wheel asghar     # Debian/Ubuntu/Mint: -aG sudo
su - asghar
```

### `the code was rejected or has expired`

The bundle is private, so the install command needs your access code:

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/ou-start/main/get.sh | bash -s -- --token YOUR-CODE
```

Common causes: a typo or a line-wrap when copying the code; an expired code; a
code you deleted; a code that does not have **Contents: Read** on
`asgtey/opencode-unlimited-v2`. Ask asgtey for a new one — the old code keeps
working until it is deleted. How codes work: [ACCESS.md](ACCESS.md).

### The one-command install stops immediately

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/ou-start/main/get.sh | bash -s -- --token YOUR-CODE
```

`get.sh` downloads the bundle to a temp folder. If you see
`could not download the bundle` **and** your code is new, the network is blocked or
`curl`/`wget` is missing. The manual route always works:

```bash
git clone https://github.com/asgtey/opencode-unlimited-v2.git
cd opencode-unlimited-v2 && ./install.sh
```

`git clone` asks for a username and password: the password is your access code, the
username can be anything (for example `x-access-token`).

If sudo never asks for a password, you are not on a terminal (for example inside a
CI job). Run the `git clone` route instead.

### `unshare -rm fails — the lane will refuse to start`

Ubuntu 24.04 and Mint 22.x restrict unprivileged user namespaces through AppArmor.

```bash
echo 'kernel.apparmor_restrict_unprivileged_userns=0' | sudo tee /etc/sysctl.d/99-opencode-userns.conf
sudo sysctl --system
unshare -rm true && echo OK
```

Then re-run `./install.sh`. Without this the lane is fail-closed on purpose.

### `apt` rejects the WARP repository (`Release ... zena`)

Linux Mint reports its own codename (`zena`, `zara`, `xia`, ...) while Cloudflare
only publishes Ubuntu codenames. The current `install.sh` uses
`UBUNTU_CODENAME`; older copies used `lsb_release -cs`.

Manual fix:

```bash
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ noble main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update && sudo apt install -y cloudflare-warp
```

### `warp-cli install failed`

Usually the codename problem above, or no network access to
`pkg.cloudflareclient.com`. Verify:

```bash
curl -I https://pkg.cloudflareclient.com
apt-cache policy cloudflare-warp
```

### `opencode V2 install failed`

The V2 installer downloads from `opencode.ai` and the npm registry. If either is
blocked, the install cannot finish. Check:

```bash
curl -I https://opencode.ai/v2/install
curl -I https://registry.npmjs.org
```

### `keeper did not start`

```bash
systemctl status opencode-unlimited-keeper --no-pager
journalctl -u opencode-unlimited-keeper -n 50 --no-pager
```

The unit runs `warp-keeper.sh` as root. If `warp-cli` is missing from root's PATH,
the installer's `/usr/local/bin/opencode-unlimited-keeper` copy plus the service
environment handles it; re-run `./install.sh` if the binary moved.

---

## Runtime

### `opencode` starts the real V2, not the lane

```bash
command -v opencode          # must be ~/.local/bin/opencode
source ~/.config/opencode-unlimited/path.sh
hash -r
command -v opencode
```

If `~/.opencode/bin` still wins, the V2 installer's PATH line is later in your rc.
The installer appends its block at the end of `~/.bashrc`; reopen the terminal.

### `doctor` says "private servers only"

That is the strict mode (`OUC_PAIR=0`). Pairing is off. To turn it back on:

```bash
opencode service unset disabled
opencode service start
cat "$(opencode debug paths config)/service.json"
```

### No IPv6 egress

```bash
warp-cli --accept-tos status
curl -6 -s -m 8 https://api64.ipify.org
ip -6 addr show CloudflareWARP
```

If the tunnel is up but there is no IPv6, the network blocks WARP's IPv6. The
kill-switch is then blocking traffic by design. Use the
[emergency exit](SECURITY.md#emergency-exit).

### Wall seen but no rotation in `guard.log`

Start with the log itself — twenty lines are usually enough:

```bash
tail -n 20 ~/.local/share/opencode-unlimited/guard/guard.log
```

If that says nothing useful, widen it and check the service:

```bash
tail -n 100 ~/.local/share/opencode-unlimited/guard/guard.log
systemctl --user status opencode-unlimited-guard --no-pager
journalctl --user -u opencode-unlimited-guard -n 50 --no-pager
sudo -n /usr/sbin/iptables -nL OUC_LEAKGUARD
```

| Log line | Meaning |
|---|---|
| `ABORT rotation: kill-switch chain missing` | keeper is down or was flushed; restart it |
| `try N: tunnel repair failed` | WARP registration failed; run `opencode-unlimited-hop` |
| `cloudflare returned a blacklisted /64` | retry; the guard walks up to 8 blocks |

### `opencode-unlimited-hop` says `kill-switch chain ... is missing`

```bash
sudo systemctl restart opencode-unlimited-keeper
sleep 10
sudo ip6tables -nL OUC_LEAKGUARD
```

If the chain never appears, `warp-keeper.sh` cannot run as root; check its journal.

### `hop` says the same `/64`

Cloudflare reused the block. Run it again; the guard blacklists the old one.

### `doctor` says `sudoers entries missing`

Re-run `./install.sh` (it rewrites `/etc/sudoers.d/opencode-unlimited`). Validate:

```bash
sudo visudo -c
```

### Guard is not running after reboot

It is a **user** service. Enable lingering:

```bash
sudo loginctl enable-linger "$USER"
```

### Free limit returns immediately after a rotation

Check the error text:

- `Free usage limit reached ...` → IP-based; rotation should help.
- `OpenCode Go`, `workspace`, `budget` → account-based; rotation cannot help.

### Pairing does not work

`opencode pair` needs the shared server. The installer leaves it running, so first
check that it is up:

```bash
opencode service status
opencode service start
opencode pair
```

If you installed with `OUC_PAIR=0`, enable it first:

```bash
opencode service unset disabled && opencode service start
```

Full walkthrough (LAN, SSH tunnel, `--remote`): [PAIRING.md](PAIRING.md).

---

## Collecting a useful bug report

```bash
opencode --version
uname -a
cat /etc/os-release
opencode-unlimited-doctor
tail -n 50 ~/.local/share/opencode-unlimited/guard/guard.log
systemctl status opencode-unlimited-keeper --no-pager -l
systemctl --user status opencode-unlimited-guard --no-pager -l
```

Redact IPs and tokens before posting.
