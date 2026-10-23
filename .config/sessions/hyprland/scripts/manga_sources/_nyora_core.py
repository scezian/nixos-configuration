# Nyora source: any of Nyora's ~390 sources through the local helper (auto-started).
# Config (optional): ~/.local/share/qs-manga/nyora.json
#   {"source": "COMICK_FUN", "lang": "english", "nsfw": false}
import glob, json, os, socket, subprocess, sys, time, urllib.parse, urllib.request, urllib.error

H = os.path.expanduser("~")
PORTF = H + "/.config/nyora/helper.port"
CFG = H + "/.local/share/qs-manga/nyora.json"
VENV = H + "/.local/share/qs-manga/venv"
LOG = H + "/.cache/qs-manga/nyora-helper.log"


def _cfg():
    try:
        return json.load(open(CFG))
    except Exception:
        return {}


def _port():
    try:
        return int(open(PORTF).read().strip().split(":")[-1])
    except Exception:
        return 0


def _alive(p):
    try:
        socket.create_connection(("127.0.0.1", p), 0.5).close()
        return True
    except Exception:
        return False


WD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_nyora_watchdog.sh")
WDPID = H + "/.cache/qs-manga/nyora-watchdog.pid"


def _watchdog():
    try:
        os.kill(int(open(WDPID).read().strip()), 0)
        return
    except Exception:
        pass
    if os.path.exists(WD):
        subprocess.Popen(["bash", WD], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)


def _jar():
    pat = VENV + "/lib/python*/site-packages/nyora_extension_server/_jar/*.jar"
    j = glob.glob(pat)
    if not j:
        try:
            subprocess.run([sys.executable, "-m", "venv", VENV], check=True, timeout=180, capture_output=True)
            subprocess.run([VENV + "/bin/pip", "install", "--quiet", "nyora"], check=True, timeout=900, capture_output=True)
        except Exception:
            pass
        j = glob.glob(pat)
    if not j:
        raise RuntimeError("nyora not installed in " + VENV)
    return j[0]


def _base_unlocked():
    p = _port()
    if not (p and _alive(p)):
        jar = _jar()
        try:
            os.remove(PORTF)
        except OSError:
            pass
        os.makedirs(os.path.dirname(PORTF), exist_ok=True)
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        lg = open(LOG, "ab")
        subprocess.Popen(["java", "-Dnyora.helper.port-file=" + PORTF, "-jar", jar],
                         stdout=lg, stderr=lg, stdin=subprocess.DEVNULL, start_new_session=True)
        for _ in range(120):
            time.sleep(0.5)
            p = _port()
            if p and _alive(p):
                break
        else:
            raise RuntimeError("nyora helper did not start; see " + LOG)
    _watchdog()
    return "http://127.0.0.1:%d" % p


