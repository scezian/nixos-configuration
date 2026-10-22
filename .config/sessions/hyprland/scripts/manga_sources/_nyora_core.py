# Nyora source: any of Nyora's ~390 sources through the local helper (auto-started).
# Config (optional): ~/.local/share/qs-manga/nyora.json
#   {"source": "COMICK_FUN", "lang": "english", "nsfw": false}
import glob, json, os, socket, subprocess, time, urllib.parse, urllib.request

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


def _base():
    p = _port()
    if not (p and _alive(p)):
        jars = glob.glob(VENV + "/lib/python*/site-packages/nyora_extension_server/_jar/*.jar")
        if not jars:
            raise RuntimeError("nyora helper jar not found; install nyora in " + VENV)
        try:
            os.remove(PORTF)
        except OSError:
            pass
        os.makedirs(os.path.dirname(PORTF), exist_ok=True)
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        lg = open(LOG, "ab")
        subprocess.Popen(["java", "-Dnyora.helper.port-file=" + PORTF, "-jar", jars[0]],
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


def _entries(d):
    es = d.get("entries", []) if isinstance(d, dict) else d
    if not _cfg().get("nsfw", False):
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
        want = str(_cfg().get("lang", "")).lower()
        pick = None
        if want:
            pick = next((b for b in groups if want in b.lower()), None)
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
