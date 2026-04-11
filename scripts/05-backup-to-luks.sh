#!/bin/bash
# =============================================================
# 05 — BACKUP TO LUKS-ENCRYPTED USB
# =============================================================
# Formats a USB drive with LUKS2 encryption and copies all
# key material onto it. Run TWICE for two separate backup USBs.
#
# USAGE:
#   bash .../scripts/05-backup-to-luks.sh
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
RED='\033[0;31m'    # Errors, critical warnings, destruction notices
GREEN='\033[0;32m'  # Success confirmations
YELLOW='\033[1;33m' # Step headings and prompts
CYAN='\033[0;36m'   # Informational notes
BOLD='\033[1m'      # Section headers
NC='\033[0m'        # Reset to default terminal color

# ============================================================
# === EXPORT DIRECTORY ===
# ============================================================
# This is where all key files were placed by script 04.
# The script will verify this directory contains the expected
# files before proceeding with any destructive disk operations.
EXPORT_DIR="/tmp/gpg-export"

# ============================================================
# === HEADER DISPLAY ===
# ============================================================
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         05 — LUKS ENCRYPTED USB BACKUP                 ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === PRE-FLIGHT CHECK: VERIFY EXPORTS EXIST ===
# ============================================================
# Before doing anything destructive (wiping a USB drive), confirm
# that the key files we want to copy actually exist. If script 04
# was never run, or /tmp was cleared, we abort here rather than
# creating an encrypted drive with no content.
# --- Verify export exists ---
if [ ! -f "$EXPORT_DIR/master-secret-key.asc" ]; then
    echo -e "${RED}  No exported keys found in $EXPORT_DIR${NC}"
    echo "  Run 04-export-keys.sh first."
    exit 1
fi

# ============================================================
# === STEP 1: CHOOSE WHICH BACKUP THIS IS ===
# ============================================================
# This script is designed to be run TWICE — once for each of two
# separate USB drives that will be stored in different physical
# locations. Having two copies protects against:
#   - USB failure (one copy becomes unreadable)
#   - Physical disaster (fire, flood) at one location
#   - Theft of one location
#
# The two drives get different filesystem labels so they can be
# distinguished even if the physical labels wear off.
#   HOME:    stored at home in a safe, lockbox, or fireproof box
#   OFFSITE: stored at a bank safe deposit box, trusted family
#            member's home, or any location geographically separate
#            from the home backup
# --- Which backup is this? ---
echo -e "${YELLOW}Which backup USB is this?${NC}"
echo ""
echo "  1. FIRST backup  — will be stored at home (safe/lockbox)"
echo "  2. SECOND backup — will be stored offsite (bank/trusted person)"
echo ""
read -p "  Select (1/2): " BACKUP_NUM
echo ""

# Set the filesystem label based on which backup this is.
# The label appears when the drive is mounted and helps identify it.
case $BACKUP_NUM in
    1) LABEL="GPG-BACKUP-HOME" ;;
    2) LABEL="GPG-BACKUP-OFFSITE" ;;
    *) echo "Invalid selection."; exit 1 ;;
esac

# ============================================================
# === STEP 2: IDENTIFY THE TARGET USB DEVICE ===
# ============================================================
# We ask the user to physically insert the USB drive BEFORE showing
# the device list. This way the new device will appear in lsblk output
# and be easy to spot (it wasn't there before insertion).
#
# IMPORTANT: Choosing the wrong device here will PERMANENTLY DESTROY
# data on that device. There is no undo. Read the lsblk output very
# carefully before entering the device name.
# --- Identify USB ---
echo -e "${YELLOW}Insert your backup USB drive now.${NC}"
read -p "  Press Enter when inserted..."
echo ""
echo -e "${CYAN}Current block devices:${NC}"
echo ""

# lsblk displays block devices in a tree format.
# -o NAME,SIZE,TYPE,LABEL,MOUNTPOINT shows only the most useful columns:
#   NAME        : device name (sda, sdb, sdc, etc.)
#   SIZE        : storage capacity
#   TYPE        : disk, part (partition), or rom
#   LABEL       : filesystem label if set
#   MOUNTPOINT  : where it is currently mounted (blank if not mounted)
# Use this output to identify your backup USB by its size and label.
lsblk -o NAME,SIZE,TYPE,LABEL,MOUNTPOINT
echo ""

# The user enters just the device name (e.g., "sdb"), not the full path.
# We prepend /dev/ ourselves to form the block device path.
read -p "  Enter the DEVICE NAME for your backup USB (e.g., sdb): " DEV_NAME
DEVICE="/dev/$DEV_NAME"

