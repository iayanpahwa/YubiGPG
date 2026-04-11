#!/bin/bash
# =============================================================
# 07 — TRANSFER SUBKEYS TO YUBIKEY
# =============================================================
# Transfers all 3 subkeys (S, E, A) to ONE YubiKey at a time.
# Run this script 3 times — once per YubiKey.
#
# KEY PRESERVATION:
#   'keytocard' is destructive — it deletes the key from disk.
#   This script ALWAYS restores keys from the export backup
#   BEFORE each transfer, guaranteeing keys are never lost.
#
# TOUCH POLICY:
#   Touch is MANDATORY and enabled on all YubiKeys — not optional.
#
# PIN NOTE:
#   Your YubiKey PINs are already changed from defaults.
#   This script does NOT reconfigure PINs.
#
# USAGE:
#   bash .../scripts/07-yubikey-transfer.sh
# =============================================================

# Exit immediately on any error, treat unset variables as errors,
# and propagate pipeline failures (so grep failures aren't swallowed).
set -euo pipefail

# ============================================================
# ANSI COLOR CODES
# ============================================================
# These variables are used throughout for colored terminal output.
# NC = No Color, resets formatting after each colored string.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# The working directory for all exported key material created
# during the Tails session (scripts 01–06).
EXPORT_DIR="/tmp/gpg-export"

clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         07 — TRANSFER SUBKEYS TO YUBIKEY               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === WHICH YUBIKEY? ===
# ============================================================
# The user runs this script 3 times — once for each YubiKey.
# This prompt records which hardware token is currently inserted
# so the script can display accurate progress and know how many
# remain. This does NOT change any behavior; it is informational.
echo -e "${YELLOW}Which YubiKey are you loading right now?${NC}"
echo ""
echo "  1. KEY-1 — Primary / Daily Carry"
echo "  2. KEY-2 — Home Backup (stored in a safe at home)"
echo "  3. KEY-3 — Offsite Backup (bank, trusted person, etc.)"
echo ""
read -p "  Select (1/2/3): " YK_NUM

# Map the numeric choice to a human-readable label used in
# progress messages and the completion summary.
case $YK_NUM in
    1) YK_NAME="KEY-1 (Primary / Daily Carry)" ;;
    2) YK_NAME="KEY-2 (Home Backup)" ;;
    3) YK_NAME="KEY-3 (Offsite Backup)" ;;
    *) echo "Invalid."; exit 1 ;;
esac

echo ""
echo -e "${GREEN}  Loading: $YK_NAME${NC}"
echo ""

# ============================================================
# === VERIFY BACKUP FILE EXISTS ===
# ============================================================
# master-secret-key.asc is required BEFORE every keytocard run.
# Because keytocard is destructive (it deletes the key from the
# local keyring), we must re-import from this file before each
# YubiKey transfer. If the file is missing, we cannot proceed.
#
# If it was accidentally wiped (e.g., after an early cleanup),
# the user must restore it from the LUKS backup USB manually.
# The instructions below walk them through that recovery.
if [ ! -f "$EXPORT_DIR/master-secret-key.asc" ]; then
    echo -e "${RED}  Cannot find $EXPORT_DIR/master-secret-key.asc${NC}"
    echo ""
    echo "  This file is needed to restore keys between YubiKey transfers."
    echo "  If it was wiped, you need to restore from your LUKS backup USB."
    echo ""
    echo "  Steps:"
    echo "    1. Insert your LUKS backup USB"
    echo "    2. sudo cryptsetup luksOpen /dev/sdX1 gpg-backup"
    echo "    3. sudo mount /dev/mapper/gpg-backup /mnt"
    echo "    4. cp /mnt/gpg-keys/master-secret-key.asc $EXPORT_DIR/"
    echo "    5. sudo umount /mnt && sudo cryptsetup luksClose gpg-backup"
    echo ""
    read -p "  Press Enter after restoring the backup file..."
    # Check again after the user says they've restored the file.
    if [ ! -f "$EXPORT_DIR/master-secret-key.asc" ]; then
        echo -e "${RED}  File still not found. Aborting.${NC}"
        exit 1
    fi
