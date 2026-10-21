#!/usr/bin/env python3
"""syshub - backend for the System Hub popup (doctor + fixes; updates/install come later)."""
import json, os, sys, time, shutil, subprocess, glob, re
from concurrent.futures import ThreadPoolExecutor

CACHE = os.path.expanduser("~/.cache/syshub")
os.makedirs(CACHE, exist_ok=True)
DOCTOR = f"{CACHE}/doctor.json"
FIXST = f"{CACHE}/fix.json"
FIXLOG = f"{CACHE}/fix.log"


def run(cmd, timeout=15):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except FileNotFoundError:
        return 127, "", "not found"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def chk(cid, title, status, detail, fix=None):
    return {"id": cid, "title": title, "status": status, "detail": detail, "fix": fix}


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


# ---------------------------------------------------------------- checks
def c_units():
    _, a, _ = run(["systemctl", "--failed", "--no-legend", "--plain"])
    _, b, _ = run(["systemctl", "--user", "--failed", "--no-legend", "--plain"])
    names = [l.split()[0] for l in (a + "\n" + b).splitlines() if l.strip()]
    if not names:
        return chk("units", "Systemd units", "ok", "No failed units")
    st = "crit" if len(names) > 3 else "warn"
    return chk("units", "Systemd units", st,
               f"{len(names)} failed: " + ", ".join(names[:6]), "Reset failed state")


def c_mirrors():
    p = "/etc/pacman.d/mirrorlist"
    try:
        age = (time.time() - os.path.getmtime(p)) / 86400
    except OSError:
        return chk("mirrors", "Mirrorlist", "info", "mirrorlist not found")
    st = "ok" if age < 30 else "warn" if age < 90 else "crit"
    detail = f"Mirrorlist is {int(age)} days old"
    fix = None
    if st != "ok":
        if shutil.which("reflector"):
            fix = "Refresh mirrors"
        else:
            detail += " (install reflector to refresh)"
    return chk("mirrors", "Mirrorlist", st, detail, fix)


def c_keyring():
    rc, out, _ = run(["pacman", "-Q", "archlinux-keyring"])
    m = re.search(r"(\d{8})", out) if rc == 0 else None
    if not m:
        return chk("keyring", "Package keyring", "info", "archlinux-keyring not found")
    age = (time.time() - time.mktime(time.strptime(m.group(1), "%Y%m%d"))) / 86400
    st = "ok" if age < 120 else "warn" if age < 240 else "crit"
    d = f"archlinux-keyring is {int(age)} days old"
    if st != "ok":
        d += " - update it before a big upgrade"
    return chk("keyring", "Package keyring", st, d)


def c_kernel():
    rel = os.uname().release
    if os.path.isdir(f"/usr/lib/modules/{rel}"):
        return chk("kernel", "Kernel", "ok", f"Running {rel}")
    return chk("kernel", "Kernel", "warn", f"Running {rel}, which is no longer installed - reboot")


def c_disk():
    parts, worst = [], "ok"
    for mp in ("/", "/boot", "/home"):
        if mp != "/" and not os.path.ismount(mp):
            continue
        u = shutil.disk_usage(mp)
        pct = round(u.used * 100 / u.total)
        parts.append(f"{mp} {pct}%")
        if pct >= 95:
            worst = "crit"
        elif pct >= 85 and worst != "crit":
            worst = "warn"
    return chk("disk", "Disk space", worst, " · ".join(parts))


def c_smart():
    if not shutil.which("smartctl"):
        return chk("smart", "Disk health (SMART)", "info", "smartmontools not installed")
    _, out, _ = run(["lsblk", "-dno", "NAME,TYPE"])
    disks = [l.split()[0] for l in out.splitlines()
             if l.split()[1:] == ["disk"] and not l.startswith(("zram", "loop", "sr"))]
    good, bad, unk = 0, [], 0
    for d in disks:
        _, o, _ = run(["smartctl", "-H", f"/dev/{d}"])
        if "PASSED" in o or "SMART Health Status: OK" in o:
            good += 1
        elif "FAILED" in o:
            bad.append(d)
        else:
            unk += 1
    if bad:
        return chk("smart", "Disk health (SMART)", "crit", "FAILING: " + ", ".join(bad))
    if good:
        return chk("smart", "Disk health (SMART)", "ok", f"{good} disk(s) healthy")
    return chk("smart", "Disk health (SMART)", "info", "Needs root to read (sudo smartctl -H /dev/DISK)")


