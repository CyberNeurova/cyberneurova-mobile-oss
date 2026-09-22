# Security Policy

## Reporting a vulnerability

Please report security issues **privately** using GitHub's private vulnerability
reporting: open the repository's **Security** tab → **Report a vulnerability**
([direct link](https://github.com/CyberNeurova/cyberneurova-mobile-oss/security/advisories/new)).
This keeps the report confidential until a fix ships.

**Please do not open a public issue for a security vulnerability.**

Where possible, include:

- the affected file(s)/component and the version or commit,
- the impact and rough severity (local vs. remote, and what an attacker gains),
- reproduction steps or a proof-of-concept, and
- a suggested fix, if you have one.

We aim to acknowledge reports within a few days and to keep you updated while we
work on a fix. Reporters are credited in the fixing commit and release notes
unless you'd rather stay anonymous.

## Scope

This repository is the open-source CyberNeurova **mobile client**. Areas that are
especially security-sensitive and welcome scrutiny:

- the **on-device agent** shell and file tools (`lib/core/agent/device/`) —
  sandbox containment, path/symlink handling, and anything that reads or writes
  files on the device;
- **auth / token handling** and secure storage;
- **deep links / intent handling** and the parsing of untrusted server payloads.

Server-side infrastructure is out of scope for this repository.

## Supported versions

Security fixes target the `main` branch (the current release line). Please test
against a recent `main` before reporting.