fi

# =============================================================
# STEP 1: ALWAYS RESTORE KEYS FROM BACKUP
# =============================================================
# This ensures keys are ALWAYS available, regardless of whether
# a previous keytocard already deleted them.
#
# WHY THIS IS SAFE:
#   After the first keytocard run, the local keys become "stubs"
#   (pointers to the YubiKey, not actual private keys). If we run
#   keytocard again from stubs, GPG would error or write garbage
#   to the next YubiKey. By deleting stubs and re-importing the
#   full key from the .asc backup every time, we guarantee each
#   YubiKey gets the real private keys, not stale stubs.
# =============================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  STEP 1/4: RESTORING KEYS FROM BACKUP               ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Clearing any existing key stubs and re-importing fresh..."
echo ""

# Find any key currently in the local keyring so we can delete it.
# The || true prevents set -e from aborting if the keyring is empty.
# --keyid-format 0xlong formats IDs as the full 16-character hex string.
EXISTING_KEY=$(gpg --list-keys --keyid-format 0xlong 2>/dev/null | grep "^pub" | head -1 | awk '{print $2}' | cut -d'/' -f2 || true)

if [ -n "$EXISTING_KEY" ]; then
    echo "  Removing existing key: $EXISTING_KEY"
    # --yes suppresses the interactive confirmation prompt.
    # --delete-secret-and-public-keys removes BOTH the secret key (or
    # stub) and the public key, leaving the keyring completely empty.
    # This prevents stubs from the previous keytocard from interfering.
    gpg --yes --delete-secret-and-public-keys "$EXISTING_KEY" 2>/dev/null || true
fi

# Import the full key (master + all subkeys) from the backup file.
# This gives us genuine private key material, not YubiKey stubs.
echo "  Importing from backup..."
gpg --import "$EXPORT_DIR/master-secret-key.asc" 2>&1 | grep -E "(secret|imported)" || true
echo ""

# Extract the 16-character key ID from the newly imported secret key.
# Used in all subsequent gpg commands to reference this specific key.
KEYID=$(gpg --list-secret-keys --keyid-format 0xlong 2>/dev/null | grep "^sec " | head -1 | awk '{print $2}' | cut -d'/' -f2)

if [ -z "$KEYID" ]; then
    echo -e "${RED}  Failed to import keys. Something is wrong with the backup.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ Keys restored. Working with: $KEYID${NC}"
echo ""

# Show the full key structure so the user can visually confirm
# all subkeys are present and they have the right key.
echo "  Key structure:"
gpg --list-secret-keys --keyid-format 0xlong "$KEYID"
echo ""

# Safety check: count the subkeys. We need exactly 3 (S, E, A).
# If fewer than 3 are present, the backup is incomplete — possibly
# it was created AFTER a partial keytocard run that left stubs.
# In that case, the user must use the gnupg-full-backup directory
# or their LUKS USB, which has a complete pre-transfer backup.
SUBKEY_COUNT=$(gpg --list-secret-keys --keyid-format 0xlong "$KEYID" 2>/dev/null | grep -c "^ssb " || true)
if [ "$SUBKEY_COUNT" -lt 3 ]; then
    echo -e "${RED}  Expected 3 subkeys but found $SUBKEY_COUNT.${NC}"
    echo "  Your backup may be from after a partial keytocard."
    echo "  Use the gnupg-full-backup directory or your LUKS backup."
    exit 1
fi
echo -e "${GREEN}  ✓ All 3 subkeys present and ready for transfer.${NC}"
echo ""

# =============================================================
# STEP 2: INSERT YUBIKEY AND VERIFY
# =============================================================
# Before attempting keytocard, we confirm GPG can communicate
# with the YubiKey via the PC/SC smart card daemon (pcscd).
# If detection fails, we attempt to restart scdaemon (the GPG
# smart card daemon) — this resolves most transient USB issues.
# =============================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  STEP 2/4: YUBIKEY DETECTION                        ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}  Insert YubiKey: $YK_NAME${NC}"
echo ""
read -p "  Press Enter when the YubiKey is plugged in..."
echo ""