# Sanity check: confirm the device actually exists as a block device.
# `-b` tests whether the path is a block device (disk/partition).
# If not, the user entered a wrong name and we abort before any harm is done.
if [ ! -b "$DEVICE" ]; then
    echo -e "${RED}  Device $DEVICE does not exist.${NC}"
    exit 1
fi

# ============================================================
# === DESTRUCTION WARNING AND CONFIRMATION ===
# ============================================================
# === WARNING: IRREVERSIBLE DATA DESTRUCTION ===
# Everything on the selected device will be permanently erased.
# We require the user to type the word "YES" in uppercase to confirm.
# A simple "y" or Enter press is NOT accepted — this forces deliberate,
# conscious confirmation of a destructive action.
echo ""
echo -e "${RED}  ╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}  ║  ALL DATA ON $DEVICE WILL BE PERMANENTLY ERASED  ║${NC}"
echo -e "${RED}  ╚═══════════════════════════════════════════════════╝${NC}"
echo ""
read -p "  Type 'YES' to confirm destruction of $DEVICE: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "  Aborted."
    exit 1
fi

# ============================================================
# === STEP 3: WIPE AND PARTITION THE DEVICE ===
# ============================================================
# We start from a completely clean slate by wiping all existing
# partition table signatures and filesystem metadata, then create
# a fresh partition table with a single partition.
# --- Wipe and partition ---
echo ""
echo -e "${YELLOW}[1/5] Wiping $DEVICE...${NC}"

# wipefs removes filesystem and partition table signatures from the device.
# `-a` means "wipe all detected signatures." This ensures LUKS format
# later starts from a clean state with no leftover metadata.
sudo wipefs -a "$DEVICE"

# Create a new MBR (DOS) partition table with a single primary partition
# using fdisk in non-interactive mode. The commands piped to fdisk are:
#   o  : create a new empty MBR partition table
#   n  : add a new partition
#   p  : primary partition type
#   1  : partition number 1
#   (blank): first sector — default (start of disk)
#   (blank): last sector — default (end of disk, use all space)
#   w  : write the partition table to disk and exit
# `2>/dev/null` suppresses informational output from fdisk.
# `|| true` prevents the script from aborting if fdisk exits non-zero
# (which it does on some systems even on success).
echo -e "o\nn\np\n1\n\n\nw" | sudo fdisk "$DEVICE" 2>/dev/null || true

# Give the kernel time to re-read the new partition table.
# Without this sleep, the partition device node (/dev/sdbX) may not
# exist yet when we try to use it in the next step.
sleep 2

# Determine the partition device path. On most systems it will be
# /dev/sdb1, but some USB drives or setups may use /dev/sdb directly.
# Detect partition
PARTITION="${DEVICE}1"
if [ ! -b "$PARTITION" ]; then
    # Fallback: if the numbered partition doesn't exist, use the whole device.
    # This handles edge cases with some USB controllers or card readers.
    PARTITION="$DEVICE"
fi
echo -e "${GREEN}  ✓ Partitioned: $PARTITION${NC}"

# ============================================================
# === STEP 4: CREATE LUKS2 ENCRYPTED CONTAINER ===
# ============================================================
# LUKS (Linux Unified Key Setup) is the standard Linux disk encryption
# format. LUKS2 is the modern version with stronger defaults and
# better header protection than LUKS1.
#
# WHY encrypt the backup: your master secret key is on this drive.
# If someone finds or steals this USB, the LUKS encryption is the
# only thing standing between them and your key. The encryption is
# only as strong as your passphrase — choose a strong one.
#
# PARAMETERS EXPLAINED:
#   --type luks2           : use LUKS version 2 (more secure than v1)
#   --cipher aes-xts-plain64: AES in XTS mode — the industry standard
#                            for disk encryption, used by FileVault,
#                            BitLocker, VeraCrypt, etc.
#   --key-size 512         : 512-bit key for AES-XTS. Note: XTS splits
#                            this into two 256-bit halves, giving you
#                            effectively AES-256 for data encryption.
#   --hash sha512          : SHA-512 is used to derive the actual
#                            encryption key from your passphrase (PBKDF2).
#                            SHA-512 is stronger than SHA-256 for this use.
#   --iter-time 5000       : PBKDF2 will iterate for 5000 milliseconds
#                            when processing your passphrase. This makes
#                            brute-force attacks ~5 seconds per attempt
#                            even on dedicated hardware. Higher is more
#                            secure but slows down unlock.
#
# After running this command, GPG will prompt you to:
#   1. Type "YES" to confirm overwriting the partition
#   2. Enter a new passphrase for this USB drive
#   3. Confirm the passphrase
#
# RECOMMENDATION: Use a different passphrase than your GPG key passphrase.
# This way, an attacker who learns one passphrase cannot use both.
# --- LUKS format ---
echo ""
echo -e "${YELLOW}[2/5] LUKS2 encryption setup...${NC}"
echo ""
echo -e "${CYAN}  Choose a strong passphrase for this backup USB.${NC}"
echo -e "${CYAN}  This can be different from your GPG passphrase.${NC}"
echo ""

