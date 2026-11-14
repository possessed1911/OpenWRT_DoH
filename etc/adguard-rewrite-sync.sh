#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

CONF="/etc/adguard-rewrite.conf"
[ -f "$CONF" ] || { echo "Missing $CONF" >&2; exit 1; }
. "$CONF"

if [ -z "$ADGH_USER" ] || [ -z "$ADGH_PASS" ]; then
    echo "Set ADGH_USER and ADGH_PASS in $CONF first." >&2
    exit 1
fi

. /lib/functions.sh

LAN_IP=$(uci -q get network.lan.ipaddr | cut -d/ -f1)
[ -z "$LAN_IP" ] && LAN_IP="192.168.0.1"
ROUTER_HOST=$(uci -q get system.@system[0].hostname)
[ -z "$ROUTER_HOST" ] && ROUTER_HOST="OpenWrt"
DOMAIN=$(uci -q get dhcp.@dnsmasq[0].domain)
[ -z "$DOMAIN" ] && DOMAIN="lan"

AUTH_B64=$(ucode -e "print(b64enc('${ADGH_USER}:${ADGH_PASS}'));")
TMP_LIST="/tmp/adgh-rewrites.$$"
TMP_DESIRED="/tmp/adgh-desired.$$"
trap 'rm -f "$TMP_LIST" "$TMP_DESIRED"' EXIT

if ! uclient-fetch -q -O "$TMP_LIST" \
    --header="Authorization: Basic ${AUTH_B64}" \
    "${ADGH_URL}/control/rewrite/list"; then
    logger -t adguard-rewrite "Failed to fetch ${ADGH_URL}/control/rewrite/list"
    exit 1
fi

EXISTING=$(ucode -e "
import { readfile } from 'fs';
let arr = json(readfile('$TMP_LIST'));
for (let item in arr)
    printf('%s|%s\\n', item.domain, item.answer);
")

printf '%s.%s|%s\n' "$ROUTER_HOST" "$DOMAIN" "$LAN_IP" > "$TMP_DESIRED"

collect_host() {
    local cfg="$1" name ip
    config_get name "$cfg" name
    config_get ip "$cfg" ip
    [ -n "$name" ] && [ -n "$ip" ] || return 0
    ip="${ip%%/*}"
    name="${name%.$DOMAIN}"
    printf '%s.%s|%s\n' "$name" "$DOMAIN" "$ip" >> "$TMP_DESIRED"
}

config_load dhcp
config_foreach collect_host host

while IFS='|' read -r dom ans; do
    [ -z "$dom" ] && continue
    if printf '%s\n' "$EXISTING" | grep -qxiF "${dom}|${ans}"; then
        continue
    fi
    PAYLOAD=$(printf '{"domain":"%s","answer":"%s"}' "$dom" "$ans")
    if uclient-fetch -q -O /dev/null \
        --header="Authorization: Basic ${AUTH_B64}" \
        --header="Content-Type: application/json" \
        --post-data="$PAYLOAD" \
        "${ADGH_URL}/control/rewrite/add"; then
        logger -t adguard-rewrite "Added rewrite: ${dom} -> ${ans}"
        echo "Added: ${dom} -> ${ans}"
    else
        logger -t adguard-rewrite "Failed to add rewrite: ${dom} -> ${ans}"
        echo "Failed: ${dom} -> ${ans}" >&2
    fi
done < "$TMP_DESIRED"
