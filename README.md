# OpenWrt Per-Device DoH with Local `.lan` Resolution

This repository contains the scripts and OpenWrt UCI configurations for routing per-device DNS over HTTPS (DoH) to AdGuard Home while preserving local `.lan` hostname resolution, DNS caching, and IPv6/DoT leak prevention.

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

## Files

- [`etc/auto-doh-sync.sh`](etc/auto-doh-sync.sh) — Syncs static DHCP leases into per-device `https-dns-proxy`, `dnsmasq` forwarders (`6000 + octet`), and `firewall` redirects.
- [`etc/config/dhcp`](etc/config/dhcp) — `dnsmasq` (`main` + `fwd_*`) and `odhcpd` configuration.
- [`etc/config/firewall`](etc/config/firewall) — Per-device DNS redirects and IPv6/DoT blocking rules.
- [`etc/config/https-dns-proxy`](etc/config/https-dns-proxy) — Per-device DoH proxy instances (`5000 + octet`) and backup resolver (`5054`).
