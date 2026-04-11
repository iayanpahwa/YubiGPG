# Contributing to YubiGPG

Thank you for your interest in contributing. YubiGPG is a security tool — scripts and configs that help people set up air-gapped GPG key generation, YubiKey transfer, and daily machine integration. Because the tool handles cryptographic key material, contributions carry a higher bar than a typical open-source project. Please read this document before opening a PR.

---

## What this project is

YubiGPG provides a numbered sequence of shell scripts (01 through 12, plus a daily machine setup script) and supporting configs for:

- Generating GPG master keys and subkeys in an air-gapped Tails OS environment
- Transferring subkeys to a YubiKey hardware token
- Creating encrypted backups on LUKS USB drives
- Configuring a daily-use macOS or Linux machine to use the YubiKey for GPG and SSH

The target user is someone who wants a well-documented, reproducible process for managing long-lived GPG keys with hardware protection. Scripts must work on real hardware — Tails OS booted from USB, physical YubiKeys, and LUKS-encrypted drives.

---

## What belongs in this repo

- Shell scripts for the setup and maintenance workflow
- GPG and gpg-agent configuration files
- Documentation explaining steps, decisions, and troubleshooting
- Maintenance scripts that extend the workflow (script 13 and beyond)

## What must NEVER be committed

**Do not commit any of the following, ever, under any circumstances:**

- Private key material of any kind (`.asc`, `.gpg`, `.key`, `.pem` files, `gnupg-full-backup/` directories)
- Passphrases, PINs, or any secret credentials — even as examples
- Paperkey output files (`paperkey-raw.txt`, `PAPER-BACKUP-PRINT-ME.txt`)
- Your personal `keyid.txt` or any file containing a real key fingerprint or ID
- Exported public keys (unless explicitly part of a test fixture, which this project doesn't use)

The `.gitignore` covers common cases, but `git status` and `git diff --cached` are your final safety net. When in doubt, do not commit the file.

---

## Reporting bugs

Open a GitHub issue. Include the following — reports missing this information will be closed and asked to resubmit:

1. **Operating system**: Tails version (for scripts 01–09, 11–12) or macOS/Linux version and distribution (for script 10, daily machine setup)
2. **YubiKey model and firmware version**: e.g. "YubiKey 5 NFC, firmware 5.4.3" — found with `ykinfo -a` or `gpg --card-status`
3. **Which script failed**: the script number (e.g. "03-generate-subkeys.sh") or "daily machine setup"
4. **Exact error output**: paste the full terminal output, including the command that was run and everything printed after it. Do not paraphrase.
5. **What you expected to happen**

Security vulnerabilities must NOT be reported as public GitHub issues. See [SECURITY.md](SECURITY.md).

---

## Pull request workflow

1. **Fork** the repository and create a branch off `main`
2. **Name your branch** with a prefix that reflects the change type:
   - `fix/` — bug fix (e.g. `fix/script-07-luks-mount`)
   - `docs/` — documentation only (e.g. `docs/troubleshooting-pinentry`)
   - `feat/` — new script or significant new capability (e.g. `feat/script-13-key-renewal`)
3. **Make your changes** — see Code Style below
4. **Describe your PR**: explain what changed and, more importantly, why. If it fixes a bug, link the issue. If it changes behavior, describe the old behavior and the new behavior.
5. Open the PR against `main`

PRs that only fix typos, formatting, or whitespace in scripts (without improving correctness or clarity) are low priority.

---

## Hardware-only testing

**CI/CD is not possible for this project.** The scripts require:

- A physical Tails OS USB drive, booted on real hardware (not a VM — Tails disables virtualization for security)
- One or more physical YubiKey hardware tokens
- Physical LUKS-encrypted USB drives for backup storage

There is no automated test suite. If you submit a new script or change an existing one, you are expected to have run it on actual hardware matching the documented environment before opening a PR. State in your PR description that you have tested it and describe your test setup (Tails version, YubiKey model, hardware used).

Changes that are documentation-only or config-only (and provably non-breaking) may be accepted without hardware validation at maintainer discretion.

---

## Good contributions

The following are especially welcome:

- **Documentation improvements**: clarifying ambiguous steps, adding troubleshooting entries, fixing outdated instructions
- **New troubleshooting entries**: if you hit a real problem and solved it, document the fix
- **New maintenance scripts (13+)**: scripts that extend the workflow — key renewal, additional backup formats, migration helpers
- **Config improvements**: better defaults, explanations of trade-offs, support for additional hardware or OS versions
- **Accessibility**: making the workflow less intimidating for people who aren't GPG experts

---

## Code style

All scripts must follow these conventions:

- **Strict mode at the top of every script**: `set -euo pipefail` — this causes the script to exit immediately on any error, undefined variable, or pipe failure, preventing silent partial execution
- **Plain-English comments**: every non-obvious command should have a comment above it explaining what it does and why. Write for someone who knows shell scripting but may not know GPG internals.
- **Section headers**: use `=== SECTION NAME ===` style headers to visually divide long scripts into logical phases
- **No bashisms in POSIX sections**: where a script must run on both Tails (Debian) and macOS, avoid bash-only syntax unless the shebang is explicitly `#!/usr/bin/env bash`
- **No hardcoded paths** that differ between systems without a clear comment and fallback
- **Fail loudly**: if something critical fails, print a clear error message and exit non-zero. Never silently continue after a failure.

---

## Security issues

Do not open public GitHub issues for security vulnerabilities. See [SECURITY.md](SECURITY.md) for the responsible disclosure process.
