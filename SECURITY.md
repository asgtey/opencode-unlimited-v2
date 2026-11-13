# Security policy

## Reporting a vulnerability

Open a private security advisory on GitHub (Security → Advisories) or email the
maintainer listed on the profile. Please do not open a public issue for a kill-switch
bypass or a privilege-escalation finding before it is fixed.

Include:

- distribution and kernel (`uname -a`, `/etc/os-release`);
- `opencode-unlimited-doctor` output;
- `ip6tables -nL OUC_LEAKGUARD` and `iptables -nL OUC_LEAKGUARD`;
- the exact command sequence that reproduces the problem.

## Threat model

The project assumes a **single-user desktop** where the user is allowed to control
their own network stack. It is not designed for multi-user hosts or shared servers.

Protected assets:

1. the host's real IP address (should not leak while the tunnel is down);
2. the user's OpenCode session data (never read by this project beyond the
   `session_message` wall check, read-only);
3. the user's OpenCode auth tokens (never read, only copied during a V1 backup).

## What the kill-switch does

`warp-keeper.sh` rebuilds `OUC_LEAKGUARD` in both `iptables` and `ip6tables` every
45 seconds and inserts it at the top of `OUTPUT`. Allowed traffic:

- loopback;
- `ESTABLISHED,RELATED`;
- RFC1918 / link-local LAN ranges;
- Cloudflare WARP control ranges (`162.159.0.0/16`, `188.114.0.0/16`,
  `2606:4700::/32`);
- anything leaving through the `CloudflareWARP` interface.

Everything else is dropped. If the tunnel drops, the chain stays installed, so the
host does not fall back to its physical interface.

## Fail-closed points

| Component | Condition | Result |
|---|---|---|
| `zen-lane.sh` | `unshare -rm` fails | refuses to start |
| `zen-lane.sh` | `/etc/hosts` bind fails | exits 97, no traffic |
| `zen-guard.sh` | `OUC_LEAKGUARD` missing | does not stop the tunnel |
| `zen-hop.sh` | `OUC_LEAKGUARD` missing | refuses to rotate |

## Known residual risks

### 1. Broad IPv6 allow rule

`ip6tables -A OUC_LEAKGUARD -d 2606:4700::/32 -j ACCEPT` is required for WARP's own
control connection. While the tunnel is down, traffic to **Cloudflare-hosted IPv6
destinations** can leave through the physical interface and expose the real address
to those destinations. Traffic to other destinations is still dropped.

Stricter, optional variant (owner-scoped):

```bash
sudo ip6tables -D OUC_LEAKGUARD -d 2606:4700::/32 -j ACCEPT
sudo ip6tables -I OUC_LEAKGUARD -m owner --uid-owner warp-svc -d 2606:4700::/32 -j ACCEPT
```

Check the service user first:

```bash
getent passwd | grep -i warp
```

If the user name differs, the tunnel will fail to establish. Apply the same idea to
the IPv4 control ranges if you need it.

### 2. Passwordless `warp-cli`

`/etc/sudoers.d/opencode-unlimited` grants `NOPASSWD` for:

- `warp-cli` with any arguments;
- `iptables -nL OUC_LEAKGUARD` and `ip6tables -nL OUC_LEAKGUARD`;
- `systemctl stop|start opencode-unlimited-keeper`.

Any process running as the user can reconfigure WARP. This is required for unattended
rotation on a desktop. Do not use this project on a shared machine.

### 3. Wrapper bypass

Only `~/.local/bin/opencode` goes through the lane. IDE extensions and any script
that calls `~/.opencode/bin/opencode` directly bypass the per-launch edge pin. The
kill-switch and IP rotation still apply at the host level, but the `/etc/hosts`
pin does not.

### 4. Provider terms

Rotating identity to extend a free tier may violate the provider's terms and can lead
to account restrictions. This is a policy risk, not a vulnerability.

## Emergency exit

If WARP cannot connect, the kill-switch will block most traffic. Restore normal
networking:

```bash
sudo systemctl stop opencode-unlimited-keeper
sudo systemctl disable opencode-unlimited-keeper

sudo iptables  -D OUTPUT -j OUC_LEAKGUARD 2>/dev/null
sudo ip6tables -D OUTPUT -j OUC_LEAKGUARD 2>/dev/null
sudo iptables  -F OUC_LEAKGUARD 2>/dev/null; sudo iptables  -X OUC_LEAKGUARD 2>/dev/null
sudo ip6tables -F OUC_LEAKGUARD 2>/dev/null; sudo ip6tables -X OUC_LEAKGUARD 2>/dev/null
```

Or remove everything (works offline):

```bash
./uninstall.sh
```

## Hardening checklist

- [ ] Read `/etc/sudoers.d/opencode-unlimited` and confirm it matches what you expect.
- [ ] Confirm the kill-switch is installed: `sudo ip6tables -nL OUC_LEAKGUARD`.
- [ ] Confirm a blocked egress: `curl -6 -m 5 https://example.com` while WARP is
      disconnected (should fail).
- [ ] Keep `~/.local/share/opencode-unlimited-backups/` on encrypted storage.
- [ ] Review the scripts before running them; they are plain bash.
