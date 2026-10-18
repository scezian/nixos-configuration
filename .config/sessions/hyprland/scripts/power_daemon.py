#!/usr/bin/env python3
"""Power & display daemon: night light (hyprsunset), idle (hypridle), battery alerts.

  power_daemon.py             run the daemon (single instance)
  power_daemon.py set K V     change a setting (V is JSON); the daemon applies it
  power_daemon.py get         print settings
  power_daemon.py status      print live status
  power_daemon.py alert-test  send both battery notifications

Settings: ~/.config/hyprpanel/config.json     Status: ~/.cache/hyprpanel_status.json"""
import fcntl, glob, json, os, signal, subprocess, sys, time
from datetime import datetime

HOME = os.path.expanduser("~")
CFG = HOME + "/.config/hyprpanel/config.json"
STATUS = HOME + "/.cache/hyprpanel_status.json"
RUNLOCK = HOME + "/.cache/hyprpanel_daemon.lock"
CFGLOCK = HOME + "/.cache/hyprpanel_cfg.lock"
IDLE_CONF = HOME + "/.config/hypr/hypridle.conf"
LOCK_SH = HOME + "/.config/hypr/scripts/lock.sh"
BEGIN, END = "# >>> hyprpanel managed >>>", "# <<< hyprpanel managed <<<"

DEFAULTS = {
    "suspend_cmd": "systemctl suspend",
    "sunset_enabled": False, "sunset_temp": 4000,
    "sunset_schedule": False, "sunset_on_hour": 19, "sunset_off_hour": 7,
    "lock_auto": False, "lock_timeout": 30,
    "suspend_auto": False, "suspend_timeout": 60,
    "battery_alerts": True, "battery_warn": 20, "battery_crit": 10,
}
LIMITS = {"sunset_temp": (1000, 10000), "sunset_on_hour": (0, 23), "sunset_off_hour": (0, 23),
          "lock_timeout": (1, 240), "suspend_timeout": (1, 480), "battery_warn": (1, 99), "battery_crit": (1, 99)}
DEVNULL = subprocess.DEVNULL


def load():
    try:
        with open(CFG) as f:
            return {**DEFAULTS, **json.load(f)}
    except Exception:
        return dict(DEFAULTS)


def save(cfg):
    os.makedirs(os.path.dirname(CFG), exist_ok=True)
    tmp = CFG + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, CFG)


