#!/bin/bash
# =============================================================
# 09 — SECURE CLEANUP & SHUTDOWN
# =============================================================
# Destroys all key material from the Tails session. Run this
# AFTER reviewing the key summary (08) and confirming all
# backups are complete.
#
# USAGE:
#   bash .../scripts/09-cleanup.sh
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

clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         09 — SECURE CLEANUP & SHUTDOWN                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
# WARNING: This operation is one-way. Once key material is shredded
# from this Tails session, it cannot be recovered from this machine.
# All recovery must come from the LUKS backup USBs or YubiKeys.
echo -e "${RED}  This will PERMANENTLY DESTROY all key material on${NC}"
echo -e "${RED}  this machine. There is no undo.${NC}"
echo ""

# =============================================================
# === PRE-WIPE SAFETY CHECKLIST ===
# =============================================================
# Before destroying anything, confirm the user has completed all
# backups. Each item maps to a concrete step in the workflow:
#
#   1. YubiKeys — script 07 must have run successfully 3 times.
#   2. LUKS USB #1 — first encrypted offline backup.
#   3. LUKS USB #2 — second encrypted offline backup (different location).
#   4. Paper backup — printed hex key on paper for disaster recovery.
#   5. Public key — copied to a USB for use on the daily machine.
#   6. Fingerprint — written down for future identity verification.
#   7. Key summary — reviewed in script 08 before wiping.
#
# If fewer than all 7 are confirmed, the script warns and requires
# the user to explicitly type "FORCE" to override — not just press
# Enter. This prevents accidental wipes from lazy confirmations.
# =============================================================

# --- Interactive checklist ---
echo -e "${BOLD}  CHECKLIST — confirm each item:${NC}"
echo ""

# CHECKS counts how many items the user confirmed with 'y'.
CHECKS=0

read -p "  ✓ All 3 YubiKeys loaded and verified? (y/n): " C1
[ "$C1" = "y" ] && CHECKS=$((CHECKS + 1))

read -p "  ✓ LUKS backup USB #1 created and verified? (y/n): " C2
[ "$C2" = "y" ] && CHECKS=$((CHECKS + 1))

read -p "  ✓ LUKS backup USB #2 created and verified? (y/n): " C3
[ "$C3" = "y" ] && CHECKS=$((CHECKS + 1))

read -p "  ✓ Paper backup copied to USB for printing? (y/n): " C4
[ "$C4" = "y" ] && CHECKS=$((CHECKS + 1))

read -p "  ✓ Public key copied to USB for daily machine? (y/n): " C5
[ "$C5" = "y" ] && CHECKS=$((CHECKS + 1))

read -p "  ✓ Fingerprint written down or photographed? (y/n): " C6
[ "$C6" = "y" ] && CHECKS=$((CHECKS + 1))

read -p "  ✓ Key summary reviewed (script 08)? (y/n): " C7
[ "$C7" = "y" ] && CHECKS=$((CHECKS + 1))

echo ""

# ============================================================
# === INCOMPLETE CHECKLIST GUARD ===
# ============================================================
# If any items are unchecked, block the wipe unless the user
# deliberately types "FORCE". This is intentionally case-sensitive
# and not a simple y/n — it forces a conscious override decision,
# not an accidental keypress. Incomplete backups mean data loss.
# ============================================================
if [ "$CHECKS" -lt 7 ]; then
    echo -e "${RED}  Only $CHECKS/7 items confirmed.${NC}"
    echo ""
    echo "  It is STRONGLY recommended to complete all items"
    echo "  before cleanup. Once wiped, you cannot recover keys"
    echo "  from this machine."
    echo ""
    # Requiring the word "FORCE" (all caps) is deliberate — it cannot
    # be triggered by accidentally pressing Enter or typing 'y'.
    read -p "  Proceed anyway? (type 'FORCE' to continue): " FORCE
    if [ "$FORCE" != "FORCE" ]; then
        echo "  Aborted. Complete the checklist and re-run."
        exit 1
    fi
fi

# ============================================================
# === FINAL TYPED CONFIRMATION ===
# ============================================================
# Even with a complete checklist, require the user to type "WIPE"
# before any destructive action begins. This is the last chance
# to abort. No key material is touched until this passes.
# ============================================================
echo -e "${YELLOW}  Final confirmation...${NC}"
read -p "  Type 'WIPE' to permanently destroy all key material: " WIPE_CONFIRM
if [ "$WIPE_CONFIRM" != "WIPE" ]; then
    echo "  Aborted."
    exit 1
fi

echo ""

