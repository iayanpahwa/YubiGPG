#!/bin/bash
# =============================================================
# 10 — DAILY MACHINE SETUP (macOS + Linux)
# =============================================================
# Run this on your DAILY (networked) machine after completing
# the air-gapped key generation and YubiKey loading.
#
# This script:
#   - Detects your OS (macOS or Linux)
#   - Installs required packages
#   - Imports your public key
#   - Installs gpg-agent.conf with correct pinentry
#   - Kills macOS SSH agent and takes over with GPG agent
#   - Sets up shell environment for GPG-based SSH
#   - Configures Git for signed commits
#   - Tests YubiKey: card detection, signing, SSH, decryption
#   - Sets public key URL on YubiKey for self-bootstrapping
#   - Explains User PIN vs Admin PIN
#
# PREREQUISITES:
#   - Your public-key.asc available (on config USB)
#   - Your daily-carry YubiKey ready
#
# USAGE:
#   bash gpg-kit/scripts/10-daily-machine-setup.sh
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
echo -e "${BOLD}║   10 — DAILY MACHINE SETUP (macOS + Linux)             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================
# STEP 1: DETECT OS
# =============================================================
# Everything downstream (package installation, pinentry path,
# SSH agent configuration, shell RC file) differs between macOS
# and Linux. We detect once here and branch throughout the script.
#
# Apple Silicon Macs use /opt/homebrew; Intel Macs use /usr/local.
# BREW_PREFIX is set here and used later to locate pinentry-mac.
# =============================================================
echo -e "${YELLOW}[Step 1/10] Detecting operating system...${NC}"
echo ""

OS_TYPE="unknown"
BREW_PREFIX=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    echo -e "${GREEN}  ✓ macOS detected${NC}"

    # Homebrew installs to different locations depending on CPU architecture.
    # Apple Silicon (arm64) uses /opt/homebrew; Intel (x86_64) uses /usr/local.
    if [[ "$(uname -m)" == "arm64" ]]; then
        BREW_PREFIX="/opt/homebrew"
        echo "  Architecture: Apple Silicon (arm64)"
    else
        BREW_PREFIX="/usr/local"
        echo "  Architecture: Intel (x86_64)"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
    echo -e "${GREEN}  ✓ Linux detected${NC}"
else
    # Unknown OS — fall back to Linux behavior as a safe default.
    echo -e "${YELLOW}  Unknown OS: $OSTYPE — proceeding with Linux defaults${NC}"
    OS_TYPE="linux"
fi
echo ""

# =============================================================
# STEP 2: INSTALL REQUIRED PACKAGES
# =============================================================
# Three tools are required for YubiKey-based GPG on macOS:
#   gnupg       — the core GPG suite (gpg, gpg-agent, scdaemon)
#   pinentry-mac — native macOS PIN dialog for GPG passphrase prompts
#   ykman       — YubiKey Manager CLI (for touch policy, card info)
#
# On Linux, GPG is typically pre-installed. We check for
# scdaemon and pcscd which are needed for smart card communication.
#   scdaemon — GPG's smart card daemon, handles YubiKey communication
#   pcscd    — PC/SC daemon, the system-level smart card middleware
# =============================================================
echo -e "${YELLOW}[Step 2/10] Checking required packages...${NC}"
echo ""

if [ "$OS_TYPE" = "macos" ]; then
    # Build a space-separated list of missing package names.
    # command -v checks if a binary is in PATH.
    MISSING=""
    command -v gpg &>/dev/null || MISSING="gnupg "
    command -v pinentry-mac &>/dev/null || MISSING="${MISSING}pinentry-mac "
    command -v ykman &>/dev/null || MISSING="${MISSING}ykman "

    if [ -n "$MISSING" ]; then
        echo -e "${YELLOW}  Missing packages: $MISSING${NC}"
        read -p "  Install with Homebrew? (y/n): " DO_INSTALL
        if [ "$DO_INSTALL" = "y" ]; then
            # Install all missing packages in a single brew invocation.
            # $MISSING is intentionally unquoted to allow word splitting
            # into separate package name arguments.
            brew install $MISSING
        else
            echo "  Install manually: brew install $MISSING"
            echo "  Continuing — some features may not work."
        fi
        echo ""
    fi

    # Report installed versions for confirmation.
    GPG_VER=$(gpg --version 2>/dev/null | head -1 || echo "not found")
    echo -e "${GREEN}  ✓ $GPG_VER${NC}"
    command -v pinentry-mac &>/dev/null && echo -e "${GREEN}  ✓ pinentry-mac${NC}" || echo -e "${RED}  ✗ pinentry-mac not found${NC}"
    command -v ykman &>/dev/null && echo -e "${GREEN}  ✓ ykman${NC}" || echo -e "${RED}  ✗ ykman not found${NC}"
