#!/usr/bin/env python3
"""manga.py - backend for the Manga panel.

Sources (all return the same shapes):
  md     MangaDex API
  local  folders / .cbz / .zip under ~/Manga (cfg local_root)
  plus any plugin in scripts/manga_sources/*.py (see _template.py)
IDs are prefixed with the source: "md:<uuid>", "local:<series>". Chapter ids likewise.
"""
import glob, hashlib, importlib.util, json, os, re, shutil, subprocess, sys, time, zipfile
import urllib.error, urllib.parse, urllib.request
from urllib.parse import quote

HOME = os.path.expanduser("~")
DATA = HOME + "/.local/share/qs-manga"
CACHE = HOME + "/.cache/qs-manga"
DL = DATA + "/downloads"
LIB = DATA + "/library.json"
for _d in (DATA, CACHE, DL, CACHE + "/meta", CACHE + "/arc"):
    os.makedirs(_d, exist_ok=True)
IMG_EXT = (".jpg", ".jpeg", ".png", ".webp", ".gif")
UA = "qs-manga/1.0 (personal desktop reader)"
RATINGS = ("safe", "suggestive")
LANG_KIND = {"ja": "MANGA", "ko": "MANHWA", "zh": "MANHUA", "zh-hk": "MANHUA"}
KIND_LANGS = {"manga": ["ja"], "manhwa": ["ko"], "manhua": ["zh", "zh-hk"]}
UUID = re.compile(r"^[0-9a-fA-F-]{36}$")
SOURCES = {}


def ratings():
    s = load()["settings"]
    out = ["safe"]
    if s.get("rating_suggestive", True) is not False:
        out.append("suggestive")
    if s.get("rating_erotica", False) is True:
        out.append("erotica")
    return out


def natural(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", s)]


def furl(path):
    return "file://" + quote(path)


# ------------------------------------------------------------ storage
def load():
    try:
        d = json.load(open(LIB))
    except Exception:
        d = {}
    d.setdefault("manga", {})
    d.setdefault("settings", {"saver": False})
    d["manga"] = {(k if ":" in k else "md:" + k): v for k, v in d["manga"].items()}
    return d


def save(d):
    tmp = LIB + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, LIB)


def cache_put(key, val):
    try:
        with open(CACHE + "/meta/" + hashlib.sha1(key.encode()).hexdigest() + ".json", "w") as f:
            json.dump(val, f)
    except Exception:
        pass


def cache_get(key):
    try:
        return json.load(open(CACHE + "/meta/" + hashlib.sha1(key.encode()).hexdigest() + ".json"))
    except Exception:
        return None


