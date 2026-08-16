-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--  ◈ AUTOSTART
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    -- [hyprpanel] hl.exec_cmd("hypridle")
    hl.exec_cmd("playerctld")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("systemctl --user enable --now easyeffects")
    hl.exec_cmd("bash ~/.config/hypr/scripts/settings_watcher.sh")
    hl.exec_cmd("bash ~/.config/hypr/scripts/volume_listener.sh")
    hl.exec_cmd("bash ~/.config/hypr/scripts/firefox_profile_link.sh")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme 'ArcMidnight-Cursors'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size 24")
    hl.exec_cmd("swayosd-server")
    hl.exec_cmd("quickshell -p ~/.config/hypr/scripts/quickshell/Main.qml")
    hl.exec_cmd("quickshell -p ~/.config/hypr/scripts/quickshell/TopBar.qml")
    hl.exec_cmd("quickshell -p ~/.config/hypr/scripts/quickshell/Floating.qml")
    hl.exec_cmd("python3 ~/.config/hypr/scripts/quickshell/focustime/focus_daemon.py")
end)