else
    # On Linux, GPG absence is a hard error — there is no automatic install.
    if ! command -v gpg &>/dev/null; then
        echo -e "${RED}  GPG not found.${NC}"
        echo "  Install: sudo apt install gnupg2 scdaemon pcscd"
        exit 1
    fi
    GPG_VER=$(gpg --version | head -1)
    echo -e "${GREEN}  ✓ $GPG_VER${NC}"

    # Check for smart card support packages. These are soft warnings
    # rather than hard errors — the user may have them under different
    # names or already running as a service.
    for pkg in scdaemon pcscd; do
        if command -v "$pkg" &>/dev/null || dpkg -l "$pkg" &>/dev/null 2>&1; then
            echo -e "${GREEN}  ✓ $pkg${NC}"
        else
            echo -e "${YELLOW}  ⚠ $pkg not found — install with: sudo apt install $pkg${NC}"
        fi
    done
fi
echo ""

# =============================================================
# STEP 3: IMPORT PUBLIC KEY
# =============================================================
# The public key must be in the local GPG keyring before GPG can:
#   - Use the YubiKey for signing (it needs to know who owns the stubs)
#   - Encrypt files to you
#   - Verify signatures from your YubiKey
#
# Importing the public key is SAFE — it contains no private material.
# The private key remains on the YubiKey and never touches this machine.
#
# After import, we set "ultimate" trust on your own key. This tells
# GPG "I know this key belongs to me; trust all signatures from it."
# Without ultimate trust, GPG may show "unknown validity" warnings
# when verifying your own signed commits.
# =============================================================
echo -e "${YELLOW}[Step 3/10] Importing your public key...${NC}"
echo ""

echo "  Where is your public-key.asc file?"
echo "  (Copied from Tails to a USB drive during key generation)"
echo ""
read -p "  Path to public-key.asc: " PUB_KEY

if [ ! -f "$PUB_KEY" ]; then
    echo -e "${RED}  File not found: $PUB_KEY${NC}"
    echo "  Check the path and try again."
    exit 1
fi

# Import the public key into the local GPG keyring.
gpg --import "$PUB_KEY"
echo ""

# Show all keys in the keyring so the user can identify their key ID.
# The key ID appears on the 'pub' line after the algorithm/length,
# e.g.: pub   ed25519/0xABCD1234EFGH5678
echo "  Your keys:"
gpg --list-keys --keyid-format 0xlong
echo ""

# The user must enter the full key ID (the 0x... hex string) so we
# can reference their specific key in all subsequent operations.
read -p "  Enter your key ID (the 0x... from the 'pub' line): " KEYID

# --- Verify ---
if ! gpg --list-keys "$KEYID" &>/dev/null; then
    echo -e "${RED}  Key $KEYID not found.${NC}"
    exit 1
fi

# ============================================================
# SET ULTIMATE TRUST
# ============================================================
# GPG's trust model: every key starts at "unknown" trust.
# For your OWN key, you should set trust to level 5 = "ultimate".
# This means "I created this key; I vouch for it completely."
#
# The --command-fd 0 flag tells gpg to read commands from stdin
# (file descriptor 0). The echo "5\ny\n" pipe provides:
#   5 = ultimate trust level
#   y = confirm the choice
# If the automated approach fails (some GPG versions behave
# differently), we fall back to manual interactive trust setting.
# ============================================================

# --- Set ultimate trust ---
echo ""
echo "  Setting ultimate trust on your own key..."
# Pipe trust commands non-interactively. "5" selects ultimate trust;
# "y" confirms; the edit-key session then saves and exits.
echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$KEYID" trust 2>/dev/null || {
    echo "  Auto-trust failed. Setting manually..."
    # Manual fallback: user types these commands in the GPG editor.
    echo -e "${CYAN}  Type: trust → 5 → y → quit${NC}"
    gpg --edit-key "$KEYID"
}
echo -e "${GREEN}  ✓ Key imported and trusted${NC}"
echo ""

# =============================================================
# STEP 4: INSTALL GPG-AGENT.CONF
# =============================================================
# gpg-agent.conf controls GPG agent behavior on this machine.
# Key settings written here:
#   enable-ssh-support        — allows gpg-agent to serve SSH keys
#                               (your [A] subkey becomes an SSH key)
#   default-cache-ttl 600     — cache GPG passphrase for 10 minutes
#   max-cache-ttl 7200        — maximum cache time: 2 hours
#   default-cache-ttl-ssh 600 — same for SSH operations
#   max-cache-ttl-ssh 7200    — same for SSH operations
#   pinentry-program PATH     — the GUI/TUI PIN entry program to use
#
# pinentry-mac is used on macOS for native password dialogs.
# On Linux we prefer pinentry-gnome3 (GUI) or pinentry-curses (TUI).
# =============================================================
echo -e "${YELLOW}[Step 4/10] Installing gpg-agent.conf...${NC}"
echo ""

