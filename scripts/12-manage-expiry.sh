#!/bin/bash
# =============================================================
# 12 — KEY EXPIRY MANAGEMENT
# =============================================================
# Extend, expire, revoke, or regenerate subkeys.
#
# PREREQUISITE: Run 11-restore-from-luks.sh first.
#
# USAGE:
#   bash .../scripts/12-manage-expiry.sh
# =============================================================

# Exit immediately on error, treat unset variables as errors,
# and propagate pipeline failures.
set -euo pipefail

# ============================================================
# ANSI COLOR CODES
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Export directory for the updated public key produced at the end.
# This directory is used as the handoff point between Tails and
# the daily machine (via USB copy).
EXPORT_DIR="/tmp/gpg-export"
mkdir -p "$EXPORT_DIR"

clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   12 — KEY EXPIRY MANAGEMENT                           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================
# === LOCATE THE MASTER KEY ===
# =============================================================
# Script 11 must have already imported the master key from the
# LUKS backup. If no secret key is found, the user is redirected
# to run script 11 first — there is nothing to manage without it.
# =============================================================

# --- Get key ID ---
# Parse gpg's colon-delimited secret key listing to extract the
# master key ID. 'sec' lines are master keys; 'ssb' lines are subkeys.
# cut -d'/' -f2 strips the algorithm prefix (e.g., "ed25519/") leaving
# just the hex key ID.
KEYID=$(gpg --list-secret-keys --keyid-format 0xlong 2>/dev/null | grep "^sec " | head -1 | awk '{print $2}' | cut -d'/' -f2 || true)

if [ -z "$KEYID" ]; then
    echo -e "${RED}  No master key found. Run 11-restore-from-luks.sh first.${NC}"
    exit 1
fi

echo -e "${GREEN}  Key: $KEYID${NC}"
echo ""
# Show the current key structure including expiry dates before
# asking the user to choose an action.
gpg --list-keys --keyid-format 0xlong "$KEYID"
echo ""

# =============================================================
# === ACTION MENU ===
# =============================================================
# Four operations are available. All of them open the interactive
# GPG editor (gpg --expert --edit-key) because GPG does not expose
# these operations as non-interactive CLI flags.
#
# --expert enables additional key types and options that are hidden
# in the default editor, required for some advanced subkey operations.
#
# The menu explains what each action does BEFORE the user chooses,
# so they understand the consequences — especially for options 3
# (revoke) and 4 (generate new subkeys, which requires re-loading
# all YubiKeys afterward).
# =============================================================

# --- Choose action ---
echo -e "${BOLD}What do you want to do?${NC}"
echo ""
echo "  1. EXTEND subkey expiry (e.g., another 7 years)"
echo "  2. MANUALLY EXPIRE a subkey (disable it, reversible)"
echo "  3. REVOKE a subkey (permanent, cannot undo)"
echo "  4. GENERATE NEW subkeys (replace old/revoked ones)"
echo ""
read -p "  Select (1/2/3/4): " ACTION

case $ACTION in

# =============================================================
# OPTION 1: EXTEND SUBKEY EXPIRY
# =============================================================
# Sets a new expiry date further in the future on one or more
# subkeys. This is the most common maintenance operation —
# done when subkeys are approaching their expiry date.
#
# The operation must be done for each subkey separately:
#   - Select the subkey with 'key N'
#   - Run 'expire' and enter the new validity period
#   - Deselect the subkey with 'key N' again
#   - Repeat for the next subkey
#   - Save with 'save'
#
# After this, the updated public key must be redistributed so
# others can see the new expiry (handled at the end of this script).
# =============================================================
1)
    echo ""
    echo -e "${BOLD}═══ EXTEND EXPIRY ══════════════════════════════════${NC}"
    echo ""
    read -p "  New expiry period (e.g., 7y, 5y, 2y): " NEW_EXPIRY
    echo ""
    echo "  In the GPG editor, for EACH subkey (1, 2, 3):"
    echo ""
    # 'key N' selects/deselects subkey N. An asterisk (*) appears
    # next to selected subkeys in the key listing.
    echo "    gpg> key N          (select subkey N)"
    echo "    gpg> expire"
    # GPG asks "Key is valid for?" — enter the period, e.g., "7y".
    echo "    Key is valid for? $NEW_EXPIRY"
    echo "    Confirm: y"
    # Deselect before moving to the next subkey to avoid accidentally
    # applying expire to multiple subkeys in one command.
    echo "    gpg> key N          (deselect before next)"
    echo ""
    echo "  After all 3:"
    # 'save' commits all changes. 'quit' without save discards them.
    echo "    gpg> save"
    echo ""
    read -p "  Press Enter to open GPG editor..."
    gpg --expert --edit-key "$KEYID"
    echo -e "${GREEN}  ✓ Expiry updated${NC}"
    ;;

