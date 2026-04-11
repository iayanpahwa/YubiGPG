#!/bin/bash
# =============================================================
# 06 — PAPER BACKUP (for physical print)
# =============================================================
# Creates a paperkey backup of your master key. The output is
# saved to the Tails machine, then you copy it to a USB drive
# for printing on a separate computer.
#
# DO NOT print directly from Tails — printers can cache data
# and a network printer would break your air gap.
#
# RECOVERY: This script also shows full paper recovery steps.
#
# NOTE: May need to briefly enable networking to install
#       'paperkey' package. Script handles this safely.
#
# USAGE:
#   bash .../scripts/06-paper-backup.sh
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
# === EXPORT DIRECTORY ===
# ============================================================
# The same staging area used by all previous scripts.
# paperkey-raw.txt and the final printable document will be
# written here alongside the other key files.
EXPORT_DIR="/tmp/gpg-export"

# ============================================================
# === HEADER DISPLAY ===
# ============================================================
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         06 — PAPER BACKUP (Physical Print)             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === STEP 1: CHECK FOR PAPERKEY AND INSTALL IF NEEDED ===
# ============================================================
# 'paperkey' is a specialized tool that extracts the SECRET portion
# of a GPG key and encodes it as human-readable hexadecimal.
#
# WHY use paperkey instead of just printing the .asc file:
#   - The .asc export file contains both the public and secret parts.
#     Paperkey strips the public portion (which you can always recover
#     from a keyserver) and outputs ONLY the secret bytes.
#   - This makes the printed output shorter (fewer pages, less to type
#     back if you ever need to restore) and more focused.
#   - Recovery from paper backup requires combining this output with the
#     public key — see the recovery instructions embedded in the
#     generated document.
#
# Tails does NOT include paperkey by default, so we may need to
# install it. The only way to install packages in Tails is via apt,
# which requires internet access. We handle this by briefly re-enabling
# the network, installing, and then disabling it again.
#
# SECURITY NOTE: Re-enabling the network here is a temporary,
# controlled exception to the air gap. The key material is still in
# /tmp and has NOT been exported to the LUKS USBs yet at this stage
# in the workflow — wait, actually by now script 05 has already backed
# up the keys. The risk of this brief network exposure is low because:
#   1. We immediately disable networking after install
#   2. No key material is transmitted over the network
#   3. apt only downloads from configured Debian/Tails repos over Tor
# --- Check for paperkey ---
if ! command -v paperkey &>/dev/null; then
    echo -e "${YELLOW}  'paperkey' is not installed on this Tails session.${NC}"
    echo ""
    echo "  To install it, I need to briefly enable networking."
    echo "  The network will be disabled immediately after install."
    echo ""
    echo "  1. Enable network, install paperkey, disable network"
    echo "  2. Skip paper backup for now"
    echo ""
    read -p "  Choose (1/2): " PKG_CHOICE

    if [ "$PKG_CHOICE" = "1" ]; then
        echo ""

        # Re-enable wireless radios that were blocked in script 01.
        # `rfkill unblock all` lifts the software kill switch.
        echo -e "${YELLOW}  Enabling networking...${NC}"
        sudo rfkill unblock all 2>/dev/null || true

        # Start NetworkManager to manage the network connection.
        sudo systemctl start NetworkManager 2>/dev/null || true
        echo ""

        # Ask the user to connect — we can't do this automatically.
        # They need to connect via the Tails network manager applet
        # in the taskbar, or plug in Ethernet.
        echo -e "${CYAN}  Connect to WiFi or plug in Ethernet now.${NC}"
        read -p "  Press Enter once you have internet..."
        echo ""

        # Install paperkey quietly (-qq suppresses most output).
        # `apt update` refreshes the package list first so we get
        # the latest version.
        echo "  Installing paperkey..."
        sudo apt update -qq && sudo apt install -y -qq paperkey
        echo ""

        # === IMPORTANT: Restore the air gap immediately after install ===
        # Stop NetworkManager first, then block all radios.
        # The sleep gives NetworkManager time to complete shutdown before
        # rfkill takes effect.
        echo -e "${YELLOW}  Disabling networking...${NC}"
        sudo systemctl stop NetworkManager 2>/dev/null || true
        sudo rfkill block all 2>/dev/null || true
        sleep 2  # Wait for interfaces to fully come down
        echo -e "${GREEN}  ✓ Network disabled. Air gap restored.${NC}"
    else
        # User chose to skip — exit cleanly without an error code.
        echo "  Skipping paper backup."
        exit 0
    fi
