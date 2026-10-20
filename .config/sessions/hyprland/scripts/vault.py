#!/usr/bin/env python3
"""vault.py - KeePass vault with Supabase sync. Prints exactly one JSON object on stdout.
Secrets (master password, entry passwords) are only ever read from stdin JSON, never argv."""
import argparse, base64, copy, fcntl, getpass, hashlib, hmac, json, math, os, re, secrets, shutil
import string, struct, subprocess, sys, time
import urllib.error, urllib.parse, urllib.request, uuid as uuidlib
from pathlib import Path

HOME = Path.home()
CONF = HOME / ".config/vault"
DATA = HOME / ".local/share/vault"
BAK = DATA / "backups"
ENV, DB = CONF / "vault.env", DATA / "vault.kdbx"
SESSION, SYNC, ATTEMPTS = DATA / "session.json", DATA / "sync.json", DATA / "attempts.json"
LOCKF, CLIPTOK, CLIPNOW = DATA / ".lock", DATA / "clip.token", DATA / "clip.now"
KEEP_REMOTE, KEEP_LOCAL, CLIP_SECS = 20, 15, 20
KDBX_SIG = bytes.fromhex("03d9a29a67fb4bb5")
MAX_FAILS = 5
_LOCK_FD = None


class Fail(Exception):
    def __init__(self, err, **kw):
        self.err, self.kw = err, kw


class ApiError(Exception):
    def __init__(self, code, msg):
        self.code, self.msg = code, msg


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


# ---------- files ----------
def ensure_dirs():
    for d in (CONF, DATA, BAK):
        d.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass


def fsync_dir(d):
    try:
        fd = os.open(d, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        pass


def write_private(path, data):
    ensure_dirs()
    b = data.encode() if isinstance(data, str) else bytes(data)
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        os.fchmod(f.fileno(), 0o600)
        f.write(b)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    fsync_dir(path.parent)


class Lock:
    """One vault.py mutation at a time: UI clicks and auto-sync can never interleave."""
    def __enter__(self):
        global _LOCK_FD
        ensure_dirs()
        self.fd = os.open(LOCKF, os.O_RDWR | os.O_CREAT, 0o600)
        deadline = time.time() + 25
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.time() > deadline:
                    os.close(self.fd)
                    raise Fail("busy", hint="another vault operation is still running")
                time.sleep(0.05)
        _LOCK_FD = self.fd
        return self

    def __exit__(self, *a):
        global _LOCK_FD
        try:
            fcntl.flock(self.fd, fcntl.LOCK_UN)
            os.close(self.fd)
        except OSError:
            pass
        _LOCK_FD = None


# ---------- config / http ----------
def cfg():
    c = {}
    if ENV.exists():
        for line in ENV.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                c[k.strip()] = v.strip().strip("\"'")
    for k in ("SUPABASE_URL", "SUPABASE_ANON_KEY"):
        if not c.get(k):
            raise Fail("not_configured", hint=f"set {k} in {ENV}")
    c["SUPABASE_URL"] = c["SUPABASE_URL"].rstrip("/")
    u = c["SUPABASE_URL"]
    if not (u.startswith("https://") or u.startswith("http://127.0.0.1") or u.startswith("http://localhost")):
        raise Fail("not_configured", hint="SUPABASE_URL must be https://")
    c.setdefault("VAULT_BUCKET", "vault")
    return c


def http(method, url, headers=None, body=None, raw=False):
    h, data = dict(headers or {}), None
    if body is not None:
        if isinstance(body, (bytes, bytearray)):
            data = bytes(body)
        else:
            data = json.dumps(body).encode()
            h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            b = r.read()
            if raw:
                return b
            return json.loads(b) if b else {}
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode(errors="replace")[:300])
    except urllib.error.URLError as e:
        raise ApiError(0, str(e.reason))
    except (TimeoutError, OSError) as e:
        raise ApiError(0, str(e))
    except ValueError:
        raise ApiError(0, "bad response")


def api_msg(raw):
    try:
        j = json.loads(raw)
        return str(j.get("msg") or j.get("error_description") or j.get("message") or j.get("error") or "")[:160]
    except Exception:
        return ""


