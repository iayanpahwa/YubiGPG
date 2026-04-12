#!/bin/bash
# =============================================================
# 03 — GENERATE SUBKEYS (Sign, Encrypt, Authenticate)
# =============================================================
# Adds three subkeys to your master key. Each with user-chosen
# expiry. All inputs via human interaction.
#
# USAGE:
#   bash .../scripts/03-generate-subkeys.sh
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
echo -e "${BOLD}║         03 — GENERATE SUBKEYS                          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === STEP 1: IDENTIFY THE MASTER KEY ===
# ============================================================
# All three subkeys must be attached to the master key created in
# script 02. We read the previously saved key ID from disk so the
# user doesn't have to retype it, but they can override it by
# entering a different value at the prompt.

# --- Get key ID ---
# Attempt to read the key ID that was saved by script 02.
# If the file doesn't exist (e.g., the user is running this script
# independently), DEFAULT_KEYID will be empty and we'll ask for it.
DEFAULT_KEYID=""
if [ -f /tmp/gpg-export/keyid.txt ]; then
    DEFAULT_KEYID=$(cat /tmp/gpg-export/keyid.txt)
fi

echo -e "${YELLOW}Which master key should the subkeys be attached to?${NC}"
echo ""

# Show existing keys so the user can visually confirm which one to use.
# `head -20` limits output in case there are many keys in the keyring.
gpg --list-keys --keyid-format 0xlong 2>/dev/null | head -20
echo ""

# If we have a saved key ID, show it as the default in the prompt.
# Pressing Enter without typing accepts the default value.
# This reduces the chance of a transcription error.
if [ -n "$DEFAULT_KEYID" ]; then
    read -p "  Enter master key ID [$DEFAULT_KEYID]: " KEYID
    KEYID=${KEYID:-$DEFAULT_KEYID}  # Use default if user pressed Enter without typing
else
    read -p "  Enter master key ID (e.g., 0xABCDEF1234567890): " KEYID
fi

# Validate the key exists before proceeding — catch typos early.
if ! gpg --list-keys "$KEYID" &>/dev/null; then
    echo -e "${RED}  Key $KEYID not found.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Using key: $KEYID${NC}"
echo ""

# ============================================================
# === STEP 2: SET SUBKEY EXPIRY ===
# ============================================================
# Unlike the master key (which has no expiry), subkeys SHOULD expire.
# WHY expiring subkeys are better:
#   - If a subkey is compromised and you don't notice immediately,
#     the attacker's window of abuse is bounded by the expiry date.
#   - Expiry forces periodic key hygiene: when renewing, you can
#     review who has your public key and re-distribute the updated one.
#   - It signals to others that the key is actively maintained.
#
# RECOMMENDATION: 1 year enforces annual key hygiene. Short enough to
# bound exposure if a subkey is compromised, long enough to be practical.
# You can always extend the expiry BEFORE it lapses using the master key.
# --- Get expiry ---
echo -e "${YELLOW}How long should subkeys be valid?${NC}"
echo ""
echo "  Examples: 1y, 2y, 5y, 7y, 10y"
echo "  Recommendation: 1y"
echo ""
read -p "  Subkey expiry [1y]: " EXPIRY
EXPIRY=${EXPIRY:-1y}  # Default to 1 year if the user just presses Enter
echo ""
echo -e "${GREEN}  ✓ Subkey expiry: $EXPIRY${NC}"
echo ""

