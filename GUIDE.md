# YubiGPG — Complete Usage Guide

This guide walks you through the full YubiGPG workflow from start to finish: generating your GPG keys on an air-gapped Tails OS machine, backing them up, loading them onto YubiKeys, and configuring your daily machine. Read this alongside the numbered scripts in `scripts/`.

---

## Recommended Hardware Setup

| YubiKey | Role | Touch Policy |
|---|---|---|
| KEY-1 | Primary — daily carry | mandatory |
| KEY-2 | Home backup — safe at home | mandatory |
| KEY-3 | Offsite backup — bank / trusted person | mandatory |

| Key | Algorithm | Expiry | Purpose |
|---|---|---|---|
| Master [C] | ed25519 | Never | Certify subkeys, manage trust hierarchy |
| Signing [S] | ed25519 | 1 year | Git commits, software/binary signatures |
| Encryption [E] | cv25519 | 1 year | Decrypt files encrypted to your public key |
| Authentication [A] | ed25519 | 1 year | SSH into servers (replaces SSH keys) |

---

## What's in the Kit

```
gpg-kit/
├── configs/
│   ├── gpg.conf              ← Hardened GPG defaults (for Tails)
│   ├── gpg-agent.conf        ← SSH agent config (for daily machine)
│   └── gpg-ssh-env.sh        ← Shell env (for daily machine .zshrc/.bashrc)
├── scripts/
│   ├── 01-tails-setup.sh     ← Verify air gap, install configs
│   ├── 02-generate-master.sh ← Create master key [C] (interactive)
│   ├── 03-generate-subkeys.sh← Add [S] [E] [A] subkeys (interactive)
│   ├── 04-export-keys.sh     ← Export all key material
│   ├── 05-backup-to-luks.sh  ← Encrypt backup to USB (run 2x)
│   ├── 06-paper-backup.sh    ← Paper backup → copy to USB for printing
│   ├── 07-yubikey-transfer.sh← Load one YubiKey (run 3x, auto-restores)
│   ├── 08-key-summary.sh     ← Review everything before cleanup
│   ├── 09-cleanup.sh         ← Secure wipe and shutdown
│   ├── 10-daily-machine-setup.sh ← Set up Mac/Linux (run on daily PC)
│   ├── 11-restore-from-luks.sh   ← Future: restore master from backup
│   └── 12-manage-expiry.sh       ← Future: extend/expire/revoke keys
└── docs/
    └── PAPER-RECOVERY.md     ← How to recover from paper backup
```

---

## Execution Order

### Phase 1: On a Networked Machine (preparation)

1. Download Tails OS from https://tails.net and verify signatures
2. Flash Tails to a USB drive
3. Copy the `gpg-kit/` folder to a separate config USB

### Phase 2: On Tails (air-gapped) — key generation

Run each script in order. Every script tells you what comes next.

```
01-tails-setup.sh          ← Verify air gap, install gpg.conf
        ↓
02-generate-master.sh      ← Create ed25519 master key (you enter name, email)
        ↓
03-generate-subkeys.sh     ← Add 3 subkeys (you enter expiry period)
        ↓
04-export-keys.sh          ← Export everything to /tmp/gpg-export/
        ↓
05-backup-to-luks.sh       ← Run TWICE (backup USB #1, then #2)
        ↓
06-paper-backup.sh         ← Generate paperkey, copy to USB for printing
        ↓
07-yubikey-transfer.sh     ← Run THREE TIMES (one per YubiKey)
        ↓                     Auto-restores keys between each transfer
08-key-summary.sh          ← Review: what is what, what's shareable
        ↓
09-cleanup.sh              ← Secure wipe → shutdown Tails
```

### Phase 3: On Your Daily Machine (Mac or Linux)

```
10-daily-machine-setup.sh  ← Import public key, configure agent, Git, SSH
```

### Phase 4: Future Maintenance (boot Tails again)

```
01-tails-setup.sh          ← Re-establish air gap
        ↓
11-restore-from-luks.sh    ← Decrypt backup USB, import master key
        ↓
12-manage-expiry.sh        ← Extend, expire, revoke, or regenerate
        ↓
07-yubikey-transfer.sh     ← If new subkeys: reload YubiKeys
        ↓
09-cleanup.sh              ← Wipe and shutdown
```

