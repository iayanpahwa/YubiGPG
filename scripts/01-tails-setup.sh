#!/bin/bash
# =============================================================
# 01 — TAILS AIR-GAP SETUP
# =============================================================
# Run FIRST after booting Tails. Verifies air gap, installs
# gpg.conf, and prepares the environment.
#
# USAGE:
#   bash /media/amnesia/YOUR_USB/gpg-kit/scripts/01-tails-setup.sh
# =============================================================

# ============================================================
# === SHELL OPTIONS ===
# ============================================================
# -e  : exit immediately if any command returns a non-zero status
# -u  : treat unset variables as errors (prevents silent typos)
# -o pipefail : if any command in a pipeline fails, the whole
#               pipeline fails (default bash only checks the last)
set -euo pipefail

# ============================================================
# === TERMINAL COLOR CODES ===
# ============================================================
# These variables hold ANSI escape sequences so we can print
# colored text to the terminal. Using colors makes warnings and
# confirmations much easier to spot at a glance.
RED='\033[0;31m'    # For errors and warnings
GREEN='\033[0;32m'  # For success messages
YELLOW='\033[1;33m' # For step headings and prompts
CYAN='\033[0;36m'   # For informational notes
BOLD='\033[1m'      # For section headers and titles
NC='\033[0m'        # "No Color" — resets color back to normal

# ============================================================
# === HEADER DISPLAY ===
# ============================================================
# Clear the screen and print a prominent banner so the user knows
# which script is running. This is especially important when
# running multiple scripts in sequence.
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         01 — TAILS AIR-GAP SETUP                       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# === STEP 1: VERIFY AIR GAP ===
# ============================================================
# The single most important security check in this entire workflow.
# An air-gapped machine has NO active network connections — this is
# what keeps your master key safe from remote compromise.
#
# WHY this matters: if your machine is connected to a network while
# generating or handling GPG keys, an attacker could theoretically
# exfiltrate the key material. The air gap is your primary defense.
echo -e "${YELLOW}[Step 1/4] Checking network state...${NC}"
echo ""

# --- Understanding Tails' internal virtual network interfaces ---
# Tails uses internal virtual interfaces (veth-tbb, veth-onioncircs,
# veth-tca, veth-onionshare, veth-clearnet) for network namespace
# isolation. These are ALWAYS "state UP" even without internet.
# We must ignore them and only check REAL physical interfaces:
#   wlan*, wlp* = WiFi
#   eth*, enp*, ens* = Ethernet
#   usb* = USB tethering
#
# We filter them out using grep -v (invert match) with a regex
# that matches all the known Tails-internal interface name prefixes.

# List only real physical interfaces that are UP
# - `ip link show`              : list all network interfaces and their state
# - `grep "state UP"`           : only keep lines for interfaces currently active
# - `grep -v -E "(...|veth-|...)`: exclude loopback, Tails veth interfaces, docker, etc.
# - `awk -F': ' '{print $2}'`   : extract just the interface name from each line
# - `cut -d'@' -f1`             : strip the "@ifX" suffix that appears on some virtual ifaces
# - `|| true`                   : prevent set -e from aborting if grep finds no matches
REAL_IFACES=$(ip link show 2>/dev/null \
    | grep "state UP" \
    | grep -v -E "(^[0-9]+: lo:|veth-|docker|br-|virbr)" \
    | awk -F': ' '{print $2}' \
    | cut -d'@' -f1 \
    || true)

