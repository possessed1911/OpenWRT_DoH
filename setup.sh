#!/usr/bin/env bash
set -euo pipefail

echo "=== OpenWRT_DoH Setup ==="

# Check environment
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example — edit it with your values"
fi

# Load environment configuration if available
if [ -f .env ]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' .env | grep -v '^$' | xargs) 2>/dev/null || true
fi

ROUTER_IP="${LAN_IP:-192.168.0.1}"
DEPLOY_TARGET="${DEPLOY_TARGET:-root@${ROUTER_IP}}"

# Detect runtime target
IS_OPENWRT=0
if [ -f /etc/openwrt_release ] || command -v uci >/dev/null 2>&1; then
  IS_OPENWRT=1
fi

if [ "$IS_OPENWRT" -eq 1 ]; then
  echo "Detected direct OpenWrt environment."
  echo "Checking required packages..."

  command -v opkg >/dev/null 2>&1 || { echo "Error: opkg is required on OpenWrt."; exit 1; }

  PKGS="https-dns-proxy ucode uclient-fetch util-linux-flock jsonfilter bind-tools"
  MISSING_PKGS=""
  for pkg in $PKGS; do
    if ! opkg list-installed | grep -q "^${pkg} "; then
      MISSING_PKGS="${MISSING_PKGS} ${pkg}"
    fi
  done

  if [ -n "$MISSING_PKGS" ]; then
    echo "Installing missing packages:${MISSING_PKGS}..."
    opkg update
    # shellcheck disable=SC2086
    opkg install $MISSING_PKGS
  else
    echo "All required OpenWrt packages are already installed."
  fi

  echo "Deploying files into router filesystem..."
  mkdir -p /etc/config /etc/init.d /etc/hotplug.d/iface /usr/bin

  cp -f etc/auto-doh-sync.sh /etc/auto-doh-sync.sh
  cp -f etc/doh-common.sh /etc/doh-common.sh
  cp -f etc/adguard-rewrite-sync.sh /etc/adguard-rewrite-sync.sh
  [ -f etc/adguard-rewrite.conf ] && cp -n etc/adguard-rewrite.conf /etc/adguard-rewrite.conf || true
  cp -f etc/irq-rps-tune.sh /etc/irq-rps-tune.sh
  cp -f etc/hotplug.d/iface/99-irq-rps /etc/hotplug.d/iface/99-irq-rps
  cp -f usr/bin/doh-watchdog.sh /usr/bin/doh-watchdog.sh
  cp -f etc/init.d/doh-watchdog /etc/init.d/doh-watchdog

  echo "Setting executable permissions..."
  chmod +x /etc/auto-doh-sync.sh \
           /etc/adguard-rewrite-sync.sh \
           /etc/irq-rps-tune.sh \
           /etc/hotplug.d/iface/99-irq-rps \
           /usr/bin/doh-watchdog.sh \
           /etc/init.d/doh-watchdog

  echo "Preserving files in /etc/sysupgrade.conf..."
  if [ -f etc/sysupgrade.conf ] && [ -f /etc/sysupgrade.conf ]; then
    while read -r line; do
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      if ! grep -qxF "$line" /etc/sysupgrade.conf 2>/dev/null; then
        echo "$line" >> /etc/sysupgrade.conf
      fi
    done < etc/sysupgrade.conf
  fi

  echo "Enabling and starting doh-watchdog service..."
  /etc/init.d/doh-watchdog enable
  /etc/init.d/doh-watchdog restart

  echo "Executing initial DoH sync..."
  /etc/auto-doh-sync.sh

  echo ""
  echo "=== Setup complete! ==="
  echo ""
  echo "Next steps on OpenWrt:"
  echo "  1. Review /etc/adguard-rewrite.conf and update credentials if needed."
  echo "  2. Monitor watchdog logs: logread -f -e doh-watchdog"
  echo "  3. Test DoH query: nslookup example.com 127.0.0.1 -port=5000"
  echo "  4. Using Claude Code? CLAUDE.md has all the context."
  exit 0
fi

# Host workstation mode
echo "Running in workstation / development mode."
echo "Checking prerequisites..."

for cmd in bash ssh scp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Warning: $cmd not found in PATH."; }
done

echo "Verifying script syntax..."
for script in etc/*.sh usr/bin/*.sh; do
  if [ -f "$script" ]; then
    if command -v sh >/dev/null 2>&1; then
      sh -n "$script"
      echo "  [OK] $script"
    fi
  fi
done

DEPLOY=0
if [ "${1:-}" = "--deploy" ] || [ "${1:-}" = "-d" ]; then
  DEPLOY=1
fi

if [ "$DEPLOY" -eq 1 ]; then
  echo ""
  echo "Deploying to router at ${DEPLOY_TARGET}..."
  ssh -q "$DEPLOY_TARGET" exit || {
    echo "Error: Cannot connect via SSH to ${DEPLOY_TARGET}."
    echo "Check network connection or set ROUTER_IP in .env"
    exit 1
  }

  echo "Copying files to router..."
  scp -r etc usr setup.sh "${DEPLOY_TARGET}:/tmp/openwrt_doh_install/"
  ssh "${DEPLOY_TARGET}" "cd /tmp/openwrt_doh_install && chmod +x setup.sh && ./setup.sh"
  ssh "${DEPLOY_TARGET}" "rm -rf /tmp/openwrt_doh_install"

  echo ""
  echo "=== Deployment complete! ==="
  exit 0
fi

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env with your configuration (router IP, AdGuard credentials)"
echo "  2. To deploy to your router, run: ./setup.sh --deploy"
echo "     (or: DEPLOY_TARGET=root@192.168.0.1 ./setup.sh --deploy)"
echo "  3. Using Claude Code? CLAUDE.md has all the context."