# --card-status reads metadata from the inserted OpenPGP smart card.
# Redirect both stdout and stderr to /dev/null — we only care about
# the exit code here (0 = card found, non-zero = not found).
if gpg --card-status &>/dev/null; then
    echo -e "${GREEN}  ✓ YubiKey detected:${NC}"
    # Show just the identifying fields so the user can confirm
    # they have the right YubiKey plugged in (serial number, version).
    gpg --card-status 2>/dev/null | grep -E "(Name|Serial|Version)" | head -5
else
    echo -e "${YELLOW}  Card not detected. Trying to restart scdaemon...${NC}"
    # scdaemon is the GPG smart card daemon. Killing it forces GPG to
    # relaunch it fresh on the next card operation, which resolves
    # most "card not found" errors caused by USB re-enumeration.
    gpgconf --kill scdaemon 2>/dev/null || true
    sleep 2
    if gpg --card-status &>/dev/null; then
        echo -e "${GREEN}  ✓ YubiKey detected after restart.${NC}"
    else
        echo -e "${RED}  ✗ YubiKey not detected.${NC}"
        echo "  Make sure pcscd is running: sudo systemctl start pcscd"
        echo "  Try removing and reinserting the YubiKey."
        read -p "  Press Enter to try again, or Ctrl+C to abort..."
        # This final call will either succeed or abort the script
        # (set -e is active), preventing us from running keytocard
        # against no card.
        gpg --card-status
    fi
fi
echo ""

# =============================================================
# STEP 3: TRANSFER SUBKEYS TO CARD
# =============================================================
# WARNING: keytocard is a DESTRUCTIVE, ONE-WAY OPERATION.
#
# What keytocard does:
#   - Moves the private key material from the local keyring
#     INTO the YubiKey's secure element.
#   - Replaces the local key with a "stub" (a reference saying
#     "this key lives on a YubiKey with serial XXXXXXXX").
#   - The private key bytes are NO LONGER on disk after this.
#
# This is WHY we re-import from backup at the start of every run:
#   The next YubiKey needs the real private key, not a stub.
#
# The user must follow the exact sequence below. GPG opens an
# interactive editor — there are no CLI flags for keytocard.
# =============================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  STEP 3/4: TRANSFER SUBKEYS TO YUBIKEY              ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${RED}  ╔════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}  ║  'keytocard' DELETES the key from local keyring.  ║${NC}"
echo -e "${RED}  ║                                                    ║${NC}"
echo -e "${RED}  ║  This is SAFE — we already have the backup and    ║${NC}"
echo -e "${RED}  ║  will restore from it for the next YubiKey.       ║${NC}"
echo -e "${RED}  ╚════════════════════════════════════════════════════╝${NC}"
echo ""
# The following is a step-by-step guide for the user to follow
# inside the interactive GPG editor. Each "key N" command toggles
# selection of subkey N (an asterisk * appears next to it when
# selected). You must DESELECT a key before selecting the next one,
# otherwise keytocard will try to move two keys into the same slot.
echo "  GPG will open in edit mode. Follow these steps exactly:"
echo ""
echo -e "  ${BOLD}── SIGNING KEY ──${NC}"
# 'key 1' selects subkey #1, which has the [S] (sign) capability.
echo -e "  gpg> ${CYAN}key 1${NC}              (asterisk appears next to subkey 1)"
# 'keytocard' moves the selected key to the YubiKey. GPG will ask
# which slot — choose (1) Signature key.
echo -e "  gpg> ${CYAN}keytocard${NC}"
echo -e "  Select: ${CYAN}(1) Signature key${NC}"
# Deselect before moving to the next key — 'key 1' again toggles off.
echo -e "  gpg> ${CYAN}key 1${NC}              (deselect — asterisk disappears)"
echo ""
echo -e "  ${BOLD}── ENCRYPTION KEY ──${NC}"
# 'key 2' selects subkey #2, which has the [E] (encrypt) capability.
echo -e "  gpg> ${CYAN}key 2${NC}              (asterisk appears next to subkey 2)"
echo -e "  gpg> ${CYAN}keytocard${NC}"
echo -e "  Select: ${CYAN}(2) Encryption key${NC}"
echo -e "  gpg> ${CYAN}key 2${NC}              (deselect)"
echo ""
echo -e "  ${BOLD}── AUTHENTICATION KEY ──${NC}"
# 'key 3' selects subkey #3, which has the [A] (authenticate) capability.
# This is the key that powers GPG-based SSH authentication.
echo -e "  gpg> ${CYAN}key 3${NC}              (asterisk appears next to subkey 3)"
echo -e "  gpg> ${CYAN}keytocard${NC}"
echo -e "  Select: ${CYAN}(3) Authentication key${NC}"
echo ""
echo -e "  ${BOLD}── SAVE ──${NC}"
# 'save' writes all changes to the YubiKey and exits the editor.
# 'quit' WITHOUT save would discard the transfer — always use 'save'.
echo -e "  gpg> ${CYAN}save${NC}"
echo ""
# GPG will prompt for the key passphrase (to decrypt the private key
# for transfer) and the YubiKey Admin PIN (to authorize writing to
# the card's secure element). Both are required.
echo -e "${YELLOW}  You will be prompted for your GPG passphrase and${NC}"
echo -e "${YELLOW}  the YubiKey admin PIN during this process.${NC}"
echo ""
read -p "  Press Enter to open GPG editor..."