fi

echo ""

# ============================================================
# === STEP 2: RESTART GPG-AGENT ===
# ============================================================
# Toggling the network (rfkill, NetworkManager start/stop) can
# disrupt the gpg-agent process, causing GPG key operations to
# fail with confusing "no secret key" or connection errors.
# We kill and restart the agent as a precaution before doing
# anything GPG-related.
#
# `gpgconf --kill gpg-agent` : sends a shutdown signal to the agent.
#                              `|| true` so we don't abort if it
#                              wasn't running.
# `sleep 1`                  : brief pause to ensure the old process
#                              is fully gone before we start a new one.
# `gpgconf --launch gpg-agent`: starts a fresh agent process.
# --- Restart gpg-agent (network toggle can disrupt it) ---
echo "  Restarting gpg-agent (may have been disrupted by network toggle)..."
gpgconf --kill gpg-agent 2>/dev/null || true
sleep 1
gpgconf --launch gpg-agent 2>/dev/null || true
echo ""

# ============================================================
# === STEP 3: IDENTIFY THE KEY ===
# ============================================================
# Read the saved key ID and verify the secret key is available
# in the keyring before proceeding.
# --- Get key ID ---
DEFAULT_KEYID=""
if [ -f "$EXPORT_DIR/keyid.txt" ]; then
    DEFAULT_KEYID=$(cat "$EXPORT_DIR/keyid.txt")
fi

# Check what secret keys are currently in the keyring.
# This can come back empty if gpg-agent was reset and the keyring
# was not preserved (see the re-import logic below).
# Show current secret keys
echo -e "${CYAN}  Checking for secret keys in keyring...${NC}"
echo ""
SECRET_LIST=$(gpg --list-secret-keys --keyid-format 0xlong 2>/dev/null)

# ============================================================
# === HANDLE MISSING SECRET KEYS (AUTO-REIMPORT) ===
# ============================================================
# After the paperkey installation (which involves restarting
# services and temporarily disabling gpg-agent), the secret
# keys may no longer be visible in the keyring. This does NOT
# mean the keys are lost — they are still safely stored in
# /tmp/gpg-export/master-secret-key.asc from script 04.
# We re-import them automatically here.
if [ -z "$SECRET_LIST" ]; then
    echo -e "${YELLOW}  No secret keys found in keyring.${NC}"
    echo ""
    echo "  This can happen if gpg-agent restarted during package install."
    echo "  Re-importing from the export backup..."
    echo ""

    if [ -f "$EXPORT_DIR/master-secret-key.asc" ]; then
        # Re-import the master secret key from the file we exported in script 04.
        # `grep -E "(secret|import)"` filters gpg output to show only the
        # relevant lines confirming what was imported.
        # `|| true` ensures the script continues even if grep finds no matches.
        gpg --import "$EXPORT_DIR/master-secret-key.asc" 2>&1 | grep -E "(secret|import)" || true
        echo ""
        # Refresh the list after re-import for the display below.
        SECRET_LIST=$(gpg --list-secret-keys --keyid-format 0xlong 2>/dev/null)
    else
        echo -e "${RED}  Cannot find $EXPORT_DIR/master-secret-key.asc${NC}"
        echo "  You need to either:"
        echo "    a) Run 04-export-keys.sh first, or"
        echo "    b) Restore from your LUKS backup USB"
        exit 1
    fi
fi

# Display the secret keys so the user can visually confirm the right one.
# `head -20` limits output in case there are many keys.
echo "$SECRET_LIST" | head -20
echo ""

# Prompt for the key ID, using the saved default if available.
if [ -n "$DEFAULT_KEYID" ]; then
    read -p "  Key ID [$DEFAULT_KEYID]: " KEYID
    KEYID=${KEYID:-$DEFAULT_KEYID}
else
    read -p "  Enter your key ID: " KEYID
