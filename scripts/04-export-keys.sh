#!/bin/bash
# =============================================================
# 04 — EXPORT ALL KEY MATERIAL
# =============================================================
# Exports master secret key, subkeys, public key, revocation
# certificate, and a full ~/.gnupg backup.
#
# USAGE:
#   bash .../scripts/04-export-keys.sh
# =============================================================

# ============================================================
# === SHELL OPTIONS ===
# ============================================================
# -e  : abort immediately on any command failure
# -u  : treat unset variables as errors
# -o pipefail : fail a pipeline if any stage in it fails
set -euo pipefail

# ============================================================
# === TERMINAL COLOR CODES ===
# ============================================================
RED='\033[0;31m'    # Errors, critical warnings
GREEN='\033[0;32m'  # Success confirmations
YELLOW='\033[1;33m' # Step headings and prompts
CYAN='\033[0;36m'   # Informational notes
BOLD='\033[1m'      # Section headers
NC='\033[0m'        # Reset to default terminal color

# ============================================================
# === EXPORT DIRECTORY SETUP ===
# ============================================================
# All key files land in /tmp/gpg-export/ — the same directory used
# throughout this entire workflow. It was created by script 01.
# We re-create it here defensively in case this script is run
# independently (e.g., to re-export after a change).
#
# IMPORTANT: /tmp is an in-memory filesystem in Tails. Nothing
# written here persists across reboots. This is intentional —
# it means sensitive key material never touches disk unless you
# explicitly copy it to an encrypted USB in script 05.
EXPORT_DIR="/tmp/gpg-export"
mkdir -p "$EXPORT_DIR"

# ============================================================
# === HEADER DISPLAY ===
# ============================================================
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         04 — EXPORT KEY MATERIAL                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === STEP 1: IDENTIFY THE KEY TO EXPORT ===
# ============================================================
# Read the previously saved key ID to pre-fill the prompt.
# The user can override it by typing a different value.
# --- Get key ID ---
DEFAULT_KEYID=""
if [ -f "$EXPORT_DIR/keyid.txt" ]; then
    DEFAULT_KEYID=$(cat "$EXPORT_DIR/keyid.txt")
fi

# If we have a saved default, use it. Otherwise show the full key list
# so the user can find the right key ID visually.
if [ -n "$DEFAULT_KEYID" ]; then
    read -p "  Key ID [$DEFAULT_KEYID]: " KEYID
    KEYID=${KEYID:-$DEFAULT_KEYID}  # Accept default if user presses Enter
else
    gpg --list-keys --keyid-format 0xlong 2>/dev/null | head -20
    echo ""
    read -p "  Enter your key ID: " KEYID
fi

# Verify the key has secret key material present before trying to export.
# A key without secret material (e.g., public-only stubs) would produce
# empty export files, which would silently corrupt the backup.
if ! gpg --list-secret-keys "$KEYID" &>/dev/null; then
    echo -e "${RED}  Secret key $KEYID not found.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Key found: $KEYID${NC}"
echo ""

# ============================================================
# === EXPORT 1/5: FULL SECRET KEY (MASTER + SUBKEYS) ===
# ============================================================
# This is your most sensitive backup file. It contains the master
# secret key AND all subkeys, all encrypted with your GPG passphrase.
#
# WHY export this: if you ever need to start over (new YubiKey,
# lost/broken YubiKey, need to extend subkey expiry), you import
# this file on an air-gapped Tails machine and work from there.
#
# --armor : encodes binary key data as ASCII text (Base64-like).
#           This makes the file human-readable and safe to copy into
#           emails or documents without encoding corruption.
# --export-secret-keys : exports the full secret key including master.
#
# WARNING: This file must NEVER be transferred to a networked
# machine in unencrypted form. It should only ever exist on:
#   1. This Tails machine (in-memory /tmp, gone at reboot)
#   2. An encrypted LUKS backup USB (created in script 05)
# --- Export master + subkeys secret ---
echo -e "${YELLOW}[1/5] Exporting full secret key (master + subkeys)...${NC}"
gpg --armor --export-secret-keys "$KEYID" > "$EXPORT_DIR/master-secret-key.asc"
echo -e "${GREEN}  ✓ $EXPORT_DIR/master-secret-key.asc${NC}"
echo ""

# ============================================================
# === EXPORT 2/5: SUBKEYS ONLY (NO MASTER) ===
# ============================================================
# This file contains ONLY the three subkeys (Sign, Encrypt,
# Authenticate), without the master secret key.
#
# WHY export subkeys separately: this is the file you would import
# on a day-to-day computer (not an air-gapped machine). It gives the
# computer the ability to use your subkeys while the master key stays
# safely offline. Even if the computer is compromised, the attacker
# cannot forge signatures from your master key or certify new subkeys.
#
# --export-secret-subkeys : exports only subkeys, stubs out the master.
#                           The master key slot will appear but contain
#                           no usable secret material (">" marker in GPG).
# --- Export subkeys only ---
echo -e "${YELLOW}[2/5] Exporting subkeys only...${NC}"
gpg --armor --export-secret-subkeys "$KEYID" > "$EXPORT_DIR/subkeys-secret.asc"
echo -e "${GREEN}  ✓ $EXPORT_DIR/subkeys-secret.asc${NC}"
echo ""