# ------------------------------------------------------------ MangaDex
class MangaDex:
    ID = "md"
    NAME = "MangaDex"
    API = "https://api.mangadex.org"

    def lang(self):
        return str(load()["settings"].get("lang") or "en")

    def api(self, path, params=None, retries=2):
        url = self.API + path + ("?" + urllib.parse.urlencode(params, doseq=True) if params else "")
        for i in range(retries + 1):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA})
                with urllib.request.urlopen(req, timeout=15) as r:
                    return json.loads(r.read().decode("utf-8", "replace"))
            except urllib.error.HTTPError as e:
                if e.code == 429 and i < retries:
                    time.sleep(1.5 * (i + 1))
                    continue
                raise
            except Exception:
                if i < retries:
                    time.sleep(0.8)
                    continue
                raise

    @staticmethod
    def parse(d):
        a = d.get("attributes", {})
        titles = a.get("title", {})
        title = titles.get("en") or next(iter(titles.values()), "?")
        desc = (a.get("description") or {}).get("en", "")
        cover, authors = None, []
        for r in d.get("relationships", []):
            at = r.get("attributes") or {}
            if r["type"] == "cover_art" and at.get("fileName"):
                cover = "https://uploads.mangadex.org/covers/%s/%s.256.jpg" % (d["id"], at["fileName"])
            elif r["type"] == "author" and at.get("name"):
                authors.append(at["name"])
        lang = a.get("originalLanguage", "")
        tags = []
        for t in a.get("tags", []):
            n = ((t.get("attributes") or {}).get("name") or {}).get("en")
            if n:
                tags.append(n)
        return {"id": d["id"], "title": title, "desc": desc, "cover": cover,
                "kind": LANG_KIND.get(lang, lang.upper() or "MANGA"), "status": a.get("status", ""),
                "year": a.get("year"), "tags": tags[:8], "authors": authors[:3],
                "official": (a.get("links") or {}).get("engtl", "")}

    def _list(self, extra, limit=24, offset=0):
        params = [("limit", limit), ("offset", offset), ("includes[]", "cover_art"),
                  ("availableTranslatedLanguage[]", self.lang()), ("hasAvailableChapters", "true")]
        params += [("contentRating[]", r) for r in ratings()] + extra
        return [self.parse(d) for d in self.api("/manga", params).get("data", [])]

    @staticmethod
    def _kind(kind):
        return [("originalLanguage[]", l) for l in KIND_LANGS.get(kind, [])]

    def browse(self, kind, sort, offset):
        order = {"popular": "order[followedCount]", "latest": "order[latestUploadedChapter]",
                 "rating": "order[rating]"}.get(sort, "order[followedCount]")
        return self._list(self._kind(kind) + [(order, "desc")], 24, offset)

    def search(self, kind, q):
        return self._list(self._kind(kind) + [("title", q), ("order[relevance]", "desc")], 24, 0)

    def info(self, sid):
        if not UUID.match(sid):
            raise ValueError("bad id")
        j = self.api("/manga/" + sid, [("includes[]", "cover_art"), ("includes[]", "author")])
        return self.parse(j["data"])

    def chapters(self, sid, lang=None):
        lang = lang or self.lang()
        if not UUID.match(sid):
            raise ValueError("bad id")
        best, off = {}, 0
        while True:
            params = [("limit", 500), ("offset", off), ("translatedLanguage[]", lang),
                      ("order[chapter]", "asc"), ("includeExternalUrl", "0")]
            params += [("contentRating[]", r) for r in ratings()]
            j = self.api("/manga/%s/feed" % sid, params)
            for c in j.get("data", []):
                a = c["attributes"]
                if not a.get("pages"):
                    continue
                num = a.get("chapter") or ""
                cur = best.get(num)
                if cur is None or a["pages"] > cur["pages"]:
                    best[num] = {"id": c["id"], "num": num, "vol": a.get("volume") or "",
                                 "title": a.get("title") or "", "pages": a["pages"]}
            off += 500
            if off >= j.get("total", 0) or not j.get("data"):
                break

        def key(c):
            try:
                return float(c["num"])
            except ValueError:
                return -1.0
        return sorted(best.values(), key=key)

    def pages(self, cid, saver=False):
        if not UUID.match(cid):
            raise ValueError("bad id")
        try:
            j = self.api("/at-home/server/" + cid)
        except Exception:
            j = self.api("/at-home/server/" + cid, [("forcePort443", "true")])
        q = "data-saver" if saver else "data"
        files = j["chapter"]["dataSaver" if saver else "data"]
        return [j["baseUrl"] + "/" + q + "/" + j["chapter"]["hash"] + "/" + f for f in files]


# ------------------------------------------------------------ local files
def img_files(d):
    try:
        return [f for f in sorted(os.listdir(d), key=natural) if f.lower().endswith(IMG_EXT) and not f.startswith(".")]
    except OSError:
        return []


def zip_images(fp):
    with zipfile.ZipFile(fp) as z:
        return sorted([n for n in z.namelist() if n.lower().endswith(IMG_EXT)
                       and "__MACOSX" not in n and not n.endswith("/")], key=natural)


def extract_archive(fp):
    key = hashlib.sha1(("%s|%s" % (fp, os.path.getmtime(fp))).encode()).hexdigest()[:16]
    d = os.path.join(CACHE, "arc", key)
    if not os.path.exists(os.path.join(d, ".ok")):
        os.makedirs(d, exist_ok=True)
        with zipfile.ZipFile(fp) as z:
            for i, n in enumerate(zip_images(fp)):
                ext = os.path.splitext(n)[1].lower()
                with z.open(n) as src, open(os.path.join(d, "%04d%s" % (i + 1, ext)), "wb") as dst:
                    shutil.copyfileobj(src, dst)
        open(os.path.join(d, ".ok"), "w").close()
    return [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.lower().endswith(IMG_EXT)]