fi

# ============================================================
# === STEP 4: VERIFY SECRET KEY IS EXPORTABLE ===
# ============================================================
# After a `keytocard` operation (loading keys onto a YubiKey),
# GPG replaces the local secret key with a "stub" that points to
# the YubiKey. The stub shows up in `--list-secret-keys` but
# contains no actual secret material — just a reference.
#
# paperkey needs the REAL secret bytes, not a stub. We check by
# actually exporting and counting the bytes. A stub export produces
# almost nothing (under 100 bytes), while a real key export is
# several hundred bytes minimum.
#
# This check is important if you have previously run script 07
# (keytocard) and are now coming back to do the paper backup.
# In that case, the full secret key must be re-imported from the
# LUKS backup USB first.
# --- Verify the key actually has secret material ---
echo ""
echo -e "${CYAN}  Verifying secret key is exportable...${NC}"

# Export the secret key and count bytes. `wc -c` counts characters (bytes).
TEST_EXPORT=$(gpg --export-secret-keys "$KEYID" 2>/dev/null | wc -c)

# If the export is tiny (under 100 bytes), the key is a stub.
if [ "$TEST_EXPORT" -lt 100 ]; then
    echo -e "${YELLOW}  Key $KEYID has no exportable secret material.${NC}"
    echo ""
    echo "  This means the keyring has stubs (from keytocard) but not"
    echo "  the actual secret keys. Re-importing from backup..."
    echo ""

    # Delete the stub entry so we can import the real key in its place.
    # `--yes` suppresses the interactive confirmation prompt.
    # `|| true` prevents abort if the delete fails for any reason.
    # Delete stubs and re-import
    gpg --yes --delete-secret-and-public-keys "$KEYID" 2>/dev/null || true

    # Re-import the full key from the backup file created in script 04.
    gpg --import "$EXPORT_DIR/master-secret-key.asc" 2>&1 | grep -E "(secret|import)" || true
    echo ""

    # Re-verify after import — if it's still under 100 bytes, the backup
    # file itself may be corrupted or is from a post-keytocard state.
    # Re-verify
    TEST_EXPORT=$(gpg --export-secret-keys "$KEYID" 2>/dev/null | wc -c)
    if [ "$TEST_EXPORT" -lt 100 ]; then
        echo -e "${RED}  Still cannot export secret key.${NC}"
        echo "  The backup file may be corrupted or from after a keytocard."
        echo "  Try restoring from your LUKS backup USB instead."
        exit 1
    fi
fi
echo -e "${GREEN}  ✓ Secret key is present and exportable ($TEST_EXPORT bytes)${NC}"

echo ""

# ============================================================
# === STEP 5: GENERATE THE PAPERKEY OUTPUT ===
# ============================================================
# paperkey takes the binary secret key from GPG and outputs ONLY
# the secret key bytes as hexadecimal, one packet per line.
#
# HOW IT WORKS:
#   1. `gpg --export-secret-keys "$KEYID"` outputs the full secret
#      key in GPG's binary packet format (not ASCII-armored).
#   2. The pipe `|` feeds that binary stream directly to paperkey.
#   3. paperkey strips the public key material (which is recoverable
#      from a keyserver) and outputs only the secret bytes as hex.
#   4. `--output` writes the result to a file.
#
# WHY hex output: hexadecimal is unambiguous for manual transcription.
# Unlike base64, hex has no uppercase/lowercase ambiguity issues and
# is easier to verify visually. Each byte becomes exactly two characters.
#
# The raw output is a series of lines like:
#   1: 5B 3A 9F ... (packet header and data)
# --- Generate paperkey ---
echo -e "${YELLOW}Generating paperkey output...${NC}"
echo ""

gpg --export-secret-keys "$KEYID" | paperkey --output "$EXPORT_DIR/paperkey-raw.txt"

# Verify the output file is non-empty. An empty file would mean
# something went wrong with the pipe or paperkey execution.
# `-s` tests whether the file exists AND has a size greater than zero.
if [ ! -s "$EXPORT_DIR/paperkey-raw.txt" ]; then
    echo -e "${RED}  ✗ paperkey output is empty. Something went wrong.${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ Raw paperkey generated${NC}"