---

## Key Preservation During YubiKey Transfers

The `keytocard` command is destructive — it moves (not copies) the secret key to the YubiKey and deletes it from disk. To load the same subkeys onto all 3 YubiKeys:

1. Script 04 exports the master key to `/tmp/gpg-export/master-secret-key.asc`
2. Script 07 **always** re-imports from this backup before each transfer
3. After `keytocard` deletes the local keys, the backup file remains intact
4. Next YubiKey run: script re-imports → transfers → keys deleted → repeat
5. The backup file is only destroyed in script 09 (cleanup) after all 3 are done

You will never lose keys between YubiKey transfers.

---

## macOS-Specific Notes

The daily machine setup script (10) handles macOS automatically:

- Detects Apple Silicon vs Intel Homebrew paths
- Installs `pinentry-mac` for native PIN dialog (instead of terminal prompt)
- Points `gpg.program` in git config to the correct `gpg` binary
- Adds `gpg-connect-agent updatestartuptty` to `.zshrc` (fixes stale TTY issue)
- Overrides macOS's built-in `ssh-agent` with `gpg-agent`

**If the PIN prompt doesn't appear on macOS:**
```bash
gpg-restart    # alias that kills and relaunches gpg-agent
```

**Common macOS issues:**
- `brew install gnupg pinentry-mac` — needed for GPG + native PIN dialog
- macOS may start its own SSH agent — the shell env overrides `SSH_AUTH_SOCK`
- After macOS sleep/wake, run `gpg-restart` if the YubiKey stops responding

---

## What Can Be Shared Publicly

| Item | Public? | Notes |
|---|---|---|
| `public-key.asc` | **YES** | Upload everywhere: GitHub, keyservers, website |
| Fingerprint | **YES** | Put in email sig, social bio, business cards |
| SSH public key | **YES** | Add to servers and GitHub SSH keys |
| `master-secret-key.asc` | **NEVER** | Anyone + passphrase = full impersonation |
| `subkeys-secret.asc` | **NEVER** | Allows sign/decrypt/SSH as you |
| `revocation-cert.asc` | **NEVER** | Can permanently destroy your key reputation |
| `PAPER-BACKUP-PRINT-ME.txt` | **NEVER** | Secret key in hex (needs pubkey + passphrase) |
| YubiKey PINs | **NEVER** | Protect physical access to your keys |
| GPG passphrase | **NEVER** | Protects the master key backups |

---

## Emergency Procedures

| Situation | Action |
|---|---|
| Lost YubiKey | Boot Tails → restore master → revoke subkeys → generate new → reload remaining YubiKeys → publish updated public key |
| Expiry approaching | Boot Tails → restore master → extend expiry → export updated public key → import on daily machine → publish |
| Key compromised | Import `revocation-cert.asc` → publish to keyservers → generate entirely new key |
| Forgot YubiKey PIN | Use admin PIN to reset user PIN. If admin locked: `ykman openpgp reset` (destroys keys on that card) |
| Both LUKS USBs lost | Use paper backup (see `docs/PAPER-RECOVERY.md`) |
| Forgot passphrase | **Unrecoverable.** All backups are useless without the passphrase. |
| CRQC threat | No post-quantum support in current YubiKey + GnuPG. Long-lived encrypted data may be at risk if a Cryptographically Relevant Quantum Computer becomes viable. See [filippo.io/crqc-timeline](https://words.filippo.io/crqc-timeline). |

---

## Quick Reference

```
Sign a commit:       git commit -m "message"   (automatic)
Sign a file:         gpg --armor --detach-sign file.tar.gz
Verify a signature:  gpg --verify file.tar.gz.asc file.tar.gz
Encrypt to self:     gpg -r YOUR_KEY_ID -e file.txt
Encrypt to someone:  gpg -r THEIR_KEY_ID -e file.txt
Decrypt:             gpg -d file.txt.gpg > file.txt
SSH (just works):    ssh user@server
SSH public key:      gpg --export-ssh-key YOUR_KEY_ID
                     (Alternative: FIDO2 SSH via `ssh-keygen -t ed25519-sk` is simpler if SSH is your only goal)
Card status:         gpg --card-status
Restart agent:       gpg-restart  (alias from setup)
List keys:           gpg-list     (alias from setup)
```
