#!/usr/bin/env python3
"""AeroGet backend: a yt-dlp wrapper with a persistent download queue.

  aeroget.py info URL                     analyze a link -> JSON (title, thumbnail, quality presets)
  aeroget.py add URL PRESET [options]     queue a download. PRESET: best | h1080 | h720 | ... | audio
                                          options: --dir D --title T --thumb P --est BYTES --uploader U --duration S
  aeroget.py list                         queue -> JSON
  aeroget.py cancel|retry|remove|open ID
  aeroget.py clear                        drop finished / failed / cancelled jobs
  aeroget.py cfg get | cfg set KEY VALUE  keys: dir, parallel
  aeroget.py pump | run ID                internal

Queue: ~/.cache/aeroget/queue.json    Config: ~/.config/aeroget/config.json"""
import fcntl, hashlib, json, os, re, shutil, signal, subprocess, sys, time, urllib.parse, urllib.request, uuid
from contextlib import contextmanager

HOME = os.path.expanduser("~")
CACHE = HOME + "/.cache/aeroget"
QUEUE, LOCK, THUMBS = CACHE + "/queue.json", CACHE + "/queue.lock", CACHE + "/thumbs"
CFG = HOME + "/.config/aeroget/config.json"
DEVNULL = subprocess.DEVNULL
ACTIVE = ("starting", "downloading")


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.write("\n")


def now():
    return int(time.time() * 1000)


# ---------------- config ----------------
def cfg_load():
    try:
        with open(CFG) as f:
            return {"dir": "", "parallel": 2, **json.load(f)}
    except Exception:
        return {"dir": "", "parallel": 2}


def cfg_save(c):
    os.makedirs(os.path.dirname(CFG), exist_ok=True)
    with open(CFG, "w") as f:
        json.dump(c, f, indent=2)


def default_dir():
    d = cfg_load().get("dir") or ""
    if d:
        return os.path.expanduser(d)
    try:
        d = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=3).stdout.strip()
    except Exception:
        d = ""
    return d if d and d != HOME else HOME + "/Downloads"