# Open the interactive GPG key editor for the specified key.
# There is no way to automate keytocard — it requires human input.
gpg --edit-key "$KEYID"

echo ""
echo -e "${GREEN}  ✓ Subkeys transferred to YubiKey.${NC}"
echo ""

# Confirm the transfer succeeded by checking that the YubiKey now
# reports key fingerprints in all three slots (sig/enc/aut).
echo "  Verifying YubiKey contents..."
echo ""
gpg --card-status 2>/dev/null | grep -E "(Signature|Encryption|Authentication|General)" | head -10
echo ""

# =============================================================
# STEP 4: SET TOUCH POLICY (MANDATORY)
# =============================================================
# Touch policy requires a physical tap on the YubiKey for every
# cryptographic operation (sign, decrypt, authenticate via SSH).
#
# WHY THIS IS NON-NEGOTIABLE:
#   Without touch policy, malware on a compromised machine can
#   silently trigger hundreds of signing or decryption operations
#   using your YubiKey without you knowing. Touch policy makes
#   every operation visible and requires physical presence.
#
# POLICY OPTIONS:
#   on    — require touch, policy CAN be changed later with ykman.
#   fixed — require touch, policy CANNOT be changed without a full
#           OpenPGP reset (which destroys all keys on the YubiKey).
#           Use 'fixed' for maximum security if you never want the
#           option to disable touch. Use 'on' for slightly more
#           flexibility while still enforcing touch.
# =============================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  STEP 4/4: ENABLE TOUCH POLICY                      ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""

# ykman (YubiKey Manager CLI) is required to configure touch policy.
# On Tails it may not be pre-installed. If missing, offer to install
# it briefly (requires momentary network access).
if ! command -v ykman &>/dev/null; then
    echo -e "${YELLOW}  'ykman' (YubiKey Manager) is not installed.${NC}"
    echo ""
    echo "  Touch policy is MANDATORY for security."
    echo "  I need to install ykman. This requires brief network access."
    echo ""
    echo "  1. Enable network, install ykman, disable network"
    echo "  2. Skip (you MUST set touch policy later manually)"
    echo ""
    read -p "  Choose (1/2): " YKMAN_CHOICE

    if [ "$YKMAN_CHOICE" = "1" ]; then
        # Temporarily unblock wireless hardware and start NetworkManager
        # just long enough to install ykman, then immediately re-block.
        sudo rfkill unblock all 2>/dev/null || true
        sudo systemctl start NetworkManager 2>/dev/null || true
        echo ""
        read -p "  Connect to network. Press Enter when ready..."
        sudo apt update -qq && sudo apt install -y -qq yubikey-manager
        # Re-establish air gap as soon as installation is complete.
        sudo systemctl stop NetworkManager 2>/dev/null || true
        sudo rfkill block all 2>/dev/null || true
        echo -e "${GREEN}  ✓ ykman installed. Network disabled.${NC}"
    fi
