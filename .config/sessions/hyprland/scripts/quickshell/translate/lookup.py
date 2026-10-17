#!/usr/bin/env python3
"""Offline Chinese dictionary backend (CC-CEDICT, CC BY-SA 4.0).
Usage: lookup.py build | analyze TEXT | word WORD | search QUERY   (JSON on stdout)"""
import io, json, os, re, sqlite3, sys, zipfile, urllib.request, urllib.error, urllib.parse, time

DB = os.path.expanduser("~/.local/share/qs-dict/cedict.db")
URL = "https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.zip"
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
LINE = re.compile(r"^(\S+) (\S+) \[([^\]]*)\] /(.*)/\s*$")
TONES = {"a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ"}
LOW = re.compile(r"^(surname |variant of|old variant|erhua variant|Japanese variant|see |abbr\. for|archaic variant|ancient variant|also written)", re.I)
PIN_REF = re.compile(r"\[([A-Za-z:]+[1-5](?: [A-Za-z:]+[1-5])*)\]")


def syl_mark(syl):
    m = re.match(r"^([A-Za-z:]+?)([1-5])$", syl)
    if not m:
        return syl
    base = m.group(1).replace("u:", "ü").replace("U:", "Ü")
    tone = int(m.group(2))
    if tone == 5:
        return base
    low = base.lower()
    if "a" in low:
        i = low.index("a")
    elif "e" in low:
        i = low.index("e")
    elif "ou" in low:
        i = low.index("o")
    else:
        i = -1
        for k in range(len(low) - 1, -1, -1):
            if low[k] in "aeiouü":
                i = k
                break
    if i < 0:
        return base
    ch = TONES[low[i]][tone - 1]
    if base[i].isupper():
        ch = ch.upper()
    return base[:i] + ch + base[i + 1:]


def pin_mark(p):
    return " ".join(syl_mark(x) for x in p.split())


def pin_plain(p):
    return re.sub(r"[^a-z]", "", p.lower().replace("u:", "v"))


def fix_def(d):
    return PIN_REF.sub(lambda m: "[" + pin_mark(m.group(1)) + "]", d)


def parse_cl(s):
    out = []
    for it in s[3:].split(","):
        m = re.match(r"^(?:(\S+?)\|)?([^\[\]]+)\[([^\]]+)\]$", it.strip())
        if m:
            out.append({"c": m.group(2), "p": pin_mark(m.group(3))})
    return out


def build():
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    print("downloading CC-CEDICT...", file=sys.stderr)
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    data = urllib.request.urlopen(req, timeout=120).read()
    z = zipfile.ZipFile(io.BytesIO(data))
    name = [n for n in z.namelist() if n.endswith(".u8") or n.endswith(".txt")][0]
    text = z.read(name).decode("utf-8")
    rows = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        m = LINE.match(line)
        if not m:
            continue
        trad, simp, pnum, defs = m.groups()
        rows.append((trad, simp, pnum, pin_mark(pnum), pin_plain(pnum), defs))
    tmp = DB + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    con = sqlite3.connect(tmp)
    con.execute("CREATE TABLE e(id INTEGER PRIMARY KEY, trad TEXT, simp TEXT, pnum TEXT, pmark TEXT, pplain TEXT, defs TEXT)")
    con.executemany("INSERT INTO e(trad,simp,pnum,pmark,pplain,defs) VALUES (?,?,?,?,?,?)", rows)
    con.execute("CREATE INDEX i_simp ON e(simp)")
    con.execute("CREATE INDEX i_trad ON e(trad)")
    con.execute("CREATE INDEX i_pp ON e(pplain)")
    con.commit()
    con.close()
    os.replace(tmp, DB)
    print("ok: %d entries" % len(rows))


def db():
    return sqlite3.connect(DB) if os.path.exists(DB) else None


def entry(r):
    trad, simp, pnum, pmark, defs = r
    ds, cl = [], []
    for d in defs.split("/"):
        d = d.strip()
        if not d:
            continue
        if d.startswith("CL:"):
            cl += parse_cl(d)
        elif not HAN.search(d):
            ds.append(fix_def(d))
    return {"simp": simp, "trad": trad, "pinyin": pmark, "defs": ds, "cl": cl}


