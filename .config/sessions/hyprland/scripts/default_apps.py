#!/usr/bin/env python3
"""Default-apps helper for the Quickshell picker.

  default_apps.py list               JSON: categories, candidate apps, current defaults
  default_apps.py set <cat> <app>    make <app>.desktop the default for the category
"""
import configparser
import json
import os
import subprocess
import sys
from pathlib import Path

CATEGORIES = [
    {"id": "browser", "label": "Web browser", "hint": "Links and web pages",
     "primary": "x-scheme-handler/https",
     "mimes": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"]},
    {"id": "files", "label": "File manager", "hint": "Opening folders",
     "primary": "inode/directory", "mimes": ["inode/directory"]},
    {"id": "text", "label": "Text editor", "hint": "Plain text, notes, scripts",
     "primary": "text/plain",
     "mimes": ["text/plain", "text/markdown", "text/x-python", "text/x-shellscript", "application/x-shellscript"]},
    {"id": "image", "label": "Image viewer", "hint": "PNG, JPG, WebP, GIF",
     "primary": "image/png",
     "mimes": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml"]},
    {"id": "video", "label": "Video player", "hint": "MP4, MKV, WebM",
     "primary": "video/mp4",
     "mimes": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo"]},
    {"id": "audio", "label": "Music player", "hint": "MP3, FLAC, OGG, WAV",
     "primary": "audio/mpeg",
     "mimes": ["audio/mpeg", "audio/flac", "audio/x-flac", "audio/x-wav", "audio/ogg", "audio/mp4", "audio/aac"]},
    {"id": "pdf", "label": "PDF viewer", "hint": "PDF documents",
     "primary": "application/pdf", "mimes": ["application/pdf"]},
    {"id": "archive", "label": "Archive manager", "hint": "ZIP, TAR, 7z, RAR",
     "primary": "application/zip",
     "mimes": ["application/zip", "application/x-tar", "application/gzip", "application/x-compressed-tar",
               "application/x-7z-compressed", "application/vnd.rar", "application/x-rar"]},
    {"id": "email", "label": "Email", "hint": "mailto: links",
     "primary": "x-scheme-handler/mailto", "mimes": ["x-scheme-handler/mailto"]},
]


def app_dirs():
    home = Path.home()
    data_home = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
    data_dirs = [Path(p) for p in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if p]
    ordered = [Path("/var/lib/flatpak/exports/share")] + list(reversed(data_dirs)) \
        + [home / ".local/share/flatpak/exports/share", data_home]   # later entries override earlier ones
    seen, out = set(), []
    for d in ordered:
        if d not in seen:
            seen.add(d)
            out.append(d / "applications")
    return out


def parse(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None, delimiters=("=",),
                                      comment_prefixes=("#",), allow_no_value=True)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except Exception:
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    g = cp["Desktop Entry"]
    if (g.get("Type") or "Application") != "Application":
        return None
    if (g.get("Hidden") or "false").lower() == "true":
        return None
    return {
        "name": g.get("Name") or path.stem,
        "icon": g.get("Icon") or "",
        "mimes": {m for m in (g.get("MimeType") or "").split(";") if m},
        "nodisplay": (g.get("NoDisplay") or "false").lower() == "true",
    }


def scan():
    apps = {}
    for base in app_dirs():
        if not base.is_dir():
            continue
        for f in sorted(base.rglob("*.desktop")):
            did = f.relative_to(base).as_posix().replace("/", "-")
            entry = parse(f)
            if entry is None:
                apps.pop(did, None)
            else:
                apps[did] = entry
    return apps


def query_default(mime):
    try:
        r = subprocess.run(["xdg-mime", "query", "default", mime],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:
        return ""


def cmd_list():
    apps = scan()
    out = []
    for c in CATEGORIES:
        current = query_default(c["primary"])
        mset = set(c["mimes"])
        cand = []
        for did, a in apps.items():
            if not (a["mimes"] & mset):
                continue
            if a["nodisplay"] and did != current:
                continue
            cand.append({"id": did, "name": a["name"], "icon": a["icon"]})
        if current and current not in {x["id"] for x in cand}:
            a = apps.get(current)
            cand.append({"id": current, "name": a["name"] if a else current, "icon": a["icon"] if a else ""})
        cand.sort(key=lambda x: x["name"].lower())
        cur_name = next((x["name"] for x in cand if x["id"] == current), "Not set")
        out.append({"id": c["id"], "label": c["label"], "hint": c["hint"],
                    "current": current, "currentName": cur_name, "apps": cand})
    print(json.dumps(out))


def cmd_set(cat_id, app_id):
    cat = next((c for c in CATEGORIES if c["id"] == cat_id), None)
    if cat is None:
        sys.exit(f"Unknown category: {cat_id}")
    if not app_id.endswith(".desktop") or "/" in app_id:
        sys.exit(f"Bad app id: {app_id}")
    r = subprocess.run(["xdg-mime", "default", app_id, *cat["mimes"]], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(r.stderr.strip() or f"xdg-mime failed (exit {r.returncode})")
    if cat_id == "browser":
        subprocess.run(["xdg-settings", "set", "default-web-browser", app_id], capture_output=True, text=True)


def main():
    a = sys.argv[1:]
    if a == ["list"]:
        cmd_list()
    elif len(a) == 3 and a[0] == "set":
        cmd_set(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