def _get(path, **params):
    i = params.get("id")
    if i and ":" not in i:
        params["id"] = "parser:" + i
    u = _base() + path + "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v is not None})
    with urllib.request.urlopen(u, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def _src():
    return _cfg().get("source", "COMICK_FUN")


def _tags(m):
    out = []
    for t in m.get("tags") or []:
        out.append(t if isinstance(t, str) else (t.get("title") or t.get("name") or ""))
    return [x for x in out if x]


def _kind(m):
    t = " ".join(_tags(m)).lower()
    if "manhua" in t:
        return "MANHUA"
    if "manhwa" in t or "long strip" in t or "web comic" in t:
        return "MANHWA"
    return "MANGA"


def _manga(e, src):
    return {
        "id": src + "|" + urllib.parse.quote(str(e.get("url", "")), safe=""),
        "title": e.get("title", ""),
        "desc": e.get("description") or "",
        "cover": e.get("cover_url") or e.get("coverUrl") or e.get("large_cover_url") or e.get("largeCoverUrl") or "",
        "kind": _kind(e),
        "status": e.get("state") or "",
        "year": e.get("year"),
        "tags": _tags(e),
        "authors": e.get("authors") or [],
        "official": e.get("public_url") or e.get("publicUrl") or "",
    }


COVERS = H + "/.cache/qs-manga/nyora-covers"


def _cover_file(url):
    if not url or not url.startswith("http"):
        return url
    import hashlib
    key = hashlib.sha1(url.encode()).hexdigest()
    dst = COVERS + "/" + key + ".img"
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        return "file://" + dst
    try:
        os.makedirs(COVERS, exist_ok=True)
        with urllib.request.urlopen(url, timeout=20) as r:
            data = r.read()
        if data:
            open(dst + ".tmp", "wb").write(data)
            os.replace(dst + ".tmp", dst)
            return "file://" + dst
    except Exception:
        pass
    return url


def _covers(items):
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(8) as ex:
        for it, c in zip(items, ex.map(lambda m: _cover_file(m["cover"]), items)):
            it["cover"] = c
    return items


LIB = H + "/.local/share/qs-manga/library.json"
LANGS = {
    "en": ["english"], "pt": ["portugu"], "pt-br": ["portugu"], "es": ["espa", "spanish"],
    "es-la": ["espa", "spanish"], "fr": ["fran", "french"], "de": ["deutsch", "german"],
    "it": ["ital"], "ru": ["рус", "russian"], "uk": ["укра"], "id": ["indonesia"],
    "ja": ["日本", "japan"], "ko": ["한국", "korean"], "zh": ["中文", "chinese", "简体", "繁體"],
    "zh-hk": ["中文", "chinese", "繁體"], "ar": ["عرب", "arabic"], "tr": ["türk", "turk"],
    "pl": ["polski", "polish"], "vi": ["tiếng việt", "viet"], "th": ["ไทย", "thai"],
    "hi": ["हिन्दी", "hindi"],
}


def _settings():
    try:
        return json.load(open(LIB)).get("settings", {})
    except Exception:
        return {}


def _nsfw():
    return _settings().get("rating_erotica", False) is True


def _lang_keys():
    code = str(_settings().get("lang") or "en").lower()
    return LANGS.get(code, [code])


def _entries(d):
    es = d.get("entries", []) if isinstance(d, dict) else d
    if not _nsfw():
        es = [e for e in es if not (e.get("is_nsfw") or e.get("isNsfw"))]
    return es


class Source:
    ID = "NYORA"
    NAME = "Nyora"
    SRC = None

    def browse(self, kind, sort, offset):
        s = self.SRC or _src()
        path = "/sources/latest" if str(sort).lower() == "latest" else "/sources/popular"
        pg = offset // 24 + 1
        d = _get(path, id=s, page=pg)
        if pg > 1:
            def ids(x):
                es = x.get("entries", []) if isinstance(x, dict) else x
                return [e.get("id") for e in es[:3]]
            if ids(_get(path, id=s, page=1)) == ids(d):
                return []
        return _covers([_manga(e, s) for e in _entries(d)])

    def search(self, kind, q):
        s = self.SRC or _src()
        return _covers([_manga(e, s) for e in _entries(_get("/sources/search", id=s, q=q, page=1))])

    def info(self, sid):
        s, url = sid.split("|", 1)
        url = urllib.parse.unquote(url)
        d = _get("/manga/details", id=s, url=url)
        m = d.get("manga", d)
        m.setdefault("url", url)
        return _covers([_manga(m, s)])[0]

    def chapters(self, sid):
        s, url = sid.split("|", 1)
        url = urllib.parse.unquote(url)
        chs = _get("/manga/details", id=s, url=url).get("chapters") or []
        groups = {}
        for c in chs:
            groups.setdefault(c.get("branch") or "", []).append(c)
        pick = None
        for k in _lang_keys():
            pick = next((b for b in groups if k in b.lower()), None)
            if pick is not None:
                break
        if pick is None:
            pick = next((b for b in groups if "english" in b.lower()), None)
        if pick is None and groups:
            pick = max(groups, key=lambda b: len(groups[b]))
        seen, out = set(), []
        for c in sorted(groups.get(pick, []), key=lambda c: (c.get("number") or 0)):
            n = c.get("number") or 0
            if n in seen:
                continue
            seen.add(n)
            out.append({
                "id": "%s|%s|%s" % (s, urllib.parse.quote(str(c.get("url", "")), safe=""), urllib.parse.quote(c.get("branch") or "", safe="")),
                "num": n,
                "vol": c.get("volume") or 0,
                "title": (c.get("title") or "").strip(),
                "pages": 0,
            })
        return out

    def pages(self, cid, saver=False):
        s, url, br = cid.split("|", 2)
        url, br = urllib.parse.unquote(url), urllib.parse.unquote(br)
        d = _get("/manga/pages", id=s, url=url, branch=br or None)
        ps = d.get("pages", []) if isinstance(d, dict) else d
        return [p["url"] if isinstance(p, dict) else p for p in ps]


# ------------------------------------------------------------ extensions manager
LEGACY = {"ASURASCANS": ("NYORA_ASURA", "Asura Scans"), "FLAMECOMICS": ("NYORA_FLAME", "Flame Comics")}
DEFAULT_ON = "ASURASCANS,FLAMECOMICS"
SRCCACHE = H + "/.cache/qs-manga/nyora_sources.json"
HEALTH = H + "/.cache/qs-manga/nyora_health.json"


def _jload(p, d):
    try:
        return json.load(open(p))
    except Exception:
        return d


def _jsave(p, v):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".tmp", "w") as f:
        json.dump(v, f)
    os.replace(p + ".tmp", p)