def lookup(con, w):
    rows = con.execute("SELECT trad,simp,pnum,pmark,defs FROM e WHERE simp=? OR trad=? ORDER BY id", (w, w)).fetchall()
    ents = [entry(r) for r in rows]
    ents.sort(key=lambda e: 1 if (e["defs"] and LOW.match(e["defs"][0])) else 0)
    return ents


def has(con, w):
    return con.execute("SELECT 1 FROM e WHERE simp=? OR trad=? LIMIT 1", (w, w)).fetchone() is not None


def segment(text, con):
    try:
        import jieba, logging
        jieba.setLogLevel(logging.CRITICAL)
        return [t for t in jieba.lcut(text) if t.strip()]
    except Exception:
        pass
    out, i, n = [], 0, len(text)
    while i < n:
        if not HAN.match(text[i]):
            j = i + 1
            while j < n and not HAN.match(text[j]):
                j += 1
            if text[i:j].strip():
                out.append(text[i:j].strip())
            i = j
            continue
        for L in range(min(8, n - i), 0, -1):
            w = text[i:i + L]
            if L == 1 or has(con, w):
                out.append(w)
                i += L
                break
    return out


def analyze(text):
    con = db()
    if con is None:
        return {"error": "no-db"}
    toks = []
    for w in segment(text, con):
        if not HAN.search(w):
            toks.append({"w": w, "han": False})
            continue
        ents = lookup(con, w)
        if ents:
            e = ents[0]
            toks.append({"w": w, "han": True, "found": True, "pinyin": e["pinyin"], "def": (e["defs"][0] if e["defs"] else "")})
        else:
            parts = []
            for c in w:
                ce = lookup(con, c) if HAN.match(c) else []
                parts.append(ce[0]["pinyin"] if ce else c)
            toks.append({"w": w, "han": True, "found": False, "pinyin": " ".join(parts), "def": ""})
    return {"tokens": toks}


def word(w):
    con = db()
    if con is None:
        return {"error": "no-db"}
    ents = lookup(con, w)
    chars = []
    if len(w) > 1:
        for c in w:
            if not HAN.match(c):
                continue
            ce = lookup(con, c)
            pins = list(dict.fromkeys(e["pinyin"] for e in ce[:4]))
            first = next((e["defs"][0] for e in ce if e["defs"] and not LOW.match(e["defs"][0])), "")
            chars.append({"c": c, "pinyin": " / ".join(pins), "def": first})
    rows = con.execute(
        "SELECT trad,simp,pnum,pmark,defs FROM e WHERE (simp LIKE ? OR trad LIKE ?) AND simp != ? ORDER BY length(simp), id LIMIT 80",
        ("%" + w + "%", "%" + w + "%", w)).fetchall()
    comps, seen = [], set()
    for r in rows:
        e = entry(r)
        if e["simp"] in seen or not e["defs"] or LOW.match(e["defs"][0]):
            continue
        seen.add(e["simp"])
        comps.append({"simp": e["simp"], "pinyin": e["pinyin"], "def": e["defs"][0]})
        if len(comps) >= 10:
            break
    return {"word": w, "entries": ents, "chars": chars, "compounds": comps}


def search(q):
    con = db()
    if con is None:
        return {"error": "no-db"}
    q = q.strip()
    out, seen = [], set()

    def add(rows, kind, cap):
        for r in rows:
            e = entry(r[1:])
            k = (e["simp"], e["pinyin"])
            if k in seen or not e["defs"]:
                continue
            seen.add(k)
            out.append({"simp": e["simp"], "trad": e["trad"], "pinyin": e["pinyin"], "def": "; ".join(e["defs"][:3]), "kind": kind})
            if len(out) >= cap:
                return

    key = re.sub(r"[\s\d']", "", q.lower().replace("ü", "v").replace("u:", "v"))
    if re.fullmatch(r"[a-z]+", key):
        rows = con.execute("SELECT id,trad,simp,pnum,pmark,defs FROM e WHERE pplain=? ORDER BY length(simp), id LIMIT 80", (key,)).fetchall()
        add(rows, "pinyin", 14)
    ql = re.sub(r"[%_]", "", q.lower())
    if ql:
        for pat in ("%/" + ql + "/%", "%/to " + ql + "/%", "%/" + ql + " (%", "%" + ql + "%"):
            if len(out) >= 40:
                break
            rows = con.execute("SELECT id,trad,simp,pnum,pmark,defs FROM e WHERE lower('/'||defs||'/') LIKE ? ORDER BY length(simp), id LIMIT 60", (pat,)).fetchall()
            add(rows, "english", 40)
    return {"query": q, "results": out}


