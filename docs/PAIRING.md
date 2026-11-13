# Use OpenCode from another device (`opencode pair`)

`opencode pair` prints one-time links and a QR code that sign a browser or the
OpenCode app in to your **background server**. Links expire after 5 minutes and
work once.

Two things to know before you start:

1. **Pairing needs the shared background service.** This project disables it
   (`opencode service set disabled true`) so that every launch gets a private
   server inside the lane. Pairing is unavailable while it is disabled — so you
   turn it on, pair, then turn it off again.
2. **A paired device talks to the shared server, not the lane.** See
   [What still works](#what-still-works-while-paired) below.

---

## The short version

On the machine running OpenCode:

```bash
opencode service unset disabled     # re-enable the shared server
opencode service start
opencode pair                       # copy the link or scan the QR
```

Open the link on the other device, then close the door again:

```bash
opencode service set disabled true
```

`opencode-unlimited-doctor` prints a red line if you forget the last step.

---

## Reaching the server from the other device

### 1. Over SSH (recommended, works everywhere)

The server listens on `127.0.0.1` only, so forward its port through SSH and open
the link locally:

```bash
# on your laptop
ssh -L 49374:127.0.0.1:49374 asghar@your-server
```

In that SSH session, run `opencode pair` and open the printed
`http://127.0.0.1:49374/auth/connect/...` link in your laptop's browser.

If the port is not 49374, ask the server:

```bash
opencode service status      # prints http://127.0.0.1:<port>
```

Nothing else is exposed, and the kill-switch does not get in the way.

### 2. Same LAN

```bash
opencode service set hostname 0.0.0.0
opencode service set port 49374
opencode service set password "a-long-secret"     # optional but recommended
opencode service start
opencode pair --url http://192.168.1.23:49374     # use the server's LAN IP
```

Changing a setting stops the server, so set everything **before** `service start`.

Then open the link on the other device, or point the OpenCode app at
`http://192.168.1.23:49374`.

Revert when you are done:

```bash
opencode service unset hostname
opencode service unset port
opencode service start
opencode service set disabled true
```

> `0.0.0.0` means "every interface". On a public network, set a password first.
> The project's kill-switch only filters outbound traffic; it does not firewall
> incoming connections.

### 3. From anywhere (OpenTunnel)

```bash
opencode pair --remote
```

The first time, OpenCode explains that this exposes the server to the internet
(end-to-end encrypted, password required) and asks you to accept. Add `--yes` in
a script with no terminal.

OpenTunnel connects **outbound**, so it goes through the WARP tunnel like any
other traffic. If it will not connect, fall back to the SSH option above.

---

## What still works while paired

| | Terminal `opencode` | Paired browser / app |
|---|---|---|
| Server | private, inside the lane | shared, outside the lane |
| Random Cloudflare edge pin | yes | no |
| Traffic through WARP | yes | yes |
| Automatic `/64` rotation on a wall | yes | yes |
| Kill-switch | yes | yes |

The tunnel and the firewall are host-wide, so a paired session still leaves from
your WARP `/64` and `zen-guard` still rotates it when the free limit appears. The
only thing it loses is the per-launch random edge, because the shared server
resolves `opencode.ai` with the host's `/etc/hosts`.

Practical effect: a paired session may hit the limit sooner than the terminal
one. When it does, wait for the rotation and re-send.

---

## Connecting a terminal instead of a browser

You do not have to pair at all. Point a client at the server URL:

```bash
OPENCODE_PASSWORD="a-long-secret" opencode --server http://192.168.1.23:49374
```

Useful for a second laptop or a tmux session on another box. The same caveats
apply: that client uses the shared server, not the lane.

---

## Turning it all off

```bash
opencode service set disabled true     # back to a private server per launch
opencode service status                # should say the service is disabled
```

Paired browser sessions last 30 days. To sign every device out immediately,
change the password and restart:

```bash
opencode service set password "another-long-secret"
opencode service start
opencode service set disabled true
```

## Security notes

- Pair links are **one-time** and expire after 5 minutes. Do not paste them in a
  public chat.
- `--remote` really does publish your server. Verify the accept prompt.
- Never set `hostname 0.0.0.0` on a machine with a public IP and no password.
- Turning the shared service back off is part of the procedure, not optional: it
  is what keeps the edge pin working for the terminal.