def set_key(key, val):
    os.makedirs(os.path.dirname(CFGLOCK), exist_ok=True)
    with open(CFGLOCK, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        cfg = load()
        cfg[key] = val
        save(cfg)


def coerce(key, raw):
    default = DEFAULTS[key]
    try:
        val = json.loads(raw)
    except Exception:
        val = raw
    if isinstance(default, bool):
        if isinstance(val, str):
            val = val.strip().lower() in ("1", "true", "yes", "on")
        return bool(val)
    if isinstance(default, int):
        lo, hi = LIMITS.get(key, (-10**9, 10**9))
        return max(lo, min(hi, int(float(val))))
    return str(val)


def battery():
    bats = sorted(glob.glob("/sys/class/power_supply/BAT*"))
    if not bats:
        return None, None
    try:
        with open(bats[0] + "/capacity") as f:
            pct = int(f.read().strip())
        with open(bats[0] + "/status") as f:
            st = f.read().strip()
        return pct, st in ("Charging", "Full", "Not charging")
    except Exception:
        return None, None


def notify(urgency, title, body):
    try:
        subprocess.Popen(["notify-send", "-u", urgency, "-a", "HyprPanel", title, body], stdout=DEVNULL, stderr=DEVNULL)
    except OSError:
        pass


def should_sun_on(cfg):
    h, on, off = datetime.now().hour, cfg["sunset_on_hour"], cfg["sunset_off_hour"]
    return (h >= on or h < off) if on > off else (on <= h < off)


def idle_block(cfg):
    guard = "pgrep -f 'quickshell.*Lock.qml' >/dev/null || bash " + LOCK_SH
    L = [BEGIN, "general {", "    lock_cmd = " + guard, "    before_sleep_cmd = loginctl lock-session", "}", ""]
    if cfg["lock_auto"]:
        L += ["listener {", "    timeout = %d" % (cfg["lock_timeout"] * 60), "    on-timeout = loginctl lock-session", "}", ""]
    if cfg["suspend_auto"]:
        L += ["listener {", "    timeout = %d" % (cfg["suspend_timeout"] * 60), "    on-timeout = " + cfg["suspend_cmd"], "}", ""]
    L.append(END)
    return "\n".join(L) + "\n"


def write_idle_conf(cfg):
    block = idle_block(cfg)
    try:
        with open(IDLE_CONF) as f:
            old = f.read()
    except OSError:
        old = ""
    if BEGIN in old and END in old:
        a, b = old.index(BEGIN), old.index(END) + len(END)
        new = old[:a] + block.rstrip("\n") + old[b:]
    else:
        if old.strip():
            bak = IDLE_CONF + ".bak-hyprpanel"
            if not os.path.exists(bak):
                with open(bak, "w") as f:
                    f.write(old)
        new = block
    if new != old:
        os.makedirs(os.path.dirname(IDLE_CONF), exist_ok=True)
        with open(IDLE_CONF, "w") as f:
            f.write(new)


class Managed:
    def __init__(self, argv):
        self.argv, self.p, self.started = argv, None, 0.0

    def alive(self):
        return self.p is not None and self.p.poll() is None

    def start(self, argv=None):
        self.stop()
        if argv:
            self.argv = argv
        self.p = subprocess.Popen(self.argv, stdout=DEVNULL, stderr=DEVNULL, start_new_session=True)
        self.started = time.time()

    def stop(self):
        if self.alive():
            self.p.terminate()
            try:
                self.p.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.p.kill()
        self.p = None


def run_daemon(verbose):
    os.makedirs(os.path.dirname(RUNLOCK), exist_ok=True)
    lockf = open(RUNLOCK, "w")
    try:
        fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("power_daemon is already running")
        return 0

    def log(*a):
        if verbose:
            print("[power]", *a, flush=True)

    sun, idle = Managed(["hyprsunset"]), Managed(["hypridle"])
    for name in ("hyprsunset", "hypridle"):          # take ownership: stray copies would fight us
        subprocess.run(["pkill", "-x", name], capture_output=True)
    time.sleep(0.3)

    st = {"stop": False, "sun": None, "idle": None, "sched": None, "warned": set(), "mtime": -1.0, "pending": 0.0}

    def on_term(*_):
        st["stop"] = True
    signal.signal(signal.SIGTERM, on_term)
    signal.signal(signal.SIGINT, on_term)

    def write_status(cfg, running=True):
        pct, ch = battery()
        data = {"running": running, "pid": os.getpid(), "ts": int(time.time() * 1000),
                "battery": {"present": pct is not None, "percent": pct, "charging": ch},
                "sunset": {"enabled": cfg["sunset_enabled"], "active": sun.alive()},
                "idle": {"active": idle.alive()}}
        try:
            tmp = STATUS + ".tmp"
            with open(tmp, "w") as f:
                json.dump(data, f)
            os.replace(tmp, STATUS)
        except OSError:
            pass

    def apply(cfg):
        sk = (cfg["sunset_enabled"], cfg["sunset_temp"])
        if sk != st["sun"]:
            st["sun"] = sk
            if cfg["sunset_enabled"]:
                try:
                    sun.start(["hyprsunset", "-t", str(cfg["sunset_temp"])])
                    log("night light on at", cfg["sunset_temp"], "K")
                except OSError as e:
                    log("hyprsunset failed:", e)
            else:
                sun.stop()
                subprocess.run(["pkill", "-x", "hyprsunset"], capture_output=True)
                log("night light off")
        ik = (cfg["lock_auto"], cfg["lock_timeout"], cfg["suspend_auto"], cfg["suspend_timeout"], cfg["suspend_cmd"])
        if ik != st["idle"]:
            st["idle"] = ik
            write_idle_conf(cfg)
            try:
                idle.start()
                log("hypridle restarted")
            except OSError as e:
                log("hypridle failed:", e)
        write_status(cfg)

    def slow(cfg):
        now = time.time()
        if cfg["sunset_schedule"]:                   # flip only when an on/off hour is crossed, so manual changes stick
            want = should_sun_on(cfg)
            if st["sched"] is None or want != st["sched"]:
                st["sched"] = want
                if want != cfg["sunset_enabled"]:
                    set_key("sunset_enabled", want)
                    log("schedule ->", "on" if want else "off")
        else:
            st["sched"] = None
        if cfg["sunset_enabled"] and not sun.alive() and now - sun.started > 15:
            try:
                sun.start(["hyprsunset", "-t", str(cfg["sunset_temp"])])
            except OSError:
                pass
        if not idle.alive() and now - idle.started > 15:
            try:
                idle.start()
            except OSError:
                pass
        pct, ch = battery()
        if cfg["battery_alerts"] and pct is not None:
            if ch:
                st["warned"].clear()
            elif pct <= cfg["battery_crit"] and "crit" not in st["warned"]:
                st["warned"] |= {"crit", "warn"}
                notify("critical", "\U0001F534 Battery Critical", "Battery at %d%%. Plug in now." % pct)
            elif pct <= cfg["battery_warn"] and "warn" not in st["warned"]:
                st["warned"].add("warn")
                notify("normal", "\U0001F7E1 Battery Low", "Battery at %d%%. Consider charging soon." % pct)
        write_status(cfg)

    cfg = load()
    apply(cfg)
    slow(cfg)
    next_slow = time.time() + 10
    log("running")
    while not st["stop"]:
        try:
            m = os.stat(CFG).st_mtime
        except OSError:
            m = 0.0
        now = time.time()
        if m != st["mtime"]:
            st["mtime"] = m
            st["pending"] = now
        if st["pending"] and now - st["pending"] >= 0.35:   # debounce slider drags
            st["pending"] = 0.0
            cfg = load()
            apply(cfg)
            slow(cfg)
        if now >= next_slow:
            next_slow = now + 10
            slow(cfg)
        time.sleep(0.25)
    sun.stop()
    idle.stop()
    write_status(cfg, running=False)
    return 0


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "run"
    if cmd == "run":
        return run_daemon(sys.stdout.isatty())
    if cmd == "set" and len(a) == 3:
        if a[1] not in DEFAULTS:
            print("unknown key:", a[1])
            return 2
        set_key(a[1], coerce(a[1], a[2]))
        return 0
    if cmd == "get":
        print(json.dumps(load(), indent=2))
        return 0
    if cmd == "status":
        try:
            with open(STATUS) as f:
                print(f.read())
        except OSError:
            print('{"running": false}')
        return 0
    if cmd == "alert-test":
        notify("normal", "\U0001F7E1 Battery Low", "Battery at 20%. Consider charging soon. (test)")
        notify("critical", "\U0001F534 Battery Critical", "Battery at 10%. Plug in now. (test)")
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