class Local:
    ID = "local"
    NAME = "Local files"

    def root(self):
        r = load()["settings"].get("local_root") or "~/Manga"
        return os.path.realpath(os.path.expanduser(str(r)))

    def _series(self):
        root = self.root()
        if not os.path.isdir(root):
            return []
        return [n for n in sorted(os.listdir(root), key=natural)
                if os.path.isdir(os.path.join(root, n)) and not n.startswith(".")]

    def _entries(self, series):
        p = os.path.join(self.root(), series)
        ents, direct = [], False
        for n in sorted(os.listdir(p), key=natural):
            fp = os.path.join(p, n)
            if n.startswith("."):
                continue
            if os.path.isdir(fp) and img_files(fp):
                ents.append(n)
            elif os.path.isfile(fp) and n.lower().endswith((".cbz", ".zip")):
                ents.append(n)
            elif os.path.isfile(fp) and n.lower().endswith(IMG_EXT):
                direct = True
        return ents if ents else (["."] if direct else [])

    def _cover(self, series):
        try:
            ents = self._entries(series)
            if not ents:
                return None
            fp = os.path.realpath(os.path.join(self.root(), series, ents[0]))
            if os.path.isdir(fp):
                f = img_files(fp)
                return furl(os.path.join(fp, f[0])) if f else None
            key = hashlib.sha1(("%s|%s" % (fp, os.path.getmtime(fp))).encode()).hexdigest()[:16]
            dst = os.path.join(CACHE, "arc", "cover-" + key)
            names = zip_images(fp)
            if not names:
                return None
            ext = os.path.splitext(names[0])[1].lower()
            if not os.path.exists(dst + ext):
                with zipfile.ZipFile(fp) as z, z.open(names[0]) as s_, open(dst + ext, "wb") as o:
                    shutil.copyfileobj(s_, o)
            return furl(dst + ext)
        except Exception:
            return None

    def _item(self, series):
        return {"id": series, "title": series, "desc": "", "cover": self._cover(series), "kind": "LOCAL",
                "status": "", "year": None, "tags": [], "authors": [], "official": ""}

    def browse(self, kind, sort, offset):
        return [] if offset else [self._item(n) for n in self._series()]

    def search(self, kind, q):
        ql = q.lower()
        return [self._item(n) for n in self._series() if ql in n.lower()]

    def info(self, sid):
        if sid not in self._series():
            raise ValueError("series not found")
        it = self._item(sid)
        it["desc"] = "Local series in " + self.root()
        return it

    def chapters(self, sid):
        if sid not in self._series():
            raise ValueError("series not found")
        out = []
        for i, e in enumerate(self._entries(sid)):
            fp = os.path.realpath(os.path.join(self.root(), sid, e))
            try:
                n = len(img_files(fp)) if os.path.isdir(fp) else len(zip_images(fp))
            except Exception:
                n = 0
            if not n:
                continue
            m = re.search(r"(\d+(?:\.\d+)?)", e)
            if m:
                s_ = m.group(1)
                num = str(float(s_)).rstrip("0").rstrip(".") if "." in s_ else str(int(s_))
            else:
                num = str(i + 1)
            title = os.path.splitext(e)[0] if e != "." else sid
            out.append({"id": sid + "/" + e, "num": num, "vol": "", "title": title, "pages": n})
        return out

    def pages(self, cid, saver=False):
        series, _, entry = cid.partition("/")
        root = self.root()
        fp = os.path.realpath(os.path.join(root, series, entry or "."))
        if not fp.startswith(root + os.sep):
            raise ValueError("bad path")
        if os.path.isdir(fp):
            return [furl(os.path.join(fp, f)) for f in img_files(fp)]
        if os.path.isfile(fp) and fp.lower().endswith((".cbz", ".zip")):
            return [furl(p) for p in extract_archive(fp)]
        raise ValueError("chapter not found")


