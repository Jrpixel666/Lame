# Security Policy

## Reporting a Vulnerability

If you find a security issue in this project, please report it privately rather than opening a
public issue:

1. Go to the [Security tab](../../security) of this repository and use **"Report a
   vulnerability"** (GitHub Private Vulnerability Reporting), or
2. If that isn't available, open a normal issue with as little detail as possible and ask a
   maintainer to follow up privately.

Please include:
- A description of the issue and its impact
- Steps to reproduce it
- The platform(s) and app version affected

## Scope

This app runs AI models **entirely on-device** — there is no backend server, user accounts, or
telemetry collecting conversation data. Relevant security concerns for this project include:
- The local OpenAI-compatible API server (`Settings → Local API Server`) binding to a network
  interface it shouldn't, or accepting requests it shouldn't
- Path handling around model import/download (zip-slip style issues, unsafe file paths)
- Dependencies with known CVEs (tracked via Dependabot)

## Supported Versions

Only the latest release on the default branch receives security fixes.