# ============================================================
# === SUBKEY 1 OF 3: SIGNING [S] ===
# ============================================================
# The signing subkey is used for:
#   - Signing emails (S/MIME or inline PGP)
#   - Signing Git commits (with `git commit -S`)
#   - Signing documents and files to prove authenticity
#
# WHY a SEPARATE signing subkey (not using the master):
#   The master key is kept offline in a vault. Day-to-day signing
#   operations happen on the YubiKey using this subkey. If the
#   YubiKey is lost or the signing subkey is compromised, you use
#   the offline master key to revoke ONLY this subkey and generate
#   a new one — your identity (the master key) is untouched.
#
# ALGORITHM CHOICE — Option 10 (ECC sign only):
#   We pick "ECC (sign only)" because we want a signing-only subkey.
#   Using Curve 25519 gives us Ed25519, the same high-security curve
#   as the master key, with compact 256-bit keys.
# --- Subkey 1: Signing ---
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SUBKEY 1 of 3: SIGNING [S]                         ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  In the GPG editor that opens:"
echo ""

# GPG's key editor requires you to type "addkey" to begin the
# subkey addition workflow. Without this command, the editor just
# sits idle and waits for further input.
echo -e "  ${BOLD}1.${NC} Type ${CYAN}addkey${NC} and press Enter"
echo ""

# Option 10 is "ECC (sign only)" — this creates a subkey restricted
# to signing operations only, using an elliptic curve algorithm.
# Restricting to sign-only is a security principle of least privilege:
# a key should only be able to do what it needs to do.
echo -e "  ${BOLD}2.${NC} Select: ${CYAN}(10) ECC (sign only)${NC}"
echo ""

# Curve 25519 is the recommended modern elliptic curve. Option 1 in
# GPG's curve selection menu corresponds to Curve 25519 (Ed25519 for
# signing keys).
echo -e "  ${BOLD}3.${NC} Select: ${CYAN}(1) Curve 25519${NC}"
echo ""

# Enter the expiry the user chose above. GPG accepts formats like
# "1y" (1 year), "365d" (365 days), or a specific date "2026-01-01".
echo -e "  ${BOLD}4.${NC} Expiry: ${CYAN}$EXPIRY${NC}"
echo ""

# GPG asks "Is this correct?" (y/n) and then "Really create?" (y/n).
# Both must be confirmed with "y" before the subkey is generated.
echo -e "  ${BOLD}5.${NC} Confirm: ${CYAN}y${NC}, then ${CYAN}y${NC}"
echo ""

# IMPORTANT: After adding the subkey you MUST type "save" to write
# the changes back to the keyring. If you type "quit" instead,
# the subkey will be discarded. We open a fresh GPG editor for each
# subkey to keep the on-screen instructions simple and unambiguous.
echo -e "  ${RED}Then type 'save' and press Enter to exit.${NC}"
echo -e "  (We reopen for each subkey to keep instructions clear.)"
echo ""
read -p "  Press Enter to open GPG editor for Signing subkey..."

# Launch GPG's key editor for the master key.
# `--expert` is required to access option 10 (ECC sign only) and
# option 11 (ECC set own capabilities). Without --expert, these
# options are hidden.
gpg --expert --edit-key "$KEYID"

echo ""
echo -e "${GREEN}  ✓ Signing subkey added.${NC}"
echo ""

# ============================================================
# === SUBKEY 2 OF 3: ENCRYPTION [E] ===
# ============================================================
# The encryption subkey is used for:
#   - Receiving encrypted emails
#   - Decrypting files encrypted to your public key
#   - GPG-encrypted storage
#
# WHY a separate encryption subkey:
#   Same reasoning as the signing subkey. The master key stays offline.
#   The YubiKey holds this subkey. Decryption happens on the YubiKey —
#   the plaintext is passed back to the computer, but the secret key
#   material never leaves the YubiKey's hardware.
#
# ALGORITHM CHOICE — Option 12 (ECC encrypt only):
#   Encryption uses Curve 25519 in its X25519 / ECDH form (different
#   from Ed25519 which is for signing). GPG calls this "cv25519".
#   Option 12 in --expert mode is "ECC (encrypt only)".
# --- Subkey 2: Encryption ---
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SUBKEY 2 of 3: ENCRYPTION [E]                      ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  In the GPG editor:"
echo ""