# ---------- session ----------
def auth_grant(c, grant, payload):
    try:
        r = http("POST", f"{c['SUPABASE_URL']}/auth/v1/token?grant_type={grant}",
                 {"apikey": c["SUPABASE_ANON_KEY"]}, payload)
    except ApiError as e:
        # only a real rejection is "auth_failed"; network trouble must never log you out
        kind = "auth_failed" if e.code in (400, 401, 403, 422) else "offline"
        raise Fail(kind, code=e.code, message=api_msg(e.msg))
    try:
        s = {"access_token": r["access_token"], "refresh_token": r["refresh_token"],
             "expires_at": int(time.time()) + int(r.get("expires_in", 3600)) - 60,
             "user_id": r["user"]["id"], "email": r["user"].get("email", "")}
    except (KeyError, TypeError):
        raise Fail("auth_failed", message="unexpected auth response")
    write_private(SESSION, json.dumps(s))
    return s


def get_session(c):
    if not SESSION.exists():
        raise Fail("not_logged_in")
    try:
        s = json.loads(SESSION.read_text())
        s["expires_at"], s["refresh_token"], s["access_token"], s["user_id"]
    except Exception:
        SESSION.unlink(missing_ok=True)
        raise Fail("not_logged_in", detail="session file unreadable")
    if time.time() >= s["expires_at"]:
        try:
            s = auth_grant(c, "refresh_token", {"refresh_token": s["refresh_token"]})
        except Fail as f:
            if f.err == "auth_failed":
                SESSION.unlink(missing_ok=True)
                raise Fail("not_logged_in", detail="session expired")
            raise
    return s


def sbh(c, s):
    return {"apikey": c["SUPABASE_ANON_KEY"], "Authorization": "Bearer " + s["access_token"]}


# ---------- remote storage ----------
def remote_list(c, s):
    try:
        r = http("POST", f"{c['SUPABASE_URL']}/storage/v1/object/list/{c['VAULT_BUCKET']}", sbh(c, s),
                 {"prefix": s["user_id"], "limit": 200, "sortBy": {"column": "name", "order": "desc"}})
    except ApiError as e:
        raise Fail("offline" if e.code == 0 else "remote_error", code=e.code, message=api_msg(e.msg))
    if not isinstance(r, list):
        raise Fail("remote_error", message="unexpected listing")
    return sorted((x["name"] for x in r if x.get("name", "").startswith("vault-")
                   and x["name"].endswith(".kdbx")), reverse=True)


def remote_fetch(c, s, name):
    try:
        b = http("GET", f"{c['SUPABASE_URL']}/storage/v1/object/authenticated/"
                        f"{c['VAULT_BUCKET']}/{s['user_id']}/{name}", sbh(c, s), raw=True)
    except ApiError as e:
        raise Fail("offline" if e.code == 0 else "download_failed", code=e.code, message=api_msg(e.msg))
    if not b.startswith(KDBX_SIG):
        raise Fail("bad_remote_file")
    return b


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sync_load():
    try:
        return json.loads(SYNC.read_text())
    except Exception:
        return {}


def sync_store(last_remote):
    write_private(SYNC, json.dumps({"last_remote": last_remote, "sha": sha(DB)}))


# ---------- local backups ----------
def backup_local(tag):
    if not DB.exists():
        return None
    ensure_dirs()
    name = time.strftime("vault-%Y%m%dT%H%M%S", time.gmtime()) + f"-{tag}-{secrets.token_hex(2)}.kdbx"
    p = BAK / name
    shutil.copyfile(DB, p)
    os.chmod(p, 0o600)
    for old in sorted(BAK.glob("vault-*.kdbx"))[:-KEEP_LOCAL]:
        old.unlink(missing_ok=True)
    return name


# ---------- vault ----------
def _pk():
    try:
        from pykeepass import PyKeePass
        from pykeepass.exceptions import CredentialsError
        return PyKeePass, CredentialsError
    except ImportError:
        raise Fail("missing_dep", hint="yay -S python-pykeepass")


def throttle_check():
    try:
        a = json.loads(ATTEMPTS.read_text())
    except Exception:
        return
    wait = a.get("until", 0) - time.time()
    if wait > 0:
        raise Fail("locked_out", retry_in=int(wait) + 1)


def throttle_fail():
    try:
        n = json.loads(ATTEMPTS.read_text()).get("n", 0)
    except Exception:
        n = 0
    n += 1
    until = time.time() + min(900, 30 * 2 ** (n - MAX_FAILS)) if n >= MAX_FAILS else 0
    write_private(ATTEMPTS, json.dumps({"n": n, "until": until}))
    return max(0, MAX_FAILS - n)