# ------------------------------------------------------------ plugins
def load_plugins():
    SOURCES["md"] = MangaDex()
    SOURCES["md"].HIDDEN = True  # stays registered so library titles and downloads still open
    SOURCES["local"] = Local()
    d = os.path.dirname(os.path.abspath(__file__)) + "/manga_sources"
    for f in sorted(glob.glob(d + "/[!_]*.py")):
        try:
            spec = importlib.util.spec_from_file_location("mgsrc_" + os.path.basename(f)[:-3], f)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            if hasattr(mod, "make_sources"):
                for s in mod.make_sources():
                    SOURCES[s.ID] = s
            else:
                s = mod.Source()
                SOURCES[s.ID] = s
        except Exception as e:
            sys.stderr.write("manga source %s failed: %s\n" % (f, e))


# ------------------------------------------------------------ dispatch
def split(i):
    src, _, rest = (i or "").partition(":")
    if not rest:
        raise ValueError("bad id")
    return src, rest


def source(src):
    s = SOURCES.get(src)
    if s is None:
        raise ValueError("unknown source " + str(src))
    return s


def tag(src, items):
    for it in items:
        it["id"] = src + ":" + it["id"]
        it["src"] = src
    return items


def cmd_sources():
    order = ["md", "local"] + [k for k in SOURCES if k not in ("md", "local")]
    return [{"id": k, "name": getattr(SOURCES[k], "NAME", k)} for k in order if k in SOURCES and not getattr(SOURCES[k], "HIDDEN", False)]


def cmd_browse(src, kind, sort, offset):
    if src == "all":
        src = "md"
    return tag(src, source(src).browse(kind, sort, offset))


def cmd_search(src, kind, q):
    if src != "all":
        return tag(src, source(src).search(kind, q))
    from concurrent.futures import ThreadPoolExecutor, as_completed
    ids = [x["id"] for x in cmd_sources() if x["id"] in SOURCES]
    res = {}
    ex = ThreadPoolExecutor(max(1, min(8, len(ids))))
    futs = {ex.submit(lambda k=k: tag(k, SOURCES[k].search(kind, q))): k for k in ids}
    try:
        for f in as_completed(futs, timeout=25):
            try:
                res[futs[f]] = f.result()
            except Exception:
                pass
    except Exception:
        pass
    ex.shutdown(wait=False, cancel_futures=True)
    out = []
    for k in ids:
        nm = getattr(SOURCES[k], "NAME", k)
        for it in res.get(k, []):
            it["srcName"] = nm
            out.append(it)
    return out


def with_cache(key, fn):
    try:
        val = fn()
        cache_put(key, val)
        return val
    except Exception:
        cached = cache_get(key)
        if cached is not None:
            return {"cached": True, "data": cached} if isinstance(cached, list) else dict(cached, cached=True)
        raise


def cmd_info(i):
    src, rest = split(i)
    it = with_cache("info:" + i, lambda: source(src).info(rest))
    it["id"] = i
    it["src"] = src
    return it


def cmd_chapters(i):
    src, rest = split(i)
    ch = with_cache("ch:" + i, lambda: tag(src, source(src).chapters(rest)))
    return ch


def dl_dir(rest):
    return os.path.join(DL, rest)


def cmd_pages(cid, saver):
    src, rest = split(cid)
    d = dl_dir_cid(cid)
    if os.path.exists(os.path.join(d, ".done")):
        return [furl(os.path.join(d, f)) for f in sorted(os.listdir(d)) if f.lower().endswith(IMG_EXT)]
    return source(src).pages(rest, saver)


# ------------------------------------------------------------ downloads (all sources)
QF = DATA + "/dlqueue.json"
QPID = CACHE + "/dlq.pid"


def dl_dir_cid(cid):
    src, rest = split(cid)
    if src == "md" and UUID.match(rest):
        return os.path.join(DL, rest)
    return os.path.join(DL, "x_" + hashlib.sha1(cid.encode()).hexdigest()[:24])