# Create the GPG home directory if it doesn't exist.
# chmod 700 is required — GPG refuses to start if ~/.gnupg is world-readable.
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Determine the correct pinentry program path for this OS.
# pinentry is the external program that shows the PIN/passphrase dialog.
# Without the correct pinentry, GPG cannot prompt for PINs and all
# operations requiring a passphrase will fail silently.
PINENTRY_LINE=""
if [ "$OS_TYPE" = "macos" ]; then
    # which pinentry-mac finds the Homebrew-installed binary path.
    PE_PATH=$(which pinentry-mac 2>/dev/null || echo "")
    if [ -n "$PE_PATH" ]; then
        PINENTRY_LINE="pinentry-program $PE_PATH"
        echo "  Using pinentry-mac at: $PE_PATH"
    else
        echo -e "${YELLOW}  pinentry-mac not found — PIN prompts may fail.${NC}"
        echo "  Install: brew install pinentry-mac"
    fi
else
    # On Linux, prefer gnome3 (GUI dialog) if available; fall back to
    # curses (terminal-based dialog). Both are functionally equivalent.
    if [ -f /usr/bin/pinentry-gnome3 ]; then
        PINENTRY_LINE="pinentry-program /usr/bin/pinentry-gnome3"
        echo "  Using pinentry-gnome3"
    elif [ -f /usr/bin/pinentry-curses ]; then
        PINENTRY_LINE="pinentry-program /usr/bin/pinentry-curses"
        echo "  Using pinentry-curses"
    fi
fi

# Back up any existing agent config before overwriting.
if [ -f ~/.gnupg/gpg-agent.conf ]; then
    cp ~/.gnupg/gpg-agent.conf ~/.gnupg/gpg-agent.conf.bak
    echo "  Backed up existing config to gpg-agent.conf.bak"
fi

# Write the agent configuration. The heredoc writes exactly these
# lines — no extra whitespace or comments (GPG is sensitive to format).
# $PINENTRY_LINE expands to the pinentry-program line, or is empty
# if no pinentry was found (gpg-agent will use its compiled-in default).
cat > ~/.gnupg/gpg-agent.conf << EOF
enable-ssh-support
default-cache-ttl 600
max-cache-ttl 7200
default-cache-ttl-ssh 600
max-cache-ttl-ssh 7200
${PINENTRY_LINE}
EOF

# chmod 600: owner read/write only. GPG refuses to use agent configs
# with looser permissions (group or world readable).
chmod 600 ~/.gnupg/gpg-agent.conf
echo -e "${GREEN}  ✓ ~/.gnupg/gpg-agent.conf installed${NC}"
echo ""

# =============================================================
# STEP 5: KILL COMPETING SSH AGENTS & SET UP GPG SSH
# =============================================================
# On macOS, the OS launches its own ssh-agent automatically via
# launchd. This agent competes with gpg-agent for SSH_AUTH_SOCK
# (the Unix socket that SSH clients use to talk to an agent).
# If macOS's agent wins, SSH will not see your YubiKey key at all.
#
# We resolve this by:
#   1. Permanently disabling the macOS ssh-agent via launchctl.
#   2. Killing any currently running ssh-agent process.
#   3. Starting gpg-agent and pointing SSH_AUTH_SOCK at its socket.
#
# The socket path is determined by gpgconf --list-dirs agent-ssh-socket,
# which returns the canonical path (typically under /run/user/UID/gnupg/
# on Linux or ~/Library/gnupg/... on macOS).
# =============================================================
echo -e "${YELLOW}[Step 5/10] Setting up GPG agent as SSH agent...${NC}"
echo ""

if [ "$OS_TYPE" = "macos" ]; then
    # macOS runs its own ssh-agent via launchd. It fights with gpg-agent
    # for SSH_AUTH_SOCK. We need to disable it.
    echo "  Disabling macOS built-in SSH agent..."
    # launchctl disable permanently prevents the service from starting
    # on future boots. "user/$UID/..." scopes it to the current user.
    launchctl disable "user/$UID/com.openssh.ssh-agent" 2>/dev/null || true
    # Kill any currently running ssh-agent process immediately.
    pkill ssh-agent 2>/dev/null || true
    echo -e "${GREEN}  ✓ macOS SSH agent disabled${NC}"
fi

# Kill gpg-agent cleanly so it restarts fresh with the new config.
# This ensures the new gpg-agent.conf (especially enable-ssh-support)
# takes effect immediately rather than at next login.
gpgconf --kill gpg-agent 2>/dev/null || true
sleep 1

# Clear any stale SSH agent environment variables from this shell session
# before setting the correct gpg-agent socket path.
unset SSH_AGENT_PID
unset SSH_AUTH_SOCK
# gpgconf --list-dirs agent-ssh-socket prints the exact socket path
# that gpg-agent will listen on for SSH requests.
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
export GPG_TTY=$(tty)   # Needed for pinentry to find the correct terminal.

# Launch gpg-agent in daemon mode. It will fork into the background.
gpgconf --launch gpg-agent
# updatestartuptty tells gpg-agent which terminal (TTY) to use for
# PIN prompts. Must be called after each new terminal session or after
# macOS sleep/wake — otherwise the agent tries to use the wrong TTY.
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

echo ""
echo "  SSH_AUTH_SOCK = $SSH_AUTH_SOCK"

# Verify that SSH_AUTH_SOCK points to the gpg-agent socket, not
# the macOS agent. The gpg-agent socket path always contains "gnupg".
if echo "$SSH_AUTH_SOCK" | grep -q "gnupg"; then
    echo -e "${GREEN}  ✓ SSH agent is GPG agent (correct)${NC}"