# =============================================================
# OPTION 2: MANUALLY EXPIRE A SUBKEY (REVERSIBLE DISABLE)
# =============================================================
# Sets a subkey's expiry to 1 day, effectively disabling it
# immediately without permanently revoking it.
#
# USE CASE: You want to temporarily disable a subkey — for
# example, if you suspect a YubiKey is lost but aren't certain,
# or you want to force contacts to use a newer subkey while
# keeping the option to re-enable the old one.
#
# REVERSIBLE: Unlike revocation, a manually expired subkey can be
# re-enabled simply by extending its expiry to a future date
# (using option 1 of this menu).
#
# After expiry takes effect, others encrypting to you will see
# the subkey as expired and should fall back to a non-expired key.
# =============================================================
2)
    echo ""
    echo -e "${BOLD}═══ MANUALLY EXPIRE ════════════════════════════════${NC}"
    echo ""
    echo "  This sets a subkey to expire in 1 day, disabling it."
    echo "  Unlike revocation, this is REVERSIBLE — you can extend"
    echo "  the expiry later to re-enable the key."
    echo ""
    echo "  In the GPG editor:"
    # Select the specific subkey you want to disable.
    echo "    gpg> key N          (select the subkey)"
    echo "    gpg> expire"
    # Enter '1' for 1 day — the shortest usable validity period.
    # The key will appear expired to anyone checking within 24 hours.
    echo "    Key is valid for? 1   (1 day)"
    echo "    Confirm: y"
    echo "    gpg> save"
    echo ""
    read -p "  Press Enter to open GPG editor..."
    gpg --expert --edit-key "$KEYID"
    echo -e "${GREEN}  ✓ Subkey expired${NC}"
    ;;

# =============================================================
# OPTION 3: REVOKE A SUBKEY (PERMANENT)
# =============================================================
# WARNING: Revocation is IRREVERSIBLE. Once a subkey is revoked
# and the revocation published, it cannot be un-revoked.
#
# USE CASE: A subkey's private key has been (or may have been)
# compromised — e.g., a YubiKey was stolen and the PIN may be
# known to an attacker. Revocation signals to the world that
# this subkey should no longer be trusted for verification,
# and encrypted mail sent to it should be considered unsafe.
#
# After revocation, the revocation must be published to the
# keyserver and distributed to contacts so they stop encrypting
# to the revoked subkey.
#
# Revocation reasons (GPG will ask):
#   (1) Key has been compromised — use if the key material is leaked.
#   (2) Key is superseded — use if replacing with a new subkey.
#   (3) Key is no longer used — use for planned retirement.
# =============================================================
3)
    echo ""
    echo -e "${BOLD}═══ REVOKE SUBKEY ═════════════════════════════════${NC}"
    echo ""
    # IMPORTANT: This warning is intentional and must remain visible.
    # Revocation cannot be undone. The user must understand this.
    echo -e "${RED}  WARNING: Revocation is PERMANENT. Cannot be undone.${NC}"
    echo ""
    # Require typing "REVOKE" (all caps) to proceed — not just 'y'.
    # This prevents accidents from fast keypresses during a stressful
    # security incident.
    read -p "  Are you sure you want to revoke? (type 'REVOKE'): " REV_CONFIRM
    if [ "$REV_CONFIRM" != "REVOKE" ]; then
        echo "  Aborted."
        exit 0
    fi
    echo ""
    echo "  In the GPG editor:"
    # Select the subkey to revoke by number.
    echo "    gpg> key N          (select the subkey to revoke)"
    # 'revkey' is the GPG editor command for subkey revocation.
    echo "    gpg> revkey"
    # GPG will ask for the revocation reason (1=compromised, 2=superseded,
    # 3=no longer used) and optional free-text explanation.
    echo "    Reason: (1) compromised, (2) superseded, (3) no longer used"
    echo "    Confirm: y"
    echo "    gpg> save"
    echo ""
    read -p "  Press Enter to open GPG editor..."
    gpg --expert --edit-key "$KEYID"
    echo -e "${GREEN}  ✓ Subkey revoked${NC}"
    ;;