# Same as subkey 1: start by typing "addkey" to enter the subkey wizard.
echo -e "  ${BOLD}1.${NC} Type ${CYAN}addkey${NC} and press Enter"
echo ""

# Option 12 is "ECC (encrypt only)" — creates a subkey restricted
# to encryption/decryption. On Curve 25519 this becomes an X25519 key.
echo -e "  ${BOLD}2.${NC} Select: ${CYAN}(12) ECC (encrypt only)${NC}"
echo ""

# Same curve as the signing key for consistency and modern best practice.
echo -e "  ${BOLD}3.${NC} Select: ${CYAN}(1) Curve 25519${NC}"
echo ""

# Apply the same expiry as the other subkeys for uniform renewal schedule.
echo -e "  ${BOLD}4.${NC} Expiry: ${CYAN}$EXPIRY${NC}"
echo ""

# Confirm both prompts. GPG is cautious and asks twice before creating
# any new key material.
echo -e "  ${BOLD}5.${NC} Confirm: ${CYAN}y${NC}, then ${CYAN}y${NC}"
echo ""

# Must type "save" — not "quit" — to persist the new subkey.
echo -e "  ${RED}Then type 'save' and press Enter.${NC}"
echo ""
read -p "  Press Enter to open GPG editor for Encryption subkey..."

# Open the GPG key editor again, same as before.
gpg --expert --edit-key "$KEYID"

echo ""
echo -e "${GREEN}  ✓ Encryption subkey added.${NC}"
echo ""

# ============================================================
# === SUBKEY 3 OF 3: AUTHENTICATION [A] ===
# ============================================================
# The authentication subkey is used for:
#   - SSH authentication (replacing SSH keys entirely)
#   - Logging into servers, GitHub, etc. using the YubiKey
#   - Any PAM/smartcard authentication
#
# WHY authentication is separate: it lets you use your YubiKey as
# an SSH key without mixing SSH and email/signing operations. If you
# ever need to revoke SSH access, you revoke just this subkey.
#
# ALGORITHM CHOICE — Option 11 (ECC set own capabilities):
#   GPG does not have a built-in "ECC authenticate only" option like
#   it does for sign (10) and encrypt (12). Instead, we use option 11
#   (set your own capabilities) and manually toggle the capabilities:
#     - Toggle Sign OFF (it defaults to ON for option 11)
#     - Toggle Authenticate ON (it defaults to OFF)
#   The result is an Authenticate-only subkey on Curve 25519 (Ed25519).
# --- Subkey 3: Authentication ---
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SUBKEY 3 of 3: AUTHENTICATION [A]                  ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  This one needs capability toggling. In the GPG editor:"
echo ""

# Start the subkey wizard as before.
echo -e "  ${BOLD}1.${NC} Type ${CYAN}addkey${NC} and press Enter"
echo ""

# Option 11 is "ECC (set your own capabilities)" — the only option
# that lets us create an Authenticate-only ECC subkey.
echo -e "  ${BOLD}2.${NC} Select: ${CYAN}(11) ECC (set your own capabilities)${NC}"
echo ""

# --- Capability toggling for the authentication subkey ---
# After selecting option 11, GPG defaults to Sign capability only.
# We need to:
#   1. Type "S" → this TOGGLES Sign OFF (removing it)
#   2. Type "A" → this TOGGLES Authenticate ON (adding it)
#   3. Type "Q" → finishes capability selection and moves on
#
# After step 2, the display should read:
#   "Current allowed actions: Authenticate"
# If it shows anything else, use S/A again to toggle until correct.
echo -e "  ${BOLD}3.${NC} You'll see 'Current allowed actions: Sign'"
echo -e "     Type ${CYAN}S${NC} → turns OFF Sign"
echo -e "     Type ${CYAN}A${NC} → turns ON Authenticate"
echo -e "     Should show: ${CYAN}'Current allowed actions: Authenticate'${NC}"
echo -e "     Type ${CYAN}Q${NC} → finish"
echo ""

