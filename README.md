# OpenWrt Per-Device DoH with Local `.lan` Resolution

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%2B-blue.svg)](https://openwrt.org/)

Per-device DNS-over-HTTPS (DoH) routing suite for OpenWrt routers. Route each local client's DNS queries to dedicated upstream AdGuard Home endpoints while preserving local `.lan` hostname resolution, dnsmasq caching, automatic failover, and strict IPv6 / DoT leak prevention.

## Features

- **Per-Device DoH Routing**: Intercepts port 53 DNS traffic per static DHCP lease and routes it through a dedicated `https-dns-proxy` instance with per-client query paths (`/dns-query/<device>`).
- **Local `.lan` Resolution**: Per-device `dnsmasq` forwarders (`192.168.0.1:6000 + octet`) route `/lan/` and reverse PTR queries directly back to the router's main `dnsmasq` (`127.0.0.1#53`).
- **Canary Domain Blocking**: Automatically blocks `use-application-dns.net`, `mask.icloud.com`, and `mask-h2.icloud.com` to prevent Apple Private Relay and browser DoH circumvention.
- **Failover Watchdog**: Procd background daemon continuously probes DoH upstream health; automatically fails over to Google DoH (`127.0.0.1#5054`) during outages and self-heals when restored.
- **Leak Prevention**: Rejects outbound IPv6 port 53 traffic, disables IPv6 DNS advertisements in `odhcpd`, and drops DNS-over-TLS (port 853) queries.
- **Automated UCI Sync**: Automatically reacts to DHCP lease modifications and dynamically reconciles `https-dns-proxy`, `dnsmasq`, and `firewall` configurations.
- **AdGuard Rewrite Sync**: Synchronizes router DHCP hostnames to AdGuard Home DNS rewrites via API.
- **Hardware IRQ Optimization**: Pins network interface interrupts across CPU cores (`irq-rps-tune.sh`).

## Quick Start

```bash
git clone https://github.com/example/OpenWRT_DoH.git
cd OpenWRT_DoH

# 1. Bootstrap environment and validate scripts
./setup.sh

# 2. Configure your environment
cp .env.example .env
# Edit .env with your AdGuard Home URL and credentials

# 3. Deploy to router over SSH
./setup.sh --deploy
```

See [CLAUDE.md](CLAUDE.md) for detailed commands, service management, and architecture.

## Architecture

- **Main `dnsmasq` (`127.0.0.1:53` / `192.168.0.1:53`)**: Handles DHCP leases, local `.lan` resolution, and default `/home` DoH (`127.0.0.1#5000`).
- **Per-device `dnsmasq` forwarders (`192.168.0.1:6000 + octet`)**:
  - Intercepts port `53` traffic per device via `firewall` DNAT redirects (`doh_<octet>`).
  - Forwards `/lan/` and `/0.168.192.in-addr.arpa/` to `127.0.0.1#53` (`rebind_domain 'lan'`).
  - Blocks browser/OS DoH canary domains (`use-application-dns.net`, `mask.icloud.com`, `mask-h2.icloud.com`).
  - Forwards external queries to the device's dedicated `https-dns-proxy` instance (`127.0.0.1:5000 + octet`), with `127.0.0.1#5054` (`dns.google`) as backup.
  - Syncs `cachesize` from `dhcp.main.cachesize` (`10000`).
- **`https-dns-proxy` (`127.0.0.1:5000 + octet`)**: Proxies each device's DNS to its per-device AdGuard Home DoH endpoint (`https://adgh.example.com/dns-query/<device>`).
- **IPv6 & DoT Leak Prevention (`/etc/config/firewall` & `odhcpd`)**:
  - `dhcp.lan.dns_service='0'` disables IPv6 DNS advertisements.
  - `block_ipv6_dns` / `block_ipv6_dns_fwd` reject outbound IPv6 port `53`.
  - `block_dot_853` rejects outbound DoT (`853`) on both IPv4 and IPv6.

## Prerequisites

- **OpenWrt 23.05 or newer** with `fw4` (nftables).
- Required packages on the router:
  - `https-dns-proxy`
  - `dnsmasq` or `dnsmasq-full`
  - `ucode`
  - `uclient-fetch`
  - `util-linux-flock`
  - `jsonfilter`
  - `bind-tools`

These packages are checked and installed automatically when running `./setup.sh` directly on OpenWrt.

## Configuration

Copy `.env.example` to `.env` to configure deployment and credentials:

```bash
cp .env.example .env
```

Key settings:

| Variable | Description | Default |
|---|---|---|
| `ADGH_URL` | AdGuard Home base API URL | `https://adgh.example.com` |
| `ADGH_USER` | AdGuard Home admin user | `REDACTED` |
| `ADGH_PASS` | AdGuard Home admin password | `REDACTED` |
| `LAN_IP` | Router LAN IP address | `192.168.0.1` |
| `ADGUARD_URL` | Base DoH query URL | `https://adgh.example.com/dns-query` |

## Repository Files

- [`etc/auto-doh-sync.sh`](etc/auto-doh-sync.sh) — Core sync engine: parses static DHCP leases and generates DoH proxy instances, forwarders, and firewall DNAT redirects.
- [`etc/doh-common.sh`](etc/doh-common.sh) — Shared library for flock file locking, redirect enumeration, and dnsmasq upstream switching.
- [`etc/adguard-rewrite-sync.sh`](etc/adguard-rewrite-sync.sh) — Syncs local DHCP hostnames to AdGuard Home DNS rewrites.
- [`usr/bin/doh-watchdog.sh`](usr/bin/doh-watchdog.sh) — Procd watchdog script providing automated DoH health checking and failover.
- [`etc/init.d/doh-watchdog`](etc/init.d/doh-watchdog) — Procd service init script with automatic trigger on DHCP configuration updates.
- [`etc/irq-rps-tune.sh`](etc/irq-rps-tune.sh) — Network interface IRQ affinity performance tuning.
- [`etc/config/dhcp`](etc/config/dhcp) — UCI configuration template for dnsmasq and odhcpd.
- [`etc/config/firewall`](etc/config/firewall) — UCI configuration template for firewall redirects and leak blocking.
- [`etc/config/https-dns-proxy`](etc/config/https-dns-proxy) — UCI configuration template for DoH proxy instances.
- [`setup.sh`](setup.sh) — One-command installation, validation, and deployment script.

## Development & Verification

Validate shell script syntax locally before deploying:

```bash
# Verify script syntax
sh -n etc/*.sh
sh -n usr/bin/*.sh

# Run local setup checks
./setup.sh
```

On the OpenWrt router, test query resolution:

```bash
# Test DoH proxy directly
nslookup example.com 127.0.0.1 -port=5000

# Test per-device forwarder (port 6000 + octet)
nslookup example.com 192.168.0.1 -port=6002

# Test local .lan resolution through forwarder
nslookup router.lan 192.168.0.1 -port=6002

# Check watchdog logs
logread -e doh-watchdog
```

## Using with Claude Code

This project includes a `CLAUDE.md` file optimized for Claude Code.

```bash
claude    # Start Claude Code — automatically reads CLAUDE.md context
```

Claude Code has immediate access to the architecture, port mappings, UCI configuration patterns, and diagnostic commands.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contributing

Contributions, bug reports, and suggestions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting pull requests.
