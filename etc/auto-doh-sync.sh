#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

. /lib/functions.sh
. /etc/doh-common.sh

ADGUARD_URL="https://adgh.example.com/dns-query"
PROXY_CONF="/etc/config/https-dns-proxy"
PREV_HASH_FILE="/tmp/auto-doh-sync.hash"
BASE_PORT=5000
FWD_BASE_PORT=6000
LAN_IP="192.168.0.1"
LAN_PREFIX="${LAN_IP%.*}"

TMP_PROXY="/tmp/https-dns-proxy.sync.$$"
TMP_HOSTS="/tmp/auto-doh-hosts.$$"

cleanup() {
    rm -f "$TMP_PROXY" "$TMP_HOSTS"
    doh_unlock
}

doh_lock || exit 0
trap 'cleanup' EXIT

doh_sync_dnsmasq "$LAN_IP"

SEEN_OCTETS=""
: > "$TMP_HOSTS"

collect_static_host() {
    local cfg="$1"
    local ip raw_name o1 o2 o3 o4 part octet clean_name proxy_port fwd_port sec fwd_sec

    config_get ip "$cfg" ip
    [ -z "$ip" ] && return 0

    case "$ip" in
        */*) ip="${ip%%/*}" ;;
    esac
    case "$ip" in
        *[!0-9.]*) return 0 ;;
    esac

    IFS=. read -r o1 o2 o3 o4 << EOF
$ip
EOF
    [ -n "$o1" ] && [ -n "$o2" ] && [ -n "$o3" ] && [ -n "$o4" ] || return 0
    for part in "$o1" "$o2" "$o3" "$o4"; do
        case "$part" in
            ''|*[!0-9]*|0?*) return 0 ;;
        esac
        [ "$part" -ge 0 ] && [ "$part" -le 255 ] || return 0
    done

    [ "$ip" = "$LAN_IP" ] && return 0
    [ "${o1}.${o2}.${o3}" = "$LAN_PREFIX" ] || return 0
    [ "$o4" -ge 2 ] && [ "$o4" -le 254 ] || return 0

    octet="$o4"
    case " $SEEN_OCTETS " in
        *" $octet "*) return 0 ;;
    esac
    SEEN_OCTETS="$SEEN_OCTETS $octet"

    config_get raw_name "$cfg" name
    clean_name=""
    if [ -n "$raw_name" ]; then
        clean_name=$(printf '%s' "$raw_name" | sed 's/\.lan$//' | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_' | sed -e 's/^[^a-z0-9]*//' -e 's/[^a-z0-9]*$//')
    fi
    [ -z "$clean_name" ] && clean_name="device_${octet}"

    proxy_port=$((BASE_PORT + octet))
    fwd_port=$((FWD_BASE_PORT + octet))
    sec="doh_${octet}"
    fwd_sec="fwd_${octet}"
    printf '%s|%s|%s|%s|%s|%s\n' "$sec" "$ip" "$proxy_port" "$fwd_port" "$clean_name" "$fwd_sec" >> "$TMP_HOSTS"
}

config_load dhcp
config_foreach collect_static_host host

FAILOVER_FLAG=0
[ -f /tmp/doh-failover ] && FAILOVER_FLAG=1

CURRENT_HASH=$( { printf 'base=%s|%s|%s|%s|%s\n' "$LAN_IP" "$BASE_PORT" "$FWD_BASE_PORT" "$ADGUARD_URL" "$FAILOVER_FLAG"; cat "$TMP_HOSTS"; } | md5sum | cut -d' ' -f1 )
if [ -f "$PREV_HASH_FILE" ] \
   && [ "$CURRENT_HASH" = "$(cat "$PREV_HASH_FILE" 2>/dev/null)" ] \
   && grep -q "doh_google_backup" "$PROXY_CONF" 2>/dev/null \
   && [ -n "$(uci -q get firewall.block_ipv6_dns_fwd)" ] \
   && [ -n "$(uci -q get firewall.doh_default)" ]; then
    exit 0
fi

# 1. Disable IPv6 DNS advertisement in odhcpd only if changed
if [ "$(uci -q get dhcp.lan.dns_service)" != "0" ] || [ -n "$(uci -q get dhcp.lan.dns)" ]; then
    uci set dhcp.lan.dns_service="0"
    uci -q delete dhcp.lan.dns
    uci commit dhcp
    /etc/init.d/odhcpd restart >/dev/null 2>&1
fi

# 2. Build https-dns-proxy config bound to 127.0.0.1
cat << HEADER > "$TMP_PROXY"
config main 'config'
	option force_dns '0'
	option dnsmasq_config_update '-'
	option heartbeat_domain '-'
	option notrack_dns '0'
	option polling_interval '3600'