def c_orphans():
    rc, out, _ = run(["pacman", "-Qtdq"])
    pk = out.split() if rc == 0 else []
    if not pk:
        return chk("orphans", "Orphan packages", "ok", "None")
    return chk("orphans", "Orphan packages", "warn",
               f"{len(pk)}: " + ", ".join(pk[:5]) + (" ..." if len(pk) > 5 else ""), "Remove orphans")


def c_cache():
    total = 0
    for f in glob.glob("/var/cache/pacman/pkg/*"):
        try:
            total += os.path.getsize(f)
        except OSError:
            pass
    gb = total / 1e9
    st = "ok" if gb < 5 else "warn" if gb < 20 else "crit"
    fix = "Clean cache" if st != "ok" and shutil.which("paccache") else None
    return chk("cache", "Package cache", st, f"{gb:.1f} GB", fix)


def c_pacnew():
    _, out, _ = run(["find", "/etc", "-xdev", "(", "-name", "*.pacnew", "-o", "-name", "*.pacsave", ")"], timeout=20)
    fl = [l for l in out.splitlines() if l.strip()]
    if not fl:
        return chk("pacnew", "Config leftovers", "ok", "No .pacnew / .pacsave files")
    return chk("pacnew", "Config leftovers", "warn",
               f"{len(fl)} file(s) - merge with pacdiff: " + ", ".join(os.path.basename(x) for x in fl[:4]))


def c_journal():
    rc, out, _ = run(["journalctl", "-p", "3", "-b", "--no-pager", "-q"], timeout=20)
    if rc != 0:
        return chk("journal", "Journal errors", "info", "Cannot read journal (add user to systemd-journal)")
    n = len([l for l in out.splitlines() if l.strip()])
    st = "ok" if n <= 10 else "warn" if n <= 100 else "crit"
    return chk("journal", "Journal errors", st, f"{n} error line(s) this boot")


def c_time():
    _, out, _ = run(["timedatectl", "show", "-p", "NTPSynchronized", "--value"])
    if out == "yes":
        return chk("time", "Time sync", "ok", "Clock synchronized")
    return chk("time", "Time sync", "warn", "Clock not synchronized", "Enable NTP")


def c_lock():
    if os.path.exists("/var/lib/pacman/db.lck"):
        rc, _, _ = run(["pgrep", "-x", "pacman"])
        if rc != 0:
            return chk("lock", "Pacman lock", "crit", "Stale db.lck - nothing is running pacman", "Remove lock")
        return chk("lock", "Pacman lock", "info", "pacman is running right now")
    return chk("lock", "Pacman lock", "ok", "No lock")


def c_updates():
    if not shutil.which("checkupdates"):
        return chk("updates", "Pending updates", "info", "Install pacman-contrib for checkupdates")
    rc, out, _ = run(["checkupdates"], timeout=90)
    repo = len(out.splitlines()) if rc == 0 else 0
    aur = 0
    if shutil.which("yay"):
        rc2, o2, _ = run(["yay", "-Qua"], timeout=60)
        aur = len(o2.splitlines()) if rc2 == 0 else 0
    n = repo + aur
    st = "ok" if n == 0 else "info" if n <= 50 else "warn"
    return chk("updates", "Pending updates", st, "Up to date" if n == 0 else f"{repo} repo · {aur} AUR")


CHECKS = [
    ("units", "Systemd units", c_units), ("mirrors", "Mirrorlist", c_mirrors),
    ("keyring", "Package keyring", c_keyring), ("kernel", "Kernel", c_kernel),
    ("disk", "Disk space", c_disk), ("smart", "Disk health (SMART)", c_smart),
    ("orphans", "Orphan packages", c_orphans), ("cache", "Package cache", c_cache),
    ("pacnew", "Config leftovers", c_pacnew), ("journal", "Journal errors", c_journal),
    ("time", "Time sync", c_time), ("lock", "Pacman lock", c_lock),
    ("updates", "Pending updates", c_updates),
]


