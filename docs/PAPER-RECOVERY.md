# Recovering Your GPG Key from Paper Backup

## When to Use This

Use this procedure ONLY if:
- Both LUKS backup USBs are lost, destroyed, or unreadable
- You need to reconstruct your master secret key
- You still have the paper printout from script 06

## What You Need

1. **Your paper printout** — the hex data between START and END markers
2. **Your public key** — from any of these sources:
   - A keyserver (keys.openpgp.org)
   - GitHub (your profile → GPG keys)
   - Someone who has your public key
   - Your own website
3. **Your GPG passphrase** — the one you set during key generation
4. **An air-gapped Tails machine** with `paperkey` installed

## Step-by-Step Recovery

### Step 1: Get Your Public Key

On any networked machine:

```bash
# Option A: From a keyserver
gpg --keyserver hkps://keys.openpgp.org --recv-keys YOUR_KEY_ID
gpg --export YOUR_KEY_ID > public-key.gpg

# Option B: From a file someone gives you
gpg --import their-copy-of-your-public-key.asc
gpg --export YOUR_KEY_ID > public-key.gpg
```

Copy `public-key.gpg` to a USB drive.

### Step 2: Boot Tails (Air-Gapped)

1. Boot Tails from USB on an Intel machine
2. Set admin password
3. DO NOT connect to network yet

### Step 3: Install paperkey

Briefly enable network:
```bash
sudo rfkill unblock all
sudo systemctl start NetworkManager
# Connect to WiFi
sudo apt update && sudo apt install -y paperkey
sudo systemctl stop NetworkManager
sudo rfkill block all
```

### Step 4: Type in the Paper Backup

Open a text editor and carefully type the hex data from your paper printout:

```bash
nano /tmp/paperkey-data.txt
```

Type everything between the START and END markers. Each line looks like:
```
1: 95 01 FE 04 67 2A 86 E2 16 04 1B 01 0A 00 ...
```

The first number is the line number followed by a colon. Type all of it exactly as printed. Double-check every line.

### Step 5: Reconstruct the Secret Key

```bash
paperkey --pubring /media/amnesia/YOURUSB/public-key.gpg \
         --secrets /tmp/paperkey-data.txt \
         --output /tmp/recovered-secret-key.gpg
```

If paperkey reports errors, you have a typo in the hex data. Fix and retry.

### Step 6: Import into GPG

```bash
gpg --import /tmp/recovered-secret-key.gpg
```

You will be prompted for your passphrase.

### Step 7: Verify

```bash
gpg --list-secret-keys --keyid-format 0xlong
```

You should see your master key with all subkeys.

### Step 8: Continue with Key Operations

You can now:
- Generate new subkeys if old ones expired
- Transfer to YubiKeys using script 07
- Extend expiry using script 12
- Create new LUKS backups using script 05

## Troubleshooting

| Problem | Solution |
|---|---|
| `paperkey: unable to parse` | Typo in hex data. Check each line carefully |
| `public key not found` | The public-key.gpg is wrong key or wrong format. Re-export with `gpg --export KEYID > file.gpg` |
| `checksums don't match` | Hex data is corrupted. Compare line by line with the original |
| `passphrase wrong` | You're entering the wrong passphrase. There is no recovery for a forgotten passphrase. |
