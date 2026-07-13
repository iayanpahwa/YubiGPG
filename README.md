# YubiGPG

**A system for generating GPG keys on an air-gapped machine and loading them onto multiple YubiKey hardware tokens, taking backup on encrypted flash drive and a paper-key**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/iayanpahwa/YubiGPG)](https://github.com/iayanpahwa/YubiGPG/releases/latest)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.21340957.svg)](https://doi.org/10.5281/zenodo.21340957)

YubiGPG is a semi-vibe-coded project which gives you a complete, scripted and an interactive workflow to generate a GPG (GNU Privacy Guard) master key in the most secure environment possible — an air-gapped Tails OS machine — and then distribute your subkeys across three YubiKey hardware tokens. After that, a single script configures your daily macOS or Linux machine to use the YubiKey for GPG signing, encryption, and SSH authentication.

P.S - This will not affect your Yubikey functionality for 2FA/MFA (TOTP, WebAuthn, FIDO etc), this will just flash your GPG keys for authentication, signing and encryption to your Yubikey and no they can never leave it, but can surely be replaced in future when they expired or when you voluntrily want to replace them with a new one. 

---

## Table of Contents

1. [Why This Exists](#why-this-exists)
2. [Security Model](#security-model)
3. [What You Will End Up With](#what-you-will-end-up-with)
4. [Hardware Checklist](#hardware-checklist)
5. [Key Architecture](#key-architecture)
6. [Getting Started — Phase 1 (Preparation)](#getting-started--phase-1-preparation)
7. [Phase Overview](#phase-overview)
8. [Script Reference](#script-reference)
9. [Configuration Files](#configuration-files)
10. [Documentation](#documentation)
11. [Glossary](#glossary)
12. [Troubleshooting](#troubleshooting)
13. [Emergency Procedures](#emergency-procedures)
14. [Future Maintenance — Phase 4](#future-maintenance--phase-4)
15. [What Can Be Shared Publicly](#what-can-be-shared-publicly)
16. [Quick Reference Cheat Sheet](#quick-reference-cheat-sheet)
17. [Contributing](#contributing)
18. [Inspiration and Credits](#inspiration-and-credits)
19. [License](#license)

---

## Why This Exists

### The Problem with Typical GPG Setups

Most people who set up GPG do it on their everyday computer. They generate their master key, add their subkeys, and keep everything in `~/.gnupg`. This works, but it means:

- Your master key (the key that controls your entire cryptographic identity) lives on a machine that is connected to the internet, runs untrusted software, and could be compromised at any time.
- If your machine is hacked, your master key is stolen. An attacker can forge signatures, decrypt your past messages, and impersonate you on keyservers — forever, unless you have a revocation certificate ready.
- If you lose your laptop, your master key is gone (or in an attacker's hands).

### Why Air-Gapped Key Generation Matters

An air-gapped machine is one that has never touched a network during the key generation session. Tails OS (The Amnesic Incognito Live System) is designed for exactly this purpose: it runs entirely from RAM, leaves no traces on the machine it boots from, and makes it easy to verify that no network interfaces are active.

By generating your GPG master key on an air-gapped Tails machine:

- The master key is **never exposed to any network**, ever.
- Even if your daily machine is completely compromised, the attacker cannot reach your master key — it never existed there.
- The Tails session is amnesic: when you shut it down, nothing is written to the machine's storage.

### Why Hardware Tokens Matter

A YubiKey is a small USB device that stores cryptographic keys in hardware. Keys loaded onto a YubiKey cannot be extracted from it. When you use a YubiKey for GPG:

- The private key **never leaves the device**. Your computer sends the data to be signed or decrypted to the YubiKey, the YubiKey does the operation internally, and returns only the result.
- If your daily machine is compromised while the YubiKey is plugged in, an attacker can use it to sign things only until you unplug it. They cannot steal the key itself.
- Touch policy enforcement means the YubiKey requires a physical button press for every cryptographic operation. Malware cannot silently use the key in the background.
- If you lose the YubiKey, it is protected by a PIN. After a small number of wrong PIN attempts, the key becomes blocked.

### Why Three YubiKeys?

Hardware can fail. YubiKeys can be lost, stolen, or damaged. This setup uses three:

- **KEY-1 (daily carry)**: Plugged into your computer during normal use.
- **KEY-2 (home backup)**: Stored in a safe at home. Grab it if the daily carry is lost.
- **KEY-3 (offsite backup)**: Stored at a bank or with a trusted person. Last-resort recovery if both others are gone.

Since all three hold the same subkeys, you can switch between them at any time without re-configuring your machine.

---

## Security Model

### What This Setup Defends Against

| Threat | Defense |
|--------|---------|
| Compromised daily machine | Subkeys live on YubiKey, never on disk. Master key never touches the daily machine. |
| Stolen YubiKey | PIN protection + touch requirement. After wrong PIN attempts, card blocks. Key cannot be extracted. |
| Lost LUKS backup USB | Second USB covers the loss. Paper backup covers both USBs being lost. |
| Nosy software on daily machine | Subkey operations require physical touch on the YubiKey. |
| Expired subkeys | Scripts 11 and 12 handle extending expiry from the air-gapped backup. |
| Accidental key destruction during YubiKey loading | Script 07 re-imports from backup before each `keytocard` run. |

### What This Setup Does NOT Protect Against

Being honest about the limits of this system:

| Threat | Why It Is Not Covered |
|--------|----------------------|
| Evil Maid attack | If someone physically modifies the machine before you boot Tails on it, all bets are off. Use hardware you trust. |
| Tails OS compromise | This setup trusts Tails. Download Tails only from tails.net and verify the signature. |
| Forgotten passphrase | The master key backups are encrypted with your passphrase. No passphrase = no access. There is no recovery. |
| Both LUKS USBs AND paper backup lost | If all three backup methods are gone, the master key is unrecoverable. Keep backups in different physical locations. |
| User errors during key generation | Scripts have safety checks, but they cannot prevent all operator mistakes. Read each script prompt carefully. |
| Rubber hose attack | If someone compels you to reveal your passphrase, this system does not help. |
| Harvest-now-decrypt-later / CRQC | Current YubiKey firmware and GnuPG do not support post-quantum algorithms (e.g., ML-KEM, ML-DSA). If a Cryptographically Relevant Quantum Computer (CRQC) becomes available, encrypted data captured today could be decrypted retroactively. See [filippo.io/crqc-timeline](https://words.filippo.io/crqc-timeline) for the current threat assessment. |

---

## What You Will End Up With

After completing all four phases, you will have:

**On your person / in your bag:**
- 1 YubiKey (KEY-1, daily carry) with your GPG subkeys loaded (Sign, Encrypt, Authenticate)
- Your daily macOS or Linux machine configured to use it for Git signing, GPG, and SSH

**In secure physical storage:**
- 1 YubiKey (KEY-2) with the same subkeys, stored in a home safe
- 1 YubiKey (KEY-3) with the same subkeys, stored offsite
- 2 separate LUKS2-encrypted USB drives, each containing a full backup of your master secret key, all subkeys, and your revocation certificate — protected by a strong passphrase
- 1 paper printout of your master secret key in hex format (via `paperkey`), which can reconstruct the key if both USBs are lost

**Published / importable:**
- Your GPG public key uploaded to keyservers, GitHub, or wherever you choose
- Your SSH public key (derived from the GPG authentication subkey) added to servers

**Key hierarchy:**
- 1 master key [C] (ed25519, no expiry) — certify only, stays air-gapped forever
- 3 subkeys (Sign [S] ed25519, Encrypt [E] cv25519, Authenticate [A] ed25519) — all 1-year expiry, all loaded on all 3 YubiKeys with mandatory touch policy

---

## Hardware Checklist

Gather everything before you start. You cannot pause mid-session on an air-gapped machine to go shopping.

### Required Hardware

| Item | Notes |
|------|-------|
| 3x YubiKey 5 series | USB-A or USB-C. Firmware 5.2.3 or later strongly recommended for ed25519 support. The YubiKey 5C NFC (USB-C with NFC) is a popular daily carry choice. |
| 1x Tails OS boot USB | 8 GB or larger. This is the USB you will boot Tails from. |
| 1x Kit transfer USB | Any size. Used to copy the YubiGPG scripts and configs from your networked machine to Tails. |
| 2x LUKS backup USBs | Any size, 1 GB is more than enough. These will hold your encrypted key backups. Use different brands if possible — if one batch has a manufacturing defect, the other is likely fine. |
| 1x Printer | For printing the paperkey hex backup. A laser printer is preferable (ink does not fade). |
| A bootable x86_64 machine | Tails requires an Intel or AMD x86_64 machine. It does not run on Apple Silicon (M-series Mac). You can use an old laptop, a desktop, or any machine where you can boot from USB. |
| Your daily machine | macOS or Linux. This is where you will run the daily machine setup script (script 10) after the Tails session. |

### Buying Guidance

- **YubiKey**: Purchase directly from Yubico (yubico.com) or an authorized reseller. Do not buy from third-party sellers on marketplaces — counterfeit or tampered YubiKeys exist.
- **USB drives**: Brand-name drives (SanDisk, Samsung, Kingston) are preferable for backup purposes. Avoid cheap no-name drives for the LUKS backup role.
- **Tails USB**: Any USB 3.0 drive of 8 GB or more works. Speed matters here — a faster drive means Tails boots faster.

### Optional but Recommended

- A USB hub, in case your machine has limited USB ports during the Tails session (you may need to plug in the Kit USB, up to 3 YubiKeys in sequence, and up to 2 backup USBs).
- A USB-A to USB-C adapter, if your YubiKeys have USB-C connectors and your Tails machine only has USB-A ports (or vice versa).

### Check Your YubiKey Firmware Before You Begin

Before generating any keys, check which firmware version your YubiKey is running — this determines which key algorithm you can use.

**How to check (on any networked machine before the Tails session):**

```bash
# Using YubiKey Manager CLI:
ykman info

# Or via Yubico Authenticator (GUI): Devices → select your key → firmware version shown

# Or via GPG after inserting the YubiKey:
gpg --card-status | grep Version
```

**ed25519 vs RSA — which should you pick?**

| Algorithm | Firmware required | Key size | Speed | Notes |
|-----------|-------------------|----------|-------|-------|
| **ed25519 / cv25519** | **≥ 5.2.3** | 256-bit | Fast | Modern elliptic-curve. Default in these scripts. |
| **RSA 4096** | Any YubiKey 5 | 4096-bit | Slower | Larger keys, but works on all firmware versions. |

- **ed25519** is a modern elliptic-curve algorithm. A 256-bit ed25519 key offers roughly equivalent security to a 3072-bit RSA key, with faster operations and smaller key material. It is what these scripts generate by default.
- **RSA 4096** is the traditional choice. Keys are larger and operations are slower, but it is universally supported and perfectly secure. Choose this if your firmware is below 5.2.3.

**Decision:**

- **Firmware ≥ 5.2.3** (all YubiKey 5 series purchased after 2019): use **ed25519/cv25519** — follow these scripts as written.
- **Firmware < 5.2.3** (older hardware): use **RSA 4096** — when GPG prompts you to select a key type during scripts 02 and 03, choose RSA instead of Curve 25519 and enter `4096` as the key size.

> If you are unsure or your hardware is old, replace it before starting. All current YubiKey 5 series ship with firmware well above 5.2.3. Purchase directly from [yubico.com](https://yubico.com).

---

## Key Architecture

### Key Hierarchy Diagram

```
                    +-----------------------------------------+
                    |         GPG Master Key [C]              |
                    |   ed25519 | No expiry | Certify only    |
                    |   NEVER touches a networked machine     |
                    +-----------------------------------------+
                                        |
                    +-------------------+-------------------+
                    |                   |                   |
           +--------+-------+  +--------+-------+  +-------+--------+
           |  Subkey [S]    |  |  Subkey [E]    |  |  Subkey [A]   |
           |  ed25519       |  |  cv25519       |  |  ed25519      |
           |  Sign          |  |  Encrypt       |  |  Authenticate |
           |  1yr expiry    |  |  1yr expiry    |  |  1yr expiry   |
           +----------------+  +----------------+  +---------------+
                    |                   |                   |
          +---------+---------+---------+---------+---------+
          |                   |                   |
   +-----------+       +-----------+       +-----------+
   | YubiKey   |       | YubiKey   |       | YubiKey   |
   | KEY-1     |       | KEY-2     |       | KEY-3     |
   | Daily     |       | Home safe |       | Offsite   |
   | carry     |       |           |       | backup    |
   +-----------+       +-----------+       +-----------+
```

### Backup Structure

```
   Master Key Backups (3 independent methods)
   ============================================

   Method 1: LUKS USB #1         Method 2: LUKS USB #2
   +---------------------------+  +---------------------------+
   | LUKS2-encrypted volume    |  | LUKS2-encrypted volume    |
   | Passphrase-protected      |  | Passphrase-protected      |
   |                           |  |                           |
   | master-secret-key.asc     |  | master-secret-key.asc     |
   | subkeys-secret.asc        |  | subkeys-secret.asc        |
   | public-key.asc            |  | public-key.asc            |
   | revocation-cert.asc       |  | revocation-cert.asc       |
   +---------------------------+  +---------------------------+
   Store: Home safe                Store: Offsite / bank

   Method 3: Paper backup
   +---------------------------+
   | Printed hex data          |
   | (paperkey format)         |
   | Requires: public key +    |
   | passphrase to reconstruct |
   +---------------------------+
   Store: Fireproof safe or
   safety deposit box
```

### What Each Key Capability Means

| Key | Capability | Real-World Use |
|-----|-----------|----------------|
| Master [C] | Certify | Signs other people's keys (web of trust), creates and revokes subkeys |
| Subkey [S] | Sign | `git commit` signatures, `gpg --detach-sign` on files and releases |
| Subkey [E] | Encrypt | `gpg --encrypt` for files and emails sent to you |
| Subkey [A] | Authenticate | SSH into servers — replaces `~/.ssh/id_ed25519` entirely |

---

## Getting Started -- Phase 1 (Preparation)

Phase 1 happens on a normal networked machine (your daily computer). You need internet access for this phase.

### Step 1: Download the gpg-kit

The easiest way is to grab the latest release — a pre-packaged archive ready to copy straight to your transfer USB:

1. Go to the [latest release](https://github.com/iayanpahwa/YubiGPG/releases/latest)
2. Download `gpg-kit-v1.0.0.tar.gz`
3. **Verify before use** (do not skip this):

```bash
# Verify the checksum
shasum -a 256 -c gpg-kit-v1.0.0.tar.gz.sha256

# Verify the GPG signature (import the maintainer's public key first)
gpg --verify gpg-kit-v1.0.0.tar.gz.asc gpg-kit-v1.0.0.tar.gz
```

4. Extract the archive:

```bash
tar -xzf gpg-kit-v1.0.0.tar.gz
# You now have a gpg-kit/ folder — this is what goes on the USB
```

Alternatively, clone the repo directly:

```bash
git clone https://github.com/iayanpahwa/YubiGPG.git
cd YubiGPG
```

### Step 2: Download and Verify Tails OS

1. Go to **https://tails.net** (the official site — be careful of typos).
2. Follow the official download instructions for your operating system.
3. **Verify the signature.** Tails provides detailed instructions for this. Do not skip verification — it is the only way to confirm you have a genuine Tails image.

### Step 3: Flash Tails to a USB Drive

Follow the official Tails installation instructions. On macOS, Tails provides a graphical installer. On Linux, you can use the `dd` command or a tool like Balena Etcher.

The Tails boot USB will be reformatted during this process. Do not use a USB that has data you need to keep. Set a sudo / administrator password during boot.

### Step 4: Copy the gpg-kit to the Transfer USB

Insert a separate USB drive (not the Tails boot USB — a different one). Format it as FAT32 or exFAT so Tails can read it.

**If you downloaded the release archive**, the extracted `gpg-kit/` folder is already structured correctly — just copy it to the USB:

```bash
# On macOS
cp -r gpg-kit/ /Volumes/YOUR_USB/gpg-kit

# On Linux
cp -r gpg-kit/ /media/YOUR_USERNAME/USBNAME/gpg-kit
```

**If you cloned the repo**, copy the repo contents into a `gpg-kit/` folder on the USB:

```bash
# On macOS
cp -r /path/to/YubiGPG /Volumes/YOUR_USB/gpg-kit

# On Linux
cp -r /path/to/YubiGPG /media/YOUR_USERNAME/USBNAME/gpg-kit
```

Confirm the directory looks like this on the USB:

```
gpg-kit/ (this github repo)
├── configs/
│   ├── gpg.conf
│   ├── gpg-agent.conf
│   └── gpg-ssh-env.sh
├── scripts/
│   ├── 01-tails-setup.sh
│   ├── 02-generate-master.sh
│   ... (all 12 scripts)
└── docs/
    └── PAPER-RECOVERY.md
```

### Step 5: Prepare Your YubiKeys

Before the Tails session, change the default PINs on each YubiKey. The factory defaults are:

- User PIN: `123456`
- Admin PIN: `12345678`
- Reset Code: (not set by default)

You can change PINs from your daily machine before the Tails session:

```bash
# Install ykman if not already installed
# macOS:
brew install ykman

# Then change PINs (do this for each YubiKey)
gpg --card-edit
# At the gpg/card> prompt:
# admin
# passwd
# Choose option 1 to change user PIN
# Choose option 3 to change admin PIN
# quit
```

Choose strong, memorable PINs. You will need the User PIN for every cryptographic operation. You will need the Admin PIN for YubiKey configuration. **If you forget the Admin PIN and the User PIN is blocked, the only recovery is a full YubiKey reset, which destroys the keys on the card.**

Write down your PINs temporarily and store them securely until you have them memorized.

### Step 6: Prepare for the Tails Session

Gather everything you need before you sit down at the air-gapped machine:

- [x] Tails boot USB
- [x] Kit transfer USB (with YubiGPG scripts)
- [x] 2 LUKS backup USBs (empty, or data you are willing to destroy)
- [x] 3 YubiKeys (with PINs changed from defaults)
- [x] Printer connected and ready (for paper backup)
- [x] A strong passphrase in your head — this will protect the master key backup. Use a memorable passphrase of at least 6 random words (diceware style). Write it down temporarily.
- [x] Your name and email address (will be embedded in the GPG key)

You are now ready for Phase 2.

---

## Phase Overview

### Phase 2: Air-Gapped Tails Session (Key Generation)

Boot the Tails OS USB on your air-gapped machine. Set an admin password when prompted (you will need it to run commands as root). Do NOT connect to a network.

Run the scripts in order. Each script will tell you what to do next.

```
01-tails-setup.sh          Verify air gap, install gpg.conf, start pcscd
        |
02-generate-master.sh      Create ed25519 master key (enter name, email, passphrase)
        |
03-generate-subkeys.sh     Add Sign, Encrypt, Authenticate subkeys (enter expiry)
        |
04-export-keys.sh          Export everything to /tmp/gpg-export/
        |
05-backup-to-luks.sh       Run TWICE — once per backup USB
        |
06-paper-backup.sh         Generate hex backup, copy to USB for printing
        |
07-yubikey-transfer.sh     Run THREE TIMES — one per YubiKey (auto-restores between runs)
        |
08-key-summary.sh          Review all output before destroying anything
        |
09-cleanup.sh              Secure wipe all key material, shutdown Tails
```

### Phase 3: Daily Machine Setup

Back on your normal daily machine (macOS or Linux):

```
10-daily-machine-setup.sh  Install packages, import public key, configure SSH/Git, test YubiKey
```

This is a one-time setup. After this, your daily machine is ready.

### Phase 4: Future Maintenance (when needed)

When subkeys approach expiry, or when you need to revoke a compromised key, boot Tails again and run:

```
01-tails-setup.sh          Re-establish air-gapped environment
        |
11-restore-from-luks.sh    Decrypt a backup USB and import the master key
        |
12-manage-expiry.sh        Extend expiry, revoke, or regenerate subkeys
        |
07-yubikey-transfer.sh     If new subkeys were generated, load them on all 3 YubiKeys
        |
09-cleanup.sh              Wipe and shutdown
```

---

## Script Reference

| Script | Purpose | Phase | How Many Times to Run |
|--------|---------|-------|-----------------------|
| `01-tails-setup.sh` | Verify air gap is active, install `gpg.conf` to `~/.gnupg/`, start the `pcscd` smart card daemon so Tails can talk to YubiKeys | Start of every Tails session | Once per session (or more if needed) |
| `02-generate-master.sh` | Interactively create the ed25519 master [C] key with your name and email | Key generation only | Once, ever |
| `03-generate-subkeys.sh` | Add the three subkeys: Sign [S] ed25519, Encrypt [E] cv25519, Authenticate [A] ed25519 | Key generation only | Once, ever |
| `04-export-keys.sh` | Export master secret key, subkeys secret, public key, and revocation certificate to `/tmp/gpg-export/` | Key generation only | Once |
| `05-backup-to-luks.sh` | Create a LUKS2-encrypted volume on a USB drive and copy all exported key material into it | Key generation only | Twice (run once per backup USB) |
| `06-paper-backup.sh` | Use `paperkey` to produce a hex representation of the master secret key, copy it to the kit USB for printing | Key generation only | Once |
| `07-yubikey-transfer.sh` | Load subkeys onto one YubiKey using `keytocard`. Automatically re-imports from backup before each run so local keys survive the destructive transfer. | Key generation + after subkey regen | Three times (once per YubiKey) |
| `08-key-summary.sh` | Display a full summary of what exists: key fingerprints, YubiKey card status, what files are on the LUKS USBs | Before cleanup | Once |
| `09-cleanup.sh` | Securely wipe `/tmp/gpg-export/` and `~/.gnupg/`, present a final checklist, and shut down Tails | End of every Tails session | Once per session |
| `10-daily-machine-setup.sh` | Install `gnupg`, `pinentry-mac` (macOS), configure `~/.gnupg/gpg-agent.conf`, import the public key, configure Git signing, add SSH env to shell RC | After first Tails session | Once (on daily machine) |
| `11-restore-from-luks.sh` | Mount a LUKS backup USB, decrypt it, import the master secret key into Tails' GPG keyring | Future maintenance | As needed |
| `12-manage-expiry.sh` | Interactively extend key expiry dates, revoke subkeys, or generate replacement subkeys | Future maintenance | As needed |

---

## Configuration Files

The `configs/` directory contains three files that are installed onto the appropriate machines by the scripts. Here is what each one does and where it ends up.

### `configs/gpg.conf`

**Installed to**: `~/.gnupg/gpg.conf` on the Tails machine (by script 01)

This file configures GPG's cryptographic preferences in hardened mode. It tells GPG to prefer the strongest available algorithms and to never output version strings (which could reveal your software version to attackers).

Key settings:
- **`personal-cipher-preferences AES256 AES192 AES`** — When encrypting, prefer AES-256. AES-256 is considered unbreakable with current technology.
- **`personal-digest-preferences SHA512 SHA384 SHA256`** — When hashing (signing, key certification), prefer SHA-512. SHA-512 produces a 512-bit hash that is computationally infeasible to reverse or collide.
- **`cert-digest-algo SHA512`** — All key certifications (signatures on keys) must use SHA-512.
- **`s2k-digest-algo SHA512` and `s2k-cipher-algo AES256`** — The string-to-key function (which derives an encryption key from your passphrase) uses SHA-512 and AES-256. This means your passphrase is protected by the strongest available algorithms.
- **`keyid-format 0xlong`** — Display long (64-bit) key IDs, which are much harder to fake than short (32-bit) IDs.
- **`with-fingerprint`** — Always display the full 160-bit fingerprint, not just the key ID.
- **`no-comments` and `no-emit-version`** — Do not include "Comment:" or "Version:" headers in exported key blocks or signatures. These headers leak information.
- **`no-auto-key-locate`** — Do not automatically fetch keys from keyservers. You decide when to fetch.

### `configs/gpg-agent.conf`

**Installed to**: `~/.gnupg/gpg-agent.conf` on your daily machine (by script 10)

The GPG agent (`gpg-agent`) is a background process that manages your private keys and PIN caching. On a YubiKey setup, it also acts as an SSH agent.

Key settings:
- **`enable-ssh-support`** — Tells `gpg-agent` to expose an SSH agent socket. Your shell will point `SSH_AUTH_SOCK` to this socket, which makes all SSH commands automatically use the authentication subkey on your YubiKey.
- **`default-cache-ttl 600`** — Cache the PIN for 10 minutes after each GPG operation. You will not be re-prompted for the PIN on every single signing operation within a 10-minute window.
- **`max-cache-ttl 7200`** — The cached PIN expires after 2 hours of inactivity at most.
- **`default-cache-ttl-ssh 600` and `max-cache-ttl-ssh 7200`** — Same caching behavior for SSH operations.
- **`pinentry-program`** — The script uncomments the correct line for your OS. On macOS, `pinentry-mac` provides a native graphical dialog for PIN entry. On Linux, `pinentry-gnome3` (GUI) or `pinentry-curses` (terminal) are available.

### `configs/gpg-ssh-env.sh`

**Appended to**: `~/.zshrc` or `~/.bashrc` on your daily machine (by script 10)

This shell environment file configures every new terminal session to route SSH through `gpg-agent`.

Key sections:
- **`export GPG_TTY=$(tty)`** — Tells GPG which terminal to use for PIN prompts in terminal-mode pinentry. Required for pinentry to work correctly.
- **macOS SSH agent override** — On macOS, the system starts its own SSH agent via `launchd`. This script unsets `SSH_AGENT_PID` to prevent confusion between the system agent and `gpg-agent`.
- **`export SSH_AUTH_SOCK`** — Points to `gpg-agent`'s SSH socket. Every time you run `ssh`, it will talk to `gpg-agent`, which in turn talks to your YubiKey.
- **`gpgconf --launch gpg-agent`** — Ensures the agent is running at the start of every terminal session.
- **`gpg-connect-agent updatestartuptty /bye`** — Tells `gpg-agent` which terminal is the current one. This fixes a common macOS issue where the PIN prompt appears on a stale, closed terminal window after sleep/wake.
- **Aliases**: `gpg-ssh-pubkey`, `gpg-card`, `gpg-restart`, `gpg-list` — convenience shortcuts for common operations.

---

## Glossary

This section explains every technical term used in this project in plain English.

### Air Gap
A physical security measure where a computer has no network connections — no Wi-Fi, no Ethernet, no Bluetooth. An air-gapped machine cannot send or receive data over a network. In this project, Tails OS is run on an air-gapped machine so that no malware on the internet can observe or steal the GPG master key during generation.

### Authentication Subkey [A]
One of the three GPG subkeys generated in this project. The authentication subkey is used to prove your identity — specifically, to authenticate SSH sessions. Instead of generating a separate `~/.ssh/id_ed25519` key pair, your SSH clients use the authentication subkey stored on your YubiKey. This means SSH access to all your servers is protected by the YubiKey's hardware and PIN.

**Alternative — FIDO2 SSH keys:** For many users, hardware-backed SSH via FIDO2 (`ssh-keygen -t ed25519-sk`) is simpler to set up and is natively supported by OpenSSH ≥ 8.2 and modern YubiKeys. If SSH is your primary use case and you do not need GPG signing or encryption, FIDO2 SSH may be a better fit. This guide uses GPG-for-SSH to keep everything on one key with one trust anchor.

### cv25519
An elliptic-curve Diffie-Hellman algorithm used for encryption. "cv" stands for Curve25519, which is a well-analyzed, modern elliptic curve designed by cryptographer Daniel J. Bernstein. It is used for the encryption subkey [E] in this project. Note: signing and authentication use ed25519, while encryption uses cv25519 — these are related but different algorithms built on the same underlying curve.

### ed25519
An elliptic-curve digital signature algorithm. "ed" stands for Edwards-curve Digital Signature Algorithm on Curve25519. It produces 64-byte signatures, is very fast, and has a strong security track record. This project uses ed25519 for the master key, signing subkey [S], and authentication subkey [A].

### ECC (Elliptic Curve Cryptography)
A family of cryptographic algorithms based on the mathematics of elliptic curves over finite fields. ECC keys are much shorter than RSA keys for the same security level — a 256-bit ECC key provides similar security to a 3072-bit RSA key. Both ed25519 and cv25519 are ECC algorithms.

### Encryption Subkey [E]
One of the three GPG subkeys. When someone wants to send you an encrypted message or file, they use your public key's encryption subkey to encrypt it. Only your YubiKey (which holds the corresponding private subkey) can decrypt it.

### gpg-agent
A background daemon (long-running process) that manages GPG private keys and PIN caching. After you enter your PIN once, `gpg-agent` caches it for the configured TTL (time to live) so you are not asked on every operation. In this project, `gpg-agent` is also configured as an SSH agent, handling SSH authentication through the YubiKey's authentication subkey.

### keytocard
A GPG command that moves a private key from the local GPG keyring onto a smart card (like a YubiKey). The key word is "moves" — after `keytocard` runs, the local copy of the private key is replaced by a stub that points to the card. The key is now on the hardware and cannot be extracted. This is why script 07 must re-import from the backup before loading each YubiKey — the first `keytocard` call would otherwise destroy the local copy before the other two YubiKeys are loaded.

### LUKS (Linux Unified Key Setup)
The standard disk encryption specification for Linux. LUKS2 (version 2) is the current standard. In this project, scripts create a LUKS2-encrypted volume on each backup USB drive. The volume is protected by a passphrase. Without the correct passphrase, the data on the drive is computationally indistinguishable from random noise — it cannot be read.

### Master Key [C]
The root of your GPG identity. The "C" stands for Certify. The master key's only function is to:
1. Sign (certify) other people's public keys (establishing web of trust relationships)
2. Create and revoke your own subkeys

The master key itself is never used for signing files, encrypting messages, or authenticating SSH sessions. Those operations use subkeys. This design means the master key can stay air-gapped forever, while subkeys (which expire) can be rotated without changing your public identity.

### Paperkey
A tool (and format) for exporting the secret parts of a GPG key as a hex text dump that can be printed on paper. Paperkey is designed for disaster recovery: if all digital backups are lost, you can reconstruct the secret key by typing in the hex data from the printout, combined with your public key (which is freely available). This project uses paperkey as the third backup method.

### Passphrase
A string of words or characters used to protect your GPG secret key backups. Unlike a PIN, which is short and used for hardware access, a passphrase is longer and used to encrypt/decrypt key files. The passphrase encrypts the LUKS volumes and the GPG secret keys exported during backup. Without it, the backups are useless. **There is no recovery mechanism for a forgotten passphrase.**

### pcscd (PC/SC Daemon)
A system service that provides communication between the operating system and smart card readers, including YubiKeys. In Tails, `pcscd` is not running by default and must be started manually. Script 01 handles this. Without `pcscd`, GPG cannot communicate with the YubiKey.

### PIN (User PIN)
A short numeric or alphanumeric code that protects the YubiKey. You enter the User PIN every time you use the YubiKey for a cryptographic operation (signing, decrypting, or authenticating — subject to the PIN cache TTL in `gpg-agent.conf`). After 3 consecutive wrong attempts, the User PIN is blocked.

### PIN (Admin PIN)
A longer PIN that protects YubiKey administrative functions, such as changing the User PIN, loading keys onto the card, or changing touch policy. After 3 consecutive wrong Admin PIN attempts, the card becomes permanently locked (all keys are destroyed). **Do not confuse the User PIN and Admin PIN.**

### Signing Subkey [S]
One of the three GPG subkeys. Used to sign files, emails, and Git commits. When you run `git commit`, Git calls GPG with the signing subkey, which sends the data to the YubiKey, which signs it after you touch the button.

### Subkey
A GPG key that is certified by and subordinate to a master key. Subkeys have their own key IDs, algorithms, and expiry dates. The public key that you share with the world contains both the master key's public portion and the subkeys' public portions. The secret portions of your subkeys are what get loaded onto the YubiKey.

### Tails OS
The Amnesic Incognito Live System. A Debian-based Linux distribution designed to run from a USB drive with no persistent state. Tails routes all traffic through Tor when network is used. For this project, we use Tails primarily because it is amnesic (leaves no traces on the machine) and because it has GPG and relevant tools pre-installed. Tails is downloaded from https://tails.net.

### Touch Policy
A YubiKey feature that requires a physical press of the YubiKey's capacitive button before any cryptographic operation. This prevents malware from silently using the YubiKey in the background. In this project, mandatory touch policy is set on all three YubiKeys for all operations (sign, encrypt, authenticate).

### Web of Trust
A decentralized trust model in GPG where users certify each other's keys. If Alice certifies Bob's key, and you trust Alice, you can transitively trust Bob. The master key [C] in this project is used to participate in the web of trust by certifying other people's keys. This is distinct from your own subkeys, which are for your own sign/encrypt/authenticate operations.

---

## Troubleshooting

### YubiKey Not Detected by GPG

**Symptom**: `gpg --card-status` returns "No card" or "Card not present"

**Causes and fixes**:

1. **`pcscd` is not running** (most common on Tails):
   ```bash
   sudo systemctl start pcscd
   ```

2. **GPG agent has a stale connection**:
   ```bash
   gpg-connect-agent "scd kill" /bye
   gpg --card-status
   ```
   Or use the alias:
   ```bash
   gpg-restart
   ```

3. **YubiKey is not recognized as a smart card** (rare hardware issue):
   ```bash
   lsusb  # Check if the YubiKey appears at all
   ```
   If the YubiKey appears in `lsusb` but not in GPG, try unplugging and re-inserting.

4. **On macOS after sleep/wake**: The `gpg-agent` loses its connection to the YubiKey after the machine wakes. Run:
   ```bash
   gpg-restart
   ```

5. **Another process is holding the smart card** (e.g., a browser extension for PIV):
   ```bash
   sudo systemctl stop pcscd
   sudo systemctl start pcscd
   ```

### Wrong PIN / Blocked User PIN

**Symptom**: GPG reports "Bad PIN" or "PIN blocked"

The YubiKey allows 3 wrong User PIN attempts before blocking. The counter resets after a correct entry.

**If the User PIN is blocked** (3 consecutive wrong attempts), use the Admin PIN to unblock it:

```bash
gpg --card-edit
# At the gpg/card> prompt:
admin
passwd
# Choose option 4: "Unblock PIN"
# Enter Admin PIN when prompted
# Set a new User PIN
quit
```

**If you have forgotten the User PIN** but remember the Admin PIN, you can reset the User PIN using the method above.

**If both PINs are wrong/forgotten**:
```bash
ykman openpgp reset
```
This performs a full factory reset of the OpenPGP application on the YubiKey. **All keys loaded on the card are permanently destroyed.** After this, you will need to reload the subkeys from your LUKS backup or paper backup via script 07.

### SSH Authentication Failures

**Symptom**: `ssh user@server` fails with "Permission denied (publickey)"

Work through these checks in order:

1. **Confirm your SSH public key is in `~/.ssh/authorized_keys` on the server**:
   ```bash
   # Get the SSH public key from the YubiKey
   gpg --export-ssh-key YOUR_KEY_ID
   # Or use the alias:
   gpg-ssh-pubkey
   ```
   Copy this output and ensure it is in `~/.ssh/authorized_keys` on the server (one line per key).

2. **Confirm `SSH_AUTH_SOCK` points to gpg-agent**:
   ```bash
   echo $SSH_AUTH_SOCK
   # Should show something like: /Users/you/.gnupg/S.gpg-agent.ssh
   # NOT: /tmp/launch-xxx/Listeners (which is the macOS system ssh-agent)
   ```
   If it shows the macOS launcher path, your shell RC changes did not take effect. Run `source ~/.zshrc` or open a new terminal.

3. **Check that the agent sees the key**:
   ```bash
   ssh-add -l
   # Should list your GPG authentication key
   ```
   If it shows "The agent has no identities", the YubiKey might not be inserted, or gpg-agent needs a restart:
   ```bash
   gpg-restart
   ssh-add -l  # Try again
   ```

4. **Test with verbose SSH output**:
   ```bash
   ssh -vvv user@server 2>&1 | grep -A2 "Offering\|Authentications"
   ```

5. **On macOS, confirm the system SSH agent is not overriding**:
   ```bash
   launchctl unload -w /System/Library/LaunchAgents/com.openssh.ssh-agent.plist
   ```
   This permanently disables the macOS SSH agent for your user. The `gpg-ssh-env.sh` handles this via `SSH_AUTH_SOCK` override, but some macOS versions are aggressive about restoring the system agent.

### GPG Agent Issues

**Symptom**: Signing fails, or you see "gpg: signing failed: Timeout"

1. **Restart the agent**:
   ```bash
   gpg-restart
   ```

2. **Make sure the YubiKey is inserted and recognized**:
   ```bash
   gpg --card-status
   ```

3. **If GPG shows stubs but no card**, the agent still has the previous session's key stubs. This can happen if you switch between YubiKeys or if the agent started before the card was inserted:
   ```bash
   gpg-connect-agent "scd serialno" /bye
   ```

4. **On macOS, check that the correct `gpg` binary is used**:
   ```bash
   which gpg
   # Should be: /opt/homebrew/bin/gpg (Apple Silicon) or /usr/local/bin/gpg (Intel)
   # NOT: /usr/bin/gpg (the old macOS built-in, if any)
   ```

### Pinentry Issues on macOS

**Symptom**: No PIN dialog appears, or it appears in the background, or you see "pinentry failed" errors

1. **Confirm `pinentry-mac` is installed**:
   ```bash
   brew list | grep pinentry
   # Should show: pinentry-mac
   ```
   If not: `brew install pinentry-mac`

2. **Confirm `gpg-agent.conf` has the correct pinentry-program line uncommented**:
   ```bash
   cat ~/.gnupg/gpg-agent.conf | grep pinentry
   # Apple Silicon (M-series Mac):
   # pinentry-program /opt/homebrew/bin/pinentry-mac
   # Intel Mac:
   # pinentry-program /usr/local/bin/pinentry-mac
   ```

3. **After changing `gpg-agent.conf`, restart the agent**:
   ```bash
   gpg-restart
   ```

4. **If the dialog appears behind other windows**: This is a macOS focus issue with `pinentry-mac`. Try clicking the menu bar to bring it forward, or check if the dialog is on a different Space/desktop.

5. **If using SSH in a terminal and no dialog appears** (common after macOS sleep):
   ```bash
   gpg-connect-agent updatestartuptty /bye
   ```
   This tells the agent to use the current terminal for PIN prompts. The `gpg-ssh-env.sh` file runs this automatically in each new shell session, but a sleep/wake cycle can invalidate it.

### Git Signing Not Working

**Symptom**: `git commit` fails with a GPG error, or commits are not signed

1. **Confirm Git is configured to use GPG signing**:
   ```bash
   git config --global user.signingkey
   # Should show your key ID
   git config --global commit.gpgsign
   # Should show: true
   git config --global gpg.program
   # Should show the path to gpg (e.g., /opt/homebrew/bin/gpg)
   ```

2. **Test GPG signing directly**:
   ```bash
   echo "test" | gpg --clearsign
   ```
   If this works (prompts for touch, produces signed output), the issue is with Git's GPG configuration. If it fails, see the GPG Agent Issues section.

3. **Confirm the signing key ID matches what is in Git config**:
   ```bash
   gpg-list
   # Find the [S] key line and its ID
   ```

---

## Emergency Procedures

### Lost One YubiKey

If you lose one YubiKey (e.g., the daily carry):

1. **Immediately stop using that YubiKey.** If it was lost rather than stolen, your keys are still protected by the PIN. If you think it was stolen, proceed to the revocation procedure below.
2. **Retrieve your KEY-2 or KEY-3 backup** and use it instead. Your daily machine will work with any of the three YubiKeys — they all hold the same subkeys.
3. **Optionally, acquire a replacement YubiKey** and load the subkeys onto it using the LUKS backup: Boot Tails → run script 01 → run script 11 (restore) → run script 07 (load the new YubiKey) → run script 09 (cleanup).

### Potentially Compromised YubiKey (Stolen with Known PIN)

If your YubiKey was stolen AND you believe the attacker knows or can guess your PIN:

1. **Import your revocation certificate** on your daily machine:
   ```bash
   # Mount the LUKS backup USB (or retrieve from backup)
   gpg --import revocation-cert.asc
   ```
2. **Publish the revocation** to keyservers:
   ```bash
   gpg --send-keys YOUR_KEY_ID
   # Or for keys.openpgp.org:
   gpg --keyserver hkps://keys.openpgp.org --send-keys YOUR_KEY_ID
   ```
3. **Generate a new key set**: Boot Tails, run scripts 02 through 09 again with a completely new key.
4. **Notify anyone who uses your public key** that the old key is revoked and share the new one.

### Blocked User PIN (Cannot Access YubiKey)

If you entered the User PIN wrong 3 times and the card is now blocked:

1. Use the Admin PIN to unblock:
   ```bash
   gpg --card-edit
   admin
   passwd
   # Select option 4: "Unblock PIN"
   ```
2. If you do not remember the Admin PIN, and you have run out of Admin PIN attempts: the card is permanently locked. Run `ykman openpgp reset` to factory-reset the OpenPGP applet. Then restore your subkeys from the LUKS backup and load them again with script 07.

### Need to Revoke the Entire Key

If your key is compromised, expired beyond recovery, or you are abandoning it for any reason:

1. **If you have the revocation certificate**:
   ```bash
   gpg --import revocation-cert.asc
   gpg --keyserver hkps://keys.openpgp.org --send-keys YOUR_KEY_ID
   ```

2. **If you need to generate a new revocation certificate** (because you lost the one from the backup), you must have access to the master secret key. Boot Tails, restore from LUKS (script 11), then:
   ```bash
   gpg --output new-revocation-cert.asc --gen-revoke YOUR_KEY_ID
   ```

### All YubiKeys Lost or Destroyed

This is the worst case: all three YubiKeys are gone, but you still have LUKS backup or paper backup.

1. **Boot Tails** (air-gapped, as always).
2. **Run script 01** (`01-tails-setup.sh`).
3. **Run script 11** (`11-restore-from-luks.sh`) to import the master key from a LUKS USB. Or, if both LUKS USBs are also gone, follow the procedure in `docs/PAPER-RECOVERY.md` to reconstruct the master key from the paper printout.
4. **Acquire 3 new YubiKeys** and run script 07 three times to load the subkeys onto them.
5. **Run script 09** to clean up.

### Both LUKS USBs Lost, Paper Backup Available

If both encrypted USB backups are gone but the paper printout survives, follow the full procedure in `docs/PAPER-RECOVERY.md`. The summary:

1. Obtain your public key from a keyserver or anyone who has it.
2. Boot Tails.
3. Install `paperkey` (brief network connection required).
4. Carefully type in the hex data from the paper printout.
5. Run `paperkey --pubring public-key.gpg --secrets paperkey-data.txt --output recovered.gpg` to reconstruct the secret key.
6. Import and proceed.

### Forgot GPG Passphrase

This is not recoverable. The LUKS USB backups and the paperkey file are all encrypted/protected by your passphrase. Without the passphrase, the backup data is permanently inaccessible.

If this happens and you still have your YubiKeys, the subkeys continue to work — you can still sign, encrypt, and authenticate for the remaining lifetime of the subkeys. You simply cannot extend expiry, revoke, or generate new subkeys.

Plan: generate a new key pair from scratch when the subkeys expire.

---

## Future Maintenance -- Phase 4

### When to Run Phase 4

- **Subkey expiry approaching**: Your subkeys expire 1 year after generation. GPG will warn you when expiry is within 6 months. Extending expiry requires the master key.
- **Subkey compromised**: If you believe a subkey was exposed, revoke it and generate a new one.
- **New YubiKey to load**: If you acquire a replacement YubiKey, load it via script 07.
- **PIN change needed**: This can be done from the daily machine with `gpg --card-edit` — no Tails session required.

### Phase 4 Procedure

1. Boot Tails on the air-gapped machine.
2. Insert the Kit USB (with YubiGPG scripts).
3. Run `01-tails-setup.sh` to set up the session.
4. Insert a LUKS backup USB and run `11-restore-from-luks.sh` to import the master key.
5. Run `12-manage-expiry.sh` and follow the interactive prompts.
6. If new subkeys were generated, run `07-yubikey-transfer.sh` three times (once per YubiKey).
7. Export an updated public key and distribute it (re-upload to keyservers, GitHub, etc.).
8. Run `09-cleanup.sh` to wipe and shut down.

### After Extending Expiry

When you extend subkey expiry and export the updated public key, anyone who has your old public key will need to import the updated version to see the new expiry dates. Distribute via keyservers:

```bash
# On your daily machine after importing the updated public key
gpg --keyserver hkps://keys.openpgp.org --send-keys YOUR_KEY_ID
```

---

## What Can Be Shared Publicly

| Item | Public? | Notes |
|------|---------|-------|
| `public-key.asc` | YES | Upload to GitHub, keyservers (keys.openpgp.org), your website, email signature |
| Key fingerprint | YES | Include in email signature, social media bio, business cards, anywhere |
| SSH public key | YES | Add to all servers' `~/.ssh/authorized_keys`, GitHub SSH keys, etc. |
| `master-secret-key.asc` | NEVER | Anyone who obtains this + your passphrase can impersonate you completely |
| `subkeys-secret.asc` | NEVER | Allows sign, decrypt, and SSH authentication as you |
| `revocation-cert.asc` | NEVER | Can be used to destroy your key's reputation on keyservers. Guard it. |
| `PAPER-BACKUP-PRINT-ME.txt` | NEVER | Contains the secret key in hex (needs public key + passphrase to reconstruct, but still) |
| YubiKey User PIN | NEVER | Physical access protection |
| YubiKey Admin PIN | NEVER | Allows full card reconfiguration |
| GPG passphrase | NEVER | Protects all key backups. If disclosed, all backups are compromised. |

---

## Quick Reference Cheat Sheet

Once set up, these are the day-to-day commands you will use:

```bash
# Git signing (automatic when configured)
git commit -m "your message"

# Sign a file
gpg --armor --detach-sign file.tar.gz
# Produces: file.tar.gz.asc

# Verify a signature
gpg --verify file.tar.gz.asc file.tar.gz

# Encrypt a file to yourself
gpg --armor --recipient YOUR_KEY_ID --encrypt file.txt
# Produces: file.txt.asc

# Encrypt a file to someone else
gpg --armor --recipient THEIR_KEY_ID --encrypt file.txt

# Decrypt a file
gpg --decrypt file.txt.asc > file.txt

# SSH (just works after setup — no extra commands needed)
ssh user@server.example.com

# Get your SSH public key from the YubiKey
gpg --export-ssh-key YOUR_KEY_ID
# Or use the alias:
gpg-ssh-pubkey

# Check YubiKey status
gpg --card-status
# Or:
gpg-card

# Restart gpg-agent (fixes most "YubiKey not responding" issues)
gpg-restart

# List your secret keys
gpg --list-secret-keys --keyid-format 0xlong
# Or:
gpg-list

# Find your key fingerprint
gpg --fingerprint YOUR_EMAIL
```

---

## Contributing

Contributions are welcome. Please open an issue before submitting a pull request for significant changes, so the approach can be discussed.

Areas where contributions are especially useful:
- Testing on specific Linux distributions and reporting compatibility issues
- Improvements to error handling in the shell scripts
- Additional troubleshooting scenarios
- Documentation clarifications

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines, code style, and the pull request process.

---

## Inspiration and Credits

This project was inspired by and built upon the community knowledge in:

**[drduh/YubiKey-Guide](https://github.com/drduh/YubiKey-Guide)** — The de facto community reference for setting up GPG with a YubiKey. If you want to understand the underlying concepts in exhaustive detail, or if you prefer to run each command manually rather than using scripts, the YubiKey-Guide is the place to start. YubiGPG is an opinionated, scripted implementation of a subset of that guide, with specific choices made for the ed25519/cv25519 algorithm set, a three-YubiKey setup, and an air-gapped Tails workflow.

Additional references:
- [Tails OS Documentation](https://tails.net/doc/) — Official Tails documentation
- [GnuPG Manual](https://www.gnupg.org/documentation/manuals/gnupg/) — Official GPG reference
- [YubiKey 5 Technical Manual](https://docs.yubico.com/hardware/yubikey/yk-tech-manual/) — YubiKey firmware and hardware reference
- [paperkey](https://www.jabberwocky.com/software/paperkey/) — The tool used for the paper backup format

---

## License

Copyright 2026 YubiGPG Contributors

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at:

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
