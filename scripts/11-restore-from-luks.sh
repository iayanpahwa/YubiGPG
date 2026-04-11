#!/bin/bash
# =============================================================
# 11 — RESTORE MASTER KEY FROM LUKS BACKUP
# =============================================================
# Use when you need to manage your keys in the future:
#   - Extend subkey expiry
#   - Revoke compromised subkeys
#   - Generate replacement subkeys
#   - Add a new email (UID)
#
# PREREQUISITES:
#   - Booted into Tails (air-gapped)
#   - Run 01-tails-setup.sh first
#   - Have your LUKS-encrypted backup USB
#
# USAGE:
#   bash .../scripts/11-restore-from-luks.sh
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
echo -e "${BOLD}║   11 — RESTORE MASTER KEY FROM LUKS BACKUP             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================
# === AIR GAP VERIFICATION ===
# =============================================================
# Before restoring secret key material, confirm the network is
# fully disabled. A live network connection during key operations
# is a serious security risk — key material could be exfiltrated
# by malware, or the air-gap assumption would be broken.
#
# Tails creates internal virtual ethernet interfaces (veth-*)
# for its own networking between internal processes. These are
# NOT real network connections and must be excluded from the check.
# We also exclude docker, bridge (br-), and virbr interfaces which
# are virtual-only and carry no external traffic.
#
# If a real physical interface (e.g., eth0, wlan0) is found to
# be UP, we immediately block all wireless hardware via rfkill
# and stop NetworkManager to restore the air gap.
# =============================================================

# --- Verify air gap (ignore Tails internal veth-* interfaces) ---
REAL_IFACES=$(ip link show 2>/dev/null | grep "state UP" | grep -v -E "(^[0-9]+: lo:|veth-|docker|br-|virbr)" | awk -F': ' '{print $2}' | cut -d'@' -f1 || true)
if [ -n "$REAL_IFACES" ]; then
    echo -e "${RED}  ⚠  Physical network UP: $REAL_IFACES — disabling...${NC}"
    # rfkill block all disables all wireless radios (WiFi, Bluetooth, etc.)
    # at the kernel level — more reliable than ifdown for air-gapping.
    sudo rfkill block all 2>/dev/null || true
    # Stop NetworkManager to prevent it from re-enabling interfaces.
    sudo systemctl stop NetworkManager 2>/dev/null || true
fi
echo -e "${GREEN}  ✓ Air gap confirmed (Tails veth-* interfaces are normal)${NC}"
echo ""

# =============================================================
# === INSERT AND IDENTIFY THE LUKS USB ===
# =============================================================
# The backup USB is encrypted with LUKS (Linux Unified Key Setup).
# LUKS is a standard Linux disk encryption format — the entire
# partition is encrypted, and cryptsetup handles decryption.
#
# We use lsblk to show the user all available block devices so
# they can identify which device/partition is the backup USB.
# The user must enter just the partition name (e.g., sdb1), not
# the full path — we prepend /dev/ below.
# =============================================================

# --- Insert LUKS USB ---
echo -e "${CYAN}  Insert your LUKS backup USB drive.${NC}"
read -p "  Press Enter when ready..."
echo ""

# lsblk displays block devices in a tree format.
# -o NAME,SIZE,TYPE,LABEL,MOUNTPOINT shows the most useful columns
# for identifying the right device without overwhelming detail.
echo "  Block devices:"
lsblk -o NAME,SIZE,TYPE,LABEL,MOUNTPOINT
echo ""

read -p "  Enter the partition to decrypt (e.g., sdb1): " PART
PARTITION="/dev/$PART"

# Verify the entered partition path is actually a block device.
# -b tests for "is a block special file". Catches typos early.
if [ ! -b "$PARTITION" ]; then
    echo -e "${RED}  $PARTITION not found.${NC}"
    exit 1
fi

# =============================================================
# === DECRYPT AND MOUNT THE LUKS VOLUME ===
# =============================================================
# cryptsetup luksOpen decrypts the LUKS container and creates a
# virtual device at /dev/mapper/gpg-backup. The user is prompted
# for the LUKS passphrase (not the GPG passphrase — these are
# different). The passphrase decrypts the disk encryption key
# stored in the LUKS header.
#
# After decryption, we mount the filesystem inside the container
# at /mnt/gpg-backup, a temporary mount point created as needed.
# =============================================================

# --- Decrypt and mount ---
echo ""
echo -e "${YELLOW}  Decrypting LUKS volume...${NC}"
# luksOpen: prompts for passphrase, decrypts the LUKS header, and
# creates /dev/mapper/gpg-backup as the decrypted block device.
# 'gpg-backup' is the name we give to this opened LUKS volume —
# it can be any name, but must match the luksClose call below.
sudo cryptsetup luksOpen "$PARTITION" gpg-backup
# Create the mount point directory if it does not already exist.
sudo mkdir -p /mnt/gpg-backup
# Mount the decrypted filesystem. The filesystem type (ext4, etc.)
# is auto-detected by mount.
sudo mount /dev/mapper/gpg-backup /mnt/gpg-backup
echo -e "${GREEN}  ✓ Mounted at /mnt/gpg-backup${NC}"
echo ""

