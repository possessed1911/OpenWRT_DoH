# Contributing to OpenWRT_DoH

Thank you for your interest in contributing to OpenWRT_DoH! We welcome bug fixes, documentation improvements, feature requests, and code contributions.

## Code of Conduct

Please be respectful, constructive, and helpful in all discussions, issues, and pull requests.

## Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/example/OpenWRT_DoH.git
   cd OpenWRT_DoH
   ```

2. **Initialize the local development environment:**
   ```bash
   ./setup.sh
   ```

3. **Verify shell scripts with `sh -n` or `shellcheck`:**
   ```bash
   sh -n etc/*.sh usr/bin/*.sh
   # If you have shellcheck installed:
   shellcheck -s sh etc/*.sh usr/bin/*.sh
   ```

## Branch & Pull Request Workflow

1. Fork the repository and create your feature branch from `master`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Make your changes and test them thoroughly.
3. Commit your changes with clear, descriptive commit messages:
   ```bash
   git commit -m "feat(sync): add support for custom upstream fallback DNS"
   ```
4. Push to your fork:
   ```bash
   git push origin feature/my-new-feature
   ```
5. Open a Pull Request against the `master` branch.

## Code Style & Guidelines

To ensure compatibility with embedded OpenWrt devices running BusyBox `ash`:

- **POSIX `/bin/sh` Compliance**: Scripts must run under POSIX `/bin/sh` on OpenWrt. Avoid bashisms such as `[[ ... ]]`, bash arrays, or non-portable process substitution.
- **Flash Memory Preservation**: OpenWrt devices run on flash storage. Always check if a UCI setting has changed before writing (`dhcp_set_opt`, `fw_set_opt`) to avoid redundant writes and service restarts.
- **Robust Locking & Cleanup**: When mutating shared firewall or dnsmasq configs, use `flock` and trap handlers (`trap 'cleanup' EXIT INT TERM`) to prevent lock file leakage or concurrency races.
- **Strict Privacy & Sanitization**:
  - **Never commit personal or network identifiers**: MAC addresses, DUIDs, real external domain names, or personal usernames/hostnames.
  - **Never commit credentials**: Use `.env.example` and keep active secrets in `.env` (ignored by `.gitignore`).
  - Use standard RFC 5737 / RFC 1918 documentation IP ranges (`192.168.0.x`, `127.0.0.1`) and dummy MACs (`00:11:22:33:44:55`).

## Reporting Issues

- **Bug Reports**: Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md). Include your OpenWrt version, target hardware architecture, router logs (`logread`), and reproduction steps.
- **Feature Requests**: Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md). Describe the use case and expected benefit.

## Using with Claude Code

This repository includes a `CLAUDE.md` file configured with the project architecture, directory structure, port allocations, and verification commands.

When developing with Claude Code:

```bash
claude
```

Claude Code will automatically detect `CLAUDE.md` and adhere to the project conventions, port schemes, and POSIX shell requirements.