echo ""

# ============================================================
# === STEP 6: BUILD THE PRINTABLE DOCUMENT ===
# ============================================================
# We wrap the raw hex output in a human-readable document that includes:
#   - Key identification (fingerprint)
#   - Date created (for future reference)
#   - Complete recovery instructions (so the paper is self-contained)
#   - The hex data between clearly marked START/END markers
#   - A reminder about secure handling
#
# WHY a formatted document instead of just printing the raw hex:
#   - If you ever need to recover, you may be doing it years later
#     under stressful circumstances. Clear instructions matter.
#   - The fingerprint lets you verify which key this belongs to.
#   - The START/END markers make it unambiguous what to type when
#     manually re-entering data during recovery.
# --- Build printable document ---
echo -e "${YELLOW}Building printable document...${NC}"

# Get the key fingerprint — this is the 40-character hex fingerprint
# that uniquely identifies the key. We embed it in the document
# so the paper can be matched back to the correct key.
FINGERPRINT=$(gpg --fingerprint "$KEYID" 2>/dev/null)

# The `cat > file << HEADER ... HEADER` syntax writes a multi-line
# "here document" to the file. Variable substitution ($KEYID, $FINGERPRINT,
# etc.) happens inside the heredoc because HEADER is unquoted.
# `$(date -u ...)` is evaluated at write time to embed the current UTC timestamp.
cat > "$EXPORT_DIR/PAPER-BACKUP-PRINT-ME.txt" << HEADER
================================================================
       GPG MASTER KEY — PAPER BACKUP
================================================================

 STORE IN FIREPROOF SAFE OR BANK SAFE DEPOSIT BOX
 KEEP SEPARATE FROM USB BACKUPS AND PASSPHRASES

================================================================

Date created: $(date -u +'%Y-%m-%d %H:%M UTC')

KEY IDENTIFICATION:
$FINGERPRINT

================================================================
 RECOVERY FROM THIS PAPER BACKUP
================================================================

 To recover your secret key from this paper backup, you need:
   1. This paper printout
   2. Your PUBLIC key (from a keyserver, GitHub, or USB backup)
   3. Your GPG passphrase
   4. An air-gapped computer running Tails with 'paperkey' installed

 STEP-BY-STEP RECOVERY:

   A. Get your public key (on any networked machine):
      gpg --keyserver hkps://keys.openpgp.org --recv-keys $KEYID
      gpg --export $KEYID > public-key.gpg
      (copy public-key.gpg to a USB drive)

   B. Boot Tails (air-gapped). Install paperkey:
      (briefly enable network)
      sudo apt install paperkey
      (disable network)

   C. Type (or OCR scan) the hex data from this page into a file:
      nano paperkey-data.txt
      (type everything between START and END markers below)

   D. Reconstruct the secret key:
      paperkey --pubring public-key.gpg \\
               --secrets paperkey-data.txt \\
               --output recovered-secret-key.gpg

   E. Import into GPG:
      gpg --import recovered-secret-key.gpg

   F. Verify:
      gpg --list-secret-keys --keyid-format 0xlong

 The recovered key will have full master + subkey capabilities.
 You can then generate new subkeys, transfer to YubiKeys, etc.

================================================================
 SECRET KEY DATA — START
================================================================
HEADER

# Append the raw paperkey hex output after the header.
# The `cat >>` (double redirect) appends rather than overwriting.
# This joins the header text with the hex data in one file.
cat "$EXPORT_DIR/paperkey-raw.txt" >> "$EXPORT_DIR/PAPER-BACKUP-PRINT-ME.txt"

# Append the footer section after the hex data.
# Note: this heredoc uses 'FOOTER' (single-quoted) which prevents
# variable substitution inside it — intentional, since the footer
# contains no variables that need expanding.
cat >> "$EXPORT_DIR/PAPER-BACKUP-PRINT-ME.txt" << 'FOOTER'

================================================================
 SECRET KEY DATA — END
================================================================

 CHECKSUM: Verify the data above matches by re-running paperkey
 after recovery and comparing hex values line by line.

================================================================
 THIS DOCUMENT CONTAINS YOUR MASTER SECRET KEY.
 TREAT WITH EXTREME CARE. SHRED WHEN NO LONGER NEEDED.