else
    echo -e "${RED}  ✗ SSH_AUTH_SOCK does not point to GPG agent${NC}"
    echo "  Expected path containing 'gnupg', got: $SSH_AUTH_SOCK"
    echo "  Fix manually: export SSH_AUTH_SOCK=\"\$(gpgconf --list-dirs agent-ssh-socket)\""
fi
echo ""

# =============================================================
# STEP 6: INSTALL SHELL ENVIRONMENT
# =============================================================
# The environment variables and agent startup commands set in
# Step 5 only apply to THIS shell session. To make them permanent,
# we append a block to the user's shell RC file (~/.zshrc or
# ~/.bashrc) that runs on every new terminal.
#
# The block (marked GPG SSH START / GPG SSH END) includes:
#   - GPG_TTY export (needed for pinentry)
#   - SSH_AUTH_SOCK pointed at gpg-agent socket
#   - gpg-agent auto-launch on shell start
#   - updatestartuptty call (fixes macOS sleep/wake TTY issues)
#   - Convenience aliases for common GPG operations
#
# If an existing GPG SSH block is found, it is replaced (not
# duplicated) to avoid accumulating stale configuration.
# =============================================================
echo -e "${YELLOW}[Step 6/10] Installing shell environment...${NC}"
echo ""

# Detect the correct RC file to modify.
# macOS defaults to zsh since Catalina. Linux may use either.
SHELL_RC=""
if [ "$OS_TYPE" = "macos" ]; then
    SHELL_RC="$HOME/.zshrc"
    echo "  macOS default: zsh → $SHELL_RC"
else
    if [ "$(basename "${SHELL:-bash}")" = "zsh" ]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.bashrc"
    fi
    echo "  Detected: $SHELL_RC"
fi

# Let the user confirm or override the RC file path.
read -p "  Use $SHELL_RC? (y/n, or enter a different path): " SHELL_CHOICE

if [ "$SHELL_CHOICE" = "y" ]; then
    : # keep the detected value
elif [ "$SHELL_CHOICE" = "n" ]; then
    read -p "  Enter shell RC file path: " SHELL_RC
else
    # If the user typed a path directly (neither y nor n), use it as-is.
    SHELL_RC="$SHELL_CHOICE"
fi

# Remove any existing GPG SSH block to avoid duplicates.
# The block is bounded by marker comments (GPG SSH START / GPG SSH END).
if grep -q "# --- GPG SSH START ---" "$SHELL_RC" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}  Existing GPG SSH block found — replacing it.${NC}"
    # sed -i '' on macOS requires an explicit empty backup suffix.
    # sed -i on Linux does not accept the '' argument — hence the branch.
    if [ "$OS_TYPE" = "macos" ]; then
        sed -i '' '/# --- GPG SSH START ---/,/# --- GPG SSH END ---/d' "$SHELL_RC"
    else
        sed -i '/# --- GPG SSH START ---/,/# --- GPG SSH END ---/d' "$SHELL_RC"
    fi
fi

# Append the GPG SSH environment block to the RC file.
# 'ENVBLOCK' is quoted to prevent variable expansion during the cat —
# the variables (like $GPG_TTY and $(...)) must be evaluated at shell
# startup time, not now. The exception is the already-resolved paths
# which are hardcoded earlier in this script.
cat >> "$SHELL_RC" << 'ENVBLOCK'

# --- GPG SSH START ---
# GPG agent replaces ssh-agent for YubiKey-based SSH authentication
export GPG_TTY=$(tty)

# Disable macOS SSH agent — GPG agent takes over
unset SSH_AGENT_PID
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi

# Launch GPG agent and refresh terminal binding
# updatestartuptty fixes stale TTY after macOS sleep/wake
gpgconf --launch gpg-agent >/dev/null 2>&1
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

# Aliases
alias gpg-restart='gpgconf --kill gpg-agent && gpgconf --launch gpg-agent && gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 && echo "gpg-agent restarted"'
alias gpg-card='gpg --card-status'
alias gpg-list='gpg --list-secret-keys --keyid-format 0xlong'
alias gpg-ssh-pubkey='gpg --export-ssh-key "$(gpg --list-keys --with-colons 2>/dev/null | grep "^pub" | head -1 | cut -d: -f5)" 2>/dev/null'
alias gpg-fix='gpgconf --kill gpg-agent; pkill ssh-agent 2>/dev/null; unset SSH_AUTH_SOCK; export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"; export GPG_TTY=$(tty); gpgconf --launch gpg-agent; gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1; echo "Fixed. Verify: ssh-add -L"'
# --- GPG SSH END ---
ENVBLOCK

echo -e "${GREEN}  ✓ Shell environment installed in $SHELL_RC${NC}"
echo ""
# Document the installed aliases so the user knows what they have.
echo "  Installed aliases:"
echo "    gpg-restart     — kill and relaunch gpg-agent"
echo "    gpg-card        — show YubiKey status"
echo "    gpg-list        — list your secret keys"
echo "    gpg-ssh-pubkey  — print your SSH public key"
echo "    gpg-fix         — nuclear fix: kill all agents, reconfigure"
echo ""