def enabled():
    v = _settings().get("nyora_on")
    if v is None:
        v = DEFAULT_ON
    return [x for x in str(v).split(",") if x]


def _sid_to_raw(sid):
    for raw, (s, _n) in LEGACY.items():
        if s == sid:
            return raw
    return sid[len("NYORA_"):]


def _new(raw, names, hidden):
    sid, nm = LEGACY.get(raw, ("NYORA_" + raw, names.get(raw) or raw.replace("_", " ").title()))
    s = Source()
    s.ID, s.NAME, s.SRC, s.HIDDEN = sid, nm, raw, hidden
    return s


def make_sources():
    names = {e["id"]: e["name"] for e in _jload(SRCCACHE, {}).get("sources", [])}
    out, seen = [], set()
    for raw in enabled():
        s = _new(raw, names, False)
        if s.ID not in seen:
            out.append(s)
            seen.add(s.ID)
    # sources still referenced by the library stay registered (hidden) so saved titles keep working
    try:
        lib = json.load(open(LIB)).get("manga", {})
    except Exception:
        lib = {}
    for k in lib:
        sid = k.split(":", 1)[0]
        if k.startswith("NYORA_") and sid not in seen:
            s = _new(_sid_to_raw(sid), names, True)
            s.ID = sid
            out.append(s)
            seen.add(sid)
    return out


def _cli_list(refresh):
    c = _jload(SRCCACHE, {})
    fresh = bool(c.get("sources")) and time.time() - c.get("ts", 0) < 7 * 86400
    if refresh or not fresh:
        try:
            d = _get("/sources")
        except Exception as e:
            if not c.get("sources"):
                return {"error": str(e)[:80]}
            d = None
        if d is not None:
            es = d.get("sources", d.get("entries", [])) if isinstance(d, dict) else d
            lst = []
            for e in es:
                i = str(e.get("id", ""))
                if not i.startswith("parser:") or e.get("is_obsolete") or e.get("isObsolete"):
                    continue
                lst.append({"id": i[7:], "name": e.get("name") or i[7:], "lang": str(e.get("lang") or "all"),
                            "nsfw": bool(e.get("is_nsfw") or e.get("isNsfw"))})
            c = {"ts": time.time(), "sources": lst}
            _jsave(SRCCACHE, c)
    on = set(enabled())
    return {"sources": [dict(e, on=e["id"] in on) for e in c.get("sources", [])], "health": _jload(HEALTH, {})}


def _cli_toggle(raw, load, save):
    cur = enabled()
    if raw in cur:
        cur.remove(raw)
    else:
        cur.append(raw)
    d = load()
    d["settings"]["nyora_on"] = ",".join(cur)
    save(d)
    return {"id": raw, "on": raw in cur}


def _cli_test(raw):
    def done(ok, detail):
        h = _jload(HEALTH, {})
        h[raw] = {"ok": ok, "detail": detail, "ts": time.time()}
        _jsave(HEALTH, h)
        return {"id": raw, "ok": ok, "detail": detail}
    try:
        d = _get("/sources/popular", id=raw, page=1)
        es = d.get("entries", []) if isinstance(d, dict) else d
        if not es:
            return done(False, "empty list")
        chap = None
        for e in es[:4]:
            chs = _get("/manga/details", id=raw, url=e.get("url")).get("chapters") or []
            if chs:
                chap = chs[0]
                break
        if chap is None:
            return done(False, "no chapters")
        pg = _get("/manga/pages", id=raw, url=chap.get("url"), branch=chap.get("branch") or None)
        ps = pg.get("pages", []) if isinstance(pg, dict) else pg
        if not ps:
            return done(False, "no pages")
        u = ps[0]["url"] if isinstance(ps[0], dict) else ps[0]
        try:
            with urllib.request.urlopen(u, timeout=25) as r:
                n = len(r.read(200000))
        except urllib.error.HTTPError as e:
            return done(False, "image HTTP %d" % e.code)
        return done(n > 1000, "ok" if n > 1000 else "image empty")
    except Exception as e:
        return done(False, str(e)[:60])


def cli(cmd, r, load, save):
    if cmd == "list":
        return _cli_list(bool(r) and r[0] == "refresh")
    if cmd == "toggle" and r:
        return _cli_toggle(r[0], load, save)
    if cmd == "test" and r:
        return _cli_test(r[0])
    return {"error": "bad nyora command"}


import threading
_LOCK = threading.Lock()


def _base():
    with _LOCK:
        return _base_unlocked()