# ============================================================
# === EXPORT 3/5: PUBLIC KEY ===
# ============================================================
# The public key is the part you share with everyone. It lets others:
#   - Send you encrypted email
#   - Verify your signatures
#   - Look up your key on keyservers
#
# This file is SAFE TO SHARE. It contains no secret material.
# You will upload this to keyservers and/or share it on your website
# after completing the full workflow.
#
# --export : exports only the public key portions. No secret key data.
# --- Export public key ---
echo -e "${YELLOW}[3/5] Exporting public key...${NC}"
gpg --armor --export "$KEYID" > "$EXPORT_DIR/public-key.asc"
echo -e "${GREEN}  ✓ $EXPORT_DIR/public-key.asc${NC}"
echo ""

# ============================================================
# === EXPORT 4/5: REVOCATION CERTIFICATE ===
# ============================================================
# A revocation certificate is a pre-signed statement that says
# "this key is no longer valid." You generate it NOW while the
# master key is available, and store it safely for use if needed.
#
# WHY generate it now:
#   - If you ever lose access to your master key (dead YubiKey + lost
#     backups, forgotten passphrase, etc.), you cannot generate a
#     revocation certificate without the master key.
#   - Having one pre-generated means you can always invalidate the key
#     even if the worst happens.
#
# WARNING: This certificate is DANGEROUS in the wrong hands.
# Anyone who obtains it can revoke your key, making it appear invalid
# to everyone who has your public key. Store it separately from the
# rest of your key material (ideally printed on paper or in a separate
# encrypted location).
#
# GPG will prompt you for:
#   - Reason for revocation (0 = no reason specified is fine as a default;
#     use 1 if you know the key has been compromised)
#   - An optional description (can be left blank)
#   - Your passphrase to sign the certificate
#
# --gen-revoke : generates a revocation certificate for the given key.
#                The output is a signed ASCII-armored block ready for import.
# --- Revocation certificate ---
echo -e "${YELLOW}[4/5] Generating revocation certificate...${NC}"
echo ""
echo "  GPG will ask for a reason. Suggestions:"
echo "    (0) No reason specified     ← good default"
echo "    (1) Key has been compromised"
echo ""
read -p "  Press Enter to generate revocation certificate..."
gpg --gen-revoke "$KEYID" > "$EXPORT_DIR/revocation-cert.asc"
echo -e "${GREEN}  ✓ $EXPORT_DIR/revocation-cert.asc${NC}"
echo ""

# ============================================================
# === EXPORT 5/5: FULL GNUPG DIRECTORY BACKUP ===
# ============================================================
# This copies the entire ~/.gnupg directory (GPG's home directory)
# as a snapshot backup. It includes:
#   - The keyring files (pubring.kbx, private-keys-v1.d/)
#   - The trust database (trustdb.gpg)
#   - Configuration files (gpg.conf, gpg-agent.conf)
#
# WHY back up the full directory: the individual .asc exports above
# cover keys, but the trustdb (which records your trust assignments
# and certifications of others' keys) is not included in those exports.
# The full directory backup preserves everything.
#
# `-r` flag : recursive copy (copies the directory and all its contents)
#
# WARNING: The private-keys-v1.d/ subdirectory within gnupg-full-backup
# contains your secret key material in GnuPG's native binary format,
# protected only by your GPG passphrase. Treat this backup with the
# same care as master-secret-key.asc.
# --- Full gnupg backup ---
echo -e "${YELLOW}[5/5] Backing up entire ~/.gnupg directory...${NC}"
cp -r ~/.gnupg "$EXPORT_DIR/gnupg-full-backup"
echo -e "${GREEN}  ✓ $EXPORT_DIR/gnupg-full-backup/${NC}"
echo ""

# ============================================================
# === SAVE KEY ID FOR SUBSEQUENT SCRIPTS ===
# ============================================================
# Write the key ID to disk so scripts 05 and 06 can read it.
# Save key ID
echo "$KEYID" > "$EXPORT_DIR/keyid.txt"

# ============================================================
# === SUMMARY AND SECURITY REMINDER ===
# ============================================================
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  EXPORT COMPLETE                                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  All exported to: $EXPORT_DIR"
echo ""

# List the exported files with human-readable sizes so the user can
# visually confirm that each file was created and has a non-zero size.
# A zero-byte export file would indicate something went wrong.
ls -lh "$EXPORT_DIR"/*.asc "$EXPORT_DIR"/keyid.txt 2>/dev/null
echo ""

# === WARNING: MASTER SECRET KEY IN MEMORY ===
# The files listed above contain the full cryptographic secret — anyone
# who can read these files AND knows your passphrase can impersonate you
# completely. They must never leave the air-gapped environment except
# onto the encrypted LUKS USB drives created in the next step.
echo -e "${RED}  These files contain your MASTER SECRET KEY.${NC}"
echo -e "${RED}  They must NEVER leave the air-gapped environment${NC}"
echo -e "${RED}  except onto encrypted backup media.${NC}"
echo ""
echo "  Next: bash .../scripts/05-backup-to-luks.sh   (run TWICE)"
echo ""
