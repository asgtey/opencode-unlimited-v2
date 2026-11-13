# Pairing: use OpenCode from your phone or another computer

The installer leaves pairing ready, so you do not have to set anything up.

```bash
opencode pair
```

The command prints a link and a QR code. Open the link on the other device, or scan
the QR with the OpenCode app. Works once, expires after 5 minutes.

That is the whole procedure.

---

## If the other device is on a different network

By default the link points at `127.0.0.1`, which only exists on the machine running
OpenCode. Two ways around it:

**Tunnel through OpenTunnel** (needs internet, nothing else):

```bash
opencode pair --remote
```

It asks once before exposing the server to the internet; traffic is encrypted and
needs your server password.

**Or forward the port over SSH:**

```bash
ssh -L 49374:127.0.0.1:49374 asghar@your-server
opencode pair
```

Then open the printed link on your laptop. If `49374` is not the port,
`opencode service status` prints the real one.

Same Wi-Fi? Use the LAN address:

```bash
opencode service set hostname 0.0.0.0
opencode service set password "a-long-secret"
opencode service start
opencode pair --url http://192.168.1.23:49374
```

---

## What is different while paired

Paired sessions run on OpenCode's shared server, which sits outside the lane:

- traffic still goes through WARP, and `zen-guard` still rotates your `/64`;
- you do **not** get a random Cloudflare edge per launch.

So a paired session can hit the free limit a bit sooner. Wait for the rotation and
re-send, same as usual. The terminal `opencode` keeps its own private server and is
not affected.

---

## Turning pairing off

```bash
opencode service set disabled true      # off
opencode service unset disabled         # on again
opencode service start
```

Or reinstall with `OUC_PAIR=0` to start in the private-only mode. The terminal works
the same either way — this only switches the shared server on or off.

Paired browsers stay signed in for 30 days. To sign every device out, change the
password and restart:

```bash
opencode service set password "another-long-secret"
opencode service start
```

## Security, one line each

- Pair links are single-use and die after 5 minutes — never post them publicly.
- `--remote` really does publish your server; accept the prompt only if you mean it.
- Do not set `hostname 0.0.0.0` on a public network without a password.