def dl_state(d, **kw):
    with open(os.path.join(d, ".status"), "w") as f:
        json.dump(kw, f)


def _url_ext(u):
    try:
        p = urllib.parse.urlparse(u)
        if p.hostname == "127.0.0.1" and p.path == "/image":
            q = urllib.parse.parse_qs(p.query).get("u")
            if q:
                p = urllib.parse.urlparse(q[0])
        ext = os.path.splitext(p.path)[1].lower()
    except Exception:
        ext = ""
    return ext if ext in IMG_EXT else ".jpg"


def _dl_fetch(u, fp):
    for attempt in range(3):
        try:
            req = urllib.request.Request(u, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as r, open(fp + ".part", "wb") as f:
                shutil.copyfileobj(r, f)
            os.replace(fp + ".part", fp)
            return
        except Exception:
            if attempt == 2:
                raise
            p = urllib.parse.urlparse(u)
            if p.hostname == "127.0.0.1" and p.path == "/image":
                try:
                    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/manga_sources")
                    import _nyora_core
                    u = _nyora_core._base() + "/image?" + p.query
                except Exception:
                    pass
            time.sleep(2)


class _DlErr(Exception):
    def __init__(self, page, cause):
        Exception.__init__(self, str(cause))
        self.page = page
        self.cause = cause


def _explain(e):
    import socket
    import urllib.error
    msg = str(e)
    if isinstance(e, urllib.error.HTTPError):
        c = e.code
        body = ""
        try:
            body = e.read().decode("utf-8", "ignore")[:200]
        except Exception:
            pass
        if c == 502 and "HTTP 403" in body:
            return "The source's image server is blocking downloads (HTTP 403 via the Nyora helper). This source cannot be downloaded or read right now."
        if c in (401, 403):
            return "The source refused the request (HTTP %d). The site may be blocking downloads or its CDN is protected." % c
        if c == 404:
            return "The page was not found on the source (HTTP 404). The chapter may have been removed or the link expired."
        if c == 429:
            return "The source is rate limiting you (HTTP 429). Wait a few minutes and retry."
        if c >= 500:
            return "The source server had an error (HTTP %d). Try again later." % c
        return "The source answered with HTTP error %d." % c
    if isinstance(e, urllib.error.URLError):
        r = getattr(e, "reason", None)
        if isinstance(r, ConnectionRefusedError) or "Connection refused" in msg:
            return "Could not reach the Nyora helper (connection refused). It may have stopped; retry to restart it."
        if isinstance(r, socket.gaierror):
            return "No internet connection (DNS lookup failed)."
        if isinstance(r, (socket.timeout, TimeoutError)):
            return "The source took too long to respond (timeout)."
        return "Network error: %s" % (r or msg)
    if isinstance(e, (socket.timeout, TimeoutError)):
        return "The source took too long to respond (timeout)."
    if "no pages" in msg.lower():
        return "The source returned no pages for this chapter."
    if isinstance(e, ConnectionError) or "Remote end closed" in msg:
        return "The connection was closed by the source or the Nyora helper mid-transfer."
    if isinstance(e, OSError) and getattr(e, "errno", None) == 28:
        return "The disk is full."
    if isinstance(e, PermissionError):
        return "Permission denied writing to the downloads folder."
    return "%s: %s" % (type(e).__name__, msg[:160])


def do_download(cid, saver):
    src, rest = split(cid)
    if src == "local":
        return
    d = dl_dir_cid(cid)
    os.makedirs(d, exist_ok=True)
    total = 0
    done = [0]
    try:
        with open(os.path.join(d, ".id"), "w") as f:
            f.write(cid)
        dl_state(d, status="running", done=0, total=0)
        urls = source(src).pages(rest, saver)
        total = len(urls)
        if total == 0:
            raise ValueError("no pages")
        dl_state(d, status="running", done=0, total=total)
        from concurrent.futures import ThreadPoolExecutor

        def one(i):
            try:
                fp = os.path.join(d, "%04d%s" % (i + 1, _url_ext(urls[i])))
                if not os.path.exists(fp):
                    _dl_fetch(urls[i], fp)
            except Exception as e:
                raise _DlErr(i + 1, e)
            done[0] += 1
            dl_state(d, status="running", done=done[0], total=total)

        with ThreadPoolExecutor(3) as ex:
            list(ex.map(one, range(total)))
        open(os.path.join(d, ".done"), "w").close()
        dl_state(d, status="done", done=total, total=total)
    except Exception as e:
        cause = e.cause if isinstance(e, _DlErr) else e
        msg = _explain(cause)
        if isinstance(e, _DlErr):
            msg = "Page %d of %d: %s" % (e.page, total, msg)
        dl_state(d, status="error", error=msg, detail="%s: %s" % (type(cause).__name__, str(cause)[:200]),
                 done=done[0], total=total, ts=int(time.time()))


def cmd_download(cid, saver):
    src, rest = split(cid)
    if src == "local":
        return {"ok": False, "error": "local chapters are already offline"}
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "_dl", cid, "saver" if saver else "full"],
                     start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "status": "started"}


