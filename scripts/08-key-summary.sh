#!/bin/bash
# =============================================================
# 08 — KEY SUMMARY & VERIFICATION
# =============================================================
# Displays a full summary of your key infrastructure BEFORE
# cleanup. Shows what each key/file is, what can be shared
# publicly, what must stay secret, and how others can verify
# your fingerprint.
#
# RUN THIS BEFORE CLEANUP to review everything.
#
# USAGE:
#   bash .../scripts/08-key-summary.sh
# =============================================================

# Exit immediately on error, treat unset variables as errors,
# and propagate pipeline failures.
set -euo pipefail

# ============================================================
# ANSI COLOR CODES
# ============================================================
# Used throughout for terminal output. NC resets color after
# each colored string.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Location of all key exports from the Tails session (scripts 01–06).
EXPORT_DIR="/tmp/gpg-export"

clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         08 — KEY SUMMARY & VERIFICATION                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === DETERMINE THE KEY ID TO SUMMARIZE ===
# ============================================================
# Prefer the key ID that was recorded to keyid.txt during key
# generation (script 02). If that file doesn't exist, ask the
# user to enter the ID manually.
#
# After YubiKey transfers (script 07), the local keyring may
# contain only stubs (not the full key). We handle that below
# by re-importing the public key for display purposes.
# ============================================================

# --- Get key ID ---
DEFAULT_KEYID=""
if [ -f "$EXPORT_DIR/keyid.txt" ]; then
    DEFAULT_KEYID=$(cat "$EXPORT_DIR/keyid.txt")
fi

if [ -n "$DEFAULT_KEYID" ]; then
    # Offer the saved ID as the default; user can override by typing a different ID.
    read -p "  Key ID [$DEFAULT_KEYID]: " KEYID
    KEYID=${KEYID:-$DEFAULT_KEYID}   # Use default if user presses Enter with no input.
else
    read -p "  Enter your key ID: " KEYID
fi

# ============================================================
# === ENSURE THE KEY IS IN THE LOCAL KEYRING ===
# ============================================================
# After keytocard (script 07), the secret key becomes a stub.
# The PUBLIC key may or may not still be present. For display
# purposes this script only needs the public key — importing
# public-key.asc is completely safe and non-destructive.
# ============================================================

# Try to get key info (may fail if keyring was cleared after yubikey transfer)
KEY_EXISTS=false
if gpg --list-keys "$KEYID" &>/dev/null; then
    KEY_EXISTS=true
elif [ -f "$EXPORT_DIR/public-key.asc" ]; then
    echo ""
    echo "  Key not in keyring (normal after YubiKey transfers)."
    echo "  Importing public key from backup for display..."
    # --import with a public key is always safe: it adds only public
    # material to the keyring. No private key data is involved.
    gpg --import "$EXPORT_DIR/public-key.asc" 2>/dev/null || true
    if gpg --list-keys "$KEYID" &>/dev/null; then
        KEY_EXISTS=true
    fi
fi

if [ "$KEY_EXISTS" = false ]; then
    echo -e "${RED}  Cannot find key $KEYID anywhere.${NC}"
    exit 1
fi

echo ""

# =============================================================
# SECTION 1: YOUR KEY STRUCTURE
# =============================================================
# Shows the full key listing: master key, all subkeys, user IDs,
# capabilities ([S]ign, [E]ncrypt, [A]uthenticate, [C]ertify),
# and expiry dates. Use this to confirm the key was created
# correctly before wiping the Tails session.
# =============================================================
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  1. YOUR KEY STRUCTURE                                ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
# --keyid-format 0xlong shows full 16-character hex key IDs,
# which are needed for referencing keys in gpg commands.
gpg --list-keys --keyid-format 0xlong "$KEYID"
echo ""

# =============================================================
# SECTION 2: YOUR FINGERPRINT
# =============================================================
# The fingerprint is a 40-character hex hash that uniquely
# identifies your key. It is derived entirely from public key
# material — sharing it reveals nothing sensitive.
#
# IMPORTANT: Write this down NOW. You will use it to verify
# your key's identity in the future, and others will use it to
# confirm they have imported the correct key (not a fake one).
# =============================================================
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  2. YOUR FINGERPRINT                                  ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
gpg --fingerprint "$KEYID"
echo ""
echo -e "${CYAN}  This fingerprint uniquely identifies your key.${NC}"
echo -e "${CYAN}  It is SAFE to share publicly — it's derived from${NC}"
echo -e "${CYAN}  your public key and reveals nothing secret.${NC}"
echo ""
echo -e "${YELLOW}  WRITE THIS DOWN or take a photo of this screen.${NC}"
echo -e "${YELLOW}  You will need it to verify your key later.${NC}"
echo ""
read -p "  Press Enter to continue..."

