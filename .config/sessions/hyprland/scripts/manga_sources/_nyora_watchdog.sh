#!/usr/bin/env bash
# Kills the Nyora helper once the manga panel has been closed for IDLE seconds.
IDLE=30
PIDF="$HOME/.cache/qs-manga/nyora-watchdog.pid"
mkdir -p "$(dirname "$PIDF")"
echo $$ > "$PIDF"
trap 'rm -f "$PIDF"' EXIT
n=0
while pgrep -f nyora-helper.jar >/dev/null; do
  if [ "$(cat /tmp/qs_current_widget 2>/dev/null)" = "manga" ]; then n=0; else n=$((n+2)); fi
  if [ "$n" -ge "$IDLE" ]; then pkill -f nyora-helper.jar; break; fi
  sleep 2
done