# ---------------- queue ----------------
@contextmanager
def queue_lock():
    os.makedirs(CACHE, exist_ok=True)
    with open(LOCK, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            with open(QUEUE) as f:
                q = json.load(f)
        except Exception:
            q = {"jobs": []}
        yield q
        tmp = QUEUE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(q, f, ensure_ascii=False)
        os.replace(tmp, QUEUE)


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def reconcile(q):
    for j in q["jobs"]:
        if j["status"] in ACTIVE and not alive(j.get("pid")):
            j["status"], j["phase"], j["speed"], j["eta"] = "error", "error", 0, None
            j["error"] = j.get("error") or "Interrupted (the download process ended)"
    while len(q["jobs"]) > 100:                      # keep the history bounded
        for i, j in enumerate(q["jobs"]):
            if j["status"] not in ACTIVE + ("queued",):
                del q["jobs"][i]
                break
        else:
            break


def update(jid, **kw):
    with queue_lock() as q:
        for j in q["jobs"]:
            if j["id"] == jid:
                j.update(kw)
                return dict(j)
    return None


def pump():
    with queue_lock() as q:
        reconcile(q)
        par = max(1, int(cfg_load().get("parallel", 2)))
        running = [j for j in q["jobs"] if j["status"] in ACTIVE]
        for j in q["jobs"]:
            if len(running) >= par:
                break
            if j["status"] == "queued":
                p = subprocess.Popen([sys.executable, os.path.abspath(__file__), "run", j["id"]],
                                     stdin=DEVNULL, stdout=DEVNULL, stderr=DEVNULL, start_new_session=True)
                j["pid"], j["status"], j["phase"] = p.pid, "starting", "boarding"
                running.append(j)


# ---------------- info ----------------
def fetch_thumb(url):
    if not url:
        return ""
    os.makedirs(THUMBS, exist_ok=True)
    path = THUMBS + "/" + hashlib.md5(url.encode()).hexdigest() + ".jpg"
    if os.path.exists(path):
        return path
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        data = urllib.request.urlopen(req, timeout=8).read()
    except Exception:
        return ""
    if shutil.which("magick"):
        r = subprocess.run(["magick", "-", "-resize", "640x", "-quality", "85", "jpg:" + path], input=data, capture_output=True)
        if r.returncode == 0 and os.path.exists(path):
            return path
    raw = path[:-4] + (os.path.splitext(urllib.parse.urlparse(url).path)[1] or ".jpg")
    with open(raw, "wb") as f:
        f.write(data)
    return raw


def cmd_info(url):
    try:
        r = subprocess.run(["yt-dlp", "-J", "--no-playlist", "--no-warnings", "--", url],
                           capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        return out({"ok": False, "error": "yt-dlp is not installed"})
    except subprocess.TimeoutExpired:
        return out({"ok": False, "error": "Timed out reading that link"})
    if r.returncode != 0:
        msg = (r.stderr.strip().splitlines() or ["yt-dlp failed"])[-1]
        return out({"ok": False, "error": re.sub(r"^ERROR:\s*(\[[^\]]+\]\s*)?", "", msg)[:220]})
    try:
        info = json.loads(r.stdout)
    except ValueError:
        return out({"ok": False, "error": "Couldn't read that link"})
    if info.get("_type") == "playlist":
        return out({"ok": False, "error": "That's a playlist. Paste a single video link."})

    fmts = info.get("formats") or []
    vids = [f for f in fmts if f.get("vcodec") not in (None, "none") and f.get("height")]
    auds = [f for f in fmts if f.get("acodec") not in (None, "none") and f.get("vcodec") in (None, "none")]

    def size(f):
        return f.get("filesize") or f.get("filesize_approx") or 0

    best_audio = max([size(f) for f in auds] or [0])
    heights = sorted({f["height"] for f in vids}, reverse=True)
    presets = []
    if heights:
        def vsize(h):
            return max([size(f) for f in vids if f["height"] == h] or [0]) + best_audio
        presets.append({"id": "best", "label": "Best", "detail": "%dp" % heights[0], "est": vsize(heights[0])})
        for h in heights[1:6]:
            presets.append({"id": "h%d" % h, "label": "%dp" % h, "detail": "video + audio", "est": vsize(h)})
    presets.append({"id": "audio", "label": "Audio only", "detail": "mp3", "est": best_audio})

    thumb = info.get("thumbnail") or ((info.get("thumbnails") or [{}])[-1].get("url") if info.get("thumbnails") else "")
    out({"ok": True, "url": url, "title": info.get("title") or "Untitled", "uploader": info.get("uploader") or info.get("channel") or "",
         "duration": info.get("duration") or 0, "duration_str": info.get("duration_string") or "", "live": bool(info.get("is_live")),
         "thumb": fetch_thumb(thumb), "presets": presets})


# ---------------- run one job ----------------
def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def preset_args(preset):
    if preset == "audio":
        return ["-f", "bestaudio/best", "-x", "--audio-format", "mp3", "--audio-quality", "0"], 1
    m = re.match(r"^h(\d+)$", preset)
    if m:
        h = m.group(1)
        return ["-f", "bv*[height<=%s]+ba/b[height<=%s]/b" % (h, h), "--merge-output-format", "mp4"], 2
    return ["-f", "bv*+ba/b", "--merge-output-format", "mp4"], 2


def notify(title, body):
    try:
        subprocess.Popen(["notify-send", "-a", "AeroGet", title, body], stdout=DEVNULL, stderr=DEVNULL)
    except OSError:
        pass


def run_job(jid):
    j = update(jid, status="downloading", pid=os.getpid(), phase="in flight", error="", percent=0.0, speed=0, eta=None)
    if not j:
        return 1
    out_dir = os.path.expanduser(j["dir"])
    os.makedirs(out_dir, exist_ok=True)
    fmt_args, streams = preset_args(j["preset"])
    cmd = (["yt-dlp", "--no-playlist", "--newline", "--no-colors", "--embed-metadata",
            "-P", out_dir, "-o", "%(title).180B.%(ext)s",
            "--progress-template",
            "download:AG|%(progress.status)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s"]
           + fmt_args + ["--", j["url"]])
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    except FileNotFoundError:
        update(jid, status="error", phase="error", error="yt-dlp is not installed")
        return 1

    est = float(j.get("est") or 0)
    prev_done, stage, last_write = 0.0, 0, 0.0
    final, err, phase = "", "", "in flight"
    for raw in p.stdout:
        line = raw.rstrip("\n")
        if line.startswith("AG|"):
            f = line.split("|")
            if len(f) < 7:
                continue
            status, done = f[1], num(f[2]) or 0.0
            total = num(f[3]) or num(f[4]) or 0.0
            speed, eta = num(f[5]), num(f[6])
            if status == "finished":
                prev_done += total or done
                stage += 1
                continue
            if est > 0:
                pct = (prev_done + done) / est * 100.0
            else:
                pct = (stage + (done / total if total else 0.0)) / max(1, streams) * 100.0
            pct = max(0.0, min(99.0, pct))
            t = time.time()
            if t - last_write >= 0.4:
                last_write = t
                update(jid, percent=round(pct, 1), speed=speed or 0, eta=eta, phase="in flight")
            continue
        m = re.search(r'Merging formats into "(.+)"', line)
        if m:
            final, phase = m.group(1), "merging"
            update(jid, phase=phase, speed=0, eta=None, percent=99.0)
            continue
        m = re.search(r"\[ExtractAudio\] Destination: (.+)", line)
        if m:
            final, phase = m.group(1).strip(), "converting"
            update(jid, phase=phase, speed=0, eta=None, percent=99.0)
            continue
        m = re.search(r"\[download\] Destination: (.+)", line) or re.search(r"\[download\] (.+) has already been downloaded", line)
        if m:
            final = m.group(1).strip()
            continue
        if line.startswith("ERROR:"):
            err = line.split("ERROR:", 1)[1].strip()[:220]
    rc = p.wait()

    cur = None
    with queue_lock() as q:
        for x in q["jobs"]:
            if x["id"] == jid:
                cur = dict(x)
    if cur and cur["status"] == "cancelled":
        return 0
    if rc == 0:
        size = os.path.getsize(final) if final and os.path.exists(final) else 0
        title = (j.get("title") or "") or (os.path.splitext(os.path.basename(final))[0] if final else j["url"])
        update(jid, status="done", phase="landed", percent=100.0, speed=0, eta=0, file=final, size=size, title=title, finished=now())
        notify("Landed", title)
    else:
        update(jid, status="error", phase="error", error=err or "yt-dlp failed (exit %d)" % rc, speed=0, eta=None)
        notify("Download failed", (j.get("title") or j["url"])[:80])
    pump()
    return 0


# ---------------- commands ----------------
def cmd_add(a):
    if not a:
        return out({"ok": False, "error": "no url"})
    url, preset, opts, i = a[0], "best", {}, 1
    if len(a) > 1 and not a[1].startswith("--"):
        preset, i = a[1], 2
    while i < len(a):
        if a[i].startswith("--") and i + 1 < len(a):
            opts[a[i][2:]] = a[i + 1]
            i += 2
        else:
            i += 1
    job = {"id": uuid.uuid4().hex[:8], "url": url, "preset": preset, "dir": opts.get("dir") or default_dir(),
           "title": opts.get("title", ""), "uploader": opts.get("uploader", ""), "thumb": opts.get("thumb", ""),
           "duration": opts.get("duration", ""), "est": int(float(opts.get("est") or 0)),
           "status": "queued", "phase": "boarding", "percent": 0.0, "speed": 0, "eta": None,
           "error": "", "file": "", "size": 0, "added": now(), "pid": 0}
    with queue_lock() as q:
        dup = next((j for j in q["jobs"] if j["url"] == url and j["preset"] == preset and j["status"] in ACTIVE + ("queued",)), None)
        if dup:
            return out({"ok": False, "error": "Already in the queue", "job": dup})
        q["jobs"].append(job)
    pump()
    out({"ok": True, "job": job})


def cmd_list():
    with queue_lock() as q:
        reconcile(q)
        data = {"jobs": q["jobs"], "dir": default_dir(), "ts": now()}
    out(data)


def cmd_cancel(jid):
    pid = None
    with queue_lock() as q:
        for j in q["jobs"]:
            if j["id"] == jid and j["status"] in ACTIVE + ("queued",):
                pid = j.get("pid") if j["status"] in ACTIVE else None
                j["status"], j["phase"], j["speed"], j["eta"] = "cancelled", "cancelled", 0, None
    if pid:
        try:
            os.killpg(pid, signal.SIGTERM)
        except OSError:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
    pump()


def cmd_retry(jid):
    with queue_lock() as q:
        for j in q["jobs"]:
            if j["id"] == jid and j["status"] in ("error", "cancelled"):
                j.update(status="queued", phase="boarding", percent=0.0, speed=0, eta=None, error="", pid=0)
    pump()


def cmd_remove(jid):
    cmd_cancel(jid)
    with queue_lock() as q:
        q["jobs"] = [j for j in q["jobs"] if j["id"] != jid]


def cmd_clear():
    with queue_lock() as q:
        q["jobs"] = [j for j in q["jobs"] if j["status"] in ACTIVE + ("queued",)]


def cmd_open(jid):
    with queue_lock() as q:
        j = next((x for x in q["jobs"] if x["id"] == jid), None)
    if j:
        target = os.path.dirname(j["file"]) if j.get("file") else os.path.expanduser(j["dir"])
        subprocess.Popen(["xdg-open", target], stdout=DEVNULL, stderr=DEVNULL, start_new_session=True)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    a = sys.argv[1:]
    c = a[0] if a else ""
    try:
        if c == "info" and len(a) > 1:
            cmd_info(a[1])
        elif c == "add":
            cmd_add(a[1:])
        elif c == "list":
            cmd_list()
        elif c in ("cancel", "retry", "remove", "open") and len(a) > 1:
            {"cancel": cmd_cancel, "retry": cmd_retry, "remove": cmd_remove, "open": cmd_open}[c](a[1])
        elif c == "clear":
            cmd_clear()
        elif c == "pump":
            pump()
        elif c == "run" and len(a) > 1:
            return run_job(a[1])
        elif c == "cfg":
            cfg = cfg_load()
            if len(a) >= 4 and a[1] == "set" and a[2] in ("dir", "parallel"):
                cfg[a[2]] = int(a[3]) if a[2] == "parallel" else a[3]
                cfg_save(cfg)
            out({**cfg, "dir_effective": default_dir()})
        else:
            print(__doc__)
            return 1
    except Exception as e:
        out({"ok": False, "error": "%s: %s" % (type(e).__name__, e)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