def suggest(w):
    try:
        url = "https://api.datamuse.com/words?sp=" + urllib.parse.quote(w) + "&max=8"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        arr = json.loads(urllib.request.urlopen(req, timeout=6).read().decode("utf-8"))
        return [x["word"] for x in arr if x.get("word") and x["word"].lower() != w.lower()][:5]
    except Exception:
        return []


DOWN = os.path.expanduser("~/.cache/qs_dictapi_down")
POS = {"n": "noun", "v": "verb", "adj": "adjective", "adv": "adverb", "u": "other"}


def api_down():
    try:
        return time.time() - os.path.getmtime(DOWN) < 600
    except OSError:
        return False


def define_fallback(w):
    """Brief definitions from Datamuse (md=d) when the Free Dictionary API is unreachable."""
    try:
        url = "https://api.datamuse.com/words?sp=" + urllib.parse.quote(w) + "&md=d&max=8"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        arr = json.loads(urllib.request.urlopen(req, timeout=8).read().decode("utf-8"))
    except Exception as e:
        return {"error": "Couldn't reach any dictionary service: %s" % (getattr(e, "reason", None) or e)}
    exact = next((x for x in arr if x.get("word", "").lower() == w and x.get("defs")), None)
    if exact is None:
        sug = [x["word"] for x in arr if x.get("word") and x["word"].lower() != w][:5]
        return {"notfound": True, "word": w, "suggestions": sug}
    groups, order = {}, []
    for d in exact["defs"]:
        pos, _, text = d.partition("\t")
        name = POS.get(pos, "other")
        g = groups.get(name)
        if g is None:
            g = groups[name] = {"pos": name, "defs": [], "synonyms": []}
            order.append(name)
        if len(g["defs"]) < 6 and text:
            g["defs"].append({"d": text, "ex": ""})
    return {"word": exact["word"], "phonetic": "", "meanings": [groups[n] for n in order], "source": "datamuse"}


def define(w):
    w = w.strip().lower()
    if not w:
        return {"error": "Type a word first."}
    data = None
    if not api_down():
        url = "https://api.dictionaryapi.dev/api/v2/entries/en/" + urllib.parse.quote(w)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            data = json.loads(urllib.request.urlopen(req, timeout=6).read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return {"notfound": True, "word": w, "suggestions": suggest(w)}
        except Exception:
            try:
                open(DOWN, "w").close()
            except OSError:
                pass
    if data is None:
        return define_fallback(w)
    if not isinstance(data, list) or not data:
        return {"notfound": True, "word": w, "suggestions": suggest(w)}
    phon, order, groups = "", [], {}
    for ent in data:
        if not phon:
            phon = ent.get("phonetic") or next((p["text"] for p in ent.get("phonetics", []) if p.get("text")), "")
        for m in ent.get("meanings", []):
            pos = m.get("partOfSpeech") or "other"
            g = groups.get(pos)
            if g is None:
                g = groups[pos] = {"pos": pos, "defs": [], "synonyms": []}
                order.append(pos)
            for d in m.get("definitions", []):
                if len(g["defs"]) < 6 and d.get("definition"):
                    g["defs"].append({"d": d["definition"], "ex": d.get("example") or ""})
                for s in d.get("synonyms") or []:
                    if s not in g["synonyms"] and len(g["synonyms"]) < 8:
                        g["synonyms"].append(s)
            for s in m.get("synonyms") or []:
                if s not in g["synonyms"] and len(g["synonyms"]) < 8:
                    g["synonyms"].append(s)
    return {"word": data[0].get("word", w), "phonetic": phon, "meanings": [groups[p] for p in order][:6]}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    if cmd == "build":
        build()
        return
    fn = {"analyze": analyze, "word": word, "search": search, "define": define}.get(cmd)
    sys.stdout.write(json.dumps(fn(arg) if fn else {"error": "bad-command"}, ensure_ascii=False))


main()
