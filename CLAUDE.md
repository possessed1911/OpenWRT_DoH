# OpenWRT_DoH
**Version:** 1.0.0 | **Port:** 53 (DNS), 5000+ (DoH Proxies), 6000+ (Forwarders) | **Stack:** OpenWrt, UCI, fw4/nftables, dnsmasq, https-dns-proxy, POSIX shell

## What
Per-device DNS-over-HTTPS (DoH) routing for OpenWrt with local `.lan` resolution, dnsmasq caching, failover watchdog, and IPv6/DoT leak prevention.

## Quick Start

```bash
./setup.sh                 # Bootstrap environment & run syntax validation
./setup.sh --deploy        # Deploy to OpenWrt router via SSH
sh -n etc/auto-doh-sync.sh # Syntax-check core sync script
```

## Commands

```bash
# Validation & Linting (Host workstation)
sh -n etc/doh-common.sh
sh -n etc/auto-doh-sync.sh
sh -n etc/adguard-rewrite-sync.sh
sh -n usr/bin/doh-watchdog.sh
sh -n etc/irq-rps-tune.sh

# Router Execution (OpenWrt target)
/etc/auto-doh-sync.sh              # Sync DHCP leases to DoH forwarders and firewall
/etc/adguard-rewrite-sync.sh       # Push local DHCP hostnames to AdGuard Home
/etc/init.d/doh-watchdog restart   # Restart DoH failover watchdog service
/etc/init.d/https-dns-proxy restart# Restart DoH proxy instances
/etc/init.d/dnsmasq restart        # Restart dnsmasq daemon
/etc/init.d/firewall reload        # Reload fw4 nftables rules

# Testing & Verification
nslookup example.com 127.0.0.1 -port=5000   # Test default DoH proxy
nslookup example.com 192.168.0.1 -port=6002 # Test per-device forwarder
nslookup router.lan 192.168.0.1 -port=6002  # Test local .lan resolution
logread -e doh-watchdog                     # Inspect watchdog failover logs
logread -e adguard-rewrite                  # Inspect rewrite sync logs
```

## Architecture

```
OpenWrt Router
├── Client (192.168.0.X:53) -> fw4 DNAT (doh_X) -> dnsmasq forwarder (:600X)
│   ├── /lan/ & reverse DNS -> main dnsmasq (:53) -> local lease resolution
│   ├── Canary domains (use-application-dns.net, mask.icloud.com) -> blocked
│   └── External queries -> https-dns-proxy (:500X) -> AdGuard DoH (/dns-query/device)
├── Watchdog (/usr/bin/doh-watchdog.sh) probes DoH -> fails over to Google DoH (:5054)
└── Leak Prevention: drop IPv6 :53 & DoT :853 via fw4 rules
```

Data flows from client port 53 through fw4 DNAT redirects into device-specific `dnsmasq` instances on port `6000+octet`. Local requests route to main `dnsmasq` (`:53`), while external queries route through dedicated `https-dns-proxy` instances (`:5000+octet`) to AdGuard Home.

## Key Files

- `etc/auto-doh-sync.sh` - Core engine: syncs DHCP leases to DoH proxies, forwarders, and firewall
- `etc/doh-common.sh` - Shared flock locking, redirect discovery, and dnsmasq upstream sync
- `usr/bin/doh-watchdog.sh` - Health probe loop; fails over to Google DoH if AdGuard is down
- `etc/init.d/doh-watchdog` - Procd service init with config-trigger on DHCP changes
- `etc/adguard-rewrite-sync.sh` - Syncs OpenWrt DHCP hostnames to AdGuard Home DNS rewrites
- `etc/config/dhcp` - UCI config for main dnsmasq, forwarders, and odhcpd
- `etc/config/firewall` - UCI fw4 redirect and leak-prevention rules
- `etc/config/https-dns-proxy` - UCI config for per-client DoH upstream proxies
- `etc/irq-rps-tune.sh` - Network IRQ CPU affinity tuning script

## Configuration

All configuration is via environment variables or UCI. See `.env.example`:

| Variable | Required | Description |
|---|---|---|
| `ADGH_URL` | Yes | AdGuard Home base URL (e.g. `https://adgh.example.com`) |
| `ADGH_USER` | Yes | AdGuard Home API admin username |
| `ADGH_PASS` | Yes | AdGuard Home API admin password |
| `LAN_IP` | No | Router LAN IP address (default: `192.168.0.1`) |
| `ADGUARD_URL` | No | Upstream DoH query endpoint (default: `${ADGH_URL}/dns-query`) |
| `PROBE_DOMAIN`| No | Target domain for DoH watchdog probe (default: `example.com`) |
| `DOH_SERVER` | No | Watchdog DoH check target (default: `127.0.0.1#5000`) |
| `CHECK_INTERVAL`| No | Watchdog health check interval in seconds (default: `30`) |
| `FAIL_THRESHOLD`| No | Consecutive failures before DoH failover (default: `3`) |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