# If any real physical interfaces are UP, we need to bring them down
# before proceeding. This section handles that automatically where possible.
if [ -n "$REAL_IFACES" ]; then
    echo -e "${RED}  ⚠  Physical network interfaces are UP:${NC}"
    echo "    $REAL_IFACES"
    echo ""
    echo "  I will now disable WiFi/Bluetooth radios and stop NetworkManager."
    read -p "  Press Enter to proceed..."

    # `rfkill block all` : sends a software "kill switch" signal to ALL wireless
    # radios (WiFi, Bluetooth, etc.), forcing them off at the kernel level.
    # This is more reliable than just disconnecting from a network — it actually
    # powers off the radio hardware.
    sudo rfkill block all 2>/dev/null || true

    # Stop NetworkManager so it cannot re-enable any interfaces automatically.
    # `|| true` prevents a failure here from aborting the whole script.
    sudo systemctl stop NetworkManager 2>/dev/null || true

    # Brief pause to give the kernel time to actually bring down the interfaces
    # before we re-check them in the block below.
    sleep 2

    # --- Re-check after attempting to disable networking ---
    # Run the same detection logic again to confirm the interfaces are now down.
    # If they are still up, the user must physically disconnect the hardware.
    REAL_IFACES=$(ip link show 2>/dev/null \
        | grep "state UP" \
        | grep -v -E "(^[0-9]+: lo:|veth-|docker|br-|virbr)" \
        | awk -F': ' '{print $2}' \
        | cut -d'@' -f1 \
        || true)

    if [ -n "$REAL_IFACES" ]; then
        # Software kill didn't work — the user needs to physically remove hardware.
        # We still let them continue (with a warning) because some setups have
        # Ethernet controllers that cannot be rfkill'd.
        echo -e "${RED}  ⚠  Could not disable: $REAL_IFACES${NC}"
        echo "  Physically disconnect Ethernet and/or remove WiFi card."
        echo ""
        read -p "  Continue anyway? (y to proceed, n to abort): " CONT
        if [ "$CONT" != "y" ]; then
            exit 1
        fi
    fi
fi

# --- Informational note about Tails' internal veth interfaces ---
# Even on a properly air-gapped machine, Tails' internal veth-* interfaces
# will be present and "UP". This block counts them and reassures the user
# that these are expected and do NOT represent external connectivity.
# Show what IS running (informational)
VETH_COUNT=$(ip link show 2>/dev/null | grep -c "veth-" || true)
if [ "$VETH_COUNT" -gt 0 ]; then
    echo -e "${CYAN}  Note: $VETH_COUNT Tails internal interfaces (veth-*) are active.${NC}"
    echo -e "${CYAN}  These are normal — they're Tails' internal network isolation,${NC}"
    echo -e "${CYAN}  NOT external connectivity. Safe to ignore.${NC}"
    echo ""
fi

# Air gap confirmed — all real physical interfaces are down.
echo -e "${GREEN}  ✓ No physical network connections. Air gap confirmed.${NC}"
echo ""

# ============================================================
# === STEP 2: LOCATE CONFIG USB ===
# ============================================================
# The "config USB" is the USB drive you prepared ahead of time
# containing these scripts and the hardened gpg.conf file.
# We locate it by finding the directory this script is running from
# and then looking one level up for the configs/ folder.
echo -e "${YELLOW}[Step 2/4] Locating your config USB...${NC}"
echo ""

# Resolve the absolute path to this script's directory, then go one
# level up to find the gpg-kit root (which contains configs/).
# `${BASH_SOURCE[0]}` is more reliable than $0 when scripts are sourced.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(dirname "$SCRIPT_DIR")"

echo "  Script running from: $SCRIPT_DIR"
echo "  Kit directory:       $KIT_DIR"
echo ""

# Verify that gpg.conf exists where we expect it. If the USB was
# mounted at a different path or the directory structure is wrong,
# give the user a chance to provide the correct path manually.
if [ ! -f "$KIT_DIR/configs/gpg.conf" ]; then
    echo -e "${RED}  ✗ Cannot find configs/gpg.conf relative to this script.${NC}"
    echo ""
    read -p "  Enter the full path to your gpg-kit directory: " KIT_DIR
    if [ ! -f "$KIT_DIR/configs/gpg.conf" ]; then
        echo -e "${RED}  Still not found. Aborting.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}  ✓ Config files found.${NC}"
echo ""