# =============================================================
# STEP 7: CONFIGURE GIT
# =============================================================
# Git can automatically sign commits and tags using GPG.
# With a YubiKey, each signed commit causes the YubiKey to blink
# and requires a touch (if touch policy is enabled).
#
# Settings applied globally (~/.gitconfig):
#   user.signingkey  — the key ID Git passes to gpg --sign
#   commit.gpgsign   — auto-sign every commit (no -S flag needed)
#   tag.gpgSign      — auto-sign every tag
#   user.name        — your name in commit metadata
#   user.email       — your email in commit metadata
#   gpg.program      — path to the gpg binary to use for signing
#
# NOTE: Use the SIGNING SUBKEY ID (the [S] subkey), not the master
# key ID. This is safer — the master key never needs to touch disk
# on your daily machine.
# =============================================================
echo -e "${YELLOW}[Step 7/10] Configuring Git for signed commits...${NC}"
echo ""

# Show the key structure to help the user identify the signing subkey.
# The signing subkey is labeled [S] in the gpg --list-keys output.
echo "  Your keys:"
gpg --list-keys --keyid-format 0xlong "$KEYID" 2>/dev/null | grep -E "(pub|sub)" || true
echo ""

echo "  The signing subkey is the one with [S]."
# Default to the master key ID if the user just presses Enter.
# Using the master ID is also valid — GPG will find the right subkey.
read -p "  Signing subkey ID (or Enter to use master $KEYID): " SIGN_KEY
SIGN_KEY=${SIGN_KEY:-$KEYID}

read -p "  Your full name for Git: " GIT_NAME
read -p "  Your email for Git: " GIT_EMAIL

# Apply all Git settings globally (affects all repos on this machine).
git config --global user.signingkey "$SIGN_KEY"
git config --global commit.gpgsign true      # Sign every commit automatically.
git config --global tag.gpgSign true         # Sign every tag automatically.
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global gpg.program "$(which gpg)"  # Explicit path prevents PATH issues.

echo -e "${GREEN}  ✓ Git configured${NC}"
echo ""

# =============================================================
# STEP 8: TEST EVERYTHING
# =============================================================
# Six optional tests verify the full YubiKey integration:
#   Test 1 — YubiKey is detected by GPG (smart card communication)
#   Test 2 — GPG signing works (sign subkey on card, user PIN, touch)
#   Test 3 — Encrypt + decrypt round-trip (encryption subkey on card)
#   Test 4 — SSH agent sees the YubiKey's authentication subkey
#   Test 5 — GitHub SSH authentication succeeds end-to-end
#   Test 6 — Git creates a signed commit that verifies locally
#
# Each test is independent and optional — skip any that aren't
# needed or whose prerequisites aren't yet met (e.g., GitHub SSH
# key not yet uploaded).
# =============================================================
echo -e "${YELLOW}[Step 8/10] Testing YubiKey and all operations...${NC}"
echo ""
echo -e "${CYAN}  Insert your daily-carry YubiKey.${NC}"
read -p "  Press Enter when inserted..."
echo ""

# Restart gpg-agent cleanly before tests to ensure it sees the
# freshly inserted YubiKey and picks up the new gpg-agent.conf.
gpgconf --kill gpg-agent 2>/dev/null || true
sleep 1
export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
gpgconf --launch gpg-agent
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true

# ============================================================
# TEST 1: CARD DETECTION
# ============================================================
# gpg --card-status communicates with the YubiKey via scdaemon
# and PC/SC. A successful response means the full smart card
# stack is working: pcscd → scdaemon → gpg-agent.
# ============================================================
echo -e "${BOLD}  Test 1: YubiKey detection${NC}"
if gpg --card-status &>/dev/null; then
    echo -e "${GREEN}    ✓ YubiKey detected${NC}"
    # Show the card's key fingerprints to confirm the correct keys
    # were transferred from Tails.
    gpg --card-status 2>/dev/null | grep -E "(Serial|Signature key|Encryption key|Authentication)" | head -5 | sed 's/^/    /'
else
    echo -e "${RED}    ✗ YubiKey not detected${NC}"
    echo "    Try: gpgconf --kill scdaemon && gpg --card-status"
fi
echo ""

# ============================================================
# TEST 2: SIGNING
# ============================================================
# Pipes a test string through gpg --clearsign, which uses the
# signing subkey on the YubiKey to create a PGP signature.
# If touch policy is enabled, the YubiKey will blink and wait
# for a physical tap before signing.
#
# USER PIN: the short PIN (6+ digits) entered for daily operations.
# This is NOT the Admin PIN — do not use the Admin PIN here.
# ============================================================
echo -e "${BOLD}  Test 2: GPG signing${NC}"
echo -e "${CYAN}    When prompted, enter your USER PIN (the short one).${NC}"
echo -e "${CYAN}    Touch YubiKey when it blinks.${NC}"
echo ""
read -p "    Run signing test? (y/n): " DO_SIGN
if [ "$DO_SIGN" = "y" ]; then
    # Redirect stdout to /dev/null — we only care about the exit code.
    if echo "test signing" | gpg --clearsign >/dev/null 2>&1; then
        echo -e "${GREEN}    ✓ Signing works${NC}"
    else
        echo -e "${RED}    ✗ Signing failed${NC}"
        echo ""
        echo "    Common causes:"
        echo "      • Wrong PIN — use USER PIN, not admin PIN"
        echo "      • PIN blocked — unblock with:"
        echo "        gpg --card-edit → admin → passwd → 2 (unblock)"
        echo "      • Agent stale — run: gpg-restart"
    fi
