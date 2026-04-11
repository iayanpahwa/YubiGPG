# Security Policy

YubiGPG is a security tool. The scripts and configs in this repository handle GPG key generation, YubiKey provisioning, and cryptographic backup procedures. A bug in this workflow can result in key material being exposed, backed up insecurely, or silently corrupted. Responsible disclosure is therefore critical.

---

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Public issues are visible to everyone immediately. A vulnerability in a key management tool could be exploited before a patch is available. Please report privately instead.

**Contact**: yubigpg@codensolder.com

### What to include in your report

- A clear description of the vulnerability and what it affects
- Step-by-step reproduction instructions (which script, which step, what input/environment)
- An impact assessment: what could an attacker do if they exploited this? What key material or data is at risk?
- Any proposed fix or mitigation, if you have one

The more detail you provide, the faster a patch can be produced.

---

## What is in scope

The following are considered valid security issues for this project:

- **Script logic bugs that leak key material**: e.g. a script that writes a private key to a location that persists after Tails reboots, or exports a private key in a way not described or intended
- **Insecure defaults**: e.g. gpg.conf or gpg-agent.conf settings that are weaker than documented, or that disable protections without warning
- **Commands that don't do what their comments claim**: e.g. a comment says "this wipes the key from RAM" but the command doesn't actually do that
- **Privilege or permission issues**: e.g. a script creates files with overly permissive modes (world-readable private key backups)
- **Verification bypass**: e.g. a script that skips signature verification in a way that could allow a tampered file to be used silently

---

## What is out of scope

The following are not security vulnerabilities in this project:

- **User errors**: forgetting a passphrase, losing a YubiKey, or not following the documented steps
- **Tails OS bugs**: report these to the Tails project at https://tails.boum.org/support/
- **YubiKey firmware bugs**: report these to Yubico at https://www.yubico.com/support/
- **GnuPG vulnerabilities**: report these to the GnuPG project at https://www.gnupg.org/contact.html
- **General hardening suggestions** that don't identify a specific exploitable flaw — these are welcome as regular GitHub issues or PRs

---

## Response timeline

- **Acknowledgement**: within 72 hours of receiving your report
- **Patch for critical issues**: within 14 days of acknowledgement
- **Patch for moderate issues**: on a best-effort basis, typically within 30 days

Critical issues are those where exploitation could result in private key material being exposed or silently compromised during a normal execution of the documented workflow.

After a patch is released, the vulnerability will be disclosed publicly (in a GitHub Security Advisory or in the commit history) with credit to the reporter, unless the reporter requests anonymity.

---

## Scope

This security policy covers only the scripts and configuration files in this repository. It does not cover forks, derivative works, or third-party tools referenced in the documentation.