# Same curve selection as all other subkeys.
echo -e "  ${BOLD}4.${NC} Select: ${CYAN}(1) Curve 25519${NC}"
echo ""

# Apply the same expiry for a uniform renewal schedule across all subkeys.
echo -e "  ${BOLD}5.${NC} Expiry: ${CYAN}$EXPIRY${NC}"
echo ""

# Confirm both prompts as before.
echo -e "  ${BOLD}6.${NC} Confirm: ${CYAN}y${NC}, then ${CYAN}y${NC}"
echo ""

# IMPORTANT: Must type "save" — not "quit" — or the subkey is discarded.
echo -e "  ${RED}Then type 'save' and press Enter.${NC}"
echo ""
read -p "  Press Enter to open GPG editor for Authentication subkey..."

# Open the GPG key editor one final time for the authentication subkey.
gpg --expert --edit-key "$KEYID"

echo ""
echo -e "${GREEN}  ✓ Authentication subkey added.${NC}"
echo ""

# ============================================================
# === VERIFICATION: REVIEW THE COMPLETE KEY STRUCTURE ===
# ============================================================
# Before proceeding to export, we show the full key structure and
# ask the user to confirm it matches expectations. The correct
# structure is critical — exporting a malformed key structure to
# backup media and then loading it onto a YubiKey would result in
# the wrong capabilities being available.
#
# WHAT TO LOOK FOR in the output:
#   sec   ed25519  [C]           : master key, Certify ONLY, no expiry date
#   ssb   ed25519  [S] [expires] : signing subkey
#   ssb   cv25519  [E] [expires] : encryption subkey (note: cv25519, not ed25519)
#   ssb   ed25519  [A] [expires] : authentication subkey
#
# If any subkey shows additional capabilities (e.g., [SC] instead of [S]),
# that means a capability toggle was missed during generation. You can
# delete the bad subkey with `gpg --edit-key KEYID` → `key N` → `delkey`.
# --- Verify complete structure ---
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  VERIFICATION                                       ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Your complete key structure:${NC}"
echo ""

# --list-secret-keys shows both the master key (sec) and subkeys (ssb).
# --keyid-format 0xlong shows full 16-char IDs for unambiguous reference.
gpg --list-secret-keys --keyid-format 0xlong "$KEYID"
echo ""
echo "  Expected structure:"
echo "    sec   ed25519  [C]           ← Master (Certify only, no expiry)"
echo "    ssb   ed25519  [S] [expires] ← Sign (${EXPIRY})"
echo "    ssb   cv25519  [E] [expires] ← Encrypt (${EXPIRY})"
echo "    ssb   ed25519  [A] [expires] ← Authenticate (${EXPIRY})"
echo ""

# If the structure is wrong, the user should NOT proceed. Provide
# instructions for how to clean up and retry rather than leaving them
# stranded. `delkey` in the GPG editor removes a specific subkey
# (first select it with `key N`, then run `delkey`).
read -p "  Does this look correct? (y/n): " VERIFY
if [ "$VERIFY" != "y" ]; then
    echo ""
    echo -e "${YELLOW}  You can fix issues with: gpg --expert --edit-key $KEYID${NC}"
    echo "  Use 'delkey' to remove a bad subkey, then re-run this script."
    exit 1
fi

# ============================================================
# === SAVE KEY ID FOR SUBSEQUENT SCRIPTS ===
# ============================================================
# Overwrite the keyid.txt file with the confirmed key ID.
# This ensures scripts 04, 05, and 06 have the correct value.
# Save key ID
echo "$KEYID" > /tmp/gpg-export/keyid.txt

# ============================================================
# === SUMMARY ===
# ============================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  ALL SUBKEYS CREATED                                   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Master [C]:  $KEYID (no expiry)"
echo "  Subkeys:     [S] [E] [A] (expiry: $EXPIRY)"
echo ""
echo "  Next: bash .../scripts/04-export-keys.sh"
echo ""