config https-dns-proxy 'doh_default'
	option resolver_url '${ADGUARD_URL}/home'
	option bootstrap_dns '1.1.1.1,8.8.8.8'
	option listen_addr '127.0.0.1'
	option listen_port '${BASE_PORT}'
	option user 'nobody'
	option group 'nogroup'

config https-dns-proxy 'doh_google_backup'
	option resolver_url 'https://dns.google/dns-query'
	option bootstrap_dns '8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844'
	option listen_addr '127.0.0.1'
	option listen_port '5054'
	option user 'nobody'
	option group 'nogroup'

HEADER

DESIRED_REDIRECTS="doh_default"
DESIRED_FWDS=""
while IFS='|' read -r sec ip proxy_port fwd_port clean_name fwd_sec; do
    [ -z "$sec" ] && continue
    DESIRED_REDIRECTS="$DESIRED_REDIRECTS $sec"
    DESIRED_FWDS="$DESIRED_FWDS $fwd_sec"
    cat << INSTANCE >> "$TMP_PROXY"
config https-dns-proxy '${sec}'
	option resolver_url '${ADGUARD_URL}/${clean_name}'
	option bootstrap_dns '1.1.1.1,8.8.8.8'
	option listen_addr '127.0.0.1'
	option listen_port '${proxy_port}'
	option user 'nobody'
	option group 'nogroup'

INSTANCE
done < "$TMP_HOSTS"

NEED_PROXY_RELOAD=0
if [ ! -f "$PROXY_CONF" ] || ! cmp -s "$TMP_PROXY" "$PROXY_CONF"; then
    cp "$TMP_PROXY" "$PROXY_CONF"
    NEED_PROXY_RELOAD=1
fi

# 3. Sync per-device dnsmasq forwarders in /etc/config/dhcp (diff-only)
DHCP_CHANGED=0
for s in $(uci show dhcp 2>/dev/null | grep -E '^dhcp\.fwd_[0-9]+=dnsmasq$' | cut -d. -f2 | cut -d= -f1); do
    case " $DESIRED_FWDS " in
        *" $s "*) ;;
        *)
            uci -q delete "dhcp.${s}"
            DHCP_CHANGED=1
            ;;
    esac
done

dhcp_set_opt() {
    local key="$1" desired="$2" cur
    cur=$(uci -q get "$key")
    if [ "$cur" != "$desired" ]; then
        uci set "${key}=${desired}"
        DHCP_CHANGED=1
    fi
}

while IFS='|' read -r sec ip proxy_port fwd_port clean_name fwd_sec; do
    [ -z "$fwd_sec" ] && continue
    dhcp_set_opt "dhcp.${fwd_sec}" "dnsmasq"
    dhcp_set_opt "dhcp.${fwd_sec}.port" "$fwd_port"
    dhcp_set_opt "dhcp.${fwd_sec}.localservice" "1"
    dhcp_set_opt "dhcp.${fwd_sec}.noresolv" "1"
    dhcp_set_opt "dhcp.${fwd_sec}.strictorder" "1"
    main_cachesize="$(uci -q get dhcp.main.cachesize)"
    [ -n "$main_cachesize" ] || main_cachesize="1000"
    dhcp_set_opt "dhcp.${fwd_sec}.cachesize" "$main_cachesize"
    dhcp_set_opt "dhcp.${fwd_sec}.min_cache_ttl" "60"
    dhcp_set_opt "dhcp.${fwd_sec}.nohosts" "1"
    dhcp_set_opt "dhcp.${fwd_sec}.ignore_hosts_dir" "1"
    dhcp_set_opt "dhcp.${fwd_sec}.rebind_protection" "1"

    cur_listen=$(uci -q get "dhcp.${fwd_sec}.listen_address" | tr '\n' ' ' | sed 's/ $//')
    if [ "$cur_listen" != "$LAN_IP" ]; then
        uci -q delete "dhcp.${fwd_sec}.listen_address"
        uci add_list "dhcp.${fwd_sec}.listen_address=${LAN_IP}"
        DHCP_CHANGED=1
    fi

    cur_rebind=$(uci -q get "dhcp.${fwd_sec}.rebind_domain" | tr '\n' ' ' | sed 's/ $//')
    if [ "$cur_rebind" != "lan" ]; then
        uci -q delete "dhcp.${fwd_sec}.rebind_domain"
        uci add_list "dhcp.${fwd_sec}.rebind_domain=lan"
        DHCP_CHANGED=1
    fi

    desired_srv="/lan/127.0.0.1#53 /0.168.192.in-addr.arpa/127.0.0.1#53 127.0.0.1#${proxy_port} 127.0.0.1#5054 /mask.icloud.com/ /mask-h2.icloud.com/ /use-application-dns.net/"
    cur_srv=$(uci -q get "dhcp.${fwd_sec}.server" | tr '\n' ' ' | sed 's/ $//')
    if [ "$cur_srv" != "$desired_srv" ]; then
        uci -q delete "dhcp.${fwd_sec}.server"
        for srv in $desired_srv; do
            uci add_list "dhcp.${fwd_sec}.server=${srv}"
        done
        DHCP_CHANGED=1
    fi