================================================================
FOOTER

echo -e "${GREEN}  ✓ Printable document created${NC}"
echo ""

# ============================================================
# === STEP 7: COPY DOCUMENT TO USB FOR OFFLINE PRINTING ===
# ============================================================
# We cannot print directly from Tails for two reasons:
#   1. Most printers are networked — sending to a network printer
#      would break the air gap and send your key over a network.
#   2. Many printers cache the last N pages internally. A printer
#      that stores your key in its internal memory is a security risk.
#
# SAFE PRINTING PROCEDURE:
#   1. Copy the file to a USB drive (any USB, including your config USB).
#   2. On a DIFFERENT, non-networked computer, open and print the file.
#      Ideally use a printer connected only by USB cable, not WiFi/Ethernet.
#   3. After printing: securely delete the file from the USB AND from
#      the other computer's filesystem and trash.
#   4. Shred the document when you no longer need the paper backup.
# --- Copy to USB ---
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  COPY TO USB FOR PRINTING                           ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "  The paper backup file is at:"
echo "    $EXPORT_DIR/PAPER-BACKUP-PRINT-ME.txt"
echo ""
echo -e "${YELLOW}  Do NOT print from this air-gapped machine.${NC}"
echo -e "${YELLOW}  Copy to a USB drive, print elsewhere, then delete${NC}"
echo -e "${YELLOW}  the file from that USB immediately after printing.${NC}"
echo ""
echo "  Insert a USB drive now for copying the paper backup."
echo "  (This can be your config USB or any other USB.)"
echo ""
read -p "  Press Enter when USB is inserted..."
echo ""

# List all directories under /media/amnesia/ — this is where Tails
# automatically mounts USB drives when inserted. The user needs to
# identify which path corresponds to the USB they just plugged in.
# `2>/dev/null` suppresses errors if /media/amnesia/ doesn't exist.
# `|| echo "(none found...)"` provides a helpful fallback message.
echo "  Available mount points:"
ls -d /media/amnesia/*/ 2>/dev/null || echo "  (none found — check if USB is mounted)"
echo ""

read -p "  Enter the mount path (e.g., /media/amnesia/MYUSB): " USB_MOUNT

# Validate the path before trying to copy — if the user made a typo
# or the USB isn't mounted, give them clear instructions for the
# manual copy command.
if [ ! -d "$USB_MOUNT" ]; then
    echo -e "${RED}  Path $USB_MOUNT not found.${NC}"
    echo "  You can manually copy later:"
    echo "    cp $EXPORT_DIR/PAPER-BACKUP-PRINT-ME.txt /media/amnesia/YOUR_USB/"
else
    # Copy the printable document to the USB drive.
    cp "$EXPORT_DIR/PAPER-BACKUP-PRINT-ME.txt" "$USB_MOUNT/"
    echo ""
    echo -e "${GREEN}  ✓ Copied to: $USB_MOUNT/PAPER-BACKUP-PRINT-ME.txt${NC}"
    echo ""

    # === IMPORTANT: Post-printing cleanup instructions ===
    # The file on the USB now contains your master secret key in
    # readable hex. It must be destroyed as soon as printing is done.
    # `shred` overwrites the file multiple times before deleting it,
    # making recovery much harder than a simple `rm`.
    # -v : verbose (show progress)
    # -f : force (change permissions if needed to allow overwrite)
    # -z : add a final zero-fill pass to hide the shredding
    # -n 3 : overwrite 3 times before deleting
    echo -e "${RED}  IMPORTANT: After printing this file on another computer:${NC}"
    echo -e "${RED}    1. Securely delete it: shred -vfz -n 3 PAPER-BACKUP-PRINT-ME.txt${NC}"
    echo -e "${RED}    2. Or at minimum: rm PAPER-BACKUP-PRINT-ME.txt${NC}"
    echo -e "${RED}    3. Empty the trash${NC}"
fi

# ============================================================
# === SUMMARY ===
# ============================================================
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  PAPER BACKUP READY FOR PRINTING                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Next: bash .../scripts/07-yubikey-transfer.sh  (run 3 times)"
echo ""