# =============================================================
# WIPE 1 OF 3: /tmp/gpg-export
# =============================================================
# This directory contains all exports from the Tails session:
#   master-secret-key.asc, subkeys-secret.asc, public-key.asc,
#   revocation-cert.asc, gnupg-full-backup/, PAPER-BACKUP*.
#
# shred flags used:
#   -v  verbose: print what is being overwritten
#   -f  force: change permissions if needed to allow overwrite
#   -z  zero: add a final pass of zeros to hide shredding
#   -n 3: overwrite 3 times before zeroing (default is 3)
#
# The || fallback to -delete handles rare cases where shred
# fails (e.g., on certain filesystems). rm -rf removes the
# now-empty directory structure.
# =============================================================
echo -e "${YELLOW}[1/3] Wiping /tmp/gpg-export...${NC}"
if [ -d /tmp/gpg-export ]; then
    # Shred every file inside the directory (not directories themselves,
    # which shred cannot handle — find -type f targets only files).
    find /tmp/gpg-export -type f -exec shred -vfz -n 3 {} \; 2>/dev/null || \
    find /tmp/gpg-export -type f -delete 2>/dev/null
    # Remove the now-empty directory tree.
    rm -rf /tmp/gpg-export
    echo -e "${GREEN}  ✓ Export directory destroyed${NC}"
else
    echo "  (not found — already clean)"
fi

# =============================================================
# WIPE 2 OF 3: ~/.gnupg
# =============================================================
# This directory is the GnuPG home: it contains the keybox
# (pubring.kbx), trust database (trustdb.gpg), private key store
# (private-keys-v1.d/), and agent configuration. After the
# YubiKey transfers, the private-keys-v1.d/ files hold stubs
# pointing to the YubiKeys — but earlier in the session they
# held actual private key material.
#
# We shred files first (cryptographic overwrite), then remove
# the directory. The || true prevents set -e from aborting if
# shred fails on any particular file (e.g., sockets or fifos).
# =============================================================
echo -e "${YELLOW}[2/3] Wiping ~/.gnupg...${NC}"
if [ -d ~/.gnupg ]; then
    # Shred every file in the gnupg directory tree before deletion.
    # This overwrites file contents so forensic recovery is prevented.
    find ~/.gnupg -type f -exec shred -vfz -n 3 {} \; 2>/dev/null || true
    rm -rf ~/.gnupg
    echo -e "${GREEN}  ✓ GnuPG directory destroyed${NC}"
else
    echo "  (not found — already clean)"
fi

# =============================================================
# WIPE 3 OF 3: SCAN FOR STRAY KEY FILES
# =============================================================
# Even with careful scripting, stray .asc or .gpg files can end
# up in /tmp or /home if the user manually copied files, ran
# standalone gpg commands, or used file managers.
#
# This scan looks for:
#   *.asc       — ASCII-armored GPG exports
#   *.gpg       — binary GPG files
#   paperkey*   — paperkey output files
#   PAPER-BACKUP* — paper backup files from script 04
#
# -maxdepth 3 limits the search to 3 directory levels deep to
# avoid scanning the entire filesystem (which would be slow).
# The 2>/dev/null suppresses "permission denied" errors from
# directories the Tails user cannot read.
# =============================================================
echo -e "${YELLOW}[3/3] Scanning for stray key material...${NC}"
STRAYS=$(find /tmp /home -maxdepth 3 \( -name "*.asc" -o -name "*.gpg" -o -name "paperkey*" -o -name "PAPER-BACKUP*" \) 2>/dev/null || true)
if [ -n "$STRAYS" ]; then
    echo "  Found stray files:"
    echo "$STRAYS" | while read -r f; do
        echo "    Shredding: $f"
        # Shred each stray file individually, falling back to plain rm
        # if shred fails (e.g., on a read-only or network filesystem).
        shred -vfz -n 3 "$f" 2>/dev/null || rm -f "$f"
    done
    echo -e "${GREEN}  ✓ Stray files destroyed${NC}"
else
    echo -e "${GREEN}  ✓ No stray files found${NC}"
fi

# =============================================================
# DONE — SHUTDOWN INSTRUCTIONS
# =============================================================
# Tails is specifically designed to leave no trace after shutdown:
# it overwrites RAM on power-off using the 'memory-erasure' service.
# The user must physically remove the Tails USB after the machine
# powers off — not before — to ensure the shutdown completes fully.
# =============================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  CLEANUP COMPLETE                                      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  All key material has been destroyed on this machine."
echo ""
echo "  Shut down Tails now:"
echo "    sudo shutdown -h now"
echo ""
# Tails overwrites RAM on shutdown via the 'tails-shutdown-on-media-removal'
# and 'tails-memory-erasure' systemd services. This prevents cold-boot
# attacks where RAM contents are read after a forced reboot.
echo "  Tails will automatically overwrite RAM on shutdown."
echo "  Remove the Tails USB after the machine powers off."
echo ""
echo "  On your daily machine, run:"
echo "    bash gpg-kit/scripts/10-daily-machine-setup.sh"
echo ""