def _q_load():
    try:
        return json.load(open(QF))
    except Exception:
        return {"saver": False, "ids": []}


def _q_save(q):
    with open(QF + ".tmp", "w") as f:
        json.dump(q, f)
    os.replace(QF + ".tmp", QF)


def _q_alive():
    try:
        os.kill(int(open(QPID).read().strip()), 0)
        return True
    except Exception:
        return False


def _q_start():
    if not _q_alive():
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "_dlq"],
                         start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _chapter_meta(mid):
    out = {}
    try:
        for c in cache_get("ch:" + mid) or []:
            out[c["id"]] = c
    except Exception:
        pass
    return out


def cmd_dl_queue(mode, mid, mtitle, cids):
    q = _q_load()
    q["saver"] = (mode == "saver")
    have = set(q["ids"])
    cm = _chapter_meta(mid)
    n = 0
    for c in cids:
        if c in have or c.startswith("local:"):
            continue
        d = dl_dir_cid(c)
        if os.path.exists(os.path.join(d, ".done")):
            continue
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, ".id"), "w") as f:
            f.write(c)
        ch = cm.get(c, {})
        with open(os.path.join(d, ".meta"), "w") as f:
            json.dump({"cid": c, "mid": mid, "manga": mtitle, "num": ch.get("num"), "title": ch.get("title", "")}, f)
        dl_state(d, status="queued")
        q["ids"].append(c)
        have.add(c)
        n += 1
    _q_save(q)
    if n:
        _q_start()
    return {"ok": True, "queued": n}


def cmd_dl_retry(cids):
    q = _q_load()
    have = set(q["ids"])
    n = 0
    for c in cids:
        if c in have:
            continue
        d = dl_dir_cid(c)
        if os.path.exists(os.path.join(d, ".done")):
            continue
        os.makedirs(d, exist_ok=True)
        dl_state(d, status="queued")
        q["ids"].append(c)
        have.add(c)
        n += 1
    _q_save(q)
    if n:
        _q_start()
    return {"ok": True, "queued": n}


def cmd_dl_clear_failed():
    alive = _q_alive()
    n = 0
    for name in os.listdir(DL):
        d = os.path.join(DL, name)
        if not os.path.isdir(d) or os.path.exists(os.path.join(d, ".done")):
            continue
        try:
            st = json.load(open(os.path.join(d, ".status")))
        except Exception:
            st = {}
        s = st.get("status")
        if s == "error" or (s in ("running", "queued") and not alive):
            shutil.rmtree(d, ignore_errors=True)
            n += 1
    return {"ok": True, "removed": n}


