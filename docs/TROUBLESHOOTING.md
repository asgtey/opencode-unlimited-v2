# Troubleshooting

Run `opencode-unlimited-doctor` first. Every red line has a fix printed next to it.

---

## Install-time

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

### `doctor` says the background service is not disabled

```bash
opencode service set disabled true
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

```bash
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

Expected: V2 pairing requires the shared service, which this project disables.
`opencode service unset disabled` restores it (and re-enables the shared server).

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
