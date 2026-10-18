#!/usr/bin/env bash
# Clipboard translate backend. Run by: wl-paste --watch clip_translate.sh  (clipboard arrives on stdin)
#   clip_translate.sh --toggle   turns the feature on/off
OFF="$HOME/.cache/qs_cliptoast_off"
if [ "${1:-}" = "--toggle" ]; then
    if [ -e "$OFF" ]; then rm -f "$OFF"; notify-send "Clipboard translate" "ON"
    else touch "$OFF"; notify-send "Clipboard translate" "OFF"; fi
    exit 0
fi
[ -e "$OFF" ] && exit 0
mkdir -p "$HOME/.cache"
tmp=$(mktemp); head -c 4000 > "$tmp"
python3 - "$tmp" << 'PY'
import hashlib, json, os, re, subprocess, sys, time

path = sys.argv[1]
raw = open(path, "rb").read()
os.remove(path)
try:
    text = raw.decode("utf-8")
except UnicodeDecodeError:
    sys.exit(0)
text = re.sub(r"\s+", " ", text).strip()
if not text or len(text) > 300 or "://" in text:
    sys.exit(0)
# only act on non-Latin scripts: CJK, kana, hangul, Cyrillic, Arabic, Devanagari, Thai
if not re.search("[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\u0400-\u04ff\u0600-\u06ff\u0900-\u097f\u0e00-\u0e7f]", text):
    sys.exit(0)

home = os.path.expanduser("~")
state, last = home + "/.cache/qs_cliptoast.json", home + "/.cache/qs_cliptoast_last"
h = hashlib.md5(text.encode()).hexdigest()
try:
    ph, pt = open(last).read().split()
    if ph == h and time.time() - float(pt) < 10:
        sys.exit(0)
except Exception:
    pass
open(last, "w").write("%s %s" % (h, time.time()))

def write(status, translated=""):
    tmp = state + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"status": status, "original": text, "translated": translated, "ts": int(time.time() * 1000)}, f, ensure_ascii=False)
    os.replace(tmp, state)

write("loading")
try:
    out = subprocess.run(["trans", "-b", ":en", text], capture_output=True, text=True, timeout=15).stdout.strip()
except Exception:
    out = ""
write("done" if out else "error", out or "Translation failed (network?)")
PY
