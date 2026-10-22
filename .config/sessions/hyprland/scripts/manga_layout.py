#!/usr/bin/env python3
"""manga_layout.py WIDTH HEIGHT_PCT SIDE - rewrite the "manga" entry in WindowRegistry.js"""
import os, re, shutil, sys

reg = os.path.expanduser("~/.config/hypr/scripts/quickshell/WindowRegistry.js")
try:
    w = max(500, min(1800, int(float(sys.argv[1]))))
    pct = max(50, min(100, int(float(sys.argv[2]))))
    side = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] in ("left", "right") else "left"
except Exception:
    print("FAILED: bad arguments"); sys.exit(1)

t = open(reg).read()
m = re.search(r'("manga":\s*\{)[^}]*(\})', t)
if not m:
    print("FAILED: manga entry not found in WindowRegistry.js"); sys.exit(1)
rx = "s(18, scale)" if side == "left" else "Math.floor(mw - s(%d, scale) - s(18, scale))" % w
entry = (' w: s(%d, scale), h: Math.floor((mh - s(92, scale)) * %s), rx: %s, ry: s(68, scale), '
         'comp: "manga/MangaPanel.qml" ' % (w, "1" if pct == 100 else "0.%02d" % pct, rx))
if not os.path.exists(reg + ".bak-layout"):
    shutil.copy(reg, reg + ".bak-layout")
open(reg, "w").write(t[:m.start()] + m.group(1) + entry + m.group(2) + t[m.end():])
print("layout set: width %d, height %d%%, side %s" % (w, pct, side))
