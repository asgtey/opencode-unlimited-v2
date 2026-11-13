# Access: who can install this

**Open to everyone.** The repository is public — no access code, no invitation, no
GitHub account needed.

```bash
curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash
```

There is nothing to request and nothing to revoke. Versions 2.0.5 and 2.0.6 briefly
required a personal code while the repository was private; that is over.

---

## If you still have an old code

It is ignored. Passing `--token` (or `OUC_TOKEN`) is still accepted for people who
run a **fork** or a private mirror, but the public repository never asks for one:

```bash
# both work; the first is all you need
curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash
curl -fsSL https://raw.githubusercontent.com/asgtey/opencode-unlimited-v2/main/get.sh | bash -s -- --token github_pat_XXXX
```

---

## Unattended installs (no terminal)

`install.sh` asks for a username and a password when run as root. When there is no
terminal (cloud-init, CI, docker), it generates a random password and prints it. To
choose the password yourself, pass `OUC_PASSWORD`:

```bash
OUC_PASSWORD='a-long-secret' bash install.sh
```
