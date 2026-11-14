# Sanitization Report: OpenWRT_DoH
**Date:** 2026-11-14
**Auditor:** opensource-sanitizer v1.0.0
**Verdict:** FAIL

## Summary

| Category | Status | Findings |
|----------|--------|----------|
| Secrets | PASS | 0 findings |
| PII | FAIL | 8 findings |
| Internal References | FAIL | 4 findings |
| Dangerous Files | PASS | 0 findings |
| Config Completeness | WARN | 2 findings |
| Git History | FAIL | 2 findings |

## Critical Findings (Must Fix Before Release)

1. **[PII]** `etc/config/dhcp:82` — Personal name identifier in static host definition: `A35-...` (`A35-de-Elmir`)
2. **[PII]** `etc/config/dhcp:68` — Personal username identifier in static host definition: `wmsa...` (`wmsaaPC`)
3. **[PII]** `etc/config/dhcp:64,70,77,83,84` — Real hardware MAC addresses: `18:d...`, `0a:e...`, `fe:7...`, `5e:a...`, `b2:5...`
4. **[PII]** `etc/config/dhcp:71` — Client DHCP Unique Identifier (DUID): `0001...`
5. **[PII]** `README.md:7`, `etc/config/dhcp:26`, `etc/config/firewall:139`, `usr/bin/doh-watchdog.sh:7` (and others) — Hardcoded internal private IP addresses (`192.168.0.x`) without `.env.example` documentation
6. **[INTERNAL]** `etc/config/firewall:136` — Internal user/device reference in redirect rule name: `DoH_...` (`DoH_a35deelmir`)
7. **[INTERNAL]** `etc/config/firewall:145` — Internal user/device reference in redirect rule name: `DoH_...` (`DoH_wmsaapc`)
8. **[INTERNAL]** `etc/config/firewall:154,163` — Internal device references in redirect rule names: `DoH_motog355g`, `DoH_tlwr841hp`
9. **[GIT]** Git History — Repository contains 7 commits instead of a single initial commit (`git log --oneline | wc -l` = 7)
10. **[GIT]** Git History (commits `b991f04` & `bc19575`) — Leaked unredacted personal DoH query endpoints in history (`/dns-query/wmsaapc`, `/dns-query/a35deelmir`)

## Warnings (Review Before Release)

1. **[CONFIG]** Repository Root — `.env.example` is missing. Environment and configuration variables (`ADGH_URL`, `ADGH_USER`, `ADGH_PASS`, `LAN_IP`, etc.) are not documented
2. **[CONFIG]** `etc/adguard-rewrite.conf:3-4` — Active configuration file contains literal `"REDACTED"` placeholders instead of providing an `.example` template

## .env.example Audit

- Variables in code but NOT in .env.example: `ADGH_URL`, `ADGH_USER`, `ADGH_PASS`, `LAN_IP`, `ADGUARD_URL`, `PROBE_DOMAIN`, `DOH_SERVER`, `CHECK_INTERVAL`, `FAIL_THRESHOLD`
- Variables in .env.example but NOT in code: none (.env.example does not exist)

## Recommendation

Fix the 10 critical findings and re-run sanitizer. Specifically:
1. Anonymize device hostnames (`wmsaaPC`, `A35-de-Elmir`) and firewall redirect names (`DoH_wmsaapc`, `DoH_a35deelmir`) using generic placeholders (e.g., `client_1`, `client_2`).
2. Replace real hardware MAC addresses and DUIDs with standard dummy documentation values (e.g., `00:11:22:33:44:55`).
3. Add a `.env.example` (or `etc/adguard-rewrite.conf.example`) documenting all configurable variables, default router IP placeholders (`192.168.0.1`), and credentials.
4. Squash git history into a single clean initial commit (`git reset --soft` or recreating the git repo) to eliminate leaked personal identifiers from previous commits.
