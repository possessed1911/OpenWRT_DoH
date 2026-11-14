#!/bin/sh

. /etc/doh-common.sh

PROBE_DOMAIN="cloudflare.com"
DOH_SERVER="127.0.0.1:5000"
LAN_IP="192.168.0.1"
CHECK_INTERVAL=30
FAIL_THRESHOLD=2
FAIL_COUNT=0

trap 'doh_unlock' EXIT
trap 'doh_unlock; exit 0' INT TERM

logger -t doh-watchdog "Starting dynamic DoH failover watchdog (Interval: ${CHECK_INTERVAL}s, Target: ${DOH_SERVER})."

# Check if PPPoE WAN has active connectivity
check_pppoe_connectivity() {
    local wan_up
    wan_up=$(ubus call network.interface.wan status 2>/dev/null | jsonfilter -e "@.up")
    [ "$wan_up" = "true" ] || return 1

    ping -c 1 -W 2 -I pppoe-wan 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 -I pppoe-wan 8.8.8.8 >/dev/null 2>&1 || return 1

    return 0
}

# Sync marker and dnsmasq state with persisted firewall redirect state on startup
if doh_lock; then
    if doh_is_disabled; then
        touch /tmp/doh-failover
    else
        rm -f /tmp/doh-failover
    fi
    doh_sync_dnsmasq "$LAN_IP"
    doh_unlock
fi

while true; do
    if nslookup "$PROBE_DOMAIN" "$DOH_SERVER" >/dev/null 2>&1; then
        FAIL_COUNT=0
        if doh_is_disabled || [ -f /tmp/doh-failover ]; then
            logger -t doh-watchdog "AdGuard DoH is healthy. Restoring all dynamic client DNAT redirects and primary dnsmasq upstream."
            if doh_lock; then
                for r in $(doh_get_redirects); do
                    uci -q delete firewall."$r".enabled
                done
                uci commit firewall
                rm -f /tmp/doh-failover
                doh_sync_dnsmasq "$LAN_IP"
                /etc/init.d/firewall reload >/dev/null 2>&1
                doh_unlock
            fi
        fi
    else
        if ! check_pppoe_connectivity; then
            logger -t doh-watchdog "AdGuard probe failed, but PPPoE WAN has no connectivity. Suppressing DoH swap."
            FAIL_COUNT=0
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            logger -t doh-watchdog "AdGuard DoH probe failed ($FAIL_COUNT/$FAIL_THRESHOLD) while PPPoE is online."
            if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]; then
                if ! doh_is_disabled || [ ! -f /tmp/doh-failover ]; then
                    logger -t doh-watchdog "AdGuard DoH confirmed DOWN! Failing over client DNAT redirects and dnsmasq upstream to Google DoH."
                    if doh_lock; then
                        for r in $(doh_get_redirects); do
                            uci set firewall."$r".enabled="0"
                        done
                        uci commit firewall
                        touch /tmp/doh-failover
                        doh_sync_dnsmasq "$LAN_IP"
                        /etc/init.d/firewall reload >/dev/null 2>&1
                        doh_unlock
                    fi
                fi
            fi
        fi
    fi
    sleep "$CHECK_INTERVAL"
done
