#!/usr/bin/env bash
# Resolves Firefox's real (XDG) default profile and keeps a stable symlink to
# it at ~/.local/state/matugen/firefox-profile, so matugen's config.toml never
# has to hardcode a profile hash that changes across installs/profile resets.
#
# Also guards against Firefox 147+'s "prefer ~/.mozilla if it exists" behavior
# silently reviving an empty legacy profile: if ~/.mozilla exists but its
# default profile has no real history while ~/.config/mozilla's does, the
# legacy dir gets moved out of the way automatically.
#
# Safe to re-run anytime (idempotent). Run from Hyprland autostart.

set -euo pipefail

XDG_PROFILES_INI="$HOME/.config/mozilla/firefox/profiles.ini"
LEGACY_PROFILES_INI="$HOME/.mozilla/firefox/profiles.ini"
LINK_DIR="$HOME/.local/state/matugen"
LINK_PATH="$LINK_DIR/firefox-profile"

row_count() {
    local db="$1"
    [ -f "$db" ] || { echo 0; return; }
    sqlite3 "$db" "SELECT COUNT(*) FROM moz_places;" 2>/dev/null || echo 0
}

default_profile_dir() {
    local ini_dir="$1"
    local ini="$2"
    [ -f "$ini" ] || return 1
    local rel
    rel=$(awk -F= '/^\[Profile0\]/{f=1} f&&/^Path=/{print $2; exit}' "$ini")
    [ -n "$rel" ] && echo "$ini_dir/$rel"
}

XDG_PROFILE=$(default_profile_dir "$HOME/.config/mozilla/firefox" "$XDG_PROFILES_INI" || true)
LEGACY_PROFILE=$(default_profile_dir "$HOME/.mozilla/firefox" "$LEGACY_PROFILES_INI" || true)

XDG_ROWS=0
LEGACY_ROWS=0
[ -n "${XDG_PROFILE:-}" ] && XDG_ROWS=$(row_count "$XDG_PROFILE/places.sqlite")
[ -n "${LEGACY_PROFILE:-}" ] && LEGACY_ROWS=$(row_count "$LEGACY_PROFILE/places.sqlite")

# If the legacy dir exists but is empty while the XDG profile has real data,
# move it out of the way so Firefox stops preferring the empty one.
if [ -d "$HOME/.mozilla" ] && [ "$LEGACY_ROWS" -eq 0 ] && [ "$XDG_ROWS" -gt 0 ]; then
    mv "$HOME/.mozilla" "$HOME/.mozilla.stub-backup-$(date +%Y%m%d-%H%M%S)"
    LEGACY_PROFILE=""
fi

REAL_PROFILE="${XDG_PROFILE:-$LEGACY_PROFILE}"

# Firefox hasn't been run yet on this machine — nothing to link.
[ -z "${REAL_PROFILE:-}" ] && exit 0

mkdir -p "$LINK_DIR" "$REAL_PROFILE/chrome"
ln -sfn "$REAL_PROFILE" "$LINK_PATH"
