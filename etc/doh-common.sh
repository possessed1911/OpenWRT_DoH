#!/bin/sh
# Shared locking, DoH redirect discovery, and dnsmasq upstream sync helpers.

DOH_LOCK_FILE="/tmp/doh-fw.lock"

doh_lock() {
    local lockfile="${1:-$DOH_LOCK_FILE}"
    local retries="${2:-30}"
    exec 9>"$lockfile"
    while ! flock -x -n 9; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
            exec 9>&- 2>/dev/null
            return 1
        fi
        sleep 1
    done
    return 0
}

doh_unlock() {
    flock -u 9 2>/dev/null
    exec 9>&- 2>/dev/null
}

doh_get_redirects() {
    local s name
    uci show firewall 2>/dev/null | grep -E '^firewall\..*=redirect$' | cut -d. -f2 | cut -d= -f1 | while read -r s; do
        name=$(uci -q get firewall."$s".name)
        case "$s" in
            doh_*|[Dd]o[Hh]_*) echo "$s"; continue ;;
        esac
        case "$name" in
            [Dd]o[Hh]_*|doh_*) echo "$s"; continue ;;
        esac
    done
}

doh_is_disabled() {
    local r
    for r in $(doh_get_redirects); do
        if [ "$(uci -q get firewall."$r".enabled)" = "0" ]; then
            return 0
        fi
    done
    return 1
}

# Keep main dnsmasq aligned with /tmp/doh-failover (127.0.0.1#5000 -> 127.0.0.1#5054)
doh_sync_dnsmasq() {
    local lan_ip="${1:-192.168.0.1}"
    local need_restart=0
    local failover=0
    local had_noglob=0
    local s cur_srv desired_srv cur_listen desired_listen

    case "$-" in *f*) had_noglob=1 ;; esac
    set -f

    [ -f /tmp/doh-failover ] && failover=1

    if [ -n "$(uci -q get dhcp.main.doh_server)" ]; then
        uci -q delete dhcp.main.doh_server
        need_restart=1
    fi
    if [ "$(uci -q get dhcp.main.noresolv)" != "1" ]; then
        uci set dhcp.main.noresolv="1"
        need_restart=1
    fi
    if [ -n "$(uci -q get dhcp.main.strict_order)" ]; then
        uci -q delete dhcp.main.strict_order
        need_restart=1
    fi
    if [ "$(uci -q get dhcp.main.strictorder)" != "1" ]; then
        uci set dhcp.main.strictorder="1"
        need_restart=1
    fi
    if [ -n "$(uci -q get dhcp.main.doh_backup_noresolv)" ] || [ -n "$(uci -q get dhcp.main.doh_backup_server)" ]; then
        uci -q delete dhcp.main.doh_backup_noresolv
        uci -q delete dhcp.main.doh_backup_server
        need_restart=1
    fi

    if [ "$failover" -eq 1 ]; then
        desired_srv="127.0.0.1#5054"
    else
        desired_srv="127.0.0.1#5000 127.0.0.1#5054"
    fi
    for s in $(uci -q get dhcp.main.server); do
        case "$s" in
            /*) desired_srv="$desired_srv $s" ;;
        esac
    done

    cur_srv=$(uci -q get dhcp.main.server | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//')
    if [ "$cur_srv" != "$desired_srv" ]; then
        uci -q delete dhcp.main.server
        for s in $desired_srv; do
            uci add_list dhcp.main.server="$s"
        done
        need_restart=1
    fi

    desired_listen="127.0.0.1 ${lan_ip}"
    cur_listen=$(uci -q get dhcp.main.listen_address | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//')
    if [ "$cur_listen" != "$desired_listen" ] || [ -n "$(uci -q get dhcp.main.notinterface)" ]; then
        uci -q delete dhcp.main.notinterface
        uci -q delete dhcp.main.listen_address
        uci add_list dhcp.main.listen_address="127.0.0.1"
        uci add_list dhcp.main.listen_address="${lan_ip}"
        need_restart=1
    fi

    [ "$had_noglob" -eq 0 ] && set +f

    if [ "$need_restart" -eq 1 ]; then
        uci commit dhcp
        /etc/init.d/dnsmasq restart >/dev/null 2>&1
    fi
}