# =============================================================
# OPTION 4: GENERATE NEW SUBKEYS
# =============================================================
# Creates fresh signing, encryption, and authentication subkeys
# under the existing master key. Use when:
#   - Old subkeys have expired and you want to replace them.
#   - A subkey was compromised and you revoked it.
#   - You want a fresh set of subkeys with a new expiry.
#
# IMPORTANT: After generating new subkeys, you MUST:
#   1. Load the new subkeys onto each YubiKey (run script 07,
#      once per YubiKey — 3 times total).
#   2. Export and distribute the updated public key (done
#      automatically at the end of this script).
#
# Key types to create in the GPG editor (using --expert mode):
#   Signing [S]:       addkey → (10) ECC sign → Curve 25519
#   Encryption [E]:    addkey → (12) ECC encrypt → Curve 25519
#   Authentication [A]: addkey → (11) ECC set caps → toggle S off,
#                       toggle A on → Curve 25519
#
# The (11) option for authentication is only visible with --expert.
# You MUST toggle capabilities manually: S is on by default, turn it
# off; A is off by default, turn it on. E must also be off.
# =============================================================
4)
    echo ""
    echo -e "${BOLD}═══ GENERATE NEW SUBKEYS ══════════════════════════${NC}"
    echo ""
    read -p "  Expiry for new subkeys (e.g., 7y): " NEW_EXP
    echo ""
    echo "  In the GPG editor, create new subkeys:"
    echo ""
    echo "  Signing [S]:       addkey → (10) ECC sign → Curve 25519 → $NEW_EXP"
    echo "  Encryption [E]:    addkey → (12) ECC encrypt → Curve 25519 → $NEW_EXP"
    # Option (11) is the "ECC with custom capabilities" choice.
    # By default it enables [S] only — you must toggle S off and A on.
    echo "  Authentication [A]: addkey → (11) ECC caps → S off, A on → 25519 → $NEW_EXP"
    echo ""
    # 'save' after all three addkey operations are complete.
    echo "  Then: save"
    echo ""
    read -p "  Press Enter to open GPG editor..."
    gpg --expert --edit-key "$KEYID"
    echo -e "${GREEN}  ✓ New subkeys created${NC}"
    echo ""
    # Remind the user that new subkeys on the master key do NOT
    # automatically appear on YubiKeys — each card must be reloaded.
    echo "  You must now transfer these to your YubiKeys."
    echo "  Run: bash .../scripts/07-yubikey-transfer.sh (once per YubiKey)"
    ;;

*)
    echo "  Invalid selection."
    exit 1
    ;;
esac

# =============================================================
# EXPORT UPDATED PUBLIC KEY
# =============================================================
# After any of the four operations above, the public key has
# changed (new expiry, revoked subkey, or new subkeys). The
# updated public key must be exported and distributed so that:
#   - Contacts know the current state of your subkeys.
#   - Keyservers can be updated with the new information.
#   - Your daily machine can import the refreshed key.
#
# The file is named public-key-updated.asc (not public-key.asc)
# to distinguish it from the original export and avoid overwriting
# the original if both files are on the same USB.
#
# --armor: ASCII output, compatible with keyservers and email.
# --export: exports only the public portion of the key.
# =============================================================
echo ""
echo -e "${YELLOW}Exporting updated public key...${NC}"
gpg --armor --export "$KEYID" > "$EXPORT_DIR/public-key-updated.asc"
echo -e "${GREEN}  ✓ $EXPORT_DIR/public-key-updated.asc${NC}"
echo ""

# =============================================================
# DISTRIBUTE THE UPDATED PUBLIC KEY
# =============================================================
# The updated public key is useless if it stays on this Tails
# machine — it must reach the keyserver and the user's daily machine.
#
# Steps to distribute (performed on the daily machine, not here):
#   1. Copy public-key-updated.asc to a USB drive.
#   2. On the daily machine: gpg --import public-key-updated.asc
#      (this refreshes the local keyring with the new subkey state)
#   3. Send to keyserver: gpg --keyserver hkps://keys.openpgp.org
#      --send-keys KEYID (propagates to the public keyserver network)
#   4. Update GitHub: re-upload the key under Settings → GPG keys
#      (GitHub needs the new version to show "Verified" on commits)
#
# If you generated new subkeys (option 4), also update your LUKS
# backup USBs with a fresh export of master-secret-key.asc — the
# old backup does not contain the new subkeys.
# =============================================================
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  DISTRIBUTE THE UPDATED PUBLIC KEY                   ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  Copy public-key-updated.asc to a USB drive."
echo "  On your daily machine:"
echo "    gpg --import public-key-updated.asc"
echo "    gpg --keyserver hkps://keys.openpgp.org --send-keys $KEYID"
echo "    Re-upload to GitHub (Settings → SSH and GPG keys)"
echo ""
# Reminder specific to option 4: new subkeys must also be backed up.
echo "  Also update your LUKS backups if you generated new subkeys."
echo ""