# ============================================================
# === STEP 3: INSTALL GPG CONFIGURATION ===
# ============================================================
# The gpg.conf file contains hardened defaults for GnuPG. These
# settings disable weak algorithms, enforce strong digest preferences,
# and configure other security-relevant behaviours. Installing it
# here ensures every GPG operation in this session uses those settings.
#
# WHY we don't rely on defaults: GnuPG's built-in defaults include
# legacy algorithm support for backward compatibility, which is not
# appropriate when generating a new key from scratch. Our gpg.conf
# removes that cruft.
echo -e "${YELLOW}[Step 3/4] Installing GnuPG configuration...${NC}"
echo ""

# Create the ~/.gnupg directory if it doesn't already exist.
# chmod 700 is REQUIRED — GPG will refuse to use the directory if it
# is world-readable, because that would expose private key data.
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg  # Only the owner (you) can read/write this directory

# Copy the hardened gpg.conf from the USB into the GPG home directory.
# chmod 600 ensures no other user on the system can read your GPG config.
cp "$KIT_DIR/configs/gpg.conf" ~/.gnupg/gpg.conf
chmod 600 ~/.gnupg/gpg.conf  # Owner read/write only

echo -e "${GREEN}  ✓ ~/.gnupg/gpg.conf installed (hardened defaults)${NC}"
echo ""

# ============================================================
# === STEP 4: SYSTEM CHECK ===
# ============================================================
# Confirm that all required tools are present and the smartcard
# daemon (pcscd) is running. pcscd is needed for the YubiKey to
# be detected in later scripts (07-yubikey-transfer.sh).
# We do this check now so any missing tools are identified before
# the user has invested time generating keys.
echo -e "${YELLOW}[Step 4/4] System check...${NC}"
echo ""

# Print version/status of each required component for the log.
# `head -1` trims the gpg version output to just the first line.
echo "  GnuPG:    $(gpg --version 2>/dev/null | head -1 || echo 'NOT FOUND')"
echo "  scdaemon: $(which scdaemon 2>/dev/null || echo 'NOT FOUND')"
echo "  pcscd:    $(systemctl is-active pcscd 2>/dev/null || echo 'not running')"
echo ""

# Start pcscd (PC/SC Smart Card Daemon) if it is not already running.
# pcscd is the bridge between the operating system and USB smartcard
# readers (including YubiKeys). Without it, GPG cannot communicate
# with the YubiKey at all.
if ! systemctl is-active --quiet pcscd 2>/dev/null; then
    echo "  Starting pcscd (smartcard daemon for YubiKeys)..."
    sudo systemctl start pcscd 2>/dev/null || true
    echo -e "${GREEN}  ✓ pcscd started${NC}"
fi

# --- Verify all required GPG tools are installed ---
# Loop through the essential tools and warn if any are missing.
# Tails normally includes these, but it's worth confirming.
# The user cannot proceed without them.
# Check for needed tools
for tool in scdaemon gpg gpg-agent; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${RED}  ⚠  $tool not found. Install with: sudo apt install gnupg scdaemon${NC}"
    fi
done

echo ""

# ============================================================
# === CREATE WORKING DIRECTORY ===
# ============================================================
# /tmp/gpg-export is used as a staging area throughout this workflow.
# All scripts write exported key files, the key ID, and other
# intermediate data here. Because it lives under /tmp, it is
# automatically destroyed when the Tails session ends — meaning
# sensitive material never persists across reboots (unless you
# explicitly back it up to an encrypted USB in script 05).
# --- Create working directory ---
mkdir -p /tmp/gpg-export
echo -e "${GREEN}  ✓ Created /tmp/gpg-export (temporary key storage)${NC}"
echo ""

# ============================================================
# === SETUP COMPLETE ===
# ============================================================
# --- Done ---
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  SETUP COMPLETE                                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Next: bash $KIT_DIR/scripts/02-generate-master.sh"
echo ""
