---
name: Bug report
about: Report a script failure or unexpected behavior
labels: bug
---

## Describe the bug

A clear and concise description of what went wrong.

---

## Which script failed?

<!-- Choose one: -->
- [ ] 01 — Tails setup
- [ ] 02 — Generate master key
- [ ] 03 — Generate subkeys
- [ ] 04 — Export and backup
- [ ] 05 — Transfer to YubiKey
- [ ] 06 — Verify YubiKey
- [ ] 07 — LUKS backup drive
- [ ] 08 — Encrypt backups
- [ ] 09 — Daily machine setup
- [ ] 10 — macOS/Linux daily machine config
- [ ] 11 — (other Tails script)
- [ ] 12 — (other Tails script)
- [ ] Daily machine setup (not a numbered script)
- [ ] Other (describe below)

---

## Operating system

**For scripts 01–09 and 11–12** (run on Tails):
- Tails version: <!-- e.g. Tails 6.2 -->

**For script 10 / daily machine setup** (run on your normal machine):
- OS and version: <!-- e.g. macOS 14.4 Sonoma / Ubuntu 24.04 -->

---

## YubiKey model and firmware version

- YubiKey model: <!-- e.g. YubiKey 5 NFC / YubiKey 5C Nano -->
- Firmware version: <!-- found with: gpg --card-status | grep "Version" or ykinfo -a -->

---

## Steps to reproduce

1. 
2. 
3. 

---

## Expected behavior

What did you expect to happen?

---

## Actual behavior / error output

<!-- Paste the full terminal output here. Include the command you ran and everything printed after it. Do not paraphrase — exact output helps. -->

```
(paste terminal output here)
```

---

## Additional context

Anything else that might be relevant: hardware model, USB drive brand, whether this is a first run or a re-run, any customizations you made to the scripts, etc.
