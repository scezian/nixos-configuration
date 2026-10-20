import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    property var notifModel: null
    property real layoutWidth: 0
    property real layoutHeight: 0

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color red: _theme.red
    readonly property string fMono: "JetBrains Mono"
    readonly property string fDisp: "Outfit"

    readonly property string home: Quickshell.env("HOME")
    readonly property string vaultPy: home + "/.config/hypr/scripts/vault.py"
    readonly property string qsManager: home + "/.config/hypr/scripts/qs_manager.sh"

    // ---- tunables ----
    readonly property int idleMs: 300000      // auto-lock after this much inactivity
    readonly property int graceSecs: 30       // lock this long after the popup is closed (0 = immediately)
    readonly property int revealSecs: 20      // revealed secrets hide themselves after this
    readonly property int clipSecs: 20        // must match CLIP_SECS in vault.py

    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    // ---------------- state ----------------
    property bool unlocked: false
    property string phase: "boot"            // boot | locked | setup
    property string setupMode: "create"      // create | restore
    property string master: ""
    property int epoch: 0                    // bumped on every lock/unlock; stale async replies are dropped
    property bool unlockBusy: false
    property string errorText: ""
    property int lockoutLeft: 0

    property var entries: []
    property var groups: []
    property int trashCount: 0
    property var navItems: []
    property string navKey: "all"
    property var filtered: []
    property string query: ""
    property string selUuid: ""
    readonly property var selEntry: findEntry(selUuid, entries)

    property string mode: "view"             // view | form
    property var secretData: null
    property int revealLeft: 0
    property string editUuid: ""
    property bool formDirty: false
    property bool formBusy: false
    property string busyText: ""             // non-empty while a vault operation runs; drives the progress pill
    readonly property bool working: busyText !== ""
    property bool discardArmed: false
    property bool removeOtp: false
    property string formError: ""
    property bool confirmDel: false
    property bool confirmPurge: false

    property int copyLeft: 0
    property string copyWhat: ""
    property var totpData: null
    property string totpFor: ""
    property string totpCode: ""
    property string totpErr: ""
    property bool totpBusy: false
    property real totpFrac: 1
    property int totpLeft: 0

    property int genLen: 20
    property int genWords: 5
    property bool genPassphrase: false
    property bool genSymbols: true
    property string genEntropy: ""

    property bool loggedIn: false
    property string email: ""
    property string syncState: "local_only"  // local_only in_sync unsynced remote_newer conflict offline failed no_local
    property string syncError: ""
    property bool syncBusy: false
    property string pendingStrategy: ""
    property bool accountOpen: false
    property string accountMsg: ""
    property bool accountBusy: false

    property string toastText: ""
    property string toastKind: "info"

    property real doorP: 0                   // 0 = doors shut, 1 = open
    property real lockEnter: 0
    property real shackle: 0
    property real dialRot: 0
    property real dialSpeed: 6
    property real paneP: 1
    property real idleFrac: 1
    property double deadline: 0
    property double lastTouch: 0
    readonly property bool live: root.visible
    readonly property int pwScore: strengthOf(fPass.text)

    onNavKeyChanged: applyFilter()
    onModeChanged: paneAnim.restart()
    onPhaseChanged: focusTimer.restart()
    onUnlockedChanged: if (!unlocked) lockEnterAnim.restart()
    onVisibleChanged: {
        if (!visible) {
            if (unlocked) { if (graceSecs <= 0) lock("closed"); else graceTimer.restart(); }
        } else {
            graceTimer.stop();
            focusTimer.restart();
        }
    }
    Component.onCompleted: { lockEnterAnim.start(); boot(); }

    // ---------------- backend ----------------
    Component {
        id: procComp
        Process {
            id: pr
            property var cb: null
            stdout: StdioCollector {
                onStreamFinished: {
                    var r;
                    try { r = JSON.parse(text); } catch (e) { r = { ok: false, error: "bad_output" }; }
                    root.busy = Math.max(0, root.busy - 1);
                    if (pr.cb) pr.cb(r);
                    pr.destroy(200);
                }
            }
        }
    }
    property int busy: 0

    function call(args, payload, cb) {
        busy = busy + 1;
        var p = procComp.createObject(root, {
            command: ["bash", "-c", 'printf "%s" "$VIN" | exec python3 "$0" "$@"', root.vaultPy].concat(args),
            environment: { VIN: JSON.stringify(payload || {}) },
            cb: cb
        });
        p.running = true;
    }
    // same as call(), but the reply is discarded if the vault was locked/unlocked in the meantime
    function callS(args, payload, cb) {
        var ep = epoch;
        call(args, payload, function (r) { if (ep === epoch) cb(r); });
    }

    function errText(r) {
        var h = r.hint || r.message || r.detail || "";
        switch (r.error) {
            case "wrong_master": return r.left !== undefined ? "Wrong master password (" + r.left + " tries before a lockout)" : "Wrong master password";
            case "locked_out": return "Too many attempts. Try again in " + r.retry_in + "s";
            case "no_vault": return "No vault on this device yet";
            case "missing_dep": return "python-pykeepass is not installed (yay -S python-pykeepass)";
            case "duplicate_title": return "An entry with that title already exists in this group";
            case "not_found": return "Entry not found";
            case "not_logged_in": return "Not signed in to the cloud";
            case "auth_failed": return "Sign-in failed" + (h ? ": " + h : "");
            case "offline": return "Cloud unreachable. Working offline";
            case "remote_error": case "download_failed": case "upload_failed": return "Cloud error" + (h ? ": " + h : "");
            case "upload_unverified": return "Upload could not be verified. Try syncing again";
            case "remote_master_differs": return "The cloud vault uses a different master password";
            case "merge_unsupported": return "Merge blocked: " + h;
            case "bad_remote_file": return "Cloud file is not a valid vault";
            case "master_too_short": return "Master password needs at least 12 characters";
            case "master_unchanged": return "New password is the same as the old one";
            case "remote_exists": return "A vault already exists in the cloud. Use Restore instead";
            case "vault_exists": return "A vault already exists on this device";
            case "not_configured": return "Cloud not configured: " + h;
            case "no_wl_copy": return "wl-clipboard is not installed";
            case "no_otp": return "This entry has no 2FA secret";
            case "bad_otp": case "otp_unsupported": return "2FA secret not accepted" + (h ? ": " + h : "");
            case "save_verify_failed": return "Save could not be verified. Nothing was changed";
            case "busy": return "Another vault operation is running. Try again";
            case "not_in_trash": return "Move it to the trash first";
            case "bad_output": return "Backend returned something unreadable";
            case "internal": return "Internal error: " + (r.detail || "");
            default: return r.error ? String(r.error) + (h ? ": " + h : "") : "Something went wrong";
        }
    }

    function toast(t, kind) { toastText = t; toastKind = kind || "info"; toastTimer.restart(); }

    function touch() {
        var n = Date.now();
        if (n - lastTouch < 300) return;
        lastTouch = n;
        deadline = n + idleMs;
    }

    function findEntry(uid, list) {
        if (!uid) return null;
        for (var i = 0; i < list.length; i++) if (list[i].uuid === uid) return list[i];
        return null;
    }

    function avColor(t) {
        var c = [mauve, pink, blue, green, peach], h = 0, str = t || "?";
        for (var i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) | 0;
        return c[Math.abs(h) % c.length];
    }

    function strengthOf(pw) {
        if (!pw || pw.length === 0) return 0;
        var cs = 0, seen = {}, uniq = 0;
        if (/[a-z]/.test(pw)) cs += 26;
        if (/[A-Z]/.test(pw)) cs += 26;
        if (/[0-9]/.test(pw)) cs += 10;
        if (/[^a-zA-Z0-9]/.test(pw)) cs += 32;
        for (var i = 0; i < pw.length; i++) if (!seen[pw[i]]) { seen[pw[i]] = 1; uniq++; }
        var eff = Math.min(pw.length, uniq * 2);
        var bits = eff * Math.log(Math.max(cs, 2)) / Math.LN2;
        if (/password|passw0rd|qwerty|letmein|123456|abcdef|iloveyou/i.test(pw)) bits = Math.min(bits, 27);
        if (bits < 28) return 1;
        if (bits < 45) return 2;
        if (bits < 70) return 3;
        return 4;
    }

    function ago(ts) {
        if (!ts) return "never";
        var d = Math.floor(Date.now() / 1000 - ts);
        if (d < 60) return "just now";
        if (d < 3600) return Math.floor(d / 60) + " min ago";
        if (d < 86400) return Math.floor(d / 3600) + " h ago";
        if (d < 86400 * 30) return Math.floor(d / 86400) + " d ago";
        return Qt.formatDate(new Date(ts * 1000), "d MMM yyyy");
    }

    function hostOf(u) { return (u || "").replace(/^[a-z]+:\/\//i, "").split("/")[0]; }

    function openUrl(u) {
        if (/^https?:\/\//i.test(u || "")) Quickshell.execDetached(["xdg-open", u]);
        else toast("Only http(s) links can be opened", "warn");
    }

    function fmtCode(c) {
        if (!c) return "";
        var h = Math.ceil(c.length / 2);
        return c.substring(0, h) + " " + c.substring(h);
    }

    // ---------------- boot / lock / unlock ----------------
    function boot() {
        call(["status", "--local"], {}, function (r) {
            if (!r.ok) { errorText = errText(r); phase = "locked"; return; }
            loggedIn = !!r.logged_in;
            phase = r.local_exists ? "locked" : "setup";
        });
    }

    function enter(pw, snap) {
        epoch = epoch + 1;
        master = pw;
        lockedField.text = ""; cMaster.text = ""; cConfirm.text = ""; rPass.text = ""; rMaster.text = "";
        errorText = ""; lockoutLeft = 0;
        query = ""; searchField.text = ""; navKey = "all";
        applySnapshot(snap);
        unlocked = true;
        deadline = Date.now() + idleMs;
        idleFrac = 1;
        unlockAnim.restart();
        refreshStatus(true);
    }

    function unlock(pw) {
        if (!pw || unlockBusy || lockoutLeft > 0) return;
        unlockBusy = true; errorText = "";
        dialSpeed = 90;
        call(["open"], { master: pw }, function (r) {
            unlockBusy = false;
            if (!r.ok) { dialSpeed = 6; lockFail(r); return; }
            enter(pw, r);
        });
    }

    function lockFail(r) {
        lockedField.text = "";
        if (r.error === "locked_out") { lockoutLeft = r.retry_in || 30; errorText = ""; }
        else errorText = errText(r);
        shake.restart();
    }

    function lock(why) {
        if (!unlocked) return;
        var hadClip = copyLeft > 0;
        epoch = epoch + 1;
        graceTimer.stop();
        master = ""; entries = []; groups = []; filtered = []; navItems = []; trashCount = 0;
        secretData = null; totpData = null; totpCode = ""; totpBusy = false; revealTimer.stop();
        selUuid = ""; mode = "view"; query = ""; searchField.text = ""; navKey = "all";
        wipeForm(); accountOpen = false; accountMsg = ""; accountBusy = false;
        confirmDel = false; confirmPurge = false; pendingStrategy = "";
        copyLeft = 0; syncBusy = false; formBusy = false; unlockBusy = false; busyText = "";
        shackle = 0; dialSpeed = 6;
        unlocked = false;
        phase = "locked";
        errorText = why === "idle" ? "Locked after inactivity" : "";
        animateDoors(0);
        if (hadClip) Quickshell.execDetached(["python3", root.vaultPy, "clipclear"]);
    }

    function animateDoors(to) {
        doorAnim.stop();
        doorAnim.from = doorP;
        doorAnim.to = to;
        doorAnim.duration = to > doorP ? 950 : 520;
        doorAnim.start();
    }

    function closePopup() {
        Quickshell.execDetached(["bash", root.qsManager, "close"]);
        if (unlocked) { if (graceSecs <= 0) lock("closed"); else graceTimer.restart(); }
    }

    // ---------------- data ----------------
    function applySnapshot(r) {
        if (!r || !r.entries) return;
        entries = r.entries;
        groups = r.groups || [];
        trashCount = r.trash || 0;
        rebuildNav();
        applyFilter();
        if (selUuid && !findEntry(selUuid, entries)) clearSelection();
    }

    function rebuildNav() {
        var live = entries.filter(function (e) { return !e.in_trash; });
        var items = [{ key: "all", label: "All items", count: live.length, depth: 0, icon: "grid" }];
        for (var i = 0; i < groups.length; i++) {
            var g = groups[i], parts = g.split("/");
            var c = live.filter(function (e) { return e.group === g || e.group.indexOf(g + "/") === 0; }).length;
            items.push({ key: "g:" + g, label: parts[parts.length - 1], count: c, depth: parts.length - 1, icon: "folder" });
        }
        var rootCount = live.filter(function (e) { return e.group === ""; }).length;
        if (rootCount > 0) items.push({ key: "root", label: "Ungrouped", count: rootCount, depth: 0, icon: "folder" });
        items.push({ key: "trash", label: "Trash", count: trashCount, depth: 0, icon: "trash" });
        navItems = items;
        var found = false;
        for (var j = 0; j < items.length; j++) if (items[j].key === navKey) found = true;
        if (!found) navKey = "all";
    }

    function applyFilter() {
        var q = query.toLowerCase().trim(), k = navKey;
        filtered = entries.filter(function (e) {
            if (k === "trash") { if (!e.in_trash) return false; }
            else {
                if (e.in_trash) return false;
                if (k === "root") { if (e.group !== "") return false; }
                else if (k.indexOf("g:") === 0) {
                    var g = k.substring(2);
                    if (!(e.group === g || e.group.indexOf(g + "/") === 0)) return false;
                }
            }
            if (!q) return true;
            return e.title.toLowerCase().indexOf(q) >= 0 || e.username.toLowerCase().indexOf(q) >= 0
                || e.url.toLowerCase().indexOf(q) >= 0 || e.group.toLowerCase().indexOf(q) >= 0;
        });
    }

    function navTitle() {
        for (var i = 0; i < navItems.length; i++) if (navItems[i].key === navKey) return navItems[i].label;
        return "All items";
    }

    function select(uuid) {
        touch();
        if (uuid === selUuid && mode === "view") return;
        selUuid = uuid; secretData = null; revealTimer.stop();
        confirmDel = false; confirmPurge = false; mode = "view";
        totpData = null; totpCode = ""; totpErr = "";
        paneAnim.restart();
        var e = findEntry(uuid, entries);
        if (e && e.has_otp && !e.in_trash) fetchTotp();
    }

    function clearSelection() {
        selUuid = ""; secretData = null; totpData = null; totpCode = ""; mode = "view"; revealTimer.stop();
    }

    function moveSel(d) {
        if (filtered.length === 0) return;
        var idx = -1;
        for (var i = 0; i < filtered.length; i++) if (filtered[i].uuid === selUuid) idx = i;
        var n = Math.max(0, Math.min(filtered.length - 1, idx < 0 ? (d > 0 ? 0 : filtered.length - 1) : idx + d));
        select(filtered[n].uuid);
        list.positionViewAtIndex(n, ListView.Contain);
    }

    function fetchSecret(cb, label) {
        var id = selUuid;
        if (!id || working) return;
        busyText = label || "Decrypting...";
        callS(["secret", id], { master: master }, function (r) {
            busyText = "";
            if (!r.ok) { toast(errText(r), "err"); return; }
            if (id !== selUuid) return;
            secretData = r; revealLeft = revealSecs; revealTimer.restart();
            if (cb) cb(r);
        });
    }

    function reveal() {
        touch();
        if (secretData) { hideSecret(); return; }
        fetchSecret(null);
    }
    function hideSecret() { secretData = null; revealTimer.stop(); }

    function copyField(field) {
        touch();
        if (working) return;
        busyText = "Copying...";
        callS(["copy", selUuid, "--field", field], { master: master }, function (r) {
            busyText = "";
            if (!r.ok) { toast(errText(r), "err"); return; }
            copyWhat = field; copyLeft = r.clears_in || clipSecs;
            if (r.warning) toast(r.warning, "warn");
        });
    }

    function fetchTotp() {
        var id = selUuid, e = findEntry(id, entries);
        if (totpBusy || !e || !e.has_otp) return;
        totpBusy = true;
        callS(["totp", id], { master: master }, function (r) {
            totpBusy = false;
            if (id !== selUuid) return;
            if (!r.ok) { totpData = null; totpCode = ""; totpErr = errText(r); return; }
            totpErr = ""; totpData = r; totpFor = id; tickTotp();
        });
    }

    function tickTotp() {
        if (!totpData || totpFor !== selUuid) return;
        var now = Date.now() / 1000;
        var idx = Math.floor((now - totpData.start) / totpData.period);
        if (idx < 0 || idx >= totpData.codes.length) { totpCode = ""; fetchTotp(); return; }
        totpCode = totpData.codes[idx];
        var into = (now - totpData.start) - idx * totpData.period;
        totpLeft = Math.ceil(totpData.period - into);
        totpFrac = 1 - into / totpData.period;
        if (idx >= totpData.codes.length - 1) fetchTotp();
    }

    // ---------------- sync / account ----------------
    function syncLabel(st) {
        switch (st) {
            case "in_sync": return "synced";
            case "unsynced": return "not uploaded";
            case "remote_newer": return "cloud has newer";
            case "conflict": return "needs merge";
            case "offline": return "offline";
            case "failed": return "sync failed";
            case "no_local": return "not downloaded";
            default: return "local only";
        }
    }
    function syncColor(st) {
        if (st === "in_sync") return green;
        if (st === "unsynced" || st === "remote_newer" || st === "conflict") return peach;
        if (st === "failed") return red;
        return subtext0;
    }

    function refreshStatus(thenSync) {
        callS(["status"], {}, function (r) {
            if (!r.ok) return;
            loggedIn = !!r.logged_in; email = r.email || email;
            syncState = r.state || "local_only";
            if (thenSync && loggedIn && (syncState === "unsynced" || syncState === "remote_newer" || syncState === "conflict")) syncNow(true, "merge");
        });
    }

    function applyReport(rep, quiet) {
        if (!rep) return;
        if (rep.ok === false) {
            syncError = rep.error || "";
            syncState = rep.error === "offline" ? "offline" : "failed";
            if (!quiet || rep.error !== "offline") toast(errText(rep), rep.error === "offline" ? "warn" : "err");
            return;
        }
        syncError = "";
        syncState = rep.state || "in_sync";
        if (rep.action === "merged" && rep.merge) {
            var n = (rep.merge.added || 0) + (rep.merge.updated || 0) + (rep.merge.conflict_copies || 0);
            if (n > 0) toast("Merged " + n + (n === 1 ? " change" : " changes") + " from the cloud", "ok");
            else if (!quiet) toast("Already up to date", "info");
        } else if (rep.action === "pulled") toast("Updated from the cloud", "ok");
        else if (rep.action === "pushed" && !quiet) toast("Synced", "ok");
        else if (rep.action === "pushed_forced") toast("Cloud now matches this device", "ok");
        else if (rep.action === "none" && !quiet) toast("Already in sync", "info");
    }

    function syncNow(quiet, strategy) {
        if (syncBusy) return;
        touch();
        syncBusy = true; pendingStrategy = "";
        if (!quiet && !working) busyText = strategy === "local" ? "Overwriting the cloud copy..." : (strategy === "remote" ? "Replacing this device with the cloud copy..." : "Syncing with the cloud...");
        callS(["sync", "--strategy", strategy || "merge"], { master: master }, function (r) {
            syncBusy = false;
            if (!quiet) busyText = "";
            if (!r.ok) {
                syncError = r.error || "";
                syncState = r.error === "offline" ? "offline" : "failed";
                if (!quiet || r.error !== "offline") toast(errText(r), r.error === "offline" ? "warn" : "err");
                return;
            }
            applySnapshot(r);
            applyReport(r.sync, quiet);
        });
    }

    function strategyClick(which) {
        if (pendingStrategy !== which) { pendingStrategy = which; strategyTimer.restart(); return; }
        syncNow(false, which);
    }

    function doLogin() {
        if (accountBusy) return;
        var em = acctEmail.text.trim(), pw = acctPass.text;
        if (!em || !pw) { accountMsg = "Enter email and password"; return; }
        accountBusy = true; accountMsg = ""; busyText = "Signing in...";
        callS(["login"], { email: em, password: pw }, function (r) {
            accountBusy = false; busyText = "";
            if (!r.ok) { accountMsg = errText(r); return; }
            acctPass.text = ""; loggedIn = true; email = r.email || em;
            toast("Signed in as " + email, "ok");
            syncNow(false, "merge");
        });
    }

    function doLogout() {
        if (accountBusy) return;
        accountBusy = true; busyText = "Signing out...";
        callS(["logout"], {}, function (r) {
            accountBusy = false; busyText = ""; loggedIn = false; email = ""; syncState = "local_only"; syncError = "";
            toast("Signed out. Vault stays on this device", "info");
        });
    }

    function doChangeMaster() {
        if (accountBusy) return;
        var cur = acctOld.text, nw = acctNew.text, cf = acctNew2.text;
        if (!cur || !nw) { accountMsg = "Fill in all three fields"; return; }
        if (nw.length < 12) { accountMsg = errText({ error: "master_too_short" }); return; }
        if (nw !== cf) { accountMsg = "New passwords do not match"; return; }
        accountBusy = true; accountMsg = ""; busyText = "Changing master password...";
        callS(["passwd"], { master: cur, new_master: nw }, function (r) {
            accountBusy = false; busyText = "";
            if (!r.ok) { accountMsg = errText(r); return; }
            master = nw; acctOld.text = ""; acctNew.text = ""; acctNew2.text = "";
            applySnapshot(r); applyReport(r.sync, true);
            accountMsg = ""; toast("Master password changed", "ok");
        });
    }

    // ---------------- entry editing ----------------
    function wipeForm() {
        fTitle.text = ""; fUser.text = ""; fPass.text = ""; fUrl.text = ""; fGroup.text = ""; fOtp.text = ""; fNotes.text = "";
        fPass.reveal = false; removeOtp = false; formError = ""; genEntropy = ""; formDirty = false; discardArmed = false; editUuid = "";
    }

    function beginAdd() {
        touch(); wipeForm();
        fGroup.text = navKey.indexOf("g:") === 0 ? navKey.substring(2) : "General";
        mode = "form"; formDirty = false;
        fTitle.input.forceActiveFocus();
    }

    function beginEdit() {
        touch();
        var e = selEntry;
        if (!e) return;
        fetchSecret(function (r) {
            wipeForm();
            editUuid = e.uuid;
            fTitle.text = e.title; fUser.text = e.username; fPass.text = r.password || "";
            fUrl.text = e.url; fGroup.text = e.group; fNotes.text = r.notes || "";
            hideSecret();
            mode = "form"; formDirty = false;
            fTitle.input.forceActiveFocus();
        }, "Opening entry...");
    }

    function cancelForm() {
        if (formDirty && !discardArmed) { discardArmed = true; discardTimer.restart(); toast("Unsaved changes. Press again to discard", "warn"); return; }
        wipeForm(); mode = "view";
    }

    function save() {
        touch();
        if (formBusy || working) return;
        if (!fTitle.text.trim()) { formError = "Title is required"; return; }
        var payload = { master: master, title: fTitle.text.trim(), username: fUser.text, password: fPass.text,
                        url: fUrl.text.trim(), notes: fNotes.text, group: fGroup.text.trim() || "General" };
        if (fOtp.text.trim() !== "") payload.otp = fOtp.text.trim();
        else if (removeOtp) payload.otp = "";
        var wasEdit = editUuid !== "", grp = payload.group;
        var moving = wasEdit && selEntry !== null && selEntry.group !== grp;
        formBusy = true; formError = "";
        busyText = moving ? "Moving to " + grp + "..." : (wasEdit ? "Saving changes..." : "Adding entry...");
        callS(wasEdit ? ["edit", editUuid] : ["add"], payload, function (r) {
            formBusy = false; busyText = "";
            if (!r.ok) { formError = errText(r); return; }
            applySnapshot(r); applyReport(r.sync, true);
            var id = r.uuid;
            wipeForm(); mode = "view";
            if (findEntry(id, entries)) { selUuid = ""; select(id); }
            toast(moving ? "Moved to " + grp : (wasEdit ? "Saved" : "Entry added"), "ok");
        });
    }

    function trashSelected() {
        touch();
        if (!selEntry || working) return;
        if (!confirmDel) { confirmDel = true; confirmTimer.restart(); return; }
        confirmDel = false; busyText = "Moving to trash...";
        callS(["trash", selUuid], { master: master }, function (r) {
            busyText = "";
            if (!r.ok) { toast(errText(r), "err"); return; }
            clearSelection(); applySnapshot(r); applyReport(r.sync, true);
            toast("Moved to trash", "info");
        });
    }

    function restoreSelected() {
        touch();
        if (working) return;
        busyText = "Restoring entry...";
        callS(["restore", selUuid], { master: master, group: "General" }, function (r) {
            busyText = "";
            if (!r.ok) { toast(errText(r), "err"); return; }
            clearSelection(); applySnapshot(r); applyReport(r.sync, true);
            toast("Restored to General", "ok");
        });
    }

    function purgeSelected() {
        touch();
        if (working) return;
        if (!confirmPurge) { confirmPurge = true; confirmTimer.restart(); return; }
        confirmPurge = false; busyText = "Deleting forever...";
        callS(["purge", selUuid], { master: master }, function (r) {
            busyText = "";
            if (!r.ok) { toast(errText(r), "err"); return; }
            clearSelection(); applySnapshot(r); applyReport(r.sync, true);
            toast("Deleted forever", "info");
        });
    }

    function generate() {
        touch();
        var args = ["generate"];
        if (genPassphrase) args = args.concat(["--words", String(genWords)]);
        else { args = args.concat(["--length", String(genLen)]); if (!genSymbols) args.push("--no-symbols"); }
        callS(args, {}, function (r) {
            if (!r.ok) { formError = errText(r); return; }
            fPass.text = r.password; fPass.reveal = true; genEntropy = r.entropy_bits + " bits";
        });
    }

    // ---------------- setup (first run) ----------------
    function createVault() {
        if (unlockBusy) return;
        var m = cMaster.text;
        if (m.length < 12) { errorText = errText({ error: "master_too_short" }); shake.restart(); return; }
        if (m !== cConfirm.text) { errorText = "The two passwords do not match"; shake.restart(); return; }
        unlockBusy = true; errorText = ""; dialSpeed = 90;
        call(["init"], { master: m }, function (r) {
            unlockBusy = false;
            if (!r.ok) { dialSpeed = 6; errorText = errText(r); shake.restart(); return; }
            enter(m, r);
            toast("Vault created. There is no way to recover a forgotten master password", "warn");
        });
    }

    function restoreVault() {
        if (unlockBusy) return;
        var m = rMaster.text;
        if (!m) { errorText = "Enter the master password of the cloud vault"; shake.restart(); return; }
        var finish = function () {
            call(["sync"], { master: m }, function (r) {
                unlockBusy = false;
                if (!r.ok) { dialSpeed = 6; errorText = errText(r); shake.restart(); return; }
                if (!r.entries) { dialSpeed = 6; errorText = "No vault found in the cloud"; shake.restart(); return; }
                enter(m, r);
            });
        };
        unlockBusy = true; errorText = ""; dialSpeed = 90;
        if (loggedIn) { finish(); return; }
        if (!rEmail.text.trim() || !rPass.text) { unlockBusy = false; dialSpeed = 6; errorText = "Enter your cloud email and password"; shake.restart(); return; }
        call(["login"], { email: rEmail.text.trim(), password: rPass.text }, function (r) {
            if (!r.ok) { unlockBusy = false; dialSpeed = 6; errorText = errText(r); shake.restart(); return; }
            loggedIn = true; email = r.email || rEmail.text.trim();
            finish();
        });
    }

    // ---------------- timers & animations ----------------
    Timer { id: ticker; interval: 500; repeat: true; running: root.unlocked
        onTriggered: {
            var left = root.deadline - Date.now();
            root.idleFrac = Math.max(0, Math.min(1, left / root.idleMs));
            if (left <= 0) root.lock("idle");
        }
    }
    Timer { id: graceTimer; interval: Math.max(1, root.graceSecs) * 1000; onTriggered: root.lock("closed") }
    Timer { id: toastTimer; interval: 3200; onTriggered: root.toastText = "" }
    Timer { id: confirmTimer; interval: 3000; onTriggered: { root.confirmDel = false; root.confirmPurge = false; } }
    Timer { id: discardTimer; interval: 3500; onTriggered: root.discardArmed = false }
    Timer { id: strategyTimer; interval: 4000; onTriggered: root.pendingStrategy = "" }
    Timer { id: focusTimer; interval: 80
        onTriggered: {
            if (root.unlocked) root.forceActiveFocus();
            else if (root.phase === "locked") lockedField.input.forceActiveFocus();
            else if (root.phase === "setup") (root.setupMode === "create" ? cMaster : (root.loggedIn ? rMaster : rEmail)).input.forceActiveFocus();
        }
    }
    Timer { interval: 1000; repeat: true; running: root.copyLeft > 0; onTriggered: root.copyLeft = root.copyLeft - 1 }
    Timer { interval: 1000; repeat: true; running: root.lockoutLeft > 0
        onTriggered: { root.lockoutLeft = root.lockoutLeft - 1; if (root.lockoutLeft <= 0) root.errorText = ""; }
    }
    Timer { id: revealTimer; interval: 1000; repeat: true
        onTriggered: { root.revealLeft = root.revealLeft - 1; if (root.revealLeft <= 0) root.hideSecret(); }
    }
    Timer { interval: 250; repeat: true
        running: root.unlocked && !!root.selEntry && root.selEntry.has_otp && root.mode === "view" && !root.selEntry.in_trash
        onTriggered: root.tickTotp()
    }
    Timer { interval: 33; repeat: true; running: root.live && (!root.unlocked || root.doorP < 0.999)
        onTriggered: root.dialRot = (root.dialRot + root.dialSpeed * 0.033) % 360
    }

    Behavior on dialSpeed { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
    NumberAnimation { id: lockEnterAnim; target: root; property: "lockEnter"; from: 0; to: 1; duration: 1000; easing.type: Easing.OutCubic }
    NumberAnimation { id: paneAnim; target: root; property: "paneP"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
    NumberAnimation { id: doorAnim; target: root; property: "doorP"; easing.type: Easing.InOutCubic }

    SequentialAnimation {
        id: unlockAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "shackle"; to: 1; duration: 320; easing.type: Easing.OutBack }
            SequentialAnimation {
                ScriptAction { script: { burst.opacity = 0.8; burst.scale = 1; root.dialSpeed = 260; } }
                ParallelAnimation {
                    NumberAnimation { target: burst; property: "scale"; to: 3.4; duration: 520; easing.type: Easing.OutCubic }
                    NumberAnimation { target: burst; property: "opacity"; to: 0; duration: 520 }
                }
            }
        }
        PauseAnimation { duration: 60 }
        ScriptAction { script: { root.animateDoors(1); root.dialSpeed = 6; root.shackle = 0; root.lastTouch = 0; root.touch(); } }
    }

    Keys.onEscapePressed: {
        if (!root.unlocked) { root.closePopup(); return; }
        if (root.accountOpen) root.accountOpen = false;
        else if (root.mode === "form") root.cancelForm();
        else if (root.query.length > 0) { searchField.text = ""; }
        else root.closePopup();
    }

    Shortcut { sequence: "Ctrl+F"; enabled: root.unlocked && root.mode === "view"; onActivated: searchField.input.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+N"; enabled: root.unlocked && !root.accountOpen; onActivated: root.beginAdd() }
    Shortcut { sequence: "Ctrl+L"; enabled: root.unlocked; onActivated: root.lock("manual") }
    Shortcut { sequence: "Ctrl+P"; enabled: root.unlocked && root.mode === "view" && !!root.selEntry && !root.accountOpen; onActivated: root.copyField("password") }
    Shortcut { sequence: "Ctrl+U"; enabled: root.unlocked && root.mode === "view" && !!root.selEntry && !root.accountOpen; onActivated: root.copyField("username") }
    Shortcut { sequence: "Ctrl+T"; enabled: root.unlocked && root.mode === "view" && !!root.selEntry && root.selEntry.has_otp; onActivated: root.copyField("otp") }
    Shortcut { sequence: "Ctrl+S"; enabled: root.unlocked && root.mode === "form"; onActivated: root.save() }

    // only real pointer movement counts as activity (Qt re-sends hover events while things animate under a resting cursor)
    HoverHandler {
        property real lx: -100
        property real ly: -100
        onPointChanged: {
            var p = point.scenePosition;
            if (Math.abs(p.x - lx) + Math.abs(p.y - ly) >= 4) { lx = p.x; ly = p.y; root.touch(); }
        }
    }

    // ---------------- reusable pieces ----------------
    component Icon: Canvas {
        id: ic
        property string name: "lock"
        property color col: root.text
        property real sz: root.s(18)
        width: sz; height: sz
        onColChanged: requestPaint()
        onNameChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            var k = width / 24;
            ctx.scale(k, k);
            ctx.strokeStyle = String(col); ctx.fillStyle = String(col);
            ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round";
            ctx.beginPath();
            switch (name) {
            case "lock":
                ctx.rect(5, 11, 14, 10); ctx.moveTo(8, 11); ctx.lineTo(8, 8); ctx.arc(12, 8, 4, Math.PI, 2 * Math.PI); ctx.lineTo(16, 11); break;
            case "key":
                ctx.arc(8, 15, 4, 0, 2 * Math.PI); ctx.moveTo(11, 12); ctx.lineTo(20, 3); ctx.moveTo(16, 7); ctx.lineTo(18, 9); break;
            case "copy":
                ctx.rect(9, 9, 11, 11); ctx.moveTo(15, 9); ctx.lineTo(15, 5); ctx.lineTo(5, 5); ctx.lineTo(5, 15); ctx.lineTo(9, 15); break;
            case "eye":
                ctx.moveTo(2, 12); ctx.quadraticCurveTo(12, 2, 22, 12); ctx.quadraticCurveTo(12, 22, 2, 12); ctx.moveTo(15, 12); ctx.arc(12, 12, 3, 0, 2 * Math.PI); break;
            case "eyeoff":
                ctx.moveTo(2, 12); ctx.quadraticCurveTo(12, 2, 22, 12); ctx.quadraticCurveTo(12, 22, 2, 12); ctx.moveTo(4, 4); ctx.lineTo(20, 20); break;
            case "plus":
                ctx.moveTo(12, 5); ctx.lineTo(12, 19); ctx.moveTo(5, 12); ctx.lineTo(19, 12); break;
            case "trash":
                ctx.moveTo(4, 7); ctx.lineTo(20, 7); ctx.rect(6, 7, 12, 14); ctx.moveTo(9, 7); ctx.lineTo(9, 4); ctx.lineTo(15, 4); ctx.lineTo(15, 7);
                ctx.moveTo(10, 11); ctx.lineTo(10, 17); ctx.moveTo(14, 11); ctx.lineTo(14, 17); break;
            case "edit":
                ctx.moveTo(4, 20); ctx.lineTo(8, 19); ctx.lineTo(19, 8); ctx.lineTo(16, 5); ctx.lineTo(5, 16); ctx.closePath(); ctx.moveTo(14, 7); ctx.lineTo(17, 10); break;
            case "sync":
                ctx.arc(12, 12, 8, Math.PI * 1.05, Math.PI * 1.95); ctx.moveTo(20, 4); ctx.lineTo(20, 9); ctx.lineTo(15, 9);
                ctx.moveTo(20, 12); ctx.arc(12, 12, 8, 0.05 * Math.PI, 0.95 * Math.PI); ctx.moveTo(4, 20); ctx.lineTo(4, 15); ctx.lineTo(9, 15); break;
            case "search":
                ctx.arc(10, 10, 6, 0, 2 * Math.PI); ctx.moveTo(15, 15); ctx.lineTo(20, 20); break;
            case "folder":
                ctx.moveTo(3, 6); ctx.lineTo(9, 6); ctx.lineTo(11, 9); ctx.lineTo(21, 9); ctx.lineTo(21, 19); ctx.lineTo(3, 19); ctx.closePath(); break;
            case "grid":
                ctx.rect(4, 4, 6, 6); ctx.rect(14, 4, 6, 6); ctx.rect(4, 14, 6, 6); ctx.rect(14, 14, 6, 6); break;
            case "check":
                ctx.moveTo(5, 12); ctx.lineTo(10, 17); ctx.lineTo(19, 7); break;
            case "x":
                ctx.moveTo(6, 6); ctx.lineTo(18, 18); ctx.moveTo(18, 6); ctx.lineTo(6, 18); break;
            case "user":
                ctx.arc(12, 8, 4, 0, 2 * Math.PI); ctx.moveTo(4, 21); ctx.quadraticCurveTo(12, 9, 20, 21); break;
            case "cloud":
                ctx.moveTo(7, 18); ctx.arc(7, 14, 4, Math.PI / 2, Math.PI * 1.5); ctx.arc(12, 9, 5, Math.PI, Math.PI * 1.9); ctx.arc(17, 14, 4, Math.PI * 1.5, Math.PI / 2); ctx.closePath(); break;
            case "shield":
                ctx.moveTo(12, 3); ctx.lineTo(20, 6); ctx.lineTo(20, 12); ctx.quadraticCurveTo(20, 19, 12, 22); ctx.quadraticCurveTo(4, 19, 4, 12); ctx.lineTo(4, 6); ctx.closePath(); break;
            case "clock":
                ctx.arc(12, 12, 9, 0, 2 * Math.PI); ctx.moveTo(12, 7); ctx.lineTo(12, 12); ctx.lineTo(16, 14); break;
            case "link":
                ctx.rect(4, 8, 12, 12); ctx.moveTo(12, 12); ctx.lineTo(20, 4); ctx.moveTo(14, 4); ctx.lineTo(20, 4); ctx.lineTo(20, 10); break;
            case "warn":
                ctx.moveTo(12, 3); ctx.lineTo(22, 20); ctx.lineTo(2, 20); ctx.closePath(); ctx.moveTo(12, 10); ctx.lineTo(12, 14); ctx.moveTo(12, 17.2); ctx.lineTo(12, 17.3); break;
            case "restore":
                ctx.moveTo(9, 14); ctx.lineTo(4, 9); ctx.lineTo(9, 4); ctx.moveTo(4, 9); ctx.lineTo(14, 9);
                ctx.quadraticCurveTo(20, 9, 20, 15); ctx.quadraticCurveTo(20, 20, 14, 20); ctx.lineTo(8, 20); break;
            }
            ctx.stroke();
        }
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property string icon: ""
        property color accent: root.mauve
        property bool filled: true
        signal clicked()
        implicitHeight: root.s(40)
        implicitWidth: brow.implicitWidth + root.s(30)
        radius: root.s(11)
        opacity: enabled ? 1.0 : 0.45
        color: filled ? (ma.containsMouse ? Qt.lighter(accent, 1.1) : accent)
                      : (ma.containsMouse ? root.surface1 : root.surface0)
        border.width: filled ? 0 : 1
        border.color: ma.containsMouse && !filled ? accent : root.surface1
        scale: ma.pressed ? 0.95 : (ma.containsMouse ? 1.03 : 1.0)
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -root.s(5)
            radius: b.radius + root.s(5)
            color: b.accent
            opacity: b.filled && ma.containsMouse ? 0.30 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Rectangle {
            visible: b.filled
            anchors.fill: parent
            anchors.margins: 1
            radius: b.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
        Row {
            id: brow
            anchors.centerIn: parent
            spacing: root.s(7)
            Icon { visible: b.icon !== ""; name: b.icon; col: b.filled ? root.crust : (ma.containsMouse ? b.accent : root.text); sz: root.s(16); anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: b.label
                visible: b.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                color: b.filled ? root.crust : root.text
                font.family: root.fDisp; font.pixelSize: root.s(14); font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    component IconBtn: Rectangle {
        id: ib
        property string icon: "lock"
        property color accent: root.mauve
        property bool spin: false
        property bool active: false
        signal clicked()
        width: root.s(36); height: root.s(36); radius: root.s(11)
        color: ima.containsMouse || active ? root.tint(accent, 0.20) : root.surface0
        border.width: 1
        border.color: ima.containsMouse || active ? accent : root.surface1
        scale: ima.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 100 } }
        Icon {
            anchors.centerIn: parent
            name: ib.icon; sz: root.s(18)
            col: ima.containsMouse || ib.active ? ib.accent : root.subtext0
            RotationAnimator on rotation { from: 0; to: 360; duration: 1100; loops: Animation.Infinite; running: ib.spin }
        }
        MouseArea { id: ima; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }

    component Chip: Rectangle {
        id: ch
        property string label: ""
        property color accent: root.subtext0
        property bool pulse: false
        height: root.s(28)
        width: crow.implicitWidth + root.s(22)
        radius: height / 2
        color: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
        border.width: 1
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.35)
        Behavior on color { ColorAnimation { duration: 250 } }
        Row {
            id: crow
            anchors.centerIn: parent
            spacing: root.s(7)
            Item {
                width: root.s(9); height: root.s(9)
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    id: halo
                    anchors.centerIn: parent
                    width: parent.width; height: width; radius: width / 2
                    color: ch.accent; opacity: 0
                    SequentialAnimation {
                        running: ch.pulse && root.live; loops: Animation.Infinite
                        onRunningChanged: if (!running) { halo.opacity = 0; halo.scale = 1; }
                        ParallelAnimation {
                            NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.6; duration: 1100; easing.type: Easing.OutCubic }
                            NumberAnimation { target: halo; property: "opacity"; from: 0.6; to: 0; duration: 1100 }
                        }
                    }
                }
                Rectangle { anchors.centerIn: parent; width: root.s(7); height: width; radius: width / 2; color: ch.accent }
            }
            Text { text: ch.label; color: ch.accent; font.family: root.fMono; font.pixelSize: root.s(11); anchors.verticalCenter: parent.verticalCenter }
        }
    }

    component Field: Rectangle {
        id: f
        property string label: ""
        property string placeholder: ""
        property bool secret: false
        property bool reveal: false
        property bool mono: false
        property bool bad: false
        property alias text: ti.text
        property alias input: ti
        default property alias trailing: tr.data
        signal accepted()
        signal up()
        signal down()
        implicitHeight: root.s(56)
        radius: root.s(12)
        color: root.surface0
        border.width: 1
        border.color: f.bad ? root.red : (ti.activeFocus ? root.mauve : root.surface1)
        Behavior on border.color { ColorAnimation { duration: 180 } }
        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.margins: -root.s(4)
            radius: f.radius + root.s(4)
            color: f.bad ? root.red : root.mauve
            opacity: ti.activeFocus ? 0.20 : 0.0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
        Text {
            x: root.s(14); y: ti.activeFocus || ti.text.length > 0 ? root.s(7) : root.s(18)
            text: f.label; color: ti.activeFocus ? root.mauve : root.subtext0
            font.pixelSize: ti.activeFocus || ti.text.length > 0 ? root.s(10) : root.s(12)
            font.family: root.fMono; font.letterSpacing: 1
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on font.pixelSize { NumberAnimation { duration: 160 } }
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        TextInput {
            id: ti
            anchors { left: parent.left; right: tr.left; bottom: parent.bottom; leftMargin: root.s(14); rightMargin: root.s(8); bottomMargin: root.s(9) }
            color: root.text
            selectionColor: root.mauve
            font.pixelSize: root.s(14)
            font.family: f.mono ? root.fMono : root.fDisp
            echoMode: f.secret && !f.reveal ? TextInput.Password : TextInput.Normal
            clip: true
            onAccepted: f.accepted()
            onTextChanged: { root.touch(); if (root.mode === "form" && ti.activeFocus) root.formDirty = true; }
            Keys.onUpPressed: f.up()
            Keys.onDownPressed: f.down()
            Text {
                visible: ti.text.length === 0 && ti.activeFocus && f.placeholder.length > 0
                text: f.placeholder; color: root.subtext0; opacity: 0.6
                font: ti.font
            }
        }
        Row {
            id: tr
            anchors { right: parent.right; rightMargin: root.s(8); verticalCenter: parent.verticalCenter }
            spacing: root.s(6)
        }
    }

    component AreaField: Rectangle {
        id: af
        property string label: ""
        property alias text: te.text
        property alias input: te
        implicitHeight: root.s(104)
        radius: root.s(12)
        color: root.surface0
        border.width: 1
        border.color: te.activeFocus ? root.mauve : root.surface1
        Behavior on border.color { ColorAnimation { duration: 180 } }
        Text {
            x: root.s(14); y: root.s(7); text: af.label
            color: te.activeFocus ? root.mauve : root.subtext0
            font.pixelSize: root.s(10); font.family: root.fMono; font.letterSpacing: 1
        }
        Flickable {
            id: fl
            anchors { fill: parent; topMargin: root.s(24); leftMargin: root.s(14); rightMargin: root.s(10); bottomMargin: root.s(8) }
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, te.contentHeight)
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: te
                width: fl.width
                color: root.text
                selectionColor: root.mauve
                font.pixelSize: root.s(14); font.family: root.fDisp
                wrapMode: TextEdit.Wrap
                onTextChanged: { root.touch(); if (root.mode === "form" && te.activeFocus) root.formDirty = true; }
                onCursorRectangleChanged: {
                    if (cursorRectangle.y < fl.contentY) fl.contentY = cursorRectangle.y;
                    else if (cursorRectangle.y + cursorRectangle.height > fl.contentY + fl.height)
                        fl.contentY = cursorRectangle.y + cursorRectangle.height - fl.height;
                }
                Keys.onPressed: (event) => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                        root.save(); event.accepted = true;
                    }
                }
            }
        }
    }

    component Ring: Item {
        id: rg
        property real frac: 0
        property color accent: root.green
        property string label: ""
        property real sz: root.s(32)
        width: sz; height: sz
        Behavior on frac { NumberAnimation { duration: 250 } }
        onFracChanged: cv.requestPaint()
        onAccentChanged: cv.requestPaint()
        onWidthChanged: cv.requestPaint()
        Canvas {
            id: cv
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d"); ctx.reset();
                var w = width, c = w / 2, r = w * 0.40;
                ctx.lineWidth = w * 0.12; ctx.lineCap = "round";
                ctx.strokeStyle = String(root.surface1);
                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke();
                ctx.strokeStyle = String(rg.accent);
                ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.001, Math.min(1, rg.frac))); ctx.stroke();
            }
        }
        Text { anchors.centerIn: parent; text: rg.label; color: rg.accent; font.family: root.fMono; font.pixelSize: rg.sz * 0.32; font.weight: Font.Bold }
    }

    component DRow: Rectangle {
        id: dr
        property string label: ""
        property string value: ""
        property bool mono: false
        property bool multiline: false
        default property alias actions: act.data
        Layout.fillWidth: true
        implicitHeight: Math.max(root.s(66), dcol.implicitHeight + root.s(24))
        radius: root.s(12)
        color: hov.hovered ? root.surface1 : root.surface0
        border.width: 1
        border.color: root.surface1
        Behavior on color { ColorAnimation { duration: 150 } }
        HoverHandler { id: hov }
        Rectangle {
            width: root.s(3); radius: width / 2
            height: hov.hovered ? parent.height - root.s(22) : root.s(10)
            anchors.verticalCenter: parent.verticalCenter
            x: root.s(6)
            color: root.mauve; opacity: hov.hovered ? 1 : 0.35
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.s(20)
            anchors.rightMargin: root.s(14)
            anchors.topMargin: root.s(12)
            anchors.bottomMargin: root.s(12)
            spacing: root.s(10)
            ColumnLayout {
                id: dcol
                Layout.fillWidth: true
                spacing: root.s(3)
                Text { text: dr.label; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 1.5 }
                Text {
                    Layout.fillWidth: true
                    text: dr.value.length ? dr.value : "-"
                    color: root.text
                    wrapMode: dr.multiline ? Text.Wrap : Text.NoWrap
                    elide: dr.multiline ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: dr.multiline ? 12 : 1
                    font.family: dr.mono ? root.fMono : root.fDisp; font.pixelSize: root.s(14)
                }
            }
            Row { id: act; spacing: root.s(8); Layout.alignment: Qt.AlignVCenter }
        }
    }

    component Pill: Rectangle {
        id: pl
        property string label: ""
        property bool on: false
        signal clicked()
        height: root.s(32)
        width: pt.implicitWidth + root.s(24)
        radius: height / 2
        color: on ? root.tint(root.mauve, 0.22) : (pm.containsMouse ? root.surface1 : root.surface0)
        border.width: 1
        border.color: on ? root.mauve : root.surface1
        scale: pm.pressed ? 0.93 : 1
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 100 } }
        Text { id: pt; anchors.centerIn: parent; text: pl.label; color: pl.on ? root.mauve : root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11) }
        MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pl.clicked() }
    }

    component Strength: Row {
        id: sb
        property int score: 0
        spacing: root.s(5)
        readonly property var cols: [root.red, root.peach, root.blue, root.green]
        Repeater {
            model: 4
            Rectangle {
                width: root.s(34); height: root.s(5); radius: height / 2
                color: sb.score > index ? sb.cols[sb.score - 1] : root.surface1
                Behavior on color { ColorAnimation { duration: 220 } }
            }
        }
        Text {
            text: ["", "weak", "fair", "good", "strong"][sb.score]
            color: sb.score > 0 ? sb.cols[sb.score - 1] : root.subtext0
            font.family: root.fMono; font.pixelSize: root.s(11)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component Orb: Item {
        id: ob
        property color tint: root.mauve
        property real size: root.s(400)
        property real strength: 0.045
        property real baseX: 0
        property real baseY: 0
        property real ax: 80
        property real ay: 60
        property int period: 9000
        property real drift: 0
        width: size; height: size
        x: baseX + drift * ax
        y: baseY + drift * ay
        SequentialAnimation on drift {
            running: root.live
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: ob.period; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: ob.period; easing.type: Easing.InOutSine }
        }
        Repeater {
            model: 5
            Rectangle {
                anchors.centerIn: parent
                width: ob.size * (1 - index * 0.17); height: width; radius: width / 2
                color: ob.tint; opacity: ob.strength
            }
        }
    }

    component Panel: Rectangle {
        radius: root.s(16)
        color: Qt.rgba(root.mantle.r, root.mantle.g, root.mantle.b, 0.72)
        border.width: 1
        border.color: root.surface1
        clip: true
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: root.s(20); rightMargin: root.s(20) }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.16) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // ---------------- main card ----------------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.s(22)
        color: root.base
        border.width: 1
        border.color: root.surface1
        clip: true

        // ambient background (paused whenever the popup is hidden)
        Orb { tint: root.mauve; size: root.s(520); baseX: -root.s(170); baseY: -root.s(200); ax: root.s(90); ay: root.s(70); period: 9000 }
        Orb { tint: root.blue; size: root.s(460); baseX: card.width - root.s(280); baseY: card.height - root.s(240); ax: -root.s(80); ay: -root.s(60); period: 11000 }
        Orb { tint: root.pink; size: root.s(300); strength: 0.03; baseX: card.width * 0.5; baseY: card.height * 0.2; ax: root.s(60); ay: -root.s(50); period: 13000 }

        Canvas {
            anchors.fill: parent
            opacity: 0.05
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d"); ctx.reset();
                ctx.fillStyle = String(root.text);
                var step = Math.max(14, root.s(26));
                for (var x = step / 2; x < width; x += step)
                    for (var y = step / 2; y < height; y += step)
                        ctx.fillRect(x, y, 1.5, 1.5);
            }
        }

        // ===================== unlocked UI =====================
        ColumnLayout {
            id: mainUi
            anchors.fill: parent
            anchors.margins: root.s(14)
            spacing: root.s(10)
            visible: root.doorP > 0.001
            opacity: Math.min(1, root.doorP * 1.4)
            scale: 0.97 + 0.03 * Math.min(1, root.doorP)

            // sync problem banner
            Rectangle {
                Layout.fillWidth: true
                visible: root.syncState === "failed" || root.syncState === "conflict" && root.syncBusy === false && root.syncError !== ""
                implicitHeight: root.s(48)
                radius: root.s(12)
                color: root.tint(root.red, 0.12)
                border.width: 1
                border.color: root.tint(root.red, 0.45)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.s(14); anchors.rightMargin: root.s(10)
                    spacing: root.s(10)
                    Icon { name: "warn"; col: root.red; sz: root.s(18) }
                    Text {
                        Layout.fillWidth: true
                        text: root.errText({ error: root.syncError, hint: "" })
                        color: root.text; elide: Text.ElideRight
                        font.family: root.fDisp; font.pixelSize: root.s(13)
                    }
                    Btn {
                        visible: root.syncError === "merge_unsupported" || root.syncError === "remote_master_differs"
                        label: root.pendingStrategy === "local" ? "Click again to overwrite cloud" : "Keep this device"
                        filled: false; accent: root.peach; implicitHeight: root.s(32)
                        onClicked: root.strategyClick("local")
                    }
                    Btn {
                        visible: root.syncError === "merge_unsupported" || root.syncError === "remote_master_differs"
                        label: root.pendingStrategy === "remote" ? "Click again to overwrite device" : "Use cloud copy"
                        filled: false; accent: root.peach; implicitHeight: root.s(32)
                        onClicked: root.strategyClick("remote")
                    }
                    Btn { label: "Retry"; filled: false; implicitHeight: root.s(32); onClicked: root.syncNow(false, "merge") }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.s(12)

                // ----- sidebar -----
                Panel {
                    Layout.preferredWidth: root.s(212)
                    Layout.maximumWidth: root.s(212)
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.s(14)
                        spacing: root.s(12)

                        RowLayout {
                            spacing: root.s(10)
                            Item {
                                Layout.preferredWidth: root.s(38); Layout.preferredHeight: root.s(38)
                                Rectangle {
                                    anchors.fill: parent; radius: root.s(12)
                                    gradient: Gradient {
                                        orientation: Gradient.Vertical
                                        GradientStop { position: 0.0; color: root.mauve }
                                        GradientStop { position: 1.0; color: root.blue }
                                    }
                                }
                                Icon { anchors.centerIn: parent; name: "shield"; col: root.crust; sz: root.s(22) }
                            }
                            Column {
                                Layout.fillWidth: true
                                spacing: root.s(2)
                                Text { text: "Vault"; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(22); font.weight: Font.Bold }
                                Rectangle {
                                    height: root.s(3); radius: height / 2
                                    width: root.unlocked ? root.s(34) : 0
                                    Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: root.mauve }
                                        GradientStop { position: 1.0; color: root.blue }
                                    }
                                }
                            }
                        }

                        Btn { Layout.fillWidth: true; label: "New entry"; icon: "plus"; accent: root.green; enabled: !root.working; onClicked: root.beginAdd() }

                        ListView {
                            id: navList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: root.s(3)
                            model: root.navItems
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Item {
                                id: nd
                                required property var modelData
                                width: ListView.view.width
                                height: root.s(38)
                                readonly property bool sel: modelData.key === root.navKey
                                Rectangle {
                                    anchors.fill: parent
                                    radius: root.s(10)
                                    color: nd.sel ? root.tint(root.mauve, 0.18) : (nma.containsMouse ? root.surface0 : "transparent")
                                    border.width: nd.sel ? 1 : 0
                                    border.color: root.tint(root.mauve, 0.55)
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: root.s(3); width: root.s(3); radius: width / 2
                                        height: nd.sel ? root.s(18) : 0
                                        color: root.mauve
                                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.s(12) + nd.modelData.depth * root.s(14)
                                        anchors.rightMargin: root.s(10)
                                        spacing: root.s(9)
                                        Icon { name: nd.modelData.icon; col: nd.sel ? root.mauve : root.subtext0; sz: root.s(16) }
                                        Text {
                                            Layout.fillWidth: true
                                            text: nd.modelData.label; elide: Text.ElideRight
                                            color: nd.sel ? root.text : root.subtext0
                                            font.family: root.fDisp; font.pixelSize: root.s(13); font.weight: nd.sel ? Font.DemiBold : Font.Normal
                                        }
                                        Text { text: nd.modelData.count; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11); opacity: 0.8 }
                                    }
                                }
                                MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.touch(); root.navKey = nd.modelData.key; } }
                            }
                        }

                        Chip {
                            label: root.syncBusy ? "syncing" : root.syncLabel(root.syncState)
                            accent: root.syncBusy ? root.blue : root.syncColor(root.syncState)
                            pulse: root.syncBusy || root.syncState === "unsynced" || root.syncState === "remote_newer"
                        }

                        RowLayout {
                            spacing: root.s(8)
                            IconBtn { icon: "sync"; accent: root.blue; spin: root.syncBusy; onClicked: { if (root.loggedIn) root.syncNow(false, "merge"); else { root.accountOpen = true; } } }
                            IconBtn { icon: "user"; accent: root.mauve; active: root.accountOpen; onClicked: root.accountOpen = !root.accountOpen }
                            Item { Layout.fillWidth: true }
                            IconBtn { icon: "lock"; accent: root.red; onClicked: root.lock("manual") }
                        }
                    }
                }

                // ----- list pane -----
                ColumnLayout {
                    Layout.preferredWidth: root.s(328)
                    Layout.maximumWidth: root.s(328)
                    Layout.fillHeight: true
                    spacing: root.s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.s(4)
                        Text { text: root.navTitle(); color: root.text; font.family: root.fDisp; font.pixelSize: root.s(20); font.weight: Font.Bold }
                        Item { Layout.fillWidth: true }
                        Text { text: root.filtered.length + (root.filtered.length === 1 ? " entry" : " entries"); color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11) }
                    }

                    Field {
                        id: searchField
                        Layout.fillWidth: true
                        label: "SEARCH"; placeholder: "title, user, url or group"
                        onUp: root.moveSel(-1)
                        onDown: root.moveSel(1)
                        onAccepted: if (root.filtered.length > 0 && !root.selEntry) root.select(root.filtered[0].uuid)
                        input.onTextChanged: { root.query = text; root.applyFilter(); }
                        Icon { name: "search"; col: root.subtext0; sz: root.s(16); anchors.verticalCenter: parent.verticalCenter }
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: root.s(6)
                        model: root.filtered
                        boundsBehavior: Flickable.StopAtBounds

                        populate: Transition {
                            SequentialAnimation {
                                PauseAnimation { duration: Math.max(0, Math.min(ViewTransition.index, 10)) * 35 }
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 280 }
                                    NumberAnimation { property: "x"; from: -root.s(24); to: 0; duration: 340; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        delegate: Item {
                            id: dlg
                            required property var modelData
                            width: ListView.view.width
                            height: root.s(64)
                            readonly property bool sel: modelData.uuid === root.selUuid

                            Rectangle {
                                id: rowBg
                                width: parent.width
                                height: root.s(62)
                                x: rowMa.containsMouse && !dlg.sel ? root.s(5) : 0
                                radius: root.s(13)
                                color: dlg.sel ? root.tint(root.mauve, 0.18) : (rowMa.containsMouse ? root.surface1 : root.surface0)
                                border.width: 1
                                border.color: dlg.sel ? root.mauve : root.surface1
                                scale: rowMa.pressed ? 0.98 : 1
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Behavior on border.color { ColorAnimation { duration: 140 } }
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: root.s(4); width: root.s(3); radius: width / 2
                                    height: dlg.sel ? root.s(30) : 0
                                    color: root.mauve
                                    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.s(14)
                                    anchors.rightMargin: root.s(10)
                                    anchors.topMargin: root.s(10)
                                    anchors.bottomMargin: root.s(10)
                                    spacing: root.s(12)
                                    Rectangle {
                                        id: avatar
                                        Layout.preferredWidth: root.s(40); Layout.preferredHeight: root.s(40)
                                        radius: width / 2
                                        property color ac: root.avColor(dlg.modelData.title)
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop { position: 0.0; color: root.tint(avatar.ac, 0.40) }
                                            GradientStop { position: 1.0; color: root.tint(avatar.ac, 0.14) }
                                        }
                                        border.width: 1
                                        border.color: root.tint(avatar.ac, 0.5)
                                        scale: dlg.sel || rowMa.containsMouse ? 1.08 : 1
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: (dlg.modelData.title || "?").charAt(0).toUpperCase()
                                            color: avatar.ac
                                            font.family: root.fDisp; font.pixelSize: root.s(17); font.weight: Font.Bold
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: root.s(2)
                                        Text { Layout.fillWidth: true; text: dlg.modelData.title; elide: Text.ElideRight; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(14); font.weight: Font.DemiBold }
                                        Text { Layout.fillWidth: true; text: dlg.modelData.username || root.hostOf(dlg.modelData.url) || (dlg.modelData.group || "no details"); elide: Text.ElideRight; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11) }
                                    }
                                    Rectangle {
                                        visible: dlg.modelData.has_otp
                                        Layout.preferredWidth: root.s(30); Layout.preferredHeight: root.s(18)
                                        radius: root.s(6); color: root.tint(root.blue, 0.18); border.width: 1; border.color: root.tint(root.blue, 0.5)
                                        Text { anchors.centerIn: parent; text: "2FA"; color: root.blue; font.family: root.fMono; font.pixelSize: root.s(9); font.weight: Font.Bold }
                                    }
                                    Rectangle { visible: dlg.modelData.expired; width: root.s(8); height: width; radius: width / 2; color: root.red }
                                }
                                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.select(dlg.modelData.uuid) }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: root.s(8)
                            visible: list.count === 0
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: root.query.length > 0 ? "search" : "key"; col: root.surface2; sz: root.s(34) }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.query.length > 0 ? "No matches" : (root.navKey === "trash" ? "Trash is empty" : "No entries here yet")
                                color: root.subtext0; font.family: root.fDisp; font.pixelSize: root.s(14)
                            }
                        }
                    }
                }

                // ----- detail pane -----
                Panel {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // empty state
                    Column {
                        id: emptyCol
                        anchors.centerIn: parent
                        spacing: root.s(12)
                        visible: root.mode === "view" && root.selEntry === null
                        property real bob: 0
                        SequentialAnimation on bob {
                            loops: Animation.Infinite; running: emptyCol.visible && root.live
                            NumberAnimation { to: 1; duration: 1800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: 1800; easing.type: Easing.InOutSine }
                        }
                        Canvas {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.s(64); height: root.s(72)
                            transform: Translate { y: -emptyCol.bob * root.s(8) }
                            onWidthChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                var w = width, h = height;
                                var g = ctx.createLinearGradient(0, 0, 0, h);
                                g.addColorStop(0, String(root.mauve)); g.addColorStop(1, String(root.blue));
                                ctx.fillStyle = g; ctx.globalAlpha = 0.9;
                                ctx.beginPath();
                                ctx.moveTo(w * 0.5, h * 0.04);
                                ctx.lineTo(w * 0.9, h * 0.18);
                                ctx.lineTo(w * 0.9, h * 0.5);
                                ctx.quadraticCurveTo(w * 0.9, h * 0.84, w * 0.5, h * 0.97);
                                ctx.quadraticCurveTo(w * 0.1, h * 0.84, w * 0.1, h * 0.5);
                                ctx.lineTo(w * 0.1, h * 0.18);
                                ctx.closePath(); ctx.fill();
                                ctx.globalAlpha = 1;
                                ctx.strokeStyle = String(root.crust); ctx.lineWidth = w * 0.08; ctx.lineCap = "round"; ctx.lineJoin = "round";
                                ctx.beginPath(); ctx.moveTo(w * 0.32, h * 0.5); ctx.lineTo(w * 0.45, h * 0.62); ctx.lineTo(w * 0.70, h * 0.36); ctx.stroke();
                            }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Select an entry"; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(18); font.weight: Font.DemiBold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Ctrl+N new  /  Ctrl+F search  /  Ctrl+L lock"; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11) }
                    }

                    // view pane
                    Flickable {
                        id: viewFlick
                        anchors.fill: parent
                        anchors.margins: root.s(20)
                        visible: root.mode === "view" && root.selEntry !== null
                        opacity: root.paneP * (root.working ? 0.55 : 1)
                        transform: Translate { x: (1 - root.paneP) * root.s(22) }
                        contentWidth: width
                        contentHeight: vcol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: vcol
                            width: viewFlick.width
                            spacing: root.s(10)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(14)
                                Rectangle {
                                    id: bigAv
                                    Layout.preferredWidth: root.s(58); Layout.preferredHeight: root.s(58); radius: width / 2
                                    property color ac: root.avColor(root.selEntry ? root.selEntry.title : "")
                                    gradient: Gradient {
                                        orientation: Gradient.Vertical
                                        GradientStop { position: 0.0; color: root.tint(bigAv.ac, 0.45) }
                                        GradientStop { position: 1.0; color: root.tint(bigAv.ac, 0.15) }
                                    }
                                    border.width: 1; border.color: root.tint(bigAv.ac, 0.55)
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.selEntry ? (root.selEntry.title || "?").charAt(0).toUpperCase() : ""
                                        color: bigAv.ac
                                        font.family: root.fDisp; font.pixelSize: root.s(26); font.weight: Font.Bold
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(3)
                                    Text { Layout.fillWidth: true; text: root.selEntry ? root.selEntry.title : ""; elide: Text.ElideRight; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(24); font.weight: Font.Bold }
                                    Row {
                                        spacing: root.s(8)
                                        Chip { visible: root.selEntry && root.selEntry.group !== ""; label: root.selEntry ? root.selEntry.group : ""; accent: root.blue }
                                        Text { visible: root.selEntry && root.selEntry.in_trash; text: "in trash"; color: root.red; font.family: root.fMono; font.pixelSize: root.s(11); anchors.verticalCenter: parent.verticalCenter }
                                        Text { visible: root.selEntry && root.selEntry.expired; text: "expired"; color: root.red; font.family: root.fMono; font.pixelSize: root.s(11); anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                            }

                            DRow {
                                label: "USERNAME"; value: root.selEntry ? root.selEntry.username : ""
                                Ring { visible: root.copyLeft > 0 && root.copyWhat === "username"; frac: root.copyLeft / root.clipSecs; label: root.copyLeft }
                                Btn {
                                    label: root.copyLeft > 0 && root.copyWhat === "username" ? "Copied" : "Copy"; icon: root.copyLeft > 0 && root.copyWhat === "username" ? "check" : "copy"
                                    accent: root.green; filled: root.copyLeft > 0 && root.copyWhat === "username"
                                    onClicked: root.copyField("username")
                                }
                            }

                            DRow {
                                label: "PASSWORD"; mono: true
                                value: root.secretData ? (root.secretData.password || "(empty)") : "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022"
                                Ring { visible: root.copyLeft > 0 && root.copyWhat === "password"; frac: root.copyLeft / root.clipSecs; label: root.copyLeft }
                                Btn { label: root.secretData ? "Hide" : "Show"; icon: root.secretData ? "eyeoff" : "eye"; filled: false; onClicked: root.reveal() }
                                Btn {
                                    label: root.copyLeft > 0 && root.copyWhat === "password" ? "Copied" : "Copy"; icon: root.copyLeft > 0 && root.copyWhat === "password" ? "check" : "copy"
                                    accent: root.copyLeft > 0 && root.copyWhat === "password" ? root.green : root.mauve
                                    onClicked: root.copyField("password")
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.secretData !== null
                                spacing: root.s(12)
                                Strength { score: root.secretData ? root.strengthOf(root.secretData.password) : 0 }
                                Item { Layout.fillWidth: true }
                                Text { text: "hides in " + root.revealLeft + "s"; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11) }
                            }

                            // TOTP
                            Rectangle {
                                Layout.fillWidth: true
                                visible: root.selEntry !== null && root.selEntry.has_otp && !root.selEntry.in_trash
                                implicitHeight: root.s(82)
                                radius: root.s(12)
                                color: root.tint(root.blue, 0.10)
                                border.width: 1
                                border.color: root.tint(root.blue, 0.45)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.s(20); anchors.rightMargin: root.s(14)
                                    spacing: root.s(14)
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: root.s(2)
                                        Text { text: "ONE-TIME CODE"; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 1.5 }
                                        Text {
                                            text: root.totpErr !== "" ? root.totpErr : (root.totpCode !== "" ? root.fmtCode(root.totpCode) : "......")
                                            color: root.totpErr !== "" ? root.red : (root.totpLeft <= 5 ? root.peach : root.blue)
                                            font.family: root.fMono; font.pixelSize: root.totpErr !== "" ? root.s(12) : root.s(28); font.weight: Font.Bold; font.letterSpacing: root.s(3)
                                            Behavior on color { ColorAnimation { duration: 250 } }
                                        }
                                    }
                                    Ring { sz: root.s(40); frac: root.totpFrac; label: root.totpLeft; accent: root.totpLeft <= 5 ? root.peach : root.blue; visible: root.totpErr === "" }
                                    Btn {
                                        label: root.copyLeft > 0 && root.copyWhat === "otp" ? "Copied" : "Copy"; icon: root.copyLeft > 0 && root.copyWhat === "otp" ? "check" : "copy"
                                        accent: root.blue; filled: root.copyLeft > 0 && root.copyWhat === "otp"
                                        enabled: root.totpErr === ""
                                        onClicked: root.copyField("otp")
                                    }
                                }
                            }

                            DRow {
                                label: "URL"; mono: true; value: root.selEntry ? root.selEntry.url : ""
                                Btn { visible: root.selEntry !== null && /^https?:\/\//i.test(root.selEntry.url); label: "Open"; icon: "link"; filled: false; onClicked: root.openUrl(root.selEntry.url) }
                            }

                            DRow {
                                visible: root.selEntry !== null && root.selEntry.has_notes
                                multiline: true
                                label: "NOTES"
                                value: root.secretData ? (root.secretData.notes || "") : "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022  (notes are hidden until you press Show)"
                            }

                            Repeater {
                                model: root.secretData && root.secretData.fields ? Object.keys(root.secretData.fields) : []
                                delegate: DRow {
                                    required property string modelData
                                    label: modelData.toUpperCase(); mono: true; multiline: true
                                    value: root.secretData && root.secretData.fields ? String(root.secretData.fields[modelData]) : ""
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "Modified " + (root.selEntry ? root.ago(root.selEntry.mtime) : "")
                                color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(11); opacity: 0.8
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: root.s(6)
                                spacing: root.s(10)
                                Item { Layout.fillWidth: true }
                                Btn { visible: root.selEntry !== null && !root.selEntry.in_trash; label: "Edit"; icon: "edit"; filled: false; enabled: !root.working; onClicked: root.beginEdit() }
                                Btn {
                                    visible: root.selEntry !== null && !root.selEntry.in_trash
                                    label: root.confirmDel ? "Click again to trash" : "Trash"; icon: "trash"; accent: root.red; filled: root.confirmDel
                                    enabled: !root.working
                                    onClicked: root.trashSelected()
                                }
                                Btn { visible: root.selEntry !== null && root.selEntry.in_trash; label: "Restore"; icon: "restore"; accent: root.green; enabled: !root.working; onClicked: root.restoreSelected() }
                                Btn {
                                    visible: root.selEntry !== null && root.selEntry.in_trash
                                    label: root.confirmPurge ? "Click again: gone forever" : "Delete forever"; icon: "trash"; accent: root.red; filled: root.confirmPurge
                                    enabled: !root.working
                                    onClicked: root.purgeSelected()
                                }
                            }
                        }
                    }

                    // form pane
                    Flickable {
                        id: formFlick
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: formFooter.top; margins: root.s(20); bottomMargin: root.s(8) }
                        visible: root.mode === "form"
                        opacity: root.paneP * (root.working ? 0.55 : 1)
                        transform: Translate { x: (1 - root.paneP) * root.s(22) }
                        contentWidth: width
                        contentHeight: formCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: formCol
                            width: formFlick.width
                            spacing: root.s(10)

                            Text { text: root.editUuid ? "Edit entry" : "New entry"; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(22); font.weight: Font.Bold }
                            Field { id: fTitle; width: parent.width; label: "TITLE"; placeholder: "e.g. GitHub"; onAccepted: fUser.input.forceActiveFocus() }
                            Field { id: fUser; width: parent.width; label: "USERNAME"; onAccepted: fPass.input.forceActiveFocus() }
                            Field {
                                id: fPass; width: parent.width; label: "PASSWORD"; mono: true; secret: true
                                onAccepted: fUrl.input.forceActiveFocus()
                                IconBtn { icon: fPass.reveal ? "eyeoff" : "eye"; accent: root.mauve; width: root.s(32); height: root.s(32); onClicked: fPass.reveal = !fPass.reveal }
                            }
                            Strength { score: root.pwScore }

                            Flow {
                                width: parent.width
                                spacing: root.s(8)
                                Btn { label: "Generate"; icon: "key"; accent: root.blue; onClicked: root.generate() }
                                Pill { label: "Passphrase"; on: root.genPassphrase; onClicked: root.genPassphrase = !root.genPassphrase }
                                Pill { visible: !root.genPassphrase; label: "Symbols"; on: root.genSymbols; onClicked: root.genSymbols = !root.genSymbols }
                                Pill { visible: !root.genPassphrase; label: "\u2212"; onClicked: root.genLen = Math.max(8, root.genLen - 2) }
                                Text { visible: !root.genPassphrase; text: root.genLen + " chars"; color: root.text; font.family: root.fMono; font.pixelSize: root.s(12); height: root.s(32); verticalAlignment: Text.AlignVCenter }
                                Pill { visible: !root.genPassphrase; label: "+"; onClicked: root.genLen = Math.min(64, root.genLen + 2) }
                                Pill { visible: root.genPassphrase; label: "\u2212"; onClicked: root.genWords = Math.max(3, root.genWords - 1) }
                                Text { visible: root.genPassphrase; text: root.genWords + " words"; color: root.text; font.family: root.fMono; font.pixelSize: root.s(12); height: root.s(32); verticalAlignment: Text.AlignVCenter }
                                Pill { visible: root.genPassphrase; label: "+"; onClicked: root.genWords = Math.min(12, root.genWords + 1) }
                                Text { visible: root.genEntropy.length > 0; text: root.genEntropy; color: root.green; font.family: root.fMono; font.pixelSize: root.s(12); height: root.s(32); verticalAlignment: Text.AlignVCenter }
                            }

                            Field { id: fUrl; width: parent.width; label: "URL"; mono: true; onAccepted: fGroup.input.forceActiveFocus() }
                            Field { id: fGroup; width: parent.width; label: "GROUP"; placeholder: "e.g. Work/Servers"; onAccepted: fOtp.input.forceActiveFocus() }
                            Flow {
                                width: parent.width
                                spacing: root.s(6)
                                visible: root.groups.length > 0
                                Repeater {
                                    model: root.groups.length > 8 ? root.groups.slice(0, 8) : root.groups
                                    delegate: Pill { required property string modelData; label: modelData; on: fGroup.text === modelData; onClicked: { fGroup.text = modelData; root.formDirty = true; } }
                                }
                            }
                            Field {
                                id: fOtp; width: parent.width; mono: true
                                label: root.editUuid && root.selEntry && root.selEntry.has_otp && !root.removeOtp ? "2FA SECRET (UNCHANGED)" : "2FA SECRET (OPTIONAL)"
                                placeholder: root.editUuid && root.selEntry && root.selEntry.has_otp && !root.removeOtp ? "unchanged. Paste a new secret to replace it" : "base32 secret or otpauth:// link"
                                onAccepted: fNotes.input.forceActiveFocus()
                                Btn {
                                    visible: root.editUuid !== "" && root.selEntry !== null && root.selEntry.has_otp
                                    label: root.removeOtp ? "Will remove" : "Remove 2FA"; filled: root.removeOtp; accent: root.red; implicitHeight: root.s(32)
                                    onClicked: { root.removeOtp = !root.removeOtp; root.formDirty = true; }
                                }
                            }
                            AreaField { id: fNotes; width: parent.width; label: "NOTES  (Ctrl+Enter saves)" }
                        }
                    }

                    Rectangle {
                        id: formFooter
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: root.s(70) + (root.formError.length > 0 ? root.s(22) : 0)
                        visible: root.mode === "form"
                        color: root.tint(root.crust, 0.55)
                        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: root.surface1 }
                        Column {
                            anchors { fill: parent; leftMargin: root.s(20); rightMargin: root.s(20); topMargin: root.s(12) }
                            spacing: root.s(8)
                            Text { visible: root.formError.length > 0; text: root.formError; color: root.red; font.family: root.fDisp; font.pixelSize: root.s(13); elide: Text.ElideRight; width: parent.width }
                            Row {
                                spacing: root.s(10)
                                layoutDirection: Qt.RightToLeft
                                width: parent.width
                                Btn { label: root.formBusy ? "Saving..." : "Save"; icon: "check"; accent: root.green; enabled: !root.working; onClicked: root.save() }
                                Btn { label: root.discardArmed ? "Discard changes" : "Cancel"; filled: root.discardArmed; accent: root.red; enabled: !root.working; onClicked: root.cancelForm() }
                            }
                        }
                    }
                }
            }
        }

        // idle auto-lock countdown
        Rectangle {
            id: idleBar
            z: 6
            anchors.top: parent.top
            height: root.s(2)
            width: card.width * root.idleFrac
            radius: height / 2
            color: root.idleFrac < 0.15 ? root.peach : root.mauve
            opacity: root.unlocked ? 0.85 : 0
            Behavior on width { NumberAnimation { duration: 500 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        // indeterminate progress sweep while an operation runs
        Rectangle {
            id: busyBar
            z: 7
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: root.s(3)
            color: "transparent"
            clip: true
            visible: root.working
            Rectangle {
                height: parent.height; width: card.width * 0.35; radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: root.blue }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                SequentialAnimation on x {
                    running: root.working && root.live; loops: Animation.Infinite
                    NumberAnimation { from: -card.width * 0.35; to: card.width; duration: 1100; easing.type: Easing.InOutQuad }
                }
            }
        }

        // ===================== account overlay =====================
        Rectangle {
            id: acctScrim
            z: 30
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            opacity: root.accountOpen ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 220 } }
            MouseArea { anchors.fill: parent; onClicked: root.accountOpen = false }

            Rectangle {
                id: acctPanel
                anchors.centerIn: parent
                width: root.s(520)
                height: Math.min(acctCol.implicitHeight + root.s(44), card.height - root.s(40))
                radius: root.s(18)
                color: root.mantle
                border.width: 1; border.color: root.surface1
                scale: root.accountOpen ? 1 : 0.94
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                MouseArea { anchors.fill: parent }
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: root.s(22)
                    contentWidth: width
                    contentHeight: acctCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: acctCol
                        width: parent.width
                        spacing: root.s(12)

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Account and security"; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(20); font.weight: Font.Bold }
                            Item { Layout.fillWidth: true }
                            IconBtn { icon: "x"; accent: root.red; onClicked: root.accountOpen = false }
                        }

                        Text { text: "CLOUD SYNC"; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 1.5 }
                        Rectangle {
                            Layout.fillWidth: true
                            visible: root.loggedIn
                            implicitHeight: root.s(64)
                            radius: root.s(12); color: root.surface0; border.width: 1; border.color: root.surface1
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(12); spacing: root.s(12)
                                Icon { name: "cloud"; col: root.green; sz: root.s(22) }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: root.s(2)
                                    Text { text: root.email !== "" ? root.email : "Signed in"; color: root.text; font.family: root.fDisp; font.pixelSize: root.s(14); font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: root.syncLabel(root.syncState); color: root.syncColor(root.syncState); font.family: root.fMono; font.pixelSize: root.s(11) }
                                }
                                Btn { label: "Sync now"; icon: "sync"; filled: false; onClicked: root.syncNow(false, "merge") }
                                Btn { label: "Sign out"; filled: false; accent: root.red; onClicked: root.doLogout() }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !root.loggedIn
                            spacing: root.s(10)
                            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Signed out. The vault lives only on this device. Sign in to keep an encrypted copy in the cloud and sync other devices."; color: root.subtext0; font.family: root.fDisp; font.pixelSize: root.s(13) }
                            Field { id: acctEmail; Layout.fillWidth: true; label: "CLOUD EMAIL"; onAccepted: acctPass.input.forceActiveFocus() }
                            Field { id: acctPass; Layout.fillWidth: true; label: "CLOUD PASSWORD"; secret: true; onAccepted: root.doLogin() }
                            Btn { label: root.accountBusy ? "Signing in..." : "Sign in and sync"; icon: "cloud"; accent: root.blue; enabled: !root.accountBusy; onClicked: root.doLogin() }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.surface1 }

                        Text { text: "CHANGE MASTER PASSWORD"; color: root.subtext0; font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 1.5 }
                        Field { id: acctOld; Layout.fillWidth: true; label: "CURRENT"; secret: true; onAccepted: acctNew.input.forceActiveFocus() }
                        Field { id: acctNew; Layout.fillWidth: true; label: "NEW (12+ CHARACTERS)"; secret: true; onAccepted: acctNew2.input.forceActiveFocus() }
                        Strength { score: root.strengthOf(acctNew.text) }
                        Field { id: acctNew2; Layout.fillWidth: true; label: "REPEAT NEW"; secret: true; onAccepted: root.doChangeMaster() }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                            text: "Other devices will need the new password the next time they sync. There is no recovery if it is forgotten."
                            color: root.subtext0; font.family: root.fDisp; font.pixelSize: root.s(12)
                        }
                        Btn { label: "Change master password"; icon: "key"; accent: root.mauve; enabled: !root.accountBusy; onClicked: root.doChangeMaster() }

                        Text { visible: root.accountMsg !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; text: root.accountMsg; color: root.red; font.family: root.fDisp; font.pixelSize: root.s(13) }
                    }
                }
            }
        }

        // ===================== vault doors + lock screen =====================
        Item {
            id: doors
            z: 20
            anchors.fill: parent
            visible: root.doorP < 0.999

            component Door: Rectangle {
                id: dr2
                property bool leftSide: true
                width: card.width / 2 + 1
                height: card.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: dr2.leftSide ? 0.0 : 1.0; color: root.base }
                    GradientStop { position: dr2.leftSide ? 1.0 : 0.0; color: root.mantle }
                }
                Canvas {
                    anchors.fill: parent
                    opacity: 0.07
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d"); ctx.reset();
                        ctx.strokeStyle = String(root.text); ctx.lineWidth = 1;
                        for (var y = 3; y < height; y += 5) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
                    }
                }
                // bolts along the outer edge
                Repeater {
                    model: 6
                    Rectangle {
                        width: root.s(12); height: width; radius: width / 2
                        x: dr2.leftSide ? root.s(18) : dr2.width - root.s(18) - width
                        y: root.s(40) + index * (dr2.height - root.s(80) - width) / 5
                        color: root.surface0; border.width: 1; border.color: root.surface2
                        Rectangle { anchors.centerIn: parent; width: parent.width * 0.4; height: width; radius: width / 2; color: root.tint(root.mauve, 0.5) }
                    }
                }
                // seam glow
                Rectangle {
                    width: root.s(3)
                    height: parent.height
                    x: dr2.leftSide ? dr2.width - width - 1 : 1
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: root.tint(root.mauve, 0.28) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }

            Door { id: doorL; leftSide: true; x: -root.doorP * width }
            Door { id: doorR; leftSide: false; x: card.width / 2 + root.doorP * width }

            // lock content sits on top of the doors and fades as they open
            Item {
                id: lockedView
                anchors.fill: parent
                opacity: 1 - Math.min(1, root.doorP * 4)
                visible: opacity > 0.01

                Column {
                    id: lockCol
                    anchors.centerIn: parent
                    width: root.s(380)
                    spacing: root.s(14)
                    transform: Translate { id: shiftT; x: 0 }

                    Item {
                        id: badge
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: root.s(190); height: width
                        opacity: Math.min(1, root.lockEnter * 2)
                        scale: 0.6 + 0.4 * Math.min(1, root.lockEnter * 1.6)

                        Repeater {
                            model: 2
                            Rectangle {
                                id: ring
                                anchors.centerIn: parent
                                width: root.s(96); height: width; radius: width / 2
                                color: "transparent"
                                border.width: root.s(2); border.color: root.mauve
                                opacity: 0
                                SequentialAnimation {
                                    running: !root.unlocked && root.live; loops: Animation.Infinite
                                    PauseAnimation { duration: index * 1300 }
                                    ParallelAnimation {
                                        NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.0; duration: 2600; easing.type: Easing.OutCubic }
                                        NumberAnimation { target: ring; property: "opacity"; from: 0.5; to: 0; duration: 2600 }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.95; height: width; radius: width / 2
                            color: root.mauve; opacity: 0.07
                        }
                        // outer dial
                        Canvas {
                            id: dialOuter
                            anchors.centerIn: parent
                            width: root.s(182); height: width
                            rotation: root.dialRot
                            onWidthChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                var c = width / 2, r = c - 3;
                                ctx.strokeStyle = String(root.surface2); ctx.lineWidth = 1.5;
                                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke();
                                for (var i = 0; i < 72; i++) {
                                    var a = i * Math.PI / 36, major = i % 6 === 0;
                                    var r0 = r - (major ? 11 : 5);
                                    ctx.strokeStyle = String(major ? root.mauve : root.surface2);
                                    ctx.lineWidth = major ? 2 : 1;
                                    ctx.beginPath();
                                    ctx.moveTo(c + Math.cos(a) * r0, c + Math.sin(a) * r0);
                                    ctx.lineTo(c + Math.cos(a) * r, c + Math.sin(a) * r);
                                    ctx.stroke();
                                }
                            }
                        }
                        // inner dial
                        Canvas {
                            id: dialInner
                            anchors.centerIn: parent
                            width: root.s(140); height: width
                            rotation: -root.dialRot * 1.7
                            onWidthChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                var c = width / 2, r = c - 4;
                                ctx.lineCap = "round"; ctx.lineWidth = 3;
                                ctx.strokeStyle = String(root.blue); ctx.globalAlpha = 0.9;
                                ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 0.8); ctx.stroke();
                                ctx.strokeStyle = String(root.mauve); ctx.globalAlpha = 0.7;
                                ctx.beginPath(); ctx.arc(c, c, r, Math.PI * 1.0, Math.PI * 1.5); ctx.stroke();
                                ctx.strokeStyle = String(root.pink); ctx.globalAlpha = 0.5;
                                ctx.beginPath(); ctx.arc(c, c, r, Math.PI * 1.65, Math.PI * 1.85); ctx.stroke();
                            }
                        }
                        Rectangle {
                            id: burst
                            anchors.centerIn: parent
                            width: root.s(96); height: width; radius: width / 2
                            color: "transparent"; border.width: root.s(3); border.color: root.green
                            opacity: 0
                        }
                        Rectangle {
                            id: errFlash
                            anchors.centerIn: parent
                            width: root.s(110); height: width; radius: width / 2
                            color: "transparent"; border.width: root.s(3); border.color: root.red
                            opacity: 0
                            SequentialAnimation on opacity { id: errFlashAnim; running: false
                                NumberAnimation { to: 0.9; duration: 80 }
                                NumberAnimation { to: 0; duration: 520 }
                            }
                        }
                        Rectangle {
                            id: disc
                            anchors.centerIn: parent
                            width: root.s(96); height: width; radius: width / 2
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: root.mauve }
                                GradientStop { position: 1.0; color: root.blue }
                            }
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 1; radius: width / 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.28) }
                                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                                }
                            }
                        }
                        Canvas {
                            id: shackleCv
                            width: root.s(40); height: root.s(56)
                            x: (parent.width - width) / 2
                            y: (parent.height - root.s(96)) / 2 + root.s(6)
                            Connections { target: root; function onShackleChanged() { shackleCv.requestPaint(); } }
                            onWidthChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset();
                                var k = width / 40, lift = root.shackle;
                                ctx.translate(0, -lift * 8 * k);
                                ctx.strokeStyle = String(root.crust); ctx.lineWidth = 4.6 * k; ctx.lineCap = "round";
                                ctx.beginPath();
                                ctx.moveTo(9 * k, (46 + lift * 8) * k);
                                ctx.lineTo(9 * k, 24 * k);
                                ctx.arc(20 * k, 24 * k, 11 * k, Math.PI, 2 * Math.PI);
                                ctx.lineTo(31 * k, 46 * k);
                                ctx.stroke();
                            }
                        }
                        Rectangle {
                            x: (parent.width - width) / 2
                            y: (parent.height - root.s(96)) / 2 + root.s(48)
                            width: root.s(38); height: root.s(28); radius: root.s(7)
                            color: root.crust
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: root.s(7); width: root.s(7); height: width; radius: width / 2; color: root.mauve }
                            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: root.s(12); width: root.s(3); height: root.s(9); radius: width / 2; color: root.mauve }
                        }
                    }

                    Text {
                        id: lockTitle
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.phase === "setup" ? "Set up your vault" : "Vault"
                        color: root.text
                        font.family: root.fDisp; font.pixelSize: root.s(32); font.weight: Font.Bold
                        opacity: Math.min(1, Math.max(0, root.lockEnter * 1.7 - 0.25))
                        transform: Translate { y: (1 - lockTitle.opacity) * root.s(12) }
                    }
                    Text {
                        id: lockSub
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.phase === "boot" ? "Checking vault..."
                            : (root.phase === "setup" ? (root.setupMode === "create" ? "Choose a master password. It encrypts everything and cannot be recovered." : "Pull your encrypted vault down from the cloud.")
                            : (root.lockoutLeft > 0 ? "Locked out for a moment" : "Enter your master password to unlock"))
                        color: root.subtext0
                        font.family: root.fDisp; font.pixelSize: root.s(13)
                        opacity: Math.min(1, Math.max(0, root.lockEnter * 1.7 - 0.45))
                        transform: Translate { y: (1 - lockSub.opacity) * root.s(12) }
                    }

                    // --- locked ---
                    Field {
                        id: lockedField
                        width: parent.width
                        visible: root.phase === "locked"
                        enabled: root.lockoutLeft <= 0 && !root.unlockBusy
                        label: "MASTER PASSWORD"; secret: true
                        opacity: Math.min(1, Math.max(0, root.lockEnter * 1.7 - 0.65))
                        transform: Translate { y: (1 - lockedField.opacity) * root.s(12) }
                        onAccepted: root.unlock(text)
                        input.onTextChanged: if (text.length > 0 && root.lockoutLeft <= 0) root.errorText = ""
                        IconBtn { icon: lockedField.reveal ? "eyeoff" : "eye"; accent: root.mauve; width: root.s(32); height: root.s(32); onClicked: lockedField.reveal = !lockedField.reveal }
                    }
                    Btn {
                        id: unlockBtn
                        width: parent.width
                        visible: root.phase === "locked"
                        enabled: root.lockoutLeft <= 0 && !root.unlockBusy
                        label: root.lockoutLeft > 0 ? "Try again in " + root.lockoutLeft + "s" : (root.unlockBusy ? "Unlocking..." : "Unlock")
                        icon: root.unlockBusy ? "" : "key"
                        opacity: Math.min(1, Math.max(0, root.lockEnter * 1.7 - 0.85)) * (enabled ? 1 : 0.5)
                        transform: Translate { y: (1 - unlockBtn.opacity) * root.s(12) }
                        onClicked: root.unlock(lockedField.text)
                    }

                    // --- setup ---
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: root.s(8)
                        visible: root.phase === "setup"
                        Pill { label: "Create new vault"; on: root.setupMode === "create"; onClicked: { root.setupMode = "create"; root.errorText = ""; focusTimer.restart(); } }
                        Pill { label: "Restore from cloud"; on: root.setupMode === "restore"; onClicked: { root.setupMode = "restore"; root.errorText = ""; focusTimer.restart(); } }
                    }
                    Field { id: cMaster; input.onTextChanged: root.errorText = ""; width: parent.width; visible: root.phase === "setup" && root.setupMode === "create"; label: "MASTER PASSWORD (12+ CHARACTERS)"; secret: true; onAccepted: cConfirm.input.forceActiveFocus() }
                    Strength { visible: root.phase === "setup" && root.setupMode === "create"; anchors.horizontalCenter: parent.horizontalCenter; score: root.strengthOf(cMaster.text) }
                    Field { id: cConfirm; input.onTextChanged: root.errorText = ""; width: parent.width; visible: root.phase === "setup" && root.setupMode === "create"; label: "REPEAT MASTER PASSWORD"; secret: true; bad: cConfirm.text.length > 0 && cConfirm.text !== cMaster.text; onAccepted: root.createVault() }
                    Btn { width: parent.width; visible: root.phase === "setup" && root.setupMode === "create"; label: root.unlockBusy ? "Creating..." : "Create vault"; icon: root.unlockBusy ? "" : "shield"; enabled: !root.unlockBusy; accent: root.green; onClicked: root.createVault() }

                    Field { id: rEmail; input.onTextChanged: root.errorText = ""; width: parent.width; visible: root.phase === "setup" && root.setupMode === "restore" && !root.loggedIn; label: "CLOUD EMAIL"; onAccepted: rPass.input.forceActiveFocus() }
                    Field { id: rPass; width: parent.width; visible: root.phase === "setup" && root.setupMode === "restore" && !root.loggedIn; label: "CLOUD PASSWORD"; secret: true; onAccepted: rMaster.input.forceActiveFocus() }
                    Field { id: rMaster; input.onTextChanged: root.errorText = ""; width: parent.width; visible: root.phase === "setup" && root.setupMode === "restore"; label: "VAULT MASTER PASSWORD"; secret: true; onAccepted: root.restoreVault() }
                    Btn { width: parent.width; visible: root.phase === "setup" && root.setupMode === "restore"; label: root.unlockBusy ? "Restoring..." : "Restore vault"; icon: root.unlockBusy ? "" : "cloud"; enabled: !root.unlockBusy; accent: root.blue; onClicked: root.restoreVault() }

                    Text {
                        width: parent.width
                        visible: root.errorText.length > 0 || root.lockoutLeft > 0
                        text: root.lockoutLeft > 0 ? "Too many wrong attempts. Wait " + root.lockoutLeft + "s." : root.errorText
                        color: root.lockoutLeft > 0 ? root.peach : root.red
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        font.family: root.fDisp; font.pixelSize: root.s(13)
                    }
                }

                SequentialAnimation {
                    id: shake
                    ScriptAction { script: errFlashAnim.restart() }
                    NumberAnimation { target: shiftT; property: "x"; to: -root.s(14); duration: 50 }
                    NumberAnimation { target: shiftT; property: "x"; to: root.s(14); duration: 80 }
                    NumberAnimation { target: shiftT; property: "x"; to: -root.s(9); duration: 70 }
                    NumberAnimation { target: shiftT; property: "x"; to: root.s(5); duration: 60 }
                    NumberAnimation { target: shiftT; property: "x"; to: 0; duration: 50 }
                }
            }
        }

        // ===================== toast =====================
        Rectangle {
            id: toastBox
            z: 40
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            readonly property bool busyShow: root.busyText.length > 0
            anchors.bottomMargin: (busyShow || root.toastText.length > 0) ? root.s(18) : -root.s(70)
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
            readonly property color kc: busyShow ? root.blue : root.toastKind === "ok" ? root.green : (root.toastKind === "err" ? root.red : (root.toastKind === "warn" ? root.peach : root.mauve))
            height: root.s(42)
            width: Math.min(card.width - root.s(40), trow.implicitWidth + root.s(34))
            radius: height / 2
            color: root.surface2
            border.width: 1; border.color: toastBox.kc
            Row {
                id: trow
                anchors.centerIn: parent
                spacing: root.s(9)
                Icon {
                    visible: toastBox.busyShow
                    name: "sync"; col: toastBox.kc; sz: root.s(16); anchors.verticalCenter: parent.verticalCenter
                    RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: toastBox.busyShow && root.live }
                }
                Icon { visible: !toastBox.busyShow; name: root.toastKind === "ok" ? "check" : (root.toastKind === "info" ? "shield" : "warn"); col: toastBox.kc; sz: root.s(16); anchors.verticalCenter: parent.verticalCenter }
                Text { id: tt; text: toastBox.busyShow ? root.busyText : root.toastText; color: root.text; elide: Text.ElideRight; width: Math.min(implicitWidth, card.width - root.s(120)); anchors.verticalCenter: parent.verticalCenter; font.family: root.fDisp; font.pixelSize: root.s(13) }
            }
        }
    }
}