# =============================================================
# SECTION 3: WHAT IS WHAT — EACH FILE EXPLAINED
# =============================================================
# This section gives the user a clear mental model of every file
# produced during the Tails session: what it contains, who can
# see it, and what would happen if it fell into the wrong hands.
#
# Three categories:
#   PUBLIC  — safe to share widely; contains no private material.
#   SECRET  — private key material; must stay encrypted and offline.
#   DANGEROUS — public material that can permanently harm your key.
# =============================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  3. YOUR FILES — WHAT IS WHAT                         ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}PUBLIC — SAFE TO SHARE AND PUBLISH:${NC}"
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │ public-key.asc                                          │"
echo "  │   Your public key. Give this to EVERYONE.               │"
echo "  │   Upload to: GitHub, keys.openpgp.org, your website.    │"
echo "  │   Others use it to: encrypt files to you, verify your   │"
echo "  │   signatures, and confirm your identity.                │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ Your fingerprint (shown above)                          │"
echo "  │   Share freely. Put in email signatures, social bios,   │"
echo "  │   business cards, Twitter/X bio, etc.                   │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ Your SSH public key (derived from [A] subkey)           │"
echo "  │   Safe to share. Add to ~/.ssh/authorized_keys on       │"
echo "  │   servers, GitHub SSH keys, etc.                        │"
echo "  │   Get it with: gpg --export-ssh-key $KEYID              │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo -e "  ${RED}SECRET — NEVER SHARE, NEVER PUBLISH:${NC}"
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │ master-secret-key.asc                                   │"
echo "  │   THE most sensitive file. Contains your master private  │"
echo "  │   key + all subkey private keys. Anyone with this file   │"
echo "  │   AND your passphrase can impersonate you completely.    │"
echo "  │   Lives ONLY on encrypted LUKS backup USBs.             │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ subkeys-secret.asc                                      │"
echo "  │   Subkey private keys without the master. Less damaging  │"
echo "  │   than the master if leaked, but still allows signing,  │"
echo "  │   decrypting, and SSH as you. Keep secret.              │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ gnupg-full-backup/                                      │"
echo "  │   Complete ~/.gnupg directory. Contains everything      │"
echo "  │   including trust database and private keys. Keep       │"
echo "  │   secret. Used for full restore if needed.              │"
echo "  ├──────────────────────────────────────────────────────────┤"
echo "  │ PAPER-BACKUP-PRINT-ME.txt                               │"
echo "  │   Paper backup of your secret key in hex format.        │"
echo "  │   Anyone who has this + your public key + passphrase    │"
echo "  │   can reconstruct your master key. Store printed copy   │"
echo "  │   in a fireproof safe. Shred digital copy after print.  │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
echo -e "  ${YELLOW}DANGEROUS — HANDLE WITH EXTREME CARE:${NC}"
echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │ revocation-cert.asc                                     │"
echo "  │   Importing this into GPG and publishing it PERMANENTLY │"
echo "  │   kills your key. No undo. Anyone who gets this file    │"
echo "  │   can destroy your key's reputation. Store alongside    │"
echo "  │   your secret key backups but know what it does.        │"
echo "  │   Use ONLY if your key is compromised beyond recovery.  │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
read -p "  Press Enter to continue..."

# =============================================================
# SECTION 4: HOW OTHERS VERIFY YOUR KEY
# =============================================================
# A public key alone cannot prove identity — anyone can create
# a key with your name and email. The fingerprint, verified via
# a SEPARATE trusted channel, is what establishes authenticity.
#
# This section explains that process to the user so they can
# guide their contacts through it.
# =============================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  4. HOW OTHERS VERIFY YOUR FINGERPRINT                ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  After someone imports your public key, they verify it by"
echo "  comparing your fingerprint through a SEPARATE channel."
echo ""
echo "  VERIFICATION STEPS FOR OTHERS:"
echo ""
echo "    1. They import your public key:"
echo "       gpg --import public-key.asc"
echo "       or: gpg --keyserver hkps://keys.openpgp.org --recv-keys $KEYID"
echo ""
echo "    2. They check the fingerprint:"
echo "       gpg --fingerprint $KEYID"
echo ""
echo "    3. They compare against your published fingerprint via a"
echo "       DIFFERENT channel than the one they got the key from."
echo ""
echo "       Good verification channels:"
echo "         • In person (read fingerprint aloud to each other)"
echo "         • Video call (show fingerprint on screen)"
echo "         • Your personal website (HTTPS)"
echo "         • Social media bio (Twitter/X, Mastodon, GitHub)"
echo "         • Business card"
echo "         • Keybase.io proof"
echo ""
echo "    4. If fingerprints match, they sign your key (optional):"
echo "       gpg --sign-key $KEYID"
echo "       This creates a 'web of trust' endorsement."
echo ""
echo "  WHY THIS MATTERS:"
echo "    Without verification, someone could create a fake key"
echo "    with your name and email. The fingerprint is the ONLY"
echo "    way to confirm you're talking to the right key."
echo ""
read -p "  Press Enter to continue..."