def cmd_dl_info():
    q = _q_load()
    if q["ids"]:
        _q_start()
    alive = _q_alive() or bool(q["ids"])
    qpos = {c: i for i, c in enumerate(q["ids"])}
    items, summ = [], {"queued": 0, "running": 0, "failed": 0, "done": 0}
    for name in os.listdir(DL):
        d = os.path.join(DL, name)
        if not os.path.isdir(d):
            continue
        if os.path.exists(os.path.join(d, ".done")):
            summ["done"] += 1
            continue
        try:
            st = json.load(open(os.path.join(d, ".status")))
        except Exception:
            continue
        try:
            meta = json.load(open(os.path.join(d, ".meta")))
        except Exception:
            meta = {}
        try:
            cid = open(os.path.join(d, ".id")).read().strip()
        except Exception:
            cid = meta.get("cid") or ("md:" + name)
        status = st.get("status", "none")
        err = st.get("error", "")
        if status in ("running", "queued") and not alive:
            status = "error"
            err = "Interrupted: the download worker stopped before finishing (the app was closed or crashed). Press RETRY to resume where it left off."
        if status not in ("running", "queued", "error"):
            continue
        summ["failed" if status == "error" else status] += 1
        items.append({"cid": cid, "manga": meta.get("manga", ""), "num": meta.get("num"), "title": meta.get("title", ""),
                      "status": status, "done": st.get("done", 0), "total": st.get("total", 0),
                      "error": err, "ts": st.get("ts", 0)})
    order = {"running": 0, "queued": 1, "error": 2}
    items.sort(key=lambda e: (order[e["status"]], qpos.get(e["cid"], 1e9), -(e.get("ts") or 0)))
    return {"items": items, "summary": summ}


def run_queue():
    import fcntl
    lf = open(QPID, "a+")
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    lf.seek(0)
    lf.truncate()
    lf.write(str(os.getpid()))
    lf.flush()
    while True:
        q = _q_load()
        if not q["ids"]:
            time.sleep(1)
            if not _q_load()["ids"]:
                break
            continue
        cid = q["ids"].pop(0)
        _q_save(q)
        if os.path.exists(os.path.join(dl_dir_cid(cid), ".done")):
            continue
        do_download(cid, q.get("saver", False))


def cmd_dl_status(cid):
    d = dl_dir_cid(cid)
    if os.path.exists(os.path.join(d, ".done")):
        return {"status": "done"}
    try:
        return json.load(open(os.path.join(d, ".status")))
    except Exception:
        return {"status": "none"}


def cmd_dl_list():
    out = []
    for n in sorted(os.listdir(DL)):
        d = os.path.join(DL, n)
        if not os.path.isdir(d):
            continue
        try:
            cid = open(os.path.join(d, ".id")).read().strip()
        except Exception:
            cid = "md:" + n
        if os.path.exists(os.path.join(d, ".done")):
            out.append(cid)
        else:
            try:
                if json.load(open(os.path.join(d, ".status"))).get("status") == "error":
                    out.append("!" + cid)
            except Exception:
                pass
    return out


def cmd_dl_rm(cid):
    d = dl_dir_cid(cid)
    if os.path.dirname(d) == DL:
        shutil.rmtree(d, ignore_errors=True)
    return {"ok": True}


# ------------------------------------------------------------ library
def cmd_lib():
    d = load()
    out = []
    for mid, m in d["manga"].items():
        item = dict(m)
        item["id"] = mid
        item["src"] = mid.partition(":")[0]
        item["read_count"] = len(m.get("read", []))
        item.pop("read", None)
        out.append(item)
    out.sort(key=lambda m: (m.get("last") or {}).get("ts", m.get("added", 0)), reverse=True)
    return out


def cmd_get(mid):
    mid = mid if ":" in mid else "md:" + mid
    m = load()["manga"].get(mid)
    return dict(m, id=mid, inlib=True) if m else {"id": mid, "inlib": False, "read": [], "last": None}


def cmd_lib_add(mid, title, cover, kind):
    d = load()
    d["manga"].setdefault(mid, {"title": title, "cover": cover, "kind": kind,
                                "added": int(time.time()), "last": None, "read": []})
    save(d)
    return {"ok": True}


def cmd_lib_rm(mid):
    d = load()
    d["manga"].pop(mid, None)
    save(d)
    return {"ok": True}


