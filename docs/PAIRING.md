# Pairing: use OpenCode from your phone or another computer

`opencode pair` gives you a link (and a QR code) that opens OpenCode's web UI on
another device. That's all it does.

The only catch in this project: pairing needs OpenCode's **shared server**, and we
turn that server off so every launch gets a private one. So you turn it on, pair,
then turn it off again.

---

## Three steps

**1. Turn the shared server on**

```bash
opencode service unset disabled
opencode service start
```

**2. Get a link**

```bash
opencode pair
```

Open the printed link on the other device, or scan the QR with the OpenCode app.
The link works once and expires after 5 minutes.

**3. Turn the shared server off again**

```bash
opencode service set disabled true
```

Step 3 is not optional: while the shared server is running, the terminal loses the
random-edge part of the lane.

---

## If the other device is not on the same machine

**Same Wi-Fi** — nothing extra. The link points at `127.0.0.1`, so replace it with
your machine's LAN address, or print it that way:

```bash
opencode service set hostname 0.0.0.0
opencode service set password "a-long-secret"
opencode service start
opencode pair --url http://192.168.1.23:49374
```

**Different network** — use the tunnel:

```bash
opencode pair --remote
```

It asks once before exposing the server to the internet. Traffic is encrypted and
needs your server password.

**Over SSH** — forward the port, then pair normally:

```bash
ssh -L 49374:127.0.0.1:49374 asghar@your-server
opencode pair
```

If `49374` is not the port, `opencode service status` prints the real one.

---

## What is different while paired

Sessions opened from the paired device run on the shared server, which sits outside
the lane:

- traffic still goes through WARP, and `zen-guard` still rotates your `/64`;
- you do **not** get a random Cloudflare edge per launch.

So a paired session can hit the limit a bit sooner. When it does, wait for the
rotation and re-send.

The terminal `opencode` is unaffected — it keeps using its private server.

---

## Turning it all off

```bash
opencode service set disabled true
```

`opencode-unlimited-doctor` shows a red line if you forget.

Paired browsers stay signed in for 30 days. To kick every device out, change the
password and restart:

```bash
opencode service set password "another-long-secret"
opencode service start
opencode service set disabled true
```

---

## Security, in one line each

- Pair links are single-use and die after 5 minutes — never post them publicly.
- `--remote` really does publish your server; accept the prompt only if you mean it.
- Do not set `hostname 0.0.0.0` on a public network without a password.
