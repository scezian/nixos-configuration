#!/usr/bin/env python3
"""Default apps + app-launch keybinds backend for the Quickshell picker.

Apps:
  list                         categories, candidate apps and current defaults (JSON)
  set <cat> <app.desktop>      make an app the default (verified afterwards)
  reset <cat>                  remove your override for a category
  launch <cat>                 launch the current default app of a category
  launch-app <app.desktop>     launch an installed app
Keybinds:
  keys                         shortcuts, built-in launcher binds, live binds, apps (JSON)
  key-save <json> [--takeover] create/update a shortcut (validated, rolled back on config errors)
  key-delete <id>              delete a shortcut (restores a bind it took over)
All mutating commands print {"ok": true|false, ...} JSON.
"""
import concurrent.futures
import configparser
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
CONF = HOME / ".config/hypr/config"
STATE = CONF / "app_keybinds.json"
LUA = CONF / "app_keybinds.lua"
MAINKB = CONF / "keybindings.lua"
XDG_CONF = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
TERM_LIST = XDG_CONF / "xdg-terminals.list"
MIMEAPPS = XDG_CONF / "mimeapps.list"
SELF = '"$HOME/.config/hypr/scripts/default_apps.py"'


def cat(id_, label, hint, primary, mimes):
    return {"id": id_, "label": label, "hint": hint, "primary": primary, "mimes": mimes}


