#!/usr/bin/env bash
STATE_FILE="$HOME/.cache/qs_battery_last_status"

get_battery_percent() { LC_ALL=C cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo "100"; }
get_battery_status() { LC_ALL=C cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo "Full"; }
get_battery_icon() {
    local percent=$(get_battery_percent)
    local status=$(get_battery_status)
    if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        if [ "$percent" -ge 90 ]; then echo "󰂅"
        elif [ "$percent" -ge 80 ]; then echo "󰂋"
        elif [ "$percent" -ge 60 ]; then echo "󰂊"
        elif [ "$percent" -ge 40 ]; then echo "󰢞"
        elif [ "$percent" -ge 20 ]; then echo "󰂆"
        else echo "󰢜"; fi
    else
        if [ "$percent" -ge 90 ]; then echo "󰁹"
        elif [ "$percent" -ge 80 ]; then echo "󰂂"
        elif [ "$percent" -ge 70 ]; then echo "󰂁"
        elif [ "$percent" -ge 60 ]; then echo "󰂀"
        elif [ "$percent" -ge 50 ]; then echo "󰁿"
        elif [ "$percent" -ge 40 ]; then echo "󰁾"
        elif [ "$percent" -ge 30 ]; then echo "󰁽"
        elif [ "$percent" -ge 20 ]; then echo "󰁼"
        elif [ "$percent" -ge 10 ]; then echo "󰁻"
        else echo "󰁺"; fi
    fi
}

status=$(get_battery_status)
percent=$(get_battery_percent)

last_status=""
[ -f "$STATE_FILE" ] && last_status=$(cat "$STATE_FILE")

# Only fire a toast if we have a previous reading AND it actually changed
if [ -n "$last_status" ] && [ "$last_status" != "$status" ]; then
    case "$status" in
        "Charging")
            notify-send -a "Battery" "Charging" "${percent}%" -t 4000 &
            ;;
        "Full")
            notify-send -a "Battery" "Fully charged" -t 4000 &
            ;;
        "Discharging")
            # Skip the unplug toast if we were already fully charged - nothing new to say
            if [ "$last_status" != "Full" ]; then
                notify-send -a "Battery" "Unplugged" "${percent}%" -t 4000 &
            fi
            ;;
    esac
fi

echo "$status" > "$STATE_FILE"

jq -n -c --arg percent "$percent" --arg status "$status" --arg icon "$(get_battery_icon)" '{percent: $percent, status: $status, icon: $icon}'