sudo cryptsetup luksFormat --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    "$PARTITION"

echo -e "${GREEN}  ✓ LUKS2 encrypted${NC}"

# ============================================================
# === STEP 5: OPEN, FORMAT, AND MOUNT THE ENCRYPTED VOLUME ===
# ============================================================
# Now that LUKS is set up, we open (unlock) the container, create
# a filesystem inside it, and mount it so we can copy files to it.
# --- Open, format, mount ---
echo ""
echo -e "${YELLOW}[3/5] Creating filesystem...${NC}"
echo ""

# cryptsetup luksOpen decrypts the LUKS container and creates a
# virtual block device at /dev/mapper/gpg-backup. All reads and
# writes to that path are transparently encrypted/decrypted.
# You will be prompted for the LUKS passphrase you just set.
echo -e "${CYAN}  Enter the LUKS passphrase you just set:${NC}"
sudo cryptsetup luksOpen "$PARTITION" gpg-backup

# Create an ext4 filesystem inside the now-open encrypted container.
# ext4 is the standard Linux filesystem — reliable, journaled, and
# well-supported in Tails. `-L "$LABEL"` sets the human-readable
# volume label visible in `lsblk` output.
sudo mkfs.ext4 -L "$LABEL" /dev/mapper/gpg-backup

# Mount the filesystem at /mnt — the standard temporary mount point.
# After mounting, /mnt behaves like a normal directory and we can
# copy files to it as usual.
sudo mount /dev/mapper/gpg-backup /mnt
echo -e "${GREEN}  ✓ Mounted at /mnt${NC}"

# ============================================================
# === STEP 6: COPY KEY MATERIAL TO THE ENCRYPTED DRIVE ===
# ============================================================
# Copy every key-related file from /tmp/gpg-export/ into a
# dedicated subdirectory on the encrypted USB. We use a subdirectory
# (gpg-keys/) so the root of the drive can hold a README too.
# --- Copy files ---
echo ""
echo -e "${YELLOW}[4/5] Copying key material...${NC}"
sudo mkdir -p /mnt/gpg-keys

# Copy each key file individually (rather than using a glob) so that
# if any specific file is missing, we get a clear error message
# rather than a silent partial copy.
sudo cp "$EXPORT_DIR/master-secret-key.asc" /mnt/gpg-keys/
sudo cp "$EXPORT_DIR/subkeys-secret.asc" /mnt/gpg-keys/
sudo cp "$EXPORT_DIR/public-key.asc" /mnt/gpg-keys/
sudo cp "$EXPORT_DIR/revocation-cert.asc" /mnt/gpg-keys/

# Copy the entire gnupg-full-backup directory recursively.
# This preserves the complete GPG home directory snapshot.
sudo cp -r "$EXPORT_DIR/gnupg-full-backup" /mnt/gpg-keys/

# ============================================================
# === WRITE RESTORE INSTRUCTIONS TO THE USB ===
# ============================================================
# Write a README directly on the drive explaining what it contains
# and how to restore from it. This is critically important:
#   - You may not remember the restore procedure years from now
#   - Someone trusted who needs to recover the key on your behalf
#     (e.g., in case of your death or incapacity) will need these steps
#   - The instructions are stored WITH the backup, so they're always
#     accessible when the drive is
#
# We use a heredoc (<<'INNEREOF'...INNEREOF) to write multi-line
# content. Note the outer `sudo bash -c "..."` is needed because
# the redirect (>) must run as root to write to /mnt which is
# owned by root after mounting.
# Write README with restore instructions
sudo bash -c "cat > /mnt/gpg-keys/README.txt << 'INNEREOF'
GPG MASTER KEY BACKUP
=====================
Label: $LABEL
Created: $(date -u +'%Y-%m-%d %H:%M UTC')