CATEGORIES = [
    cat("browser", "Web browser", "Links and web pages", "x-scheme-handler/https",
        ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"]),
    cat("files", "File manager", "Opening folders", "inode/directory", ["inode/directory"]),
    {"id": "terminal", "label": "Terminal", "hint": "Terminal emulator for shortcuts and scripts",
     "primary": "", "mimes": [], "special": "terminal"},
    cat("text", "Text editor", "Plain text, notes, Markdown", "text/plain",
        ["text/plain", "text/markdown", "text/x-log", "text/x-readme"]),
    cat("code", "Code editor", "Source code, JSON, config files", "text/x-python",
        ["text/x-python", "text/x-shellscript", "application/x-shellscript", "application/json", "application/xml",
         "text/xml", "text/x-csrc", "text/x-chdr", "text/x-c++src", "text/x-java", "text/x-lua", "text/x-rust",
         "text/css", "text/javascript", "application/javascript", "application/x-yaml", "text/yaml",
         "application/toml", "text/x-makefile"]),
    cat("pdf", "PDF viewer", "PDF documents", "application/pdf", ["application/pdf"]),
    cat("ebook", "E-book reader", "EPUB, MOBI, FB2", "application/epub+zip",
        ["application/epub+zip", "application/x-mobipocket-ebook", "application/x-fictionbook+xml"]),
    cat("docs", "Word processor", "DOCX, ODT, RTF", "application/vnd.oasis.opendocument.text",
        ["application/vnd.oasis.opendocument.text", "application/msword", "application/rtf",
         "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]),
    cat("sheets", "Spreadsheet", "XLSX, ODS, CSV", "application/vnd.oasis.opendocument.spreadsheet",
        ["application/vnd.oasis.opendocument.spreadsheet", "application/vnd.ms-excel", "text/csv",
         "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"]),
    cat("slides", "Presentations", "PPTX, ODP", "application/vnd.oasis.opendocument.presentation",
        ["application/vnd.oasis.opendocument.presentation", "application/vnd.ms-powerpoint",
         "application/vnd.openxmlformats-officedocument.presentationml.presentation"]),
    cat("image", "Image viewer", "PNG, JPG, WebP, GIF, AVIF", "image/png",
        ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml", "image/avif",
         "image/heic", "image/tiff", "image/jxl"]),
    cat("video", "Video player", "MP4, MKV, WebM, AVI", "video/mp4",
        ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg",
         "video/ogg", "video/3gpp", "video/x-flv"]),
    cat("audio", "Music player", "MP3, FLAC, OGG, WAV, M4A", "audio/mpeg",
        ["audio/mpeg", "audio/flac", "audio/x-flac", "audio/x-wav", "audio/ogg", "audio/mp4", "audio/aac",
         "audio/opus", "audio/x-opus+ogg", "audio/x-vorbis+ogg", "audio/x-m4a", "audio/x-ms-wma"]),
    cat("archive", "Archive manager", "ZIP, TAR, 7z, RAR, ZST", "application/zip",
        ["application/zip", "application/x-tar", "application/gzip", "application/x-compressed-tar",
         "application/x-xz-compressed-tar", "application/x-bzip2-compressed-tar",
         "application/x-zstd-compressed-tar", "application/x-7z-compressed", "application/vnd.rar",
         "application/x-rar", "application/zstd", "application/x-xz", "application/x-bzip2"]),
    cat("email", "Email", "mailto: links", "x-scheme-handler/mailto", ["x-scheme-handler/mailto"]),
    cat("calendar", "Calendar", "ICS files and webcal links", "text/calendar",
        ["text/calendar", "x-scheme-handler/webcal"]),
    cat("torrent", "Torrent client", "Torrent files and magnet links", "application/x-bittorrent",
        ["application/x-bittorrent", "x-scheme-handler/magnet"]),
]


# ----------------------------------------------------------------- small utils
def out(obj):
    print(json.dumps(obj))


def fail(msg, **extra):
    out({"ok": False, "error": msg, **extra})
    return 1


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def notify(msg):
    try:
        subprocess.run(["notify-send", "-a", "Default apps", "Default apps", msg], timeout=5)
    except Exception:
        pass


def run(cmd, timeout=8):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


# ----------------------------------------------------------------- desktop files
def app_dirs():
    data_home = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
    data_dirs = [Path(p) for p in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if p]
    low = [Path("/var/lib/flatpak/exports/share"), Path("/var/lib/snapd/desktop"),
           Path("/nix/var/nix/profiles/default/share"), Path("/run/current-system/sw/share")]
    high = [HOME / ".nix-profile/share", HOME / ".local/share/flatpak/exports/share"]
    ordered = low + list(reversed(data_dirs)) + high + [data_home]  # later entries override earlier ones
    seen, res = set(), []
    for d in ordered:
        if d not in seen:
            seen.add(d)
            res.append(d / "applications")
    return res


def split_list(v):
    return {x for x in (v or "").split(";") if x}


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
    if (g.get("Type") or "Application") != "Application" or (g.get("Hidden") or "").lower() == "true":
        return None
    te = g.get("TryExec") or ""
    if te and not (shutil.which(te) or (os.path.isabs(te) and os.access(te, os.X_OK))):
        return None   # leftover entry of an uninstalled app
    return {"name": g.get("Name") or path.stem, "icon": g.get("Icon") or "",
            "mimes": split_list(g.get("MimeType")), "cats": split_list(g.get("Categories")),
            "nodisplay": (g.get("NoDisplay") or "").lower() == "true",
            "exec": g.get("Exec") or "", "path": g.get("Path") or "",
            "terminal": (g.get("Terminal") or "").lower() == "true", "file": str(path)}


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
    r = run(["xdg-mime", "query", "default", mime], 5)
    return r.stdout.strip() if r else ""


# ----------------------------------------------------------------- state
def load_state():
    d = {"version": 1, "shortcuts": [], "prefs": {}}
    try:
        raw = json.loads(STATE.read_text(encoding="utf-8"))
        if isinstance(raw.get("shortcuts"), list):
            d["shortcuts"] = [s for s in raw["shortcuts"] if isinstance(s, dict) and s.get("id") and s.get("combo")]
        if isinstance(raw.get("prefs"), dict):
            d["prefs"] = raw["prefs"]
    except FileNotFoundError:
        pass
    except Exception:
        try:
            shutil.copy2(STATE, STATE.with_suffix(".json.bad"))
        except Exception:
            pass
    return d


def save_state(d):
    atomic_write(STATE, json.dumps(d, indent=2) + "\n")


# ----------------------------------------------------------------- terminal role
def term_list_ids():
    try:
        return [l.strip() for l in TERM_LIST.read_text().splitlines() if l.strip() and not l.startswith("#")]
    except Exception:
        return []


def terminal_current(apps):
    pref = load_state()["prefs"].get("terminal", "")
    if pref in apps:
        return pref
    for did in term_list_ids():
        if did in apps:
            return did
    return ""


def set_terminal(app_id):
    st = load_state()
    st["prefs"]["terminal"] = app_id
    save_state(st)
    ids = [app_id] + [i for i in term_list_ids() if i != app_id]
    atomic_write(TERM_LIST, "\n".join(ids) + "\n")


FALLBACK_TERMS = ["kitty", "foot", "alacritty", "wezterm", "ghostty", "konsole", "gnome-terminal", "xterm"]


def terminal_tokens(apps):
    did = terminal_current(apps)
    if did:
        toks = expand_exec(apps[did]["exec"], apps[did]["name"], apps[did]["icon"], apps[did]["file"])
        if toks:
            return toks
    for t in FALLBACK_TERMS:
        if shutil.which(t):
            return [t]
    return []


# ----------------------------------------------------------------- categories
def find_cat(cid):
    return next((c for c in CATEGORIES if c["id"] == cid), None)


def candidates(c, apps, current):
    if c.get("special") == "terminal":
        pool = {d: a for d, a in apps.items() if "TerminalEmulator" in a["cats"]}
    else:
        mset = set(c["mimes"])
        pool = {d: a for d, a in apps.items() if a["mimes"] & mset}
    res = [{"id": d, "name": a["name"], "icon": a["icon"],
            "exec": os.path.basename((a.get("exec") or "").split(" ")[0])} for d, a in pool.items()
           if not a["nodisplay"] or d == current]
    if current and current not in {x["id"] for x in res}:
        a = apps.get(current)
        res.append({"id": current, "name": a["name"] if a else current + " (not installed)",
                    "icon": a["icon"] if a else ""})
    res.sort(key=lambda x: x["name"].lower())
    return res


def current_for(c, apps):
    return terminal_current(apps) if c.get("special") == "terminal" else query_default(c["primary"])


def cmd_list():
    apps = scan()
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        currents = list(ex.map(lambda c: current_for(c, apps), CATEGORIES))
    res = []
    for c, cur in zip(CATEGORIES, currents):
        cand = candidates(c, apps, cur)
        name = next((x["name"] for x in cand if x["id"] == cur), "Not set")
        res.append({"id": c["id"], "label": c["label"], "hint": c["hint"], "current": cur,
                    "currentName": name, "apps": cand})
    print(json.dumps(res))


def other_mimeapps_overrides():
    found = []
    try:
        found = [str(p) for p in XDG_CONF.glob("*-mimeapps.list")]
    except Exception:
        pass
    return found


def cmd_set(cid, app_id):
    c = find_cat(cid)
    if c is None:
        return fail(f"Unknown category: {cid}")
    if not app_id.endswith(".desktop") or "/" in app_id:
        return fail(f"Bad app id: {app_id}")
    if c.get("special") == "terminal":
        set_terminal(app_id)
        return out({"ok": True})
    r = run(["xdg-mime", "default", app_id, *c["mimes"]], 15)
    if r is None or r.returncode != 0:
        return fail((r.stderr.strip() if r else "") or "xdg-mime failed")
    if cid == "browser":
        run(["xdg-settings", "set", "default-web-browser", app_id], 15)
    now = query_default(c["primary"])
    if now != app_id:
        ov = other_mimeapps_overrides()
        hint = f" Check {ov[0]}." if ov else ""
        return fail(f"Saved, but the system still reports {now or 'nothing'} as the default.{hint}")
    out({"ok": True})


def strip_defaults(mimes):
    if not MIMEAPPS.exists():
        return
    res, sec = [], None
    for ln in MIMEAPPS.read_text(encoding="utf-8").splitlines(keepends=True):
        m = re.match(r"\s*\[(.+?)\]\s*$", ln)
        if m:
            sec = m.group(1)
        elif sec == "Default Applications" and "=" in ln and ln.split("=", 1)[0].strip() in mimes:
            continue
        res.append(ln)
    atomic_write(MIMEAPPS, "".join(res))


def cmd_reset(cid):
    c = find_cat(cid)
    if c is None:
        return fail(f"Unknown category: {cid}")
    if c.get("special") == "terminal":
        st = load_state()
        st["prefs"].pop("terminal", None)
        save_state(st)
    else:
        strip_defaults(set(c["mimes"]))
    out({"ok": True})


# ----------------------------------------------------------------- launching
def expand_exec(exec_str, name, icon, path):
    try:
        toks = shlex.split(exec_str)
    except ValueError:
        return []
    res = []
    for t in toks:
        if t == "%i":
            res += ["--icon", icon] if icon else []
            continue
        t = t.replace("%%", "\0")
        t = re.sub(r"%[fFuUdDnNvm]", "", t)
        t = t.replace("%c", name).replace("%k", str(path)).replace("\0", "%")
        if t:
            res.append(t)
    return res


def launch_entry(apps, did):
    a = apps.get(did)
    if a is None:
        notify(f"{did} is not installed")
        return 1
    cmd = expand_exec(a["exec"], a["name"], a["icon"], a["file"])
    if not cmd:
        notify(f"Can't read the launch command of {a['name']}")
        return 1
    if a["terminal"]:
        term = terminal_tokens(apps)
        if not term:
            notify("No terminal emulator found")
            return 1
        sep = "--" if Path(term[0]).name == "gnome-terminal" else "-e"
        cmd = term + [sep] + cmd
    try:
        subprocess.Popen(cmd, cwd=a["path"] or None, start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        notify(f"Couldn't start {a['name']}: {e}")
        return 1
    return 0


def cmd_launch(cid):
    c = find_cat(cid)
    if c is None:
        notify(f"Unknown category {cid}")
        return 1
    apps = scan()
    if c.get("special") == "terminal":
        if not terminal_current(apps):
            toks = terminal_tokens(apps)
            if not toks:
                notify("No terminal emulator found")
                return 1
            subprocess.Popen(toks, start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return 0
        return launch_entry(apps, terminal_current(apps))
    did = query_default(c["primary"])
    a = apps.get(did)
    if a is None or a["nodisplay"]:          # unset, uninstalled, or a hidden URL-handler like kitty-open
        pool = candidates(c, apps, "")
        did = pool[0]["id"] if pool else ""
    if not did:
        notify(f"No {c['label'].lower()} installed or set")
        return 1
    return launch_entry(apps, did)


# ----------------------------------------------------------------- key combos
MODS = {"SUPER": 64, "SHIFT": 1, "CTRL": 4, "ALT": 8}
ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]
ALIAS = {"SUPER": "SUPER", "WIN": "SUPER", "META": "SUPER", "MOD4": "SUPER", "LOGO": "SUPER",
         "CTRL": "CTRL", "CONTROL": "CTRL", "ALT": "ALT", "MOD1": "ALT", "SHIFT": "SHIFT"}
NAMED = {"return": "Return", "enter": "Return", "space": "space", "tab": "Tab", "escape": "Escape",
         "esc": "Escape", "backspace": "BackSpace", "delete": "Delete", "insert": "Insert", "home": "Home",
         "end": "End", "pageup": "Prior", "pagedown": "Next", "prior": "Prior", "next": "Next",
         "left": "left", "right": "right", "up": "up", "down": "down", "print": "Print", "comma": "comma",
         "period": "period", "slash": "slash", "backslash": "backslash", "minus": "minus", "equal": "equal",
         "grave": "grave", "semicolon": "semicolon", "apostrophe": "apostrophe",
         "bracketleft": "bracketleft", "bracketright": "bracketright"}


def canon_key(k):
    k = k.strip()
    if len(k) == 1 and k.isalnum():
        return k.upper()
    if re.fullmatch(r"[Ff]([1-9]|1[0-9]|2[0-4])", k):
        return k.upper()
    if re.fullmatch(r"XF86[A-Za-z0-9]+", k):
        return k
    if re.fullmatch(r"code:\d+", k):
        return k
    if k.lower() in NAMED:
        return NAMED[k.lower()]
    raise ValueError(f"Unknown key “{k}”. Use a letter, digit, F1–F24, Return, space, Tab, arrows, Print or an XF86 key.")


def soft_key(k):
    try:
        return canon_key(k)
    except ValueError:
        return k


def parse_combo(text, main="SUPER"):
    parts = [p.strip() for p in text.split("+") if p.strip()]
    if not parts:
        raise ValueError("Empty key combination")
    mods = []
    for p in parts[:-1]:
        m = ALIAS.get(p.upper()) or (main if p == "mainMod" else None)
        if m is None:
            raise ValueError(f"Unknown modifier “{p}”")
        if m not in mods:
            mods.append(m)
    mods = [m for m in ORDER if m in mods]
    return mods, canon_key(parts[-1])


def combo_str(mods, key):
    return " + ".join(mods + [key])


def sig(mods, key):
    return ("+".join(sorted(mods)), key.upper())


def sig_of_combo(text):
    m, k = parse_combo(text)
    return sig(m, k)


# ----------------------------------------------------------------- live + static binds
def live_binds():
    r = run(["hyprctl", "binds", "-j"], 6)
    if r is None or r.returncode != 0:
        return None
    try:
        data = json.loads(r.stdout)
    except Exception:
        return None
    res = []
    for b in data:
        key = b.get("key") or (f"code:{b['keycode']}" if b.get("keycode") else "")
        if not key:
            continue
        mm = int(b.get("modmask") or 0)
        mods = [m for m in ORDER if mm & MODS[m]]
        disp, arg = b.get("dispatcher") or "", b.get("arg") or ""
        desc = arg if disp == "exec" else f"{disp} {arg}".strip()
        sm = b.get("submap") or ""
        k = soft_key(key)
        res.append({"combo": combo_str(mods, k), "sig": sig(mods, k), "desc": desc or "(no description)",
                    "submap": sm})
    return res


BIND_RE = re.compile(
    r'^(?P<indent>\s*)hl\.bind\(\s*(?:mainMod\s*\.\.\s*"(?P<m>[^"]*)"|"(?P<s>[^"]*)")\s*,\s*'
    r'hl\.dsp\.exec_cmd\(\s*(?P<arg>"(?:[^"\\]|\\.)*"|[A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\)\s*(?:--.*)?$')
ALL_BIND_RE = re.compile(r'^\s*hl\.bind\(\s*(?:mainMod\s*\.\.\s*"(?P<m>[^"]*)"|"(?P<s>[^"]*)")')
MAIN_RE = re.compile(r'^\s*local\s+mainMod\s*=\s*"([^"]+)"', re.M)


def main_mod(text):
    m = MAIN_RE.search(text)
    return ALIAS.get(m.group(1).upper(), "SUPER") if m else "SUPER"


def unlua(s):
    return s[1:-1].replace('\\"', '"').replace("\\\\", "\\")


def static_binds():
    """Simple one-line exec binds in keybindings.lua that can be adopted."""
    try:
        text = MAINKB.read_text(encoding="utf-8")
    except Exception:
        return []
    main = main_mod(text)
    res = []
    for i, ln in enumerate(text.splitlines()):
        m = BIND_RE.match(ln)
        if not m:
            continue
        raw = (main + m.group("m")) if m.group("m") is not None else m.group("s")
        try:
            mods, key = parse_combo(raw, main)
        except ValueError:
            continue
        arg = m.group("arg")
        if arg.startswith('"'):
            res.append({"line": i, "mods": mods, "key": key, "cmd": unlua(arg), "role": ""})
        elif arg == "terminal":
            res.append({"line": i, "mods": mods, "key": key, "cmd": "", "role": "terminal"})
    return res


def edit_main_lines(fn):
    text = MAINKB.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    main = main_mod(text)
    changed = False
    for i, ln in enumerate(lines):
        new = fn(ln.rstrip("\n"), main)
        if new is not None:
            lines[i] = new + ("\n" if ln.endswith("\n") else "")
            changed = True
    if changed:
        atomic_write(MAINKB, "".join(lines))
    return changed


def disable_sig(target):
    def fn(ln, main):
        m = BIND_RE.match(ln)
        if not m:
            return None
        raw = (main + m.group("m")) if m.group("m") is not None else m.group("s")
        try:
            mods, key = parse_combo(raw, main)
        except ValueError:
            return None
        return f'{m.group("indent")}-- [picker] {ln.lstrip()}' if sig(mods, key) == target else None
    return edit_main_lines(fn)


def restore_sigs(targets):
    def fn(ln, main):
        m = re.match(r"^(\s*)-- \[picker\] (.*)$", ln)
        if not m:
            return None
        inner = BIND_RE.match(m.group(1) + m.group(2))
        if not inner:
            return None
        raw = (main + inner.group("m")) if inner.group("m") is not None else inner.group("s")
        try:
            mods, key = parse_combo(raw, main)
        except ValueError:
            return None
        return m.group(1) + m.group(2) if sig(mods, key) in targets else None
    return edit_main_lines(fn)


# ----------------------------------------------------------------- shortcuts
def command_for(sc):
    if sc["type"] == "category":
        return f'python3 {SELF} launch {sc["target"]}'
    if sc["type"] == "app":
        return f'python3 {SELF} launch-app {shlex.quote(sc["target"])}'
    return sc["target"]


def lua_str(s):
    if any(ord(c) < 32 for c in s):
        raise ValueError("Control characters aren't allowed in commands")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def gen_lua(shortcuts):
    rows = [f"  {{ combo = {lua_str(s['combo'])}, cmd = {lua_str(command_for(s))} }}," for s in shortcuts]
    return ("-- GENERATED by the Default apps popup from app_keybinds.json. Edit shortcuts there.\n"
            "return {\n" + "\n".join(rows) + "\n}\n")


ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHELL_META = re.compile(r"[;&|<>`$(){}*?]")


def strip_env(toks):
    toks = list(toks)
    while toks and (toks[0] == "env" or ENV_RE.match(toks[0])):
        toks.pop(0)
    return toks


def bind_argv(cmd):
    """Tokens of a plain one-command bind, or None for anything shell-ish or unclear."""
    if SHELL_META.search(cmd):
        return None
    try:
        toks = strip_env(shlex.split(cmd))
    except ValueError:
        return None
    return toks or None


def ignored_ids():
    """Desktop ids listed in ~/.config/hypr/config/app_match_ignore.txt are never matched to a bind."""
    try:
        lines = (CONF / "app_match_ignore.txt").read_text(encoding="utf-8").splitlines()
        return {l.strip() for l in lines if l.strip() and not l.lstrip().startswith("#")}
    except Exception:
        return set()


def exact_app_match(cmd, apps):
    """Name an app only when the bind runs exactly that app's launch command.

    Never guesses from the first word (python3, bash, sh... would match anything), never claims
    commands from your Hyprland config, and refuses when more than one app fits.
    """
    if "/.config/hypr/" in cmd or cmd.lstrip().startswith("~/.config/hypr"):
        return ""
    bt = bind_argv(cmd)
    if not bt:
        return ""
    hits = []
    skip = ignored_ids()
    for did, a in apps.items():
        if a["nodisplay"] or did in skip:
            continue
        et = strip_env(expand_exec(a["exec"], a["name"], a["icon"], a["file"]))
        if et and len(et) == len(bt) and Path(et[0]).name == Path(bt[0]).name and et[1:] == bt[1:]:
            hits.append(did)
    return hits[0] if len(hits) == 1 else ""


INTERPRETERS = {"python", "python3", "bash", "sh", "zsh", "fish", "node", "nodejs", "perl", "ruby", "lua", "luajit",
                "env", "sudo", "nohup", "setsid", "exec", "uwsm", "flatpak", "kitty", "foot", "alacritty"}


def nice_label(cmd):
    m = re.search(r"qs_manager\.sh\s+toggle\s+(\w+)", cmd)
    if m:
        return m.group(1).capitalize() + " popup"
    if SHELL_META.search(cmd):
        return "Shell command"
    try:
        toks = strip_env(shlex.split(cmd))
    except ValueError:
        return "Shortcut"
    while toks and (Path(toks[0]).name.rstrip("0123456789.") in INTERPRETERS or toks[0].startswith("-")):
        toks.pop(0)
    if not toks:
        return "Shortcut"
    stem = re.sub(r"[-_.]+", " ", Path(toks[0]).stem).strip()
    return stem.capitalize() if stem else "Shortcut"


def target_text(sc, apps):
    if sc["type"] == "category":
        c = find_cat(sc["target"])
        return "Default " + (c["label"].lower() if c else sc["target"])
    if sc["type"] == "app":
        a = apps.get(sc["target"])
        return a["name"] if a else sc["target"] + " (not installed)"
    return sc["target"]


def cmd_keys():
    apps = scan()
    st = load_state()
    live = live_binds()
    shortcuts = []
    for s in st["shortcuts"]:
        shortcuts.append({**s, "kind": "managed", "targetText": target_text(s, apps)})
    managed_sigs = set()
    for s in st["shortcuts"]:
        try:
            managed_sigs.add(sig_of_combo(s["combo"]))
        except ValueError:
            pass
    builtin = []
    for b in static_binds():
        if sig(b["mods"], b["key"]) in managed_sigs:
            continue
        combo = combo_str(b["mods"], b["key"])
        origin = f"keybindings.lua:{b['line'] + 1}"
        if b["role"] == "terminal":
            typ, tgt, label, conf, cmdline = "category", "terminal", "Terminal", "role", "terminal (variable in keybindings.lua)"
        else:
            cmdline = b["cmd"]
            did = exact_app_match(cmdline, apps)
            if did:
                typ, tgt, label, conf = "app", did, apps[did]["name"], "exact"
            else:
                typ, tgt, label, conf = "custom", cmdline, nice_label(cmdline), "command"
        shown = tgt if typ == "custom" else target_text({"type": typ, "target": tgt}, apps)
        if typ == "app":
            shown = f"{shown}  ·  runs: {cmdline}"
        builtin.append({"kind": "builtin", "id": "", "label": label, "combo": combo, "type": typ, "target": tgt,
                        "targetText": shown, "command": cmdline, "origin": origin, "confidence": conf})
    src = {}
    try:
        text = MAINKB.read_text(encoding="utf-8")
        main = main_mod(text)
        for i, ln in enumerate(text.splitlines()):
            if ln.lstrip().startswith("--"):
                continue
            m = ALL_BIND_RE.match(ln)
            if not m:
                continue
            raw = (main + m.group("m")) if m.group("m") is not None else m.group("s")
            try:
                mods, key = parse_combo(raw, main)
                src.setdefault(sig(mods, key), f"keybindings.lua:{i + 1}")
            except ValueError:
                pass
    except Exception:
        pass
    for sg in managed_sigs:
        src[sg] = "my shortcut"
    all_live = []
    if live:
        for b in sorted(live, key=lambda x: x["combo"].lower())[:500]:
            all_live.append({"combo": b["combo"], "src": src.get(b["sig"], "hyprland config"),
                             "desc": b["desc"] + (f"  [{b['submap']}]" if b["submap"] else "")})
    visible = sorted(({"id": d, "name": a["name"], "icon": a["icon"],
                       "exec": os.path.basename((a.get("exec") or "").split(" ")[0])} for d, a in apps.items() if not a["nodisplay"]),
                     key=lambda x: x["name"].lower())
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        currents = list(ex.map(lambda c: current_for(c, apps), CATEGORIES))
    cats = []
    for c, cur in zip(CATEGORIES, currents):
        nm = (apps[cur]["name"] if cur in apps else "") if cur else ""
        cats.append({"id": c["id"], "label": c["label"], "currentName": nm or "not set"})
    out({"ok": True, "liveOk": live is not None, "shortcuts": shortcuts, "builtin": builtin, "live": all_live,
         "apps": visible, "cats": cats})


def validate(p, apps):
    label = str(p.get("label") or "").strip()[:40]
    mods = [m for m in ORDER if m in (p.get("mods") or [])]
    key = canon_key(str(p.get("key") or ""))
    plain_ok = bool(re.fullmatch(r"F\d+|XF86.*|Print|code:\d+", key))
    if not plain_ok and not [m for m in mods if m != "SHIFT"]:
        raise ValueError("Add Super, Ctrl or Alt — a bare letter or Shift+letter would break typing.")
    typ, target = p.get("type"), str(p.get("target") or "").strip()
    if typ == "category":
        if find_cat(target) is None:
            raise ValueError("Pick a category")
    elif typ == "app":
        if not target.endswith(".desktop") or target not in apps:
            raise ValueError("Pick an installed app")
    elif typ == "custom":
        if not target or len(target) > 500 or "\n" in target:
            raise ValueError("Enter a command (one line)")
        lua_str(target)
    else:
        raise ValueError("Pick what the shortcut should launch")
    return {"id": str(p.get("id") or ""), "label": label or "Shortcut", "combo": combo_str(mods, key),
            "type": typ, "target": target}


def config_errors():
    r = run(["hyprctl", "configerrors"], 6)
    if r is None or r.returncode != 0:
        return None
    return [l.strip() for l in r.stdout.splitlines() if l.strip()]


def reload_cfg():
    r = run(["hyprctl", "reload"], 15)
    time.sleep(0.4)
    return r is not None and r.returncode == 0


def apply_changes(mutate):
    files = [STATE, LUA, MAINKB]
    snap = {p: (p.read_text(encoding="utf-8") if p.exists() else None) for p in files}
    before = config_errors()
    try:
        mutate()
    except Exception:
        restore_files(snap)
        raise
    reached = reload_cfg()
    after = config_errors()
    if before is not None and after is not None:
        new = [l for l in after if l not in before]
        if new:
            restore_files(snap)
            reload_cfg()
            return False, "Hyprland rejected the change, so it was undone: " + "; ".join(new)[:300]
    return True, "" if reached else "Saved, but Hyprland isn't reachable. It applies on the next start."


def restore_files(snap):
    for p, t in snap.items():
        if t is None:
            p.unlink(missing_ok=True)
        else:
            atomic_write(p, t)


def cmd_key_save(raw, takeover):
    apps = scan()
    try:
        sc = validate(json.loads(raw), apps)
    except (ValueError, json.JSONDecodeError) as e:
        return fail(str(e))
    st = load_state()
    mysig = sig_of_combo(sc["combo"])
    for s in st["shortcuts"]:
        if s["id"] != sc["id"]:
            try:
                same = sig_of_combo(s["combo"]) == mysig
            except ValueError:
                same = False
            if same:
                return fail(f"{sc['combo']} is already used by your shortcut “{s['label']}”.")
    old = next((s for s in st["shortcuts"] if s["id"] == sc["id"]), None)
    owned = set()
    for s in st["shortcuts"]:
        try:
            owned.add(sig_of_combo(s["combo"]))
        except ValueError:
            pass
    conflict_desc = None
    live = live_binds()
    if live:
        for b in live:
            if b["submap"] == "" and b["sig"] == mysig and mysig not in owned:
                conflict_desc = b["desc"]
                break
    adoptable = next((b for b in static_binds() if sig(b["mods"], b["key"]) == mysig), None)
    if adoptable and mysig not in owned and conflict_desc is None:
        conflict_desc = adoptable["cmd"] or "terminal"
    take = False
    if conflict_desc is not None:
        if not takeover:
            return out({"ok": False, "error": f"{sc['combo']} is already in use.",
                        "conflict": {"combo": sc["combo"], "desc": conflict_desc, "canTakeOver": bool(adoptable)}})
        if not adoptable:
            return fail(f"{sc['combo']} belongs to a built-in bind ({conflict_desc}) that can't be overridden here. "
                        "Pick another combination.")
        take = True
    sc["restore"] = list(dict.fromkeys((old or {}).get("restore", []) + ([sc["combo"]] if take else [])))
    if not sc["id"]:
        sc["id"] = f"sc{int(time.time() * 1000)}"

    def mutate():
        if take:
            disable_sig(mysig)
        st2 = load_state()
        st2["shortcuts"] = [s for s in st2["shortcuts"] if s["id"] != sc["id"]] + [sc]
        save_state(st2)
        atomic_write(LUA, gen_lua(st2["shortcuts"]))

    try:
        ok, msg = apply_changes(mutate)
    except Exception as e:
        return fail(str(e))
    if not ok:
        return fail(msg)
    warn = msg
    time.sleep(0.2)
    live2 = live_binds()
    if not warn and live2 is not None and not any(b["sig"] == mysig and b["submap"] == "" for b in live2):
        warn = "Saved, but Hyprland doesn't list the bind yet. If it doesn't work, run hyprctl reload."
    out({"ok": True, "warn": warn, "id": sc["id"]})


def cmd_key_delete(sid):
    st = load_state()
    sc = next((s for s in st["shortcuts"] if s["id"] == sid), None)
    if sc is None:
        return fail("That shortcut no longer exists")

    def mutate():
        targets = set()
        for c in sc.get("restore", []):
            try:
                targets.add(sig_of_combo(c))
            except ValueError:
                pass
        if targets and MAINKB.exists():
            restore_sigs(targets)
        st2 = load_state()
        st2["shortcuts"] = [s for s in st2["shortcuts"] if s["id"] != sid]
        save_state(st2)
        atomic_write(LUA, gen_lua(st2["shortcuts"]))

    try:
        ok, msg = apply_changes(mutate)
    except Exception as e:
        return fail(str(e))
    out({"ok": ok, "error": "" if ok else msg, "warn": msg if ok else ""})


def cmd_try(raw):
    apps = scan()
    try:
        p = json.loads(raw)
        typ, target = p.get("type"), str(p.get("target") or "").strip()
        if typ == "category":
            if find_cat(target) is None:
                raise ValueError("Pick a category")
            rc = cmd_launch(target)
        elif typ == "app":
            if target not in apps:
                raise ValueError("Pick an installed app")
            rc = launch_entry(apps, target)
        elif typ == "custom":
            if not target or "\n" in target:
                raise ValueError("Enter a command (one line)")
            subprocess.Popen(["/bin/sh", "-c", target], start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            rc = 0
        else:
            raise ValueError("Pick what to launch")
    except (ValueError, json.JSONDecodeError) as e:
        return fail(str(e))
    except Exception as e:
        return fail(f"Couldn't run it: {e}")
    return out({"ok": rc == 0, "error": "" if rc == 0 else "It didn't start (check the notification)."})


def main():
    a = sys.argv[1:]
    if a == ["list"]:
        return cmd_list()
    if len(a) == 3 and a[0] == "set":
        return cmd_set(a[1], a[2])
    if len(a) == 2 and a[0] == "reset":
        return cmd_reset(a[1])
    if len(a) == 2 and a[0] == "launch":
        return cmd_launch(a[1])
    if len(a) == 2 and a[0] == "launch-app":
        return launch_entry(scan(), a[1])
    if a == ["keys"]:
        return cmd_keys()
    if len(a) == 2 and a[0] == "try":
        return cmd_try(a[1])
    if len(a) in (2, 3) and a[0] == "key-save":
        return cmd_key_save(a[1], "--takeover" in a[2:])
    if len(a) == 2 and a[0] == "key-delete":
        return cmd_key_delete(a[1])
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main() or 0)
