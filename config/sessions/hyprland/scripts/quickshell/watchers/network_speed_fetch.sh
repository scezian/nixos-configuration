#!/usr/bin/env bash
IFACE=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -n1)
if [ -z "$IFACE" ]; then
    jq -n -c '{down: "0 B/s", up: "0 B/s"}'
    exit 0
fi

read RX1 TX1 < <(awk -v iface="$IFACE:" '$1==iface {print $2, $10}' /proc/net/dev)
sleep 1
read RX2 TX2 < <(awk -v iface="$IFACE:" '$1==iface {print $2, $10}' /proc/net/dev)

RX_RATE=$(( (RX2 - RX1) ))
TX_RATE=$(( (TX2 - TX1) ))

format_speed() {
    local bytes=$1
    if [ "$bytes" -ge 1048576 ]; then
        printf "%.1f MB/s" "$(echo "$bytes / 1048576" | bc -l)"
    elif [ "$bytes" -ge 1024 ]; then
        printf "%.0f KB/s" "$(echo "$bytes / 1024" | bc -l)"
    else
        printf "%d B/s" "$bytes"
    fi
}

jq -n -c --arg down "$(format_speed $RX_RATE)" --arg up "$(format_speed $TX_RATE)" '{down: $down, up: $up}'