Contents:
  master-secret-key.asc  — Full master + subkeys (SECRET)
  subkeys-secret.asc     — Subkeys only (SECRET)
  public-key.asc         — Public key (SAFE to share)
  revocation-cert.asc    — Revocation cert (DANGEROUS — use with extreme care)
  gnupg-full-backup/     — Complete ~/.gnupg snapshot

RESTORE PROCEDURE:
  1. Boot Tails OS (air-gapped, no network)
  2. Decrypt: sudo cryptsetup luksOpen /dev/sdX1 gpg-backup
  3. Mount:   sudo mount /dev/mapper/gpg-backup /mnt
  4. Import:  gpg --import /mnt/gpg-keys/master-secret-key.asc
  5. Trust:   gpg --edit-key KEYID → trust → 5 (ultimate) → save
  6. Work:    extend expiry, revoke subkeys, generate new ones
  7. Export updated public key and distribute
  8. Unmount: sudo umount /mnt && sudo cryptsetup luksClose gpg-backup

NEVER plug this USB into a networked computer.
INNEREOF"

echo -e "${GREEN}  ✓ All files copied${NC}"

# ============================================================
# === STEP 7: VERIFY THE BACKUP ===
# ============================================================
# Confirming that the data on the drive is readable is just as
# important as copying it. A backup you cannot restore from is
# not a backup at all.
#
# We use `gpg --dry-run --import` which simulates an import without
# actually changing the keyring. If GPG can parse the file and
# reports "secret key" in its output, we know the file is intact
# and readable.
# --- Verify ---
echo ""
echo -e "${YELLOW}[5/5] Verifying backup integrity...${NC}"
echo ""
echo "  Files on drive:"

# List files on the drive with sizes to confirm everything was copied.
sudo ls -lh /mnt/gpg-keys/*.asc
echo ""

echo "  Testing master key import (dry run)..."

# --dry-run : parse and validate the key file without actually importing it.
# This tests that the file is not corrupted without touching the live keyring.
# We capture the first 5 lines of output to check for success indicators.
VERIFY_OUT=$(sudo gpg --dry-run --import /mnt/gpg-keys/master-secret-key.asc 2>&1 | head -5)
echo "  $VERIFY_OUT"
echo ""

# Check if the output contains "secret key" — GPG's success message
# when it finds importable secret key material in the file.
# `-qi` means case-insensitive, quiet (no output, just exit code).
if echo "$VERIFY_OUT" | grep -qi "secret key"; then
    echo -e "${GREEN}  ✓ Backup verified — master key is readable${NC}"
else
    # Verification was inconclusive — not necessarily a failure, but
    # the user should check manually before trusting this backup.
    echo -e "${RED}  ⚠  Verification unclear. Check manually before relying on this backup.${NC}"
fi

# ============================================================
# === STEP 8: UNMOUNT AND LOCK THE ENCRYPTED DRIVE ===
# ============================================================
# Always unmount and close the LUKS container before physically
# removing the USB drive. Removing without unmounting can corrupt
# the filesystem (the filesystem may have unflushed writes in cache).
# Closing the LUKS container destroys the in-memory decryption key,
# re-locking the data.
# --- Unmount ---
echo ""

# umount flushes all pending writes and unmounts the filesystem.
sudo umount /mnt

# luksClose tears down the /dev/mapper/gpg-backup virtual device
# and securely wipes the in-memory encryption key. After this, the
# drive is fully locked and unreadable without the passphrase.
sudo cryptsetup luksClose gpg-backup
echo -e "${GREEN}  ✓ Drive unmounted and locked${NC}"

# ============================================================
# === SUMMARY AND NEXT STEPS ===
# ============================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  BACKUP #$BACKUP_NUM COMPLETE — $LABEL                   ${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Give different next-step instructions depending on whether this
# was the first or second backup. After both backups are done,
# the user proceeds to the paper backup script.
if [ "$BACKUP_NUM" = "1" ]; then
    echo "  → Remove this USB. Label it: HOME BACKUP"
    echo "  → Insert your SECOND backup USB"
    echo "  → Run this script again"
    echo ""
    echo "  Next: bash .../scripts/05-backup-to-luks.sh  (second run)"
else
    echo "  → Remove this USB. Label it: OFFSITE BACKUP"
    echo "  → Store at a different physical location from USB #1"
    echo ""
    echo "  Next: bash .../scripts/06-paper-backup.sh"
fi
echo ""
