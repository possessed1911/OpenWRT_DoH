---
name: Bug Report
about: Create a report to help us improve OpenWRT_DoH
title: "[BUG] "
labels: ["bug"]
assignees: ""
---

## Description
A clear and concise description of the bug.

## Steps to Reproduce
1. Configure `...` in `/etc/config/dhcp`
2. Run `/etc/auto-doh-sync.sh`
3. Execute DNS query: `nslookup example.com ...`
4. See error

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior
What actually happened (e.g. DNS leak, timeout, failover not triggering).

## Environment
- **OpenWrt Version**: (e.g. 23.05.3, SNAPSHOT)
- **Device Model / Target**: (e.g. MediaTek MT7621, x86_64)
- **Firewall Version**: (e.g. fw4 / nftables)
- **Package Versions**:
  - `https-dns-proxy`: 
  - `dnsmasq` / `dnsmasq-full`: 
  - `ucode`: 

## Logs & Diagnostics
Provide relevant output from router diagnostics:

```bash
# Watchdog logs
logread -e doh-watchdog

# Auto sync logs
/etc/auto-doh-sync.sh

# Firewall redirect rules
uci show firewall | grep -i doh
```

## Additional Context
Add any other context about the problem here.
