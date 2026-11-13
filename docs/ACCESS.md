# Access: who can install this

This repository is private. Nobody can download the installer without an access
code, so you decide who gets it — and you can revoke anyone, one by one.

There are two pieces:

| Piece | What it is |
|---|---|
| `asgtey/ou-start` | tiny **public** launcher (no secrets, no install logic) |
| `asgtey/opencode-unlimited-v2` | this **private** repo, the real bundle |

The launcher asks GitHub for `get.sh` with the code; without a valid code GitHub
returns 404 and nothing is downloaded.

---

## Giving someone access

One code per person. If someone leaks theirs, you delete only that one.

1. Open <https://github.com/settings/personal-access-tokens/new>.
2. **Token name**: the person's name, e.g. `ali-laptop`.
3. **Expiration**: 30 or 90 days (short is safer; they ask again later).
4. **Repository access** → *Only select repositories* → `asgtey/opencode-unlimited-v2`.
5. **Permissions** → *Repository permissions* → **Contents: Read-only**.
   Nothing else is needed. Leave everything else as *No access*.
6. **Generate token** and copy the `github_pat_…` string **once** — GitHub never
   shows it again.

Send that string with the install command:

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/ou-start/main/get.sh | bash -s -- --token github_pat_XXXXXXXX
```

---

## Revoking someone

<https://github.com/settings/personal-access-tokens> → click the code → **Delete**
(or **Regenerate**, which kills the old string immediately).

Their installed copy keeps working — the code only gates the *download*. To lock
out a machine that is already installed, you cannot reach it remotely; you need
access to that machine.

---

## What the person sees

```
  checking your access code…
  ===============================
  Opencode Unlimited — OpenCode 2.x
  ===============================
  downloading asgtey/opencode-unlimited-v2 (main)…
```

A wrong, expired or deleted code stops at the first line:

```
  ✗ the code was rejected or has expired — ask asgtey for a new one
```

After a successful install the code is not needed again. Updates are done with the
same command.

---

## Alternative: GitHub collaborators

If the person already has a GitHub account and you would rather not manage codes,
add them as a collaborator with **Read** role (Settings → Collaborators). Then they
can use `git clone` and the raw URLs with their own login, but the install command
becomes longer and needs their browser session. Codes are simpler.

---

## Unattended installs (no terminal)

`install.sh` asks for a username and a password when run as root. When there is
no terminal (cloud-init, CI, docker), it generates a random password instead and
prints it. To choose it yourself, pass `OUC_PASSWORD`:

```bash
OUC_PASSWORD='a-long-secret' bash install.sh
```
