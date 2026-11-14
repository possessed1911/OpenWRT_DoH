#!/bin/sh
# Pin MT7621 Ethernet and MT7915E Wi-Fi IRQs across CPUs (no firewall mutations).

ETH_IRQ=$(awk '/1e100000\.ethernet/ {gsub(/:/,"",$1); print $1}' /proc/interrupts)
HIF_IRQ=$(awk '/mt7915e-hif/ {gsub(/:/,"",$1); print $1}' /proc/interrupts)
WIFI_IRQ=$(awk '$NF == "mt7915e" {gsub(/:/,"",$1); print $1}' /proc/interrupts)

[ -n "$ETH_IRQ" ]  && [ -f "/proc/irq/$ETH_IRQ/smp_affinity" ]  && echo 1 > "/proc/irq/$ETH_IRQ/smp_affinity"
[ -n "$WIFI_IRQ" ] && [ -f "/proc/irq/$WIFI_IRQ/smp_affinity" ] && echo 4 > "/proc/irq/$WIFI_IRQ/smp_affinity"
[ -n "$HIF_IRQ" ]  && [ -f "/proc/irq/$HIF_IRQ/smp_affinity" ]  && echo 8 > "/proc/irq/$HIF_IRQ/smp_affinity"

[ -f /sys/class/net/pppoe-wan/tx_queue_len ] && echo 100 > /sys/class/net/pppoe-wan/tx_queue_len
