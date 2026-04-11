#!/bin/bash
# =============================================================
# 02 — GENERATE MASTER KEY (Certify Only, No Expiry)
# =============================================================
# Creates an ed25519 master key with ONLY the Certify capability.
# All inputs are entered by you interactively.
#
# USAGE:
#   bash .../scripts/02-generate-master.sh
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
CYAN='\033[0;36m'   # Informational notes and examples
BOLD='\033[1m'      # Section headers
NC='\033[0m'        # Reset to default terminal color

# ============================================================
# === HEADER DISPLAY ===
# ============================================================
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         02 — GENERATE MASTER KEY                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  This creates your ed25519 master key with ONLY the Certify"
echo "  capability. It will never expire. Subkeys come in the next step."
echo ""

# ============================================================
# === STEP 1: COLLECT IDENTITY INFORMATION ===
# ============================================================
# GPG keys include a "User ID" (UID) that identifies the key owner.
# The UID is typically: Full Name (Optional Comment) <email@example.com>
#
# WHY this matters: your UID is baked into the key and becomes part
# of the signed certificate. It cannot be changed without generating
# a new key (though additional UIDs can be added later).
# Choose carefully — use the name and email you want associated with
# this key publicly.
# --- Collect identity ---
echo -e "${YELLOW}First, let me collect your identity details.${NC}"
echo ""

# Prompt for full name — this appears in the key's User ID
read -p "  Your full name (as it should appear on the key): " REAL_NAME
echo ""

# Prompt for primary email — used to look up the key and verify ownership
read -p "  Your primary email address: " EMAIL
echo ""

# An optional comment — commonly used for things like "work key" or
# "personal key" to distinguish between multiple keys for the same person.
# Leave blank if you only have one key for this identity.
read -p "  Add a comment to the key? (leave blank for none): " COMMENT
echo ""

# Preview the full UID and ask for confirmation before proceeding.
# This is the exact format GPG will use, so mistakes are easy to spot here.
echo -e "${CYAN}  Identity: $REAL_NAME ($COMMENT) <$EMAIL>${NC}"
read -p "  Is this correct? (y/n): " ID_OK
if [ "$ID_OK" != "y" ]; then
    echo "  Please re-run this script with the correct details."
    exit 1
fi

# ============================================================
# === STEP 2: INTERACTIVE GPG KEY GENERATION ===
# ============================================================
# We now launch GPG's interactive key generation wizard. This is a
# fully manual process — GPG prompts you for each decision, and you
# type your responses directly.
#
# WHY we use --expert: the standard key generation menu hides many
# algorithm and capability options. --expert exposes them all,
# including option 11 (ECC with custom capabilities) which is the
# only way to create a Certify-only master key.
#
# WHY --full-gen-key instead of --gen-key: --gen-key uses "quick"
# mode which applies defaults without asking. --full-gen-key gives
# us the full interactive menu with all options visible.
#
# WHAT "Certify only" means and WHY:
# GPG keys can have four capabilities: Sign (S), Encrypt (E),
# Authenticate (A), and Certify (C). Certify is special — only the
# master key can have it, and it is the one capability that lets you
# vouch for subkeys and other people's keys (create signatures on
# key material itself). By stripping Sign from the master key and
# keeping ONLY Certify, we ensure:
#   1. The master key is NEVER used for day-to-day operations
#   2. If a subkey is compromised, you revoke that subkey with the
#      master key (still safely offline) without starting over
#   3. You can let subkeys expire and replace them without ever
#      touching the master key
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  GPG will now open in interactive mode.              ${NC}"
echo -e "${YELLOW}  Follow these steps EXACTLY:                        ${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
echo ""

# --- GPG Interactive Step 1: Select key type ---
# GPG will show a numbered menu of key types. Option 11 is
# "ECC (set your own capabilities)" which lets us manually choose
# exactly which capabilities (Sign, Encrypt, Certify, Authenticate)
# this key will have. This is the only option that gives full control.
echo -e "  ${BOLD}1.${NC} Select:  ${CYAN}(11) ECC (set your own capabilities)${NC}"
echo ""

# --- GPG Interactive Step 2: Strip the Sign capability ---
# After selecting option 11, GPG defaults to allowing both Sign AND
# Certify on the master key. We want ONLY Certify.
# Typing "S" toggles the Sign capability OFF. After pressing Enter,
# the display should update to show: "Current allowed actions: Certify"
# WHY remove Sign from the master key: it forces all signing to go
# through the signing SUBKEY. This keeps the master key truly offline —
# even for signing operations you do every day.
echo -e "  ${BOLD}2.${NC} You'll see 'Current allowed actions: Sign Certify'"
echo -e "     Type ${CYAN}S${NC} and press Enter → turns OFF Sign"
echo -e "     Now it should show: 'Current allowed actions: Certify'"
echo ""

# --- GPG Interactive Step 3: Finish capability selection ---
# Typing "Q" tells GPG you are done adjusting capabilities and
# to proceed to the next step (curve selection).
echo -e "  ${BOLD}3.${NC} Type ${CYAN}Q${NC} and press Enter → finishes capability selection"
echo ""

# --- GPG Interactive Step 4: Choose the elliptic curve ---
# Option 1 is Curve 25519 (also called "Ed25519" for signing keys).
# WHY Curve 25519: it is a modern, well-audited elliptic curve that
# provides excellent security (equivalent to ~3000-bit RSA) with
# small key sizes and fast operations. It is the current gold standard
# for new GPG key generation.
echo -e "  ${BOLD}4.${NC} Select curve: ${CYAN}(1) Curve 25519${NC}"
echo ""