done < "$TMP_HOSTS"

if [ "$DHCP_CHANGED" -eq 1 ]; then
    uci commit dhcp
fi

# 4. Sync fw4 rules and dstnat_lan redirects
FW_CHANGED=0

fw_set_opt() {
    local key="$1" desired="$2" current
    current=$(uci -q get "$key")
    if [ "$current" != "$desired" ]; then
        uci set "${key}=${desired}"
        FW_CHANGED=1
    fi
}

fw_del_opt() {
    local key="$1"
    if [ -n "$(uci -q get "$key")" ]; then
        uci -q delete "$key"
        FW_CHANGED=1
    fi
}

for s in $(doh_get_redirects); do
    case " $DESIRED_REDIRECTS " in
        *" $s "*) ;;
        *)
            uci -q delete "firewall.${s}"
            FW_CHANGED=1
            ;;
    esac
done

fw_set_opt "firewall.block_ipv6_dns" "rule"
fw_set_opt "firewall.block_ipv6_dns.name" "Block_LAN_IPv6_DNS"
fw_set_opt "firewall.block_ipv6_dns.src" "lan"
fw_del_opt "firewall.block_ipv6_dns.dest"
fw_set_opt "firewall.block_ipv6_dns.proto" "tcp udp"
fw_set_opt "firewall.block_ipv6_dns.family" "ipv6"
fw_set_opt "firewall.block_ipv6_dns.dest_port" "53"
fw_set_opt "firewall.block_ipv6_dns.target" "REJECT"

fw_set_opt "firewall.block_ipv6_dns_fwd" "rule"
fw_set_opt "firewall.block_ipv6_dns_fwd.name" "Block_LAN_IPv6_DNS_Forward"
fw_set_opt "firewall.block_ipv6_dns_fwd.src" "lan"
fw_set_opt "firewall.block_ipv6_dns_fwd.dest" "*"
fw_set_opt "firewall.block_ipv6_dns_fwd.proto" "tcp udp"
fw_set_opt "firewall.block_ipv6_dns_fwd.family" "ipv6"
fw_set_opt "firewall.block_ipv6_dns_fwd.dest_port" "53"
fw_set_opt "firewall.block_ipv6_dns_fwd.target" "REJECT"

while IFS='|' read -r sec ip proxy_port fwd_port clean_name fwd_sec; do
    [ -z "$sec" ] && continue
    fw_set_opt "firewall.${sec}" "redirect"
    fw_set_opt "firewall.${sec}.name" "DoH_${clean_name}"
    fw_set_opt "firewall.${sec}.src" "lan"
    fw_set_opt "firewall.${sec}.proto" "tcp udp"
    fw_set_opt "firewall.${sec}.src_ip" "$ip"
    fw_set_opt "firewall.${sec}.src_dport" "53"
    fw_set_opt "firewall.${sec}.dest_port" "$fwd_port"
    fw_set_opt "firewall.${sec}.target" "DNAT"
    fw_del_opt "firewall.${sec}.enabled"
done < "$TMP_HOSTS"

LAST_REDIR=$(doh_get_redirects | tail -n 1)
if [ -n "$LAST_REDIR" ] && [ "$LAST_REDIR" != "doh_default" ]; then
    uci -q delete firewall.doh_default
    FW_CHANGED=1
fi

fw_set_opt "firewall.doh_default" "redirect"
fw_set_opt "firewall.doh_default.name" "DoH_Default"
fw_set_opt "firewall.doh_default.src" "lan"
fw_del_opt "firewall.doh_default.src_ip"
fw_set_opt "firewall.doh_default.dest_ip" "!${LAN_IP}"
fw_set_opt "firewall.doh_default.proto" "tcp udp"
fw_set_opt "firewall.doh_default.src_dport" "53"
fw_set_opt "firewall.doh_default.dest_port" "53"
fw_set_opt "firewall.doh_default.target" "DNAT"
fw_del_opt "firewall.doh_default.enabled"

if [ "$FW_CHANGED" -eq 1 ]; then
    uci commit firewall
fi

echo "$CURRENT_HASH" > "$PREV_HASH_FILE"

[ "$NEED_PROXY_RELOAD" -eq 1 ] && /etc/init.d/https-dns-proxy restart >/dev/null 2>&1
[ "$DHCP_CHANGED" -eq 1 ] && /etc/init.d/dnsmasq restart >/dev/null 2>&1
[ "$FW_CHANGED" -eq 1 ] && /etc/init.d/firewall reload >/dev/null 2>&1
[ -x /etc/adguard-rewrite-sync.sh ] && /etc/adguard-rewrite-sync.sh >/dev/null 2>&1 &
exit 0