fi

if command -v ykman &>/dev/null; then
    echo ""
    echo "  Touch policy options:"
    echo ""
    echo "    on    — require physical touch for every crypto operation"
    echo "    fixed — same as 'on' but CANNOT be changed without full"
    echo "            YubiKey OpenPGP reset (destroys keys on the card)"
    echo ""

    # Default to 'on' if the user just presses Enter.
    read -p "  Touch policy for this YubiKey (on/fixed) [on]: " TOUCH
    TOUCH=${TOUCH:-on}

    echo ""
    echo "  Setting touch policy to '$TOUCH' for all key slots..."
    echo ""

    # Set touch policy independently for each of the three key slots:
    #   sig = signing slot  (subkey with [S] capability)
    #   enc = encryption slot (subkey with [E] capability)
    #   aut = authentication slot (subkey with [A] capability, used for SSH)
    # The YubiKey Admin PIN is required for each of these commands.
    ykman openpgp keys set-touch sig "$TOUCH" && echo -e "  ${GREEN}✓ Signature: $TOUCH${NC}" || echo -e "  ${RED}✗ Failed for signature${NC}"
    ykman openpgp keys set-touch enc "$TOUCH" && echo -e "  ${GREEN}✓ Encryption: $TOUCH${NC}" || echo -e "  ${RED}✗ Failed for encryption${NC}"
    ykman openpgp keys set-touch aut "$TOUCH" && echo -e "  ${GREEN}✓ Authentication: $TOUCH${NC}" || echo -e "  ${RED}✗ Failed for authentication${NC}"

    echo ""
    echo -e "${GREEN}  ✓ Touch policy enabled.${NC}"
    echo "  The YubiKey will blink and require a tap for every operation."
else
    # IMPORTANT: If ykman is still unavailable, the user MUST set touch
    # policy manually later before using this YubiKey. Without it,
    # malware can silently use the key.
    echo ""
    echo -e "${RED}  ⚠  ykman not available. You MUST set touch policy later:${NC}"
    echo ""
    echo "    ykman openpgp keys set-touch sig on"
    echo "    ykman openpgp keys set-touch enc on"
    echo "    ykman openpgp keys set-touch aut on"
    echo ""
    echo "  Without touch policy, malware can silently use your key."
fi

# =============================================================
# DONE — PROGRESS AND NEXT STEPS
# =============================================================
# If more YubiKeys remain, remind the user of the workflow:
#   1. Store this YubiKey safely.
#   2. Insert the next one.
#   3. Run this script again — it will re-import from backup automatically.
# =============================================================

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  YUBIKEY LOADED: $YK_NAME ${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Calculate how many YubiKeys are still unloaded.
REMAINING=$((3 - YK_NUM))
if [ "$REMAINING" -gt 0 ]; then
    echo "  $REMAINING YubiKey(s) remaining."
    echo ""
    echo "  Steps:"
    echo "    1. REMOVE this YubiKey (put it in its storage location)"
    echo "    2. INSERT the next YubiKey"
    echo "    3. Run this script again"
    echo ""
    echo "  The script will automatically restore keys from backup"
    echo "  before transferring — your keys are never lost."
    echo ""
    echo "  Next: bash .../scripts/07-yubikey-transfer.sh  (again)"
else
    # All 3 YubiKeys loaded — proceed to the summary script.
    echo -e "${GREEN}  All 3 YubiKeys are loaded!${NC}"
    echo ""
    echo "  Next: bash .../scripts/08-key-summary.sh"
fi
echo ""