fi
echo ""

# ============================================================
# TEST 3: ENCRYPT + DECRYPT ROUND-TRIP
# ============================================================
# Encrypts a test message to your own key (using your public key),
# then decrypts it (using the encryption subkey on the YubiKey).
# This exercises the full encryption subkey path.
#
# The encrypted output is temporarily saved to /tmp/gpg-test-enc.asc
# and deleted after the test. If decryption returns the exact
# original message, the test passes.
# ============================================================
echo -e "${BOLD}  Test 3: Encrypt + Decrypt round-trip${NC}"
read -p "    Run encryption test? (y/n): " DO_ENC
if [ "$DO_ENC" = "y" ]; then
    TEST_MSG="YubiKey encryption test $(date)"
    # --armor: ASCII output (not binary)
    # --encrypt: encrypt the message
    # --recipient: encrypt to this key ID (your own public key)
    echo "$TEST_MSG" | gpg --armor --encrypt --recipient "$KEYID" > /tmp/gpg-test-enc.asc 2>/dev/null

    if [ -s /tmp/gpg-test-enc.asc ]; then
        echo -e "${GREEN}    ✓ Encryption succeeded${NC}"
        echo ""
        echo -e "${CYAN}    Decrypting — touch YubiKey and enter USER PIN...${NC}"
        # Decrypt and capture output. || echo "FAILED" prevents set -e
        # from aborting if decryption fails.
        DECRYPTED=$(gpg --decrypt /tmp/gpg-test-enc.asc 2>/dev/null || echo "FAILED")
        if [ "$DECRYPTED" = "$TEST_MSG" ]; then
            echo -e "${GREEN}    ✓ Decryption succeeded — message matches${NC}"
        else
            echo -e "${RED}    ✗ Decryption failed or message mismatch${NC}"
        fi
    else
        echo -e "${RED}    ✗ Encryption failed${NC}"
    fi
    # Clean up the temporary encrypted file.
    rm -f /tmp/gpg-test-enc.asc
fi
echo ""

# ============================================================
# TEST 4: SSH AGENT
# ============================================================
# ssh-add -L lists all keys known to the SSH agent. When GPG
# agent is the SSH agent and a YubiKey is inserted, it should
# show a key derived from the [A] (authentication) subkey.
#
# If no keys are shown, the most common cause on macOS is the
# system ssh-agent overriding SSH_AUTH_SOCK — which is why we
# disabled it in Step 5.
# ============================================================
echo -e "${BOLD}  Test 4: SSH via GPG agent${NC}"
echo ""
echo "    SSH_AUTH_SOCK = $SSH_AUTH_SOCK"

# ssh-add -L returns 1 if no identities are loaded, which would
# abort the script under set -e. We capture output and check manually.
SSH_KEYS=$(ssh-add -L 2>/dev/null || echo "")
if echo "$SSH_KEYS" | grep -q "ssh-"; then
    echo -e "${GREEN}    ✓ SSH agent sees your key:${NC}"
    echo "$SSH_KEYS" | head -1 | sed 's/^/      /'
else
    echo -e "${RED}    ✗ SSH agent has no keys${NC}"
    echo ""
    echo "    This usually means macOS ssh-agent is overriding gpg-agent."
    echo ""
    echo "    Fix:"
    echo "      1. launchctl disable user/\$UID/com.openssh.ssh-agent"
    echo "      2. pkill ssh-agent"
    echo "      3. gpgconf --kill gpg-agent"
    echo "      4. export SSH_AUTH_SOCK=\"\$(gpgconf --list-dirs agent-ssh-socket)\""
    echo "      5. gpgconf --launch gpg-agent"
    echo "      6. gpg-connect-agent updatestartuptty /bye"
    echo "      7. ssh-add -L  (should now show your key)"
    echo ""
    echo "    Or after setup, just run: gpg-fix"
fi
echo ""