# =============================================================
# SECTION 5: YOUR YUBIKEY DEPLOYMENT
# =============================================================
# Summarizes the three physical YubiKeys, their firmware versions,
# and intended storage locations. Each YubiKey is a fully
# independent backup — any one of them is sufficient for daily use.
# =============================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  5. YOUR YUBIKEY DEPLOYMENT                           ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ┌─────────────┬────────────────────────────────────────┐"
echo "  │ YubiKey     │ Location                               │"
echo "  ├─────────────┼────────────────────────────────────────┤"
echo "  │ KEY-1       │ Keychain / daily carry                 │"
echo "  │ KEY-2       │ Home safe                              │"
echo "  │ KEY-3       │ Offsite location (bank / trusted person)│"
echo "  └─────────────┴────────────────────────────────────────┘"
echo ""
echo "  Each YubiKey contains ALL 3 subkeys: [S] [E] [A]"
echo "  Any single YubiKey is sufficient for daily operations."
echo "  The other two are backups in case of loss/damage."
echo ""
echo "  Touch policy is enabled on all — the key blinks and"
echo "  requires a physical tap for every crypto operation."
echo ""
echo ""

# =============================================================
# SECTION 6: BACKUP LOCATIONS CHECKLIST
# =============================================================
# Prompts the user to confirm and record where each physical
# backup is stored. This creates a mental (and logged) record
# of the backup plan before everything is wiped in script 09.
#
# SECURITY RULE: Never store the passphrase with the key material.
# If someone finds your LUKS USB, they still need the passphrase.
# If someone reads your passphrase, they still need the USB.
# =============================================================
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  6. BACKUP LOCATIONS CHECKLIST                        ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Let me confirm your backup plan:"
echo ""

read -p "  Where is LUKS backup USB #1 stored? " LOC1
read -p "  Where is LUKS backup USB #2 stored? " LOC2
read -p "  Where will the paper backup be stored? " LOC3
echo ""

echo "  Your backup plan:"
echo "    LUKS USB #1:    $LOC1"
echo "    LUKS USB #2:    $LOC2"
echo "    Paper backup:   $LOC3"
echo "    Passphrase:     Your memory (+ sealed envelope at separate location)"
echo ""

# WARNING: The passphrase and key material must NEVER be stored together.
# If they are co-located, a single physical breach compromises everything.
echo -e "${YELLOW}  Remember: NEVER store the passphrase with the key material.${NC}"
echo ""
read -p "  Press Enter to continue..."

# =============================================================
# SECTION 7: NEXT STEPS ON THE DAILY MACHINE
# =============================================================
# After the Tails session is wiped (script 09), the user's daily
# machine still needs to be configured to use the YubiKey.
# Script 10 automates these steps for both macOS and Linux.
# =============================================================
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  7. NEXT STEPS ON YOUR DAILY MACHINE                  ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  After shutting down Tails, on your Mac or Linux machine:"
echo ""
echo "    1. Import public key:  gpg --import public-key.asc"
echo "    2. Install configs:    copy gpg-agent.conf, gpg-ssh-env.sh"
echo "    3. Set up Git signing: run git-gpg-setup.sh"
echo "    4. Upload public key:  GitHub → Settings → SSH and GPG keys"
echo "    5. Upload to keyserver: gpg --keyserver hkps://keys.openpgp.org --send-keys $KEYID"
echo ""
echo "  The included script 10-daily-machine-setup.sh automates"
echo "  steps 1–3 for both macOS and Linux."
echo ""
echo ""

# =============================================================
# FINAL — SHOW FINGERPRINT ONE MORE TIME
# =============================================================
# The fingerprint is displayed a second time at the end so the
# user can photograph or write it down before closing this script.
# grep -A1 "fingerprint" extracts just the label line and the
# hex fingerprint line from gpg --fingerprint output.
# =============================================================
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  SUMMARY COMPLETE                                      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  You now have a clear picture of your entire GPG setup."
echo ""
echo "  Save your fingerprint now (photo, write it down, etc.):"
echo ""
gpg --fingerprint "$KEYID" 2>/dev/null | grep -A1 "fingerprint"
echo ""
echo "  Next: bash .../scripts/09-cleanup.sh"
echo ""
