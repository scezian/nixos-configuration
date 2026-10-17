#!/usr/bin/env bash
# Lexicon backend: select region -> OCR -> translate -> open the hub
# Usage: ocr_translate.sh [--empty] [--redo] [--text "..."] [--lang CODES] [--to LANG]
set -u
MODE=ocr; TARGET=en; TEXT_IN=""; LANGS="${OCR_LANGS:-chi_sim+eng}"
while [ $# -gt 0 ]; do
    case "$1" in
        --empty) MODE=empty; shift ;;
        --redo)  MODE=redo; shift ;;
        --text)  MODE=text; TEXT_IN="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
        --lang)  LANGS="${2:-$LANGS}"; [ $# -ge 2 ] && shift 2 || shift ;;
        --to)    TARGET="${2:-en}"; [ $# -ge 2 ] && shift 2 || shift ;;
        *) shift ;;
    esac
done

STATE="$HOME/.cache/qs_translate.json"
IMG="$HOME/.cache/qs_translate_last.png"
QS="$HOME/.config/hypr/scripts/qs_manager.sh"
IPC="/tmp/qs_widget_state"
mkdir -p "$HOME/.cache"

write_state() { # status original translated [phonetic]
    python3 -c 'import json,sys,time; a=sys.argv; print(json.dumps({"status":a[1],"original":a[2],"translated":a[3],"phonetic":a[4],"langs":a[5],"ts":int(time.time()*1000)}, ensure_ascii=False))' \
        "$1" "$2" "$3" "${4:-}" "$LANGS" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

open_popup() { case "$MODE" in ocr|empty) bash "$QS" open translate ;; esac; }

if [ "$MODE" = empty ]; then
    write_state idle "" ""
    open_popup
    exit 0
fi

for c in grim slurp tesseract trans wl-copy python3 magick perl; do
    command -v "$c" >/dev/null || { notify-send "OCR Translate" "Missing dependency: $c"; exit 1; }
done

do_ocr() {
    local proc mean
    proc=$(mktemp --suffix=.png)
    magick "$IMG" -resize 300% -colorspace Gray -normalize "$proc"
    mean=$(magick "$proc" -format '%[fx:mean]' info:)
    awk "BEGIN{exit !($mean < 0.5)}" && magick "$proc" -negate "$proc"
    tesseract "$proc" - -l "$LANGS" --psm 6 2>/dev/null | tr '\n' ' ' \
        | perl -CSD -pe 's/(?<=[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}])\s+(?=[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}])//g; s/\s+/ /g; s/^ | $//g'
    rm -f "$proc"
}

get_phonetic() {
    case "$LANGS" in *chi_*) ;; *) return 0 ;; esac
    local py="$HOME/.local/share/qs-venv/bin/python"
    [ -x "$py" ] || py=python3
    "$py" - "$1" << 'PY' 2>/dev/null
import sys
try:
    from pypinyin import pinyin, Style
except ImportError:
    sys.exit(0)
t = sys.argv[1]
if not any("\u4e00" <= c <= "\u9fff" for c in t):
    sys.exit(0)
print(" ".join(x[0] for x in pinyin(t, style=Style.TONE)))
PY
}

case "$MODE" in
    ocr)
        echo "close" > "$IPC"; sleep 0.5      # make sure the hub isn't in the screenshot
        region=$(slurp) || exit 0
        grim -g "$region" "$IMG" || exit 1
        text=$(do_ocr) ;;
    redo)
        if [ ! -f "$IMG" ]; then
            write_state error "" "No captured image yet. Press SUPER+T first."; exit 1
        fi
        text=$(do_ocr) ;;
    text)
        text=$(printf '%s' "$TEXT_IN" | tr '\n' ' ' | sed 's/^ *//; s/ *$//') ;;
esac

if [ -z "$text" ]; then
    write_state error "" "No text found."
    open_popup; exit 1
fi

write_state loading "$text" ""
open_popup

out=$(trans -b ":$TARGET" "$text" 2>/dev/null)
if [ -z "$out" ]; then
    write_state error "$text" "Translation failed (network?)."
    exit 1
fi

printf '%s' "$out" | wl-copy
write_state done "$text" "$out" "$(get_phonetic "$text")"