# ============================================================
# TEST 5: GITHUB SSH
# ============================================================
# Tests full end-to-end SSH authentication via GitHub's API.
# Prerequisite: your SSH public key (from the YubiKey [A] subkey)
# must already be uploaded to GitHub → Settings → SSH keys.
#
# If the YubiKey has touch policy, it will blink during this test.
# The expected response from GitHub is "successfully authenticated".
# ============================================================
echo -e "${BOLD}  Test 5: GitHub SSH${NC}"
read -p "    Test GitHub SSH? (y/n): " DO_GH
if [ "$DO_GH" = "y" ]; then
    echo ""
    echo -e "${CYAN}    Touch YubiKey when it blinks...${NC}"
    # ssh -T: don't allocate a pseudo-terminal (GitHub doesn't open a shell).
    # || true: GitHub SSH returns exit code 1 even on success (no shell).
    # We capture the output and check the message content instead.
    GH_RESULT=$(ssh -T git@github.com 2>&1 || true)
    if echo "$GH_RESULT" | grep -qi "successfully authenticated"; then
        echo -e "${GREEN}    ✓ GitHub SSH works!${NC}"
        echo "    $GH_RESULT" | head -1 | sed 's/^/    /'
    else
        echo -e "${RED}    ✗ GitHub SSH failed${NC}"
        echo "    $GH_RESULT" | head -3 | sed 's/^/    /'
        echo ""
        echo "    Upload your SSH key to GitHub:"
        # pbcopy is macOS-only. On Linux, use xclip or xsel instead.
        echo "      gpg --export-ssh-key $KEYID | pbcopy"
        echo "      → GitHub → Settings → SSH and GPG keys → New SSH key"
    fi
fi
echo ""

# ============================================================
# TEST 6: GIT SIGNED COMMIT
# ============================================================
# Creates a temporary git repo, adds a file, and makes a signed
# commit. Then verifies the signature locally using git log
# --show-signature.
#
# Note: local verification requires that your public key is in the
# keyring AND trusted (done in Step 3). GitHub shows "Verified" on
# commits once the GPG key is uploaded to GitHub Settings.
# ============================================================
echo -e "${BOLD}  Test 6: Git signed commit${NC}"
read -p "    Create a test repo with signed commit? (y/n): " DO_GIT
if [ "$DO_GIT" = "y" ]; then
    # mktemp -d creates a unique temporary directory. We create a
    # subdirectory inside it for the test repo for clean isolation.
    TEST_REPO=$(mktemp -d)/gpg-test-repo
    mkdir -p "$TEST_REPO" && cd "$TEST_REPO"
    git init -q
    echo "gpg test" > README.md
    git add .
    echo ""
    echo -e "${CYAN}    Touch YubiKey...${NC}"
    # -q suppresses the commit summary output. The signing happens
    # automatically because commit.gpgsign=true was set in Step 7.
    if git commit -q -m "test signed commit" 2>/dev/null; then
        # --show-signature displays the GPG verification result for the
        # most recent commit. "Good signature" means the signing key on
        # the YubiKey matches the public key in the local keyring.
        SIG_CHECK=$(git log --show-signature -1 2>&1)
        if echo "$SIG_CHECK" | grep -qi "good signature"; then
            echo -e "${GREEN}    ✓ Signed commit verified locally!${NC}"
        else
            echo -e "${YELLOW}    ⚠ Commit created but local verification unclear${NC}"
            echo "    GitHub will show 'Verified' once pushed."
        fi
    else
        echo -e "${RED}    ✗ Signing failed${NC}"
    fi
    # Return to home directory and clean up the test repo entirely.
    cd ~
    rm -rf "$(dirname "$TEST_REPO")"
fi
echo ""

# =============================================================
# STEP 9: SET PUBLIC KEY URL ON YUBIKEY
# =============================================================
# YubiKeys can store a URL in their card data. When someone (or you)
# runs: gpg --card-edit → fetch
# GPG downloads the public key from that URL and imports it automatically.
#
# This makes it easy to bootstrap GPG on a new machine: insert the
# YubiKey, run gpg --card-edit → fetch, and your public key is imported
# without needing to manually copy the .asc file.
#
# The URL is stored in the card's public key URL field. Setting it
# requires the YubiKey Admin PIN.
#
# Best URL choices (in order of preference):
#   1. keys.openpgp.org — decentralized, high-availability keyserver
#   2. GitHub .gpg endpoint — works if you've uploaded to GitHub
#   3. Your own website — most control, requires you to keep it live
# =============================================================
echo -e "${YELLOW}[Step 9/10] Set public key URL on YubiKey...${NC}"
echo ""
echo "  Storing a URL on your YubiKey lets you bootstrap on any"
echo "  new machine: gpg --card-edit → fetch → quit"
echo ""
read -p "  Set URL now? (y/n): " DO_URL
if [ "$DO_URL" = "y" ]; then
    # Extract the full 40-character fingerprint from GPG's colon-delimited
    # output. Field 10 of the 'fpr' record is the fingerprint hex string.
    FINGERPRINT=$(gpg --fingerprint --with-colons "$KEYID" 2>/dev/null | grep "^fpr" | head -1 | cut -d: -f10)
    echo ""
    echo "  Your fingerprint: $FINGERPRINT"
    echo ""
    echo "  Suggested URLs:"
    echo "    1. https://keys.openpgp.org/vks/v1/by-fingerprint/$FINGERPRINT"
    echo "    2. https://github.com/USERNAME.gpg (replace USERNAME)"
    echo "    3. https://yoursite.com/pgp.asc"
    echo ""
    SUGGESTED="https://keys.openpgp.org/vks/v1/by-fingerprint/$FINGERPRINT"
    read -p "  Enter URL (or Enter for keys.openpgp.org): " KEY_URL
    KEY_URL=${KEY_URL:-$SUGGESTED}   # Use the keys.openpgp.org URL if Enter is pressed.
    echo ""
    # Setting the URL requires the GPG card editor. The user must type
    # these commands manually because there is no CLI flag for card URL.
    echo -e "${CYAN}  In the card editor:${NC}"
    echo "    Type: admin"      # Enables admin commands (requires Admin PIN).
    echo "    Type: url"        # Opens the URL field for editing.
    echo "    Paste: $KEY_URL"  # The URL to store on the card.
    echo "    Type: quit"       # Saves and exits.
    echo ""
    read -p "  Press Enter to open card editor..."
    gpg --card-edit
    echo -e "${GREEN}  ✓ URL set${NC}"
