import QtQuick
import Quickshell
import Quickshell.Io

// Runs lookup.py <mode> <arg>; only the latest request's result is delivered.
Item {
    id: lp
    property string mode: "word"
    property string want: ""
    property string cur: ""
    property bool busy: false
    signal result(var data, string arg)

    readonly property string py: Quickshell.env("HOME") + "/.local/share/qs-venv/bin/python"
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/translate/lookup.py"

    function request(arg) { want = arg; if (!proc.running) kick(); }
    function kick() { cur = want; busy = true; proc.command = [py, script, mode, cur]; proc.running = true; }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                if (lp.cur !== lp.want) return;
                try { lp.result(JSON.parse(this.text), lp.cur); }
                catch (e) { lp.result({ error: "parse" }, lp.cur); }
            }
        }
        onExited: { if (lp.cur !== lp.want) lp.kick(); else lp.busy = false; }
    }
}