def open_file(path, master, count_failure=True):
    PyKeePass, CredentialsError = _pk()
    try:
        return PyKeePass(str(path), password=master)
    except CredentialsError:
        left = throttle_fail() if count_failure else None
        raise Fail("wrong_master", **({"left": left} if left is not None else {}))
    except Exception as e:
        raise Fail("open_failed", detail=type(e).__name__)


def open_db(master):
    if not DB.exists():
        raise Fail("no_vault", hint="run init, or login then sync")
    throttle_check()
    kp = open_file(DB, master)
    ATTEMPTS.unlink(missing_ok=True)
    return kp


def digest(kp):
    h = hashlib.sha256()
    rows = sorted((str(e.uuid), e.title or "", e.username or "", e.password or "", e.url or "",
                   e.notes or "", e.otp or "", "/".join(e.group.path) if e.group else "")
                  for e in kp.entries)
    for r in rows:
        h.update(json.dumps(r).encode())
    return h.hexdigest()


def save_db(kp, master, tag="save"):
    """Write to temp, re-open and compare, keep a rotating backup, then atomically replace."""
    ensure_dirs()
    PyKeePass, _ = _pk()
    tmp = DB.with_name("vault.kdbx.tmp")
    want = digest(kp)
    kp.save(filename=str(tmp))
    os.chmod(tmp, 0o600)
    try:
        ok = digest(PyKeePass(str(tmp), password=master)) == want
    except Exception:
        ok = False
    if not ok:
        tmp.unlink(missing_ok=True)
        raise Fail("save_verify_failed", hint="nothing was changed on disk")
    fd = os.open(tmp, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    backup_local(tag)
    os.replace(tmp, DB)
    fsync_dir(DB.parent)


def gpath(g):
    return list(g.path) if g is not None and g.path else []


def ensure_group(kp, names):
    cur = kp.root_group
    for n in names:
        nxt = next((x for x in cur.subgroups if x.name == n), None)
        cur = nxt or kp.add_group(cur, n)
    return cur


def clean_group(s):
    parts = [p.strip().replace("/", "-") for p in str(s or "").split("/")]
    return [p for p in parts if p]


def in_trash(kp, e):
    rb = kp.recyclebin_group
    if not rb:
        return False
    g = e.group
    while g is not None:
        if g.uuid == rb.uuid:
            return True
        g = g.parentgroup
    return False


def find(kp, uid):
    try:
        e = kp.find_entries(uuid=uuidlib.UUID(str(uid)), first=True)
    except ValueError:
        e = None
    if not e:
        raise Fail("not_found")
    return e


def brief(kp, e):
    return {"uuid": str(e.uuid), "title": e.title or "", "username": e.username or "",
            "url": e.url or "", "group": "/".join(gpath(e.group)),
            "has_notes": bool(e.notes), "has_otp": bool(e.otp),
            "mtime": int(e.mtime.timestamp()) if e.mtime else 0,
            "expired": bool(e.expired), "in_trash": in_trash(kp, e)}


def snapshot(kp):
    rb = kp.recyclebin_group
    items = [brief(kp, e) for e in kp.entries]
    items.sort(key=lambda x: x["title"].lower())
    groups = set()
    for g in kp.groups:
        if g.is_root_group or (rb and any(x.uuid == rb.uuid for x in [g] + _ancestors(g))):
            continue
        p = gpath(g)
        for i in range(1, len(p) + 1):
            groups.add("/".join(p[:i]))
    return {"entries": items, "groups": sorted(groups, key=str.lower),
            "trash": sum(1 for x in items if x["in_trash"])}


def _ancestors(g):
    out_, p = [], g.parentgroup
    while p is not None:
        out_.append(p)
        p = p.parentgroup
    return out_


# ---------- merge (never loses an entry) ----------
def _fields(e):
    return (e.title or "", e.username or "", e.password or "", e.url or "", e.notes or "", e.otp or "",
            tuple(gpath(e.group)), tuple(sorted((e.custom_properties or {}).items())))


def _clone(local, remote, r, conflict_copy=False):
    from pykeepass.entry import Entry
    trashed = in_trash(remote, r)
    dest = local.root_group if trashed else ensure_group(local, gpath(r.group))
    ent = Entry(element=copy.deepcopy(r._element), kp=local)
    if conflict_copy:
        ent.uuid = uuidlib.uuid4()
        ent.title = (ent.title or "") + " (conflict copy)"
        ent.touch(modify=True)
    dest.append(ent)
    if trashed:
        local.trash_entry(ent)
    return ent


def merge_into(local, remote):
    """Union by UUID. Newer modification time wins. Entries that exist on one side only are kept,
    so a merge can resurrect a deleted entry but can never lose a password."""
    lm = {str(e.uuid): e for e in local.entries}
    add, upd, tie = [], [], []
    for r in remote.entries:
        l = lm.get(str(r.uuid))
        if l is None:
            add.append(r)
        elif _fields(l) == _fields(r):
            continue
        elif r.mtime > l.mtime:
            upd.append((l, r))
        elif r.mtime == l.mtime:
            tie.append(r)
    for r in add + [x for _, x in upd] + tie:
        if r.attachments:
            raise Fail("merge_unsupported", hint=f"'{r.title}' has attachments; resolve with --strategy")
    for r in add:
        _clone(local, remote, r)
    for l, r in upd:
        local.delete_entry(l)
        _clone(local, remote, r)
    for r in tie:
        _clone(local, remote, r, conflict_copy=True)
    return {"added": len(add), "updated": len(upd), "conflict_copies": len(tie)}


# ---------- sync ----------
def _push(c, s, names, tag="push"):
    if not DB.exists():
        raise Fail("no_vault")
    name = time.strftime("vault-%Y%m%dT%H%M%SZ.kdbx", time.gmtime())
    if names and name <= names[0]:
        name = time.strftime("vault-%Y%m%dT%H%M%SZ.kdbx", time.gmtime(time.time() + 1))
    base = f"{c['SUPABASE_URL']}/storage/v1/object"
    try:
        http("POST", f"{base}/{c['VAULT_BUCKET']}/{s['user_id']}/{name}",
             {**sbh(c, s), "Content-Type": "application/octet-stream"}, DB.read_bytes())
    except ApiError as e:
        raise Fail("offline" if e.code == 0 else "upload_failed", code=e.code, message=api_msg(e.msg))
    if name not in remote_list(c, s):
        raise Fail("upload_unverified", hint="remote listing does not show the new file")
    sync_store(name)
    old = [f"{s['user_id']}/{n}" for n in names[KEEP_REMOTE - 1:]]
    pruned = 0
    if old:
        try:
            http("DELETE", f"{base}/{c['VAULT_BUCKET']}", sbh(c, s), {"prefixes": old})
            pruned = len(old)
        except ApiError:
            pass  # pruning is housekeeping; the push itself succeeded
    res = {"state": "in_sync", "action": "pushed", "remote": name, "pruned": pruned}
    bdir = c.get("VAULT_BACKUP_DIR")
    if bdir:
        try:
            Path(bdir).mkdir(parents=True, exist_ok=True)
            shutil.copy2(DB, Path(bdir) / "vault.kdbx")
            res["backup"] = "ok"
        except Exception as e:
            res["backup"] = f"failed: {type(e).__name__}"
    return res


def _install_remote(c, s, name, master):
    b = remote_fetch(c, s, name)
    tmp = DATA / "remote.kdbx.tmp"
    write_private(tmp, b)
    try:
        if master:
            try:
                open_file(tmp, master, count_failure=False)
            except Fail as f:
                if f.err == "wrong_master":
                    raise Fail("remote_master_differs",
                               hint="the cloud vault uses a different master password; local copy untouched")
                raise
        backup_local("prepull")
        os.replace(tmp, DB)
        fsync_dir(DB.parent)
    finally:
        tmp.unlink(missing_ok=True)
    sync_store(name)
    return {"state": "in_sync", "action": "pulled", "remote": name}


def sync_now(master, kp=None, strategy="merge"):
    """Returns (kp_or_None, report). kp is None when the local file was replaced and must be re-opened."""
    if not SESSION.exists():
        return kp, {"state": "local_only", "action": "skipped"}
    c = cfg()
    s = get_session(c)
    names = remote_list(c, s)
    head = names[0] if names else None
    st = sync_load()
    last = st.get("last_remote")
    exists = DB.exists()
    changed = exists and sha(DB) != st.get("sha")
    if not exists:
        if not head:
            return kp, {"state": "no_remote", "action": "nothing"}
        return None, _install_remote(c, s, head, master)
    if head is None:
        return kp, _push(c, s, names)
    if head == last:
        if changed:
            return kp, _push(c, s, names)
        return kp, {"state": "in_sync", "action": "none"}
    # the cloud has a version this device has not seen
    if strategy == "remote" or (not changed and strategy != "local"):
        return None, _install_remote(c, s, head, master)
    if strategy == "local":
        rep = _push(c, s, names)
        rep["action"] = "pushed_forced"
        return kp, rep
    if kp is None:
        kp = open_db(master)
    tmp = DATA / "remote.kdbx.tmp"
    write_private(tmp, remote_fetch(c, s, head))
    try:
        try:
            rk = open_file(tmp, master, count_failure=False)
        except Fail as f:
            if f.err == "wrong_master":
                raise Fail("remote_master_differs",
                           hint="the cloud vault uses a different master password; nothing was merged")
            raise
        stats = merge_into(kp, rk)
    finally:
        tmp.unlink(missing_ok=True)
    if any(stats.values()):
        save_db(kp, master, "premerge")
    rep = _push(c, s, names)
    rep.update(action="merged", merge=stats)
    return kp, rep


def auto_sync(kp, master):
    if not SESSION.exists():
        return kp, {"ok": True, "state": "local_only", "action": "skipped"}
    try:
        kp2, rep = sync_now(master, kp, "merge")
        if kp2 is None:
            kp2 = open_db(master)
        return kp2, {"ok": True, **rep}
    except Fail as f:
        return kp, {"ok": False, "error": f.err, **f.kw}
    except ApiError as e:
        return kp, {"ok": False, "error": "offline", "code": e.code}


def sync_status(local_only=False):
    res = {"logged_in": SESSION.exists(), "local_exists": DB.exists(), "state": "local_only"}
    st = sync_load()
    changed = DB.exists() and sha(DB) != st.get("sha")
    if DB.exists():
        res["unsynced_local_changes"] = bool(changed)
    if not SESSION.exists() or local_only:
        return res
    try:
        c = cfg()
        s = get_session(c)
        names = remote_list(c, s)
    except Fail as f:
        res.update(state="offline" if f.err in ("offline", "remote_error") else f.err, remote_error=f.err)
        if f.err == "not_logged_in":
            res["logged_in"] = False
            res["state"] = "local_only"
        return res
    head = names[0] if names else None
    res.update(email=s["email"], remote_latest=head)
    if not DB.exists():
        res["state"] = "no_local"
    elif head is None or head == st.get("last_remote"):
        res["state"] = "unsynced" if changed else "in_sync"
    else:
        res["state"] = "conflict" if changed else "remote_newer"
    res["remote_newer"] = res["state"] in ("conflict", "remote_newer")
    return res


# ---------- clipboard ----------
def clip(value):
    """Copy, then clear after CLIP_SECS, but only if the clipboard still holds this value.
    The secret never goes through env or argv: a forked child keeps it in memory only."""
    if not shutil.which("wl-copy"):
        raise Fail("no_wl_copy")
    warn = None
    r = subprocess.run(["wl-copy", "--sensitive"], input=value.encode(), stderr=subprocess.DEVNULL)
    if r.returncode != 0:
        subprocess.run(["wl-copy"], input=value.encode(), check=True)
        warn = "wl-copy has no --sensitive; cliphist may store this copy"
    CLIPNOW.unlink(missing_ok=True)
    tok = secrets.token_hex(8)
    write_private(CLIPTOK, tok)
    pid = os.fork()
    if pid:
        return warn
    try:  # detached timer child
        os.setsid()
        if _LOCK_FD is not None:
            os.close(_LOCK_FD)
        dn = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(dn, fd)
        end = time.time() + CLIP_SECS
        while time.time() < end:
            time.sleep(0.25)
            try:
                if CLIPTOK.read_text() != tok:
                    os._exit(0)  # superseded by a newer copy
            except OSError:
                os._exit(0)
            if CLIPNOW.exists():
                break
        try:
            if CLIPTOK.read_text() == tok:
                cur = subprocess.run(["wl-paste", "-n"], capture_output=True, timeout=5).stdout
                if cur == value.encode():
                    subprocess.run(["wl-copy", "--clear"], timeout=5)
                CLIPTOK.unlink(missing_ok=True)
                CLIPNOW.unlink(missing_ok=True)
        except Exception:
            pass
    finally:
        os._exit(0)


def clip_clear_now():
    if CLIPTOK.exists():
        write_private(CLIPNOW, "1")
        return True
    return False


# ---------- TOTP ----------
def totp_params(raw):
    s = (raw or "").strip()
    if not s:
        raise Fail("no_otp")
    digits, period, algo, secret = 6, 30, "SHA1", s
    if s.lower().startswith("otpauth://"):
        u = urllib.parse.urlparse(s)
        if u.netloc.lower() != "totp":
            raise Fail("otp_unsupported", hint="only TOTP is supported")
        q = {k.lower(): v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        if q.get("encoder", "").lower() == "steam":
            raise Fail("otp_unsupported", hint="Steam codes are not supported")
        secret = q.get("secret", "")
        digits = int(q.get("digits", 6))
        period = int(q.get("period", 30))
        algo = q.get("algorithm", "SHA1").upper()
    secret = re.sub(r"[\s-]", "", secret).upper()
    algos = {"SHA1": hashlib.sha1, "SHA256": hashlib.sha256, "SHA512": hashlib.sha512}
    if algo not in algos or not (4 <= digits <= 10) or period <= 0 or not secret:
        raise Fail("bad_otp")
    try:
        key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    except Exception:
        raise Fail("bad_otp", hint="secret is not valid base32")
    return key, digits, period, algos[algo]


def totp_at(key, digits, period, algo, t):
    h = hmac.new(key, struct.pack(">Q", int(t // period)), algo).digest()
    o = h[-1] & 0x0F
    n = (struct.unpack(">I", h[o:o + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(n).zfill(digits)


def totp_pack(raw, now=None):
    key, digits, period, algo = totp_params(raw)
    now = time.time() if now is None else now
    start = int(now // period) * period
    return {"digits": digits, "period": period, "start": start,
            "codes": [totp_at(key, digits, period, algo, start + i * period) for i in range(3)]}


# ---------- generator ----------
def gen_password(n, symbols):
    pools = [string.ascii_lowercase, string.ascii_uppercase, string.digits]
    if symbols:
        pools.append("!@#$%^&*()-_=+[]{};:,.?")
    alphabet = "".join(pools)
    while True:
        pw = "".join(secrets.choice(alphabet) for _ in range(n))
        if all(any(ch in p for ch in pw) for p in pools):
            return pw, round(n * math.log2(len(alphabet)), 1)


def gen_passphrase(k):
    wl = Path("/usr/share/dict/words")
    if not wl.exists():
        raise Fail("no_wordlist", hint="sudo pacman -S words")
    words = sorted({w for w in wl.read_text().split() if w.isalpha() and w.islower() and 4 <= len(w) <= 8})
    if len(words) < 5000:
        raise Fail("wordlist_too_small")
    return "-".join(secrets.choice(words) for _ in range(k)), round(k * math.log2(len(words)), 1)


# ---------- input ----------
def read_in():
    if sys.stdin.isatty():
        return {}
    raw = sys.stdin.read().strip()
    try:
        d = json.loads(raw) if raw else {}
    except ValueError:
        raise Fail("bad_input")
    if not isinstance(d, dict):
        raise Fail("bad_input")
    return d


def master_of(d, key="master", prompt="master password: "):
    m = d.get(key)
    if m is None and sys.stdin.isatty():
        m = getpass.getpass(prompt)
    if not isinstance(m, str) or not m:
        raise Fail("master_required")
    return m


def finish(kp, master, extra=None):
    kp, rep = auto_sync(kp, master)
    return {"sync": rep, **snapshot(kp), **(extra or {})}


def check_dup(kp, title, group, skip=None):
    hit = kp.find_entries(title=title, group=group, recursive=False, first=True)
    if hit and (skip is None or str(hit.uuid) != str(skip.uuid)):
        raise Fail("duplicate_title", hint="an entry with this title already exists in that group")


# ---------- commands ----------
def run(a):
    cmd = a.cmd
    if cmd == "generate":
        if a.words:
            pw, bits = gen_passphrase(max(3, min(a.words, 12)))
        else:
            pw, bits = gen_password(max(8, min(a.length, 128)), not a.no_symbols)
        return {"password": pw, "entropy_bits": bits}
    if cmd == "clipclear":
        return {"cleared": clip_clear_now()}

    with Lock():
        if cmd == "login":
            d = read_in()
            if not d.get("email") or not d.get("password"):
                raise Fail("bad_input", hint='stdin {"email":..,"password":..}')
            s = auth_grant(cfg(), "password", {"email": d["email"], "password": d["password"]})
            return {"email": s["email"]}

        if cmd == "logout":
            try:
                c, s = cfg(), json.loads(SESSION.read_text())
                http("POST", f"{c['SUPABASE_URL']}/auth/v1/logout", sbh(c, s), {})
            except Exception:
                pass  # best-effort server-side revoke; the local session is removed regardless
            SESSION.unlink(missing_ok=True)
            return {}

        if cmd == "status":
            return sync_status(a.local)

        if cmd == "backups":
            ensure_dirs()
            return {"backups": [{"name": p.name, "bytes": p.stat().st_size, "mtime": int(p.stat().st_mtime)}
                                for p in sorted(BAK.glob("vault-*.kdbx"), reverse=True)]}

        if cmd == "rollback":
            if not re.fullmatch(r"vault-[0-9A-Za-z_.\-]+\.kdbx", a.name or "") or not (BAK / a.name).exists():
                raise Fail("not_found", hint="see: vault.py backups")
            b = (BAK / a.name).read_bytes()
            if not b.startswith(KDBX_SIG):
                raise Fail("bad_backup")
            backup_local("prerollback")
            write_private(DB, b)
            return {"restored": a.name, "note": "local copy now differs from the cloud; sync to resolve"}

        if cmd == "pull":
            c = cfg()
            s = get_session(c)
            names = remote_list(c, s)
            if not names:
                return {"pulled": None, "remote": "empty"}
            if DB.exists() and not a.force and sha(DB) != sync_load().get("sha"):
                raise Fail("local_unsynced", hint="push first, or pull --force (a backup is kept)")
            return _install_remote(c, s, names[0], None)

        if cmd == "push":
            c = cfg()
            s = get_session(c)
            names = remote_list(c, s)
            if names and names[0] != sync_load().get("last_remote") and not a.force:
                raise Fail("remote_newer", remote=names[0], hint="run sync, or push --force")
            return _push(c, s, names)

        d = read_in()
        m = master_of(d)

        if cmd == "init":
            if DB.exists():
                raise Fail("vault_exists")
            if len(m) < 12:
                raise Fail("master_too_short", hint="use at least 12 characters")
            if SESSION.exists():
                c = cfg()
                if remote_list(c, get_session(c)):
                    raise Fail("remote_exists", hint="a vault already exists in the cloud; sync to restore it")
            try:
                from pykeepass import create_database
            except ImportError:
                raise Fail("missing_dep", hint="yay -S python-pykeepass")
            ensure_dirs()
            create_database(str(DB), password=m)
            os.chmod(DB, 0o600)
            kp = open_file(DB, m)
            return {"created": True, **finish(kp, m)}

        if cmd == "sync":
            kp = open_db(m) if DB.exists() else None
            kp2, rep = sync_now(m, kp, a.strategy)
            if kp2 is None:
                kp2 = open_db(m)
            return {"sync": {"ok": True, **rep}, **snapshot(kp2)}

        kp = open_db(m)

        if cmd in ("open", "unlock"):
            return snapshot(kp)

        if cmd == "list":
            q = (a.q or "").lower()
            snap = snapshot(kp)
            snap["entries"] = [x for x in snap["entries"] if not q or q in x["title"].lower()
                               or q in x["username"].lower() or q in x["url"].lower()]
            return snap

        if cmd == "get":
            e = find(kp, a.uuid)
            return {**brief(kp, e)}

        if cmd == "secret":
            e = find(kp, a.uuid)
            return {"uuid": str(e.uuid), "password": e.password or "", "notes": e.notes or "",
                    "fields": dict(e.custom_properties or {})}

        if cmd == "totp":
            return totp_pack(find(kp, a.uuid).otp)

        if cmd == "copy":
            e = find(kp, a.uuid)
            if a.field == "otp":
                p = totp_pack(e.otp)
                val = p["codes"][0]
            else:
                val = (e.username if a.field == "username" else e.password) or ""
            r = {"copied": a.field, "clears_in": CLIP_SECS}
            w = clip(val)
            if w:
                r["warning"] = w
            return r

        if cmd == "add":
            if not str(d.get("title", "")).strip():
                raise Fail("bad_input", hint="title required")
            names = clean_group(d.get("group")) or ["General"]
            g = ensure_group(kp, names)
            check_dup(kp, d["title"], g)
            if d.get("otp"):
                totp_params(d["otp"])
            e = kp.add_entry(g, d["title"], d.get("username", ""), d.get("password", ""),
                             url=d.get("url") or None, notes=d.get("notes") or None,
                             otp=d.get("otp") or None)
            save_db(kp, m, "add")
            return finish(kp, m, {"uuid": str(e.uuid)})

        if cmd == "edit":
            e = find(kp, a.uuid)
            e.save_history()
            if "otp" in d and d["otp"]:
                totp_params(d["otp"])
            g = e.group
            if "group" in d:
                g = ensure_group(kp, clean_group(d["group"]) or ["General"])
            new_title = d.get("title", e.title)
            if not str(new_title or "").strip():
                raise Fail("bad_input", hint="title required")
            check_dup(kp, new_title, g, skip=e)
            for k in ("title", "username", "password", "url", "notes", "otp"):
                if k in d:
                    setattr(e, k, d[k] if d[k] is not None else "")
            if g.uuid != e.group.uuid:
                kp.move_entry(e, g)
            e.touch(modify=True)  # pykeepass setters do not bump mtime; merge depends on it
            save_db(kp, m, "edit")
            return finish(kp, m, {"uuid": str(e.uuid)})

        if cmd == "trash":
            e = find(kp, a.uuid)
            if in_trash(kp, e):
                raise Fail("already_trashed")
            kp.trash_entry(e)
            e.touch(modify=True)
            save_db(kp, m, "trash")
            return finish(kp, m)

        if cmd == "restore":
            e = find(kp, a.uuid)
            if not in_trash(kp, e):
                raise Fail("not_in_trash")
            g = ensure_group(kp, clean_group(d.get("group")) or ["General"])
            check_dup(kp, e.title, g, skip=e)
            kp.move_entry(e, g)
            e.touch(modify=True)
            save_db(kp, m, "restore")
            return finish(kp, m, {"uuid": str(e.uuid)})

        if cmd == "purge":
            e = find(kp, a.uuid)
            if not in_trash(kp, e):
                raise Fail("not_in_trash", hint="move it to the trash first")
            kp.delete_entry(e)
            save_db(kp, m, "purge")
            return finish(kp, m)

        if cmd == "passwd":
            n = master_of(d, "new_master", "new master password: ")
            if len(n) < 12:
                raise Fail("master_too_short", hint="use at least 12 characters")
            if n == m:
                raise Fail("master_unchanged")
            kp.password = n
            save_db(kp, n, "passwd")
            return finish(kp, n)


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status").add_argument("--local", action="store_true")
    for n in ("login", "logout", "init", "open", "unlock", "add", "passwd", "backups", "clipclear"):
        sub.add_parser(n)
    for n in ("pull", "push"):
        sub.add_parser(n).add_argument("--force", action="store_true")
    sub.add_parser("sync").add_argument("--strategy", choices=["merge", "local", "remote"], default="merge")
    sub.add_parser("list").add_argument("--q")
    for n in ("get", "secret", "totp", "edit", "trash", "restore", "purge"):
        sub.add_parser(n).add_argument("uuid")
    c = sub.add_parser("copy")
    c.add_argument("uuid")
    c.add_argument("--field", choices=["password", "username", "otp"], default="password")
    sub.add_parser("rollback").add_argument("name")
    ge = sub.add_parser("generate")
    ge.add_argument("--length", type=int, default=20)
    ge.add_argument("--words", type=int, default=0)
    ge.add_argument("--no-symbols", action="store_true")
    a = p.parse_args()
    try:
        out({"ok": True, **(run(a) or {})})
    except Fail as f:
        out({"ok": False, "error": f.err, **f.kw})
        sys.exit(1)
    except ApiError as e:
        out({"ok": False, "error": "offline" if e.code == 0 else "network", "code": e.code})
        sys.exit(1)
    except Exception as e:
        out({"ok": False, "error": "internal", "detail": f"{type(e).__name__}: {str(e)[:160]}"})
        sys.exit(1)


if __name__ == "__main__":
    main()
