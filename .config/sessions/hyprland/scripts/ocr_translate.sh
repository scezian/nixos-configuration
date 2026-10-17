#!/usr/bin/env bash
# Lexicon backend: select region -> OCR (auto language) -> translate -> open the hub
# Usage: ocr_translate.sh [--empty] [--redo] [--text "..."] [--lang CODES|auto] [--to LANG]
set -u
MODE=ocr; TARGET=en; TEXT_IN=""
LANGS="${OCR_LANGS:-chi_sim+eng}"; LANG_EXPLICIT=0
[ -n "${OCR_LANGS:-}" ] && LANG_EXPLICIT=1
CONF=0
while [ $# -gt 0 ]; do
    case "$1" in
        --empty) MODE=empty; shift ;;
        --redo)  MODE=redo; shift ;;
        --text)  MODE=text; TEXT_IN="${2:-}"; [ $# -ge 2 ] && shift 2 || shift ;;
        --lang)
            if [ "${2:-auto}" = auto ]; then LANG_EXPLICIT=0; else LANGS="$2"; LANG_EXPLICIT=1; fi
            [ $# -ge 2 ] && shift 2 || shift ;;
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
    python3 -c 'import json,sys,time; a=sys.argv; print(json.dumps({"status":a[1],"original":a[2],"translated":a[3],"phonetic":a[4],"langs":a[5],"conf":int(float(a[6])),"ts":int(time.time()*1000)}, ensure_ascii=False))' \
        "$1" "$2" "$3" "${4:-}" "$LANGS" "${CONF:-0}" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
}

open_popup() { case "$MODE" in ocr|empty) bash "$QS" open translate ;; esac; }

if [ "$MODE" = empty ]; then
    write_state idle "" ""
    open_popup
    exit 0
fi

for c in grim slurp tesseract trans wl-copy python3 magick; do
    command -v "$c" >/dev/null || { notify-send "OCR Translate" "Missing dependency: $c"; exit 1; }
done

# Runs tesseract once per candidate language set (in parallel), keeps the best read.
# Prints three lines: language set, confidence (0-100), cleaned text.
ocr_pick() {
    python3 - "$1" "$2" << 'PY'
import os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

img, cands = sys.argv[1], sys.argv[2].split(",")
CJK = "\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af"
KANA = re.compile("[\u3040-\u30ff]")
HANGUL = re.compile("[\uac00-\ud7af]")
PRIO = {"chi_sim": 2.0, "chi_tra": 1.0}


def run(lang):
    env = dict(os.environ, OMP_THREAD_LIMIT="1")
    r = subprocess.run(["tesseract", img, "-", "-l", lang, "--psm", "6", "tsv"],
                       capture_output=True, text=True, env=env)
    lines, confs, ws = {}, [], []
    for row in r.stdout.splitlines()[1:]:
        f = row.split("\t")
        if len(f) < 12:
            continue
        try:
            c = float(f[10])
        except ValueError:
            continue
        txt = f[11].strip()
        if c < 0 or not txt:
            continue
        lines.setdefault((f[2], f[3], f[4]), []).append(txt)
        confs.append(c)
        ws.append(max(1, len(txt)))
    text = " ".join(" ".join(v) for v in lines.values())
    score = sum(c * w for c, w in zip(confs, ws)) / sum(ws) if ws else 0.0
    return lang, text, score


CYR = re.compile("[\u0400-\u04ff]")
ARA = re.compile("[\u0600-\u06ff]")
HAN = re.compile("[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")


def bonus(lang, text):
    base = lang.split("+")[0]
    b = PRIO.get(base, 0.0)
    kana, hangul, han = bool(KANA.search(text)), bool(HANGUL.search(text)), bool(HAN.search(text))
    cyr, ara = bool(CYR.search(text)), bool(ARA.search(text))
    cjk = kana or hangul or han
    if base == "jpn":
        b += 8 if kana else 0
        if not cjk:
            b -= 8
    elif base == "kor":
        b += 8 if hangul else -8
    elif base.startswith("chi"):
        if kana or hangul:
            b -= 10
        if not han:
            b -= 8
    elif base == "rus":
        if not cyr:
            b -= 8
    elif base == "ara":
        if not ara:
            b -= 8
    elif cjk or cyr or ara:      # Latin-script group read non-Latin text: garbage
        b -= 10
    return b


def clean(t):
    t = re.sub(r"(?<=[%s])\s+(?=[%s])" % (CJK, CJK), "", t)       # spaces between CJK characters
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"(?:\s*[#\uff03]\S*)+\s*$", "", t)                  # trailing hashtags
    t = re.sub(r"(?<=[%s])\s+\d{1,2}$" % CJK, "", t)                # lone number after CJK text (often a misread #)
    t = re.sub(r"^[\s\]\)\}\|\\_/~`]+", "", t)                      # stray closers / noise at the start
    t = re.sub(r"[\s\(\[\{\|\\_/~`]+$", "", t)                      # stray openers / noise at the end
    return t.strip()


with ThreadPoolExecutor(max_workers=len(cands)) as ex:
    results = list(ex.map(run, cands))
best = None
for lang, text, score in results:
    eff = score + bonus(lang, text)
    if text.strip() and (best is None or eff > best[0]):
        best = (eff, lang, text, score)
if best is None:
    print(cands[0]); print(0); print("")
else:
    print(best[1]); print(int(round(best[3]))); print(clean(best[2]))
PY
}

do_ocr() {
    local proc mean cands out
    proc=$(mktemp --suffix=.png)
    magick "$IMG" -resize 300% -colorspace Gray -normalize "$proc"
    mean=$(magick "$proc" -format '%[fx:mean]' info:)
    awk "BEGIN{exit !($mean < 0.5)}" && magick "$proc" -negate "$proc"
    if [ "$LANG_EXPLICIT" = 1 ]; then cands="$LANGS"; else cands="${OCR_AUTO:-chi_sim+eng,chi_tra+eng,jpn+eng,kor+eng,rus+eng,ara+eng,eng+spa+fra+deu+por+ita}"; fi
    out=$(ocr_pick "$proc" "$cands")
    rm -f "$proc"
    { IFS= read -r OCR_LANG; IFS= read -r OCR_CONF; IFS= read -r OCR_TEXT; } <<< "$out"
    OCR_LANG="${OCR_LANG:-$LANGS}"; OCR_CONF="${OCR_CONF:-0}"; OCR_TEXT="${OCR_TEXT:-}"
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
        do_ocr; text="$OCR_TEXT"; LANGS="$OCR_LANG"; CONF="$OCR_CONF" ;;
    redo)
        if [ ! -f "$IMG" ]; then
            write_state error "" "No captured image yet. Scan something first."; exit 1
        fi
        do_ocr; text="$OCR_TEXT"; LANGS="$OCR_LANG"; CONF="$OCR_CONF" ;;
    text)
        text=$(printf '%s' "$TEXT_IN" | tr '\n' ' ' | sed 's/^ *//; s/ *$//') ;;
esac

if [ -z "$text" ]; then
    write_state error "" "No text found."
    open_popup; exit 1
fi

if [ "$MODE" != text ] && awk "BEGIN{exit !($CONF < ${OCR_MIN_CONF:-45})}"; then
    write_state error "$text" "OCR isn't confident (${CONF}%). Try a tighter box, pause the video, or fix the text on the left and press Enter."
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