# =============================================================
# === LOCATE THE MASTER SECRET KEY FILE ===
# =============================================================
# The backup was created by script 05, which wrote files to a
# 'gpg-keys/' subdirectory inside the LUKS volume. We check
# both the subdirectory path and the root of the volume in case
# the user organized files differently when creating the backup.
#
# If auto-detection fails, the user is prompted to enter the
# full path manually so the script doesn't silently use the
# wrong file.
# =============================================================

# --- Find master key ---
echo "  Contents:"
# Show the gpg-keys/ subdirectory if it exists; fall back to root listing.
ls -la /mnt/gpg-backup/gpg-keys/ 2>/dev/null || ls -la /mnt/gpg-backup/
echo ""

MASTER_KEY=""
# Check the two most likely locations for master-secret-key.asc.
for p in "/mnt/gpg-backup/gpg-keys/master-secret-key.asc" "/mnt/gpg-backup/master-secret-key.asc"; do
    if [ -f "$p" ]; then
        MASTER_KEY="$p"
        break  # Stop at first match — don't import twice.
    fi
done

if [ -z "$MASTER_KEY" ]; then
    # Auto-detection failed. Ask the user to point us at the file.
    echo -e "${YELLOW}  Could not auto-detect master key file.${NC}"
    read -p "  Enter the full path to master-secret-key.asc: " MASTER_KEY
fi

if [ ! -f "$MASTER_KEY" ]; then
    echo -e "${RED}  File not found.${NC}"
    exit 1
fi

# =============================================================
# === IMPORT THE MASTER KEY ===
# =============================================================
# gpg --import reads the ASCII-armored key file and loads both
# the master private key and all subkeys into the local keyring.
# This is the full key — not stubs — so all key operations
# (including keytocard) will work correctly after this step.
#
# The imported key requires the GPG passphrase for any operation
# that uses the private key (signing, keytocard, etc.). The
# passphrase is NOT stored in the key file — it encrypts the
# private key material within the file.
# =============================================================

# --- Import ---
echo ""
echo -e "${YELLOW}  Importing master key...${NC}"
gpg --import "$MASTER_KEY"
echo ""

# Extract the key ID from the just-imported key for use in
# subsequent operations and to confirm the right key was imported.
KEYID=$(gpg --list-secret-keys --keyid-format 0xlong | grep "^sec " | head -1 | awk '{print $2}' | cut -d'/' -f2)
echo -e "${GREEN}  ✓ Master key restored: $KEYID${NC}"
echo ""

# Display the full key structure — verify all 3 subkeys are present
# (they should be: the master-secret-key.asc backup was created
# BEFORE any keytocard runs).
echo "  Key structure:"
gpg --list-secret-keys --keyid-format 0xlong "$KEYID"
echo ""

# =============================================================
# === UNMOUNT OR KEEP MOUNTED ===
# =============================================================
# After importing the key, the LUKS USB is no longer needed
# UNLESS the user plans to immediately run script 12 (expiry
# management) and wants to export an updated public key back
# to the USB. In that case, keeping it mounted saves having to
# re-decrypt it later.
#
# If unmounting now: the LUKS volume is closed and the passphrase
# is no longer in memory. The USB can be safely removed.
#
# If keeping mounted: the decrypted volume stays accessible at
# /mnt/gpg-backup. The user should unmount it before shutting down.
# =============================================================

# --- Keep mounted? ---
read -p "  Unmount the backup USB now? (y/n): " UMOUNT
if [ "$UMOUNT" = "y" ]; then
    # umount removes the filesystem from the mount point.
    sudo umount /mnt/gpg-backup
    # luksClose destroys the decrypted /dev/mapper/gpg-backup device,
    # re-encrypting access to the physical partition. The USB is now
    # safe to remove.
    sudo cryptsetup luksClose gpg-backup
    echo -e "${GREEN}  ✓ Backup USB unmounted and locked${NC}"
else
    echo "  USB remains at /mnt/gpg-backup"
    echo "  Unmount later: sudo umount /mnt/gpg-backup && sudo cryptsetup luksClose gpg-backup"
fi

# =============================================================
# DONE — NEXT STEPS
# =============================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  RESTORE COMPLETE — Key: $KEYID  ${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  You can now:"
echo "    • Manage expiry:   bash .../scripts/12-manage-expiry.sh"
echo "    • Edit key:        gpg --expert --edit-key $KEYID"
echo "    • Transfer to YubiKey: bash .../scripts/07-yubikey-transfer.sh"
echo ""