def cmd_progress(mid, cid, num, page, cts=None, title=None, cover=None, kind=None):
    d = load()
    m = d["manga"].get(mid)
    if m is None:
        if title is None:
            return {"ok": False}
        m = d["manga"].setdefault(mid, {"title": title, "cover": cover or "", "kind": kind or "",
                                        "added": int(time.time()), "last": None, "read": []})
    try:
        c = int(float(cts)) if cts is not None else 0
    except ValueError:
        c = 0
    last = m.get("last") or {}
    if c and c < int(last.get("cts", 0)):
        return {"ok": True, "stale": True}
    m["last"] = {"chapter_id": cid, "num": num, "page": int(page), "ts": int(time.time()), "cts": c}
    save(d)
    return {"ok": True}


def cmd_read(mid, cid):
    d = load()
    m = d["manga"].get(mid)
    if m is not None and cid not in m["read"]:
        m["read"].append(cid)
        save(d)
    return {"ok": True}


def cmd_cfg(a):
    d = load()
    if len(a) >= 2:
        v = a[1]
        d["settings"][a[0]] = True if v == "true" else False if v == "false" else v
        save(d)
    return d["settings"]


def main():
    load_plugins()
    a = sys.argv[1:]
    if not a:
        print(json.dumps({"error": "usage"}))
        return 1
    c, r = a[0], a[1:]
    lockf = None
    if c in ("lib-add", "lib-rm", "progress", "read", "cfg", "cfg-reset"):
        import fcntl
        lockf = open(DATA + "/.lib.lock", "a+")
        fcntl.flock(lockf, fcntl.LOCK_EX)
    try:
        if c == "sources":
            out = cmd_sources()
        elif c == "browse":
            out = cmd_browse(r[0] if r else "md", r[1] if len(r) > 1 else "all",
                             r[2] if len(r) > 2 else "popular", int(r[3]) if len(r) > 3 else 0)
        elif c == "search" and len(r) >= 3:
            out = cmd_search(r[0], r[1], " ".join(r[2:]))
        elif c == "info" and r:
            out = cmd_info(r[0])
        elif c == "chapters" and r:
            out = cmd_chapters(r[0])
        elif c == "pages" and r:
            out = cmd_pages(r[0], len(r) > 1 and r[1] == "saver")
        elif c == "download" and r:
            out = cmd_download(r[0], len(r) > 1 and r[1] == "saver")
        elif c == "dl-status" and r:
            out = cmd_dl_status(r[0])
        elif c == "dl-list":
            out = cmd_dl_list()
        elif c == "dl-queue" and len(r) >= 4:
            out = cmd_dl_queue(r[0], r[1], r[2], r[3:])
        elif c == "dl-info":
            out = cmd_dl_info()
        elif c == "dl-retry" and r:
            out = cmd_dl_retry(r)
        elif c == "dl-clear-failed":
            out = cmd_dl_clear_failed()
        elif c == "_dlq":
            run_queue()
            out = {"ok": True}
        elif c == "dl-rm" and r:
            out = cmd_dl_rm(r[0])
        elif c == "_dl" and r:
            do_download(r[0], len(r) > 1 and r[1] == "saver")
            out = {"ok": True}
        elif c == "lib":
            out = cmd_lib()
        elif c == "get" and r:
            out = cmd_get(r[0])
        elif c == "lib-add" and len(r) >= 4:
            out = cmd_lib_add(r[0], r[1], r[2], r[3])
        elif c == "lib-rm" and r:
            out = cmd_lib_rm(r[0])
        elif c == "progress" and len(r) >= 4:
            out = cmd_progress(*r[:8])
        elif c == "read" and len(r) >= 2:
            out = cmd_read(r[0], r[1])
        elif c == "cfg-reset":
            _d = load()
            _d["settings"] = {"saver": False}
            save(_d)
            out = _d["settings"]
        elif c == "cfg":
            out = cmd_cfg(r)
        elif c.startswith("nyora-"):
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/manga_sources")
            import _nyora_core
            out = _nyora_core.cli(c[6:], r, load, save)
        else:
            out = {"error": "bad command"}
    except Exception as e:
        out = {"error": str(e)}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