fi
echo ""

# =============================================================
# STEP 10: PIN REFERENCE & FINAL SUMMARY
# =============================================================
# The YubiKey has two distinct PINs with separate purposes and
# lockout counters. Confusing them is the most common user mistake.
#
# USER PIN (6+ digits, default: 123456):
#   Used for: every signing, decryption, or SSH operation.
#   Frequency: daily, multiple times per day.
#   Lockout: 3 wrong attempts → blocked. Unblock with Admin PIN.
#
# ADMIN PIN (8+ digits, default: 12345678):
#   Used for: changing PINs, keytocard, touch policy (ykman).
#   Frequency: rarely — only during key management.
#   Lockout: 3 wrong attempts → permanently blocked. Full card reset
#            required (destroys all keys on the YubiKey).
#
# IMPORTANT: If the Admin PIN is blocked, the YubiKey cannot be
# recovered — it must be reset (ykman openpgp reset), which wipes all
# stored keys. The keys can then be reloaded from the LUKS backup.
# =============================================================
echo -e "${YELLOW}[Step 10/10] Important: your YubiKey PINs${NC}"
echo ""
echo -e "${BOLD}  ┌──────────────────────────────────────────────────────┐${NC}"
echo -e "${BOLD}  │  YOUR YUBIKEY HAS TWO DIFFERENT PINS                │${NC}"
echo -e "${BOLD}  ├──────────────────────────────────────────────────────┤${NC}"
echo "  │                                                      │"
echo -e "  │  ${CYAN}USER PIN${NC}  (6+ digits)                               │"
echo "  │    Used for: signing, decrypting, SSH                │"
echo "  │    When: every day, every operation                  │"
echo "  │    This is what the macOS PIN dialog asks for.       │"
echo "  │                                                      │"
echo -e "  │  ${CYAN}ADMIN PIN${NC}  (8+ digits)                              │"
echo "  │    Used for: keytocard, changing PINs, touch policy  │"
echo "  │    When: rarely — only admin tasks                   │"
echo "  │    You almost never need this on your daily machine. │"
echo "  │                                                      │"
echo -e "  │  ${RED}PIN BLOCKED? (3 wrong attempts)${NC}                     │"
echo "  │    User PIN blocked → unblock with admin PIN:        │"
echo "  │      gpg --card-edit → admin → passwd → 2 (unblock)  │"
echo "  │    Admin PIN blocked → full reset (destroys keys):   │"
echo "  │      ykman openpgp reset                             │"
echo "  │      (then reload from backup YubiKey or Tails)      │"
echo "  │                                                      │"
echo "  └──────────────────────────────────────────────────────┘"
echo ""

echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  SETUP COMPLETE                                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Daily use:"
echo "    git commit -m \"message\"     — auto-signed (YubiKey blinks)"
echo "    ssh user@server              — YubiKey SSH (blinks for touch)"
echo "    gpg --detach-sign file.tgz   — sign a file"
echo "    gpg --decrypt file.gpg       — decrypt (touch + user PIN)"
echo ""
echo "  Troubleshooting aliases:"
echo "    gpg-restart  — restart GPG agent"
echo "    gpg-fix      — nuclear fix (kills all agents, reconfigures)"
echo "    gpg-card     — check YubiKey connection"
echo "    ssh-add -L   — verify SSH sees your YubiKey key"
echo ""
echo "  Upload to GitHub (if not done):"
echo "    GPG key: gpg --armor --export $KEYID | pbcopy"
echo "             → GitHub → Settings → SSH and GPG keys → New GPG key"
echo ""
echo "    SSH key: gpg --export-ssh-key $KEYID | pbcopy"
echo "             → GitHub → Settings → SSH and GPG keys → New SSH key"
echo ""
echo "  Publish to keyserver:"
echo "    gpg --keyserver hkps://keys.openpgp.org --send-keys $KEYID"
echo ""
# NOTE: The new shell environment (aliases, SSH_AUTH_SOCK, GPG_TTY) only
# takes effect in NEW terminal sessions. The current session will NOT
# have these until the user opens a fresh terminal.
echo "  ${BOLD}Open a new terminal for all changes to take effect.${NC}"
echo ""