# --- GPG Interactive Step 5: Set expiry to never ---
# The master key should NOT expire because:
#   1. If it expires while your subkeys are still in use, you cannot
#      use the master key to extend them without starting over
#   2. The master key is kept offline and never used day-to-day, so
#      "rotation" is achieved by letting SUBKEYS expire, not the master
#   3. If the master key is lost or compromised, you use the revocation
#      certificate (generated in script 04) to invalidate the entire key
# Entering "0" means "does not expire". GPG asks for confirmation — type "y".
echo -e "  ${BOLD}5.${NC} Expiry: ${CYAN}0${NC} (does not expire)"
echo -e "     Confirm with: ${CYAN}y${NC}"
echo ""

# --- GPG Interactive Step 6: Enter your identity ---
# GPG will prompt for Real Name, Email, and Comment separately.
# Enter the exact values you provided to this script above.
echo -e "  ${BOLD}6.${NC} Enter your name, email, and comment when prompted"
echo -e "     (they should match what you entered above)"
echo ""

# --- GPG Interactive Step 7: Set the master key passphrase ---
# IMPORTANT: This passphrase is the LAST LINE OF DEFENSE for your
# master key. Even if someone steals the key file, they cannot use
# it without this passphrase. Choose wisely.
#
# RECOMMENDATION: Use at least 6 diceware words (e.g., "correct horse
# battery staple fire soup"). This gives ~77 bits of entropy — far
# more than any typical password. Write the passphrase on paper and
# store it separately from your USB backups (so a thief who finds
# your USB still cannot use the key).
#
# WARNING: If you forget this passphrase AND lose your paper copy,
# your master key is permanently inaccessible. There is no recovery.
echo -e "  ${BOLD}7.${NC} ${RED}Set a STRONG passphrase — 6+ diceware words${NC}"
echo -e "     ${RED}Write it on paper. Store separately from key backups.${NC}"
echo ""
read -p "  Press Enter to launch GPG..."
echo ""

# ============================================================
# === LAUNCH GPG KEY GENERATION ===
# ============================================================
# This is the actual command that opens the interactive GPG wizard.
# Everything the user does inside this session is handled by GPG
# directly — this script just waits for GPG to exit.
#
# After GPG finishes, the new master key is stored in ~/.gnupg/
# and will appear in `gpg --list-keys` output.
gpg --expert --full-gen-key

echo ""
echo -e "${GREEN}  ✓ Master key generation complete.${NC}"
echo ""

# ============================================================
# === DISPLAY GENERATED KEYS ===
# ============================================================
# Show the keyring contents so the user can identify the new key.
# --keyid-format 0xlong shows the full 16-character hex key ID with
# a "0x" prefix, which is the most unambiguous format for copying.
# --- Show what was created ---
echo -e "${YELLOW}Here are your keys:${NC}"
echo ""
gpg --list-keys --keyid-format 0xlong
echo ""

# ============================================================
# === STEP 3: RECORD THE KEY ID ===
# ============================================================
# The key ID is a unique identifier for this specific key. Every
# subsequent script in this workflow needs it to know which key to
# operate on. We ask the user to read it from the GPG output above
# and enter it here so we can save it to a file for later use.
#
# WHERE to find it: look for the line starting with "pub ed25519/".
# The key ID is the long hex string that follows the slash character.
# Example line:  pub   ed25519/0xABCDEF1234567890  2024-01-01 [C]
#                                 ^^^^^^^^^^^^^^^^  ← this is the key ID
# --- Get key ID from user ---
echo -e "${CYAN}  Look at the line starting with 'pub ed25519/'${NC}"
echo -e "${CYAN}  The key ID is the hex string after the slash.${NC}"
echo -e "${CYAN}  Example: ed25519/0xABCDEF1234567890${NC}"
echo ""
read -p "  Enter your master key ID (e.g., 0xABCDEF1234567890): " KEYID
echo ""

# ============================================================
# === VERIFY KEY ID IS VALID ===
# ============================================================
# Confirm that the key ID the user entered actually exists in the
# keyring. If it doesn't, they may have made a typo — abort early
# rather than letting a bad key ID propagate to later scripts.
# --- Verify ---
if ! gpg --list-keys "$KEYID" &>/dev/null; then
    echo -e "${RED}  Key $KEYID not found. Check the ID and try again.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ Confirmed key: $KEYID${NC}"
echo ""

# ============================================================
# === SAVE KEY ID FOR SUBSEQUENT SCRIPTS ===
# ============================================================
# Write the verified key ID to a file in our working directory.
# Scripts 03, 04, 05, and 06 all read from this file to pre-fill
# the key ID prompt, reducing the chance of a typo in later steps.
# The file is stored in /tmp (which is wiped when Tails reboots).
# Save key ID to a temp file so subsequent scripts can offer it as default
echo "$KEYID" > /tmp/gpg-export/keyid.txt

# ============================================================
# === SUMMARY ===
# ============================================================
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  MASTER KEY CREATED                                    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Key ID:   $KEYID"
echo "  Identity: $REAL_NAME <$EMAIL>"
echo "  Expiry:   Never"
echo "  Caps:     [C] Certify only"
echo ""
echo "  Next: bash .../scripts/03-generate-subkeys.sh"
echo ""