def safe(item):
    cid, title, fn = item
    try:
        return fn()
    except Exception as e:
        return chk(cid, title, "info", f"Check failed: {e}")


def meta():
    up = float(open("/proc/uptime").read().split()[0])
    mi = {}
    for l in open("/proc/meminfo"):
        k, v = l.split(":")
        mi[k] = int(v.split()[0])
    disks = []
    for mp in ("/", "/boot", "/home"):
        if mp != "/" and not os.path.ismount(mp):
            continue
        u = shutil.disk_usage(mp)
        disks.append({"mount": mp, "total": u.total, "used": u.used, "pct": round(u.used * 100 / u.total)})
    return {
        "host": os.uname().nodename, "kernel": os.uname().release, "uptime": int(up),
        "mem_total": mi.get("MemTotal", 0) * 1024,
        "mem_used": (mi.get("MemTotal", 0) - mi.get("MemAvailable", 0)) * 1024,
        "swap_total": mi.get("SwapTotal", 0) * 1024,
        "swap_used": (mi.get("SwapTotal", 0) - mi.get("SwapFree", 0)) * 1024,
        "load": os.getloadavg(), "disks": disks,
    }


def doctor():
    with ThreadPoolExecutor(8) as ex:
        res = list(ex.map(safe, CHECKS))
    counts = {"ok": 0, "warn": 0, "crit": 0, "info": 0}
    score = 100
    for r in res:
        counts[r["status"]] += 1
        score -= 12 if r["status"] == "crit" else 5 if r["status"] == "warn" else 0
    out = {"ts": int(time.time()), "score": max(0, score), "counts": counts, "meta": meta(), "checks": res}
    write_json(DOCTOR, out)
    return out


# ---------------------------------------------------------------- fixes
def f_orphans():
    rc, out, _ = run(["pacman", "-Qtdq"])
    pk = out.split() if rc == 0 else []
    return [["pkexec", "pacman", "-Rns", "--noconfirm"] + pk] if pk else []


FIXES = {
    "units": lambda: [["systemctl", "--user", "reset-failed"], ["pkexec", "systemctl", "reset-failed"]],
    "mirrors": lambda: [["pkexec", "reflector", "--latest", "20", "--protocol", "https",
                         "--sort", "rate", "--save", "/etc/pacman.d/mirrorlist"]],
    "orphans": f_orphans,
    "cache": lambda: [["pkexec", "paccache", "-rk2"]],
    "time": lambda: [["pkexec", "timedatectl", "set-ntp", "true"]],
    "lock": lambda: [["pkexec", "rm", "-f", "/var/lib/pacman/db.lck"]],
}


def do_fix(fid):
    cmds = FIXES[fid]()
    open(FIXLOG, "w").close()
    write_json(FIXST, {"id": fid, "status": "running", "ts": time.time()})
    ok = True
    with open(FIXLOG, "a") as lg:
        for c in cmds:
            lg.write("$ " + " ".join(c) + "\n")
            lg.flush()
            try:
                p = subprocess.run(c, stdout=lg, stderr=subprocess.STDOUT)
                if p.returncode != 0:
                    ok = False
                    lg.write(f"[exit {p.returncode}]\n")
            except Exception as e:
                ok = False
                lg.write(f"[error: {e}]\n")
    write_json(FIXST, {"id": fid, "status": "done" if ok else "error", "ts": time.time()})


def main():
    a = sys.argv[1:]
    if not a:
        print("usage: syshub.py doctor|last|fix ID")
        return 1
    cmd = a[0]
    if cmd == "doctor":
        print(json.dumps(doctor()))
    elif cmd == "last":
        print(open(DOCTOR).read() if os.path.exists(DOCTOR) else "{}")
    elif cmd == "fix" and len(a) > 1:
        if a[1] not in FIXES:
            print("unknown fix", a[1])
            return 1
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "_fix", a[1]],
                         start_new_session=True, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("started")
    elif cmd == "_fix" and len(a) > 1 and a[1] in FIXES:
        do_fix(a[1])
    else:
        print("bad command")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
