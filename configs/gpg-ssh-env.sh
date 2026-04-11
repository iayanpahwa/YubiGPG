# =============================================================
# GPG SSH Environment — macOS + Linux
# =============================================================
# Append to ~/.zshrc (macOS default) or ~/.bashrc (Linux)
#
#   cat gpg-kit/configs/gpg-ssh-env.sh >> ~/.zshrc
#
# The daily machine setup script (09-daily-machine-setup.sh)
# does this for you interactively.
# =============================================================

# --- Bind GPG to the current terminal ---
# GPG_TTY tells gpg-agent which terminal to use when it needs to display a
# passphrase prompt. Without this, the agent has no idea where to send the
# pinentry dialog, and passphrase prompts silently fail or appear on the wrong
# terminal — especially common when you open new shell tabs or SSH into a machine.
# $(tty) returns the path of the current terminal device (e.g. /dev/ttys003).
# This must be set every time a new shell session starts, hence it lives in .zshrc.
export GPG_TTY=$(tty)

# --- Disable macOS built-in SSH agent ---
# macOS runs its own ssh-agent automatically via launchd (the macOS init system).
# This built-in agent only handles traditional SSH key files (~/.ssh/id_rsa, etc.)
# and has no knowledge of GPG keys or YubiKeys. If it's running alongside
# gpg-agent, SSH clients may connect to the wrong agent — the macOS one — and
# authentication will fail when your key is on a YubiKey managed by gpg-agent.
#
# We fix this by unsetting SSH_AGENT_PID, which removes the reference to the
# macOS agent process. The SSH_AUTH_SOCK override below then points SSH clients
# to gpg-agent's socket instead.
if [[ "$OSTYPE" == "darwin"* ]]; then
    # On macOS, launchctl may start ssh-agent. We override by pointing
    # SSH_AUTH_SOCK to gpg-agent's socket.
    unset SSH_AGENT_PID
fi

# --- Redirect SSH authentication to gpg-agent ---
# SSH clients find the SSH agent by reading the SSH_AUTH_SOCK environment variable,
# which holds the path to a Unix socket. Normally this points to the macOS or
# system ssh-agent socket. We change it to gpg-agent's SSH socket so that all
# SSH authentication requests go through gpg-agent — and therefore through your
# YubiKey's authentication subkey.
#
# The condition checks gnupg_SSH_AUTH_SOCK_by: if this variable is already set
# to the current process's PID ($$), it means gpg-agent itself set SSH_AUTH_SOCK
# in this session and we should leave it alone. This avoids a redirect loop.
if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi

# --- Ensure gpg-agent is running ---
# gpgconf --launch gpg-agent starts the agent if it isn't already running.
# If it's already running, this is a no-op. Output is suppressed because
# it's noisy and not useful on every shell start.
gpgconf --launch gpg-agent >/dev/null 2>&1

# --- Refresh the agent's TTY after macOS sleep/wake ---
# When macOS sleeps and wakes, or when you switch between terminal windows,
# gpg-agent can get "stuck" pointing to a stale TTY that no longer exists.
# This causes passphrase prompts to fail silently, with the agent appearing
# to hang. The updatestartuptty command tells the agent to re-register the
# current terminal as its active TTY, fixing the stale state.
# This runs every time a shell starts — cheap enough to always do it.
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

# --- Convenience aliases ---

# Print the SSH public key derived from your GPG authentication subkey.
# Paste this into ~/.ssh/authorized_keys on remote servers, or into GitHub/GitLab
# SSH key settings. It reads the first public key found in your GPG keyring.
alias gpg-ssh-pubkey='gpg --export-ssh-key "$(gpg --list-keys --with-colons 2>/dev/null | grep "^pub" | head -1 | cut -d: -f5)" 2>/dev/null'

# Show the status of the inserted YubiKey or smart card: key stubs loaded,
# card serial number, PIN retry counters, and which GPG subkeys are on the card.
alias gpg-card='gpg --card-status'

# Kill and restart gpg-agent. Useful when the agent gets into a bad state
# (e.g. after waking from sleep, after reinserting a YubiKey, or after
# changing gpg-agent.conf). Cheaper than rebooting and usually fixes things.
alias gpg-restart='gpgconf --kill gpg-agent && gpgconf --launch gpg-agent && echo "gpg-agent restarted"'

# List all secret keys (including YubiKey stubs) with their full 64-bit key IDs.
# Stubs show as "Card key not available" until a YubiKey is inserted.
# Use this to confirm your key is imported and to find key IDs for scripting.
alias gpg-list='gpg --list-secret-keys --keyid-format 0xlong'
