#!/bin/bash

# Script to disable Qt Virtual Keyboard at login screen and in Hyprland
# This prevents the onscreen keyboard from appearing when typing password

echo "Disabling Qt Virtual Keyboard..."

# Update SDDM configuration to disable virtual keyboard at login
SDDM_CONF="/etc/sddm.conf.d/10-wayland-matugen.conf"
if [ -f "$SDDM_CONF" ]; then
    sudo cp "$SDDM_CONF" "$SDDM_CONF.backup"
    sudo tee "$SDDM_CONF" > /dev/null <<EOF
[Theme]
Current=matugen-minimal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QT_IM_MODULE= QT_VIRTUALKEYBOARD_DISABLE=1
EOF
    echo "Updated SDDM configuration"
fi

# Update Hyprland environment configuration
ENV_CONF="\$HOME/.config/hypr/config/env.conf"
if [ -f "$ENV_CONF" ]; then
    cp "$ENV_CONF" "$ENV_CONF.backup"
    tee "$ENV_CONF" > /dev/null <<EOF
# === DOTFILES AUTO-INJECTED ENV ===
env = XDG_PICTURES_DIR,\$HOME/Pictures
env = XDG_VIDEOS_DIR,\$HOME/Videos
env = WALLPAPER_DIR,\$HOME/Pictures/Wallpapers
env = SCRIPT_DIR,\$HOME/.config/hypr/scripts
env = QT_QPA_PLATFORMTHEME,qt6ct
# Disable Qt Virtual Keyboard
env = QT_IM_MODULE,
env = GTK_IM_MODULE,
env = QT_QPA_PLATFORM_PLUGIN_PATH,
env = QT_VIRTUALKEYBOARD_DISABLE,1
# === END DOTFILES ENV ===
EOF
    echo "Updated Hyprland environment configuration"
fi

echo "Virtual keyboard disabled. Restart SDDM or reboot to apply changes."
