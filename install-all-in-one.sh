#!/bin/bash

# All-in-One Installer for scezian/nixos-configuration
# Includes: Original setup + Spotify/Rambox/qBittorrent + Virtual Keyboard fix

set -e

echo "╔════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                    ◈ ALL-IN-ONE INSTALLER ◈                                            ║"
echo "║  Complete Hyprland Setup with Extra Apps & Virtual Keyboard Fix                          ║"
echo "╚════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root (which we should avoid)
if [ "$EUID" -eq 0 ]; then
    echo "❌ ERROR: Do NOT run this script as root!"
    echo "   This installer sends anonymous telemetry and should be run as a regular user."
    exit 1
fi

echo "🚀 Starting complete installation process..."
echo ""

# Phase 1: Run the modified installer with extra packages
echo "📦 Phase 1: Installing packages and configurations..."
echo "   - Original Hyprland setup"
echo "   - Spotify, Rambox, qBittorrent"
echo "   - All customizations and themes"
echo ""

if [ -f "./install-modified.sh" ]; then
    chmod +x ./install-modified.sh
    ./install-modified.sh
else
    echo "❌ ERROR: install-modified.sh not found!"
    exit 1
fi

echo ""
echo "✅ Phase 1 completed successfully!"
echo ""

# Phase 2: Apply virtual keyboard fix
echo "⌨️  Phase 2: Disabling Virtual Keyboard..."
echo "   - Prevent onscreen keyboard at login"
echo "   - Fix password field keyboard popup"
echo ""

# Apply virtual keyboard fix directly
echo "🔧 Updating SDDM configuration..."
SDDM_CONF="/etc/sddm.conf.d/10-wayland-matugen.conf"
if [ -f "$SDDM_CONF" ]; then
    sudo cp "$SDDM_CONF" "$SDDM_CONF.backup" 2>/dev/null || true
    sudo tee "$SDDM_CONF" > /dev/null <<EOF
[Theme]
Current=matugen-minimal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QT_IM_MODULE= QT_VIRTUALKEYBOARD_DISABLE=1
EOF
    echo "   ✅ SDDM configuration updated"
else
    echo "   ⚠️  SDDM config not found, creating new one..."
    sudo mkdir -p /etc/sddm.conf.d
    sudo tee "$SDDM_CONF" > /dev/null <<EOF
[Theme]
Current=matugen-minimal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QT_IM_MODULE= QT_VIRTUALKEYBOARD_DISABLE=1
EOF
    echo "   ✅ SDDM configuration created"
fi

echo "🔧 Updating Hyprland environment..."
ENV_CONF="$HOME/.config/hypr/config/env.conf"
if [ -f "$ENV_CONF" ]; then
    cp "$ENV_CONF" "$ENV_CONF.backup" 2>/dev/null || true
    mkdir -p "$(dirname "$ENV_CONF")"
    tee "$ENV_CONF" > /dev/null <<EOF
# === DOTFILES AUTO-INJECTED ENV ===
env = XDG_PICTURES_DIR,$HOME/Pictures
env = XDG_VIDEOS_DIR,$HOME/Videos
env = WALLPAPER_DIR,$HOME/Pictures/Wallpapers
env = SCRIPT_DIR,$HOME/.config/hypr/scripts
env = QT_QPA_PLATFORMTHEME,qt6ct
# Disable Qt Virtual Keyboard
env = QT_IM_MODULE,
env = GTK_IM_MODULE,
env = QT_QPA_PLATFORM_PLUGIN_PATH,
env = QT_VIRTUALKEYBOARD_DISABLE,1
# === END DOTFILES ENV ===
EOF
    echo "   ✅ Hyprland environment updated"
else
    echo "   ⚠️  Hyprland env config not found, skipping..."
fi

echo ""
echo "✅ Phase 2 completed successfully!"
echo ""

# Phase 3: Final setup and restart
echo "🔄 Phase 3: Final setup..."
echo ""

# Restart SDDM to apply changes immediately
echo "🔄 Restarting SDDM to apply virtual keyboard fix..."
if systemctl is-active sddm >/dev/null 2>&1; then
    echo "   SDDM is running, restarting to apply changes..."
    echo "   ⚠️  Your session will restart. Save any work!"
    echo "   Press Ctrl+C to cancel restart, or wait 5 seconds..."
    sleep 5
    sudo systemctl restart sddm
else
    echo "   ✅ SDDM changes applied (will take effect on next boot)"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                              🎉 INSTALLATION COMPLETE! 🎉                               ║"
echo "╚════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 What's been installed:"
echo "   ✅ Complete Hyprland desktop environment"
echo "   ✅ Custom themes, wallpapers, and configurations"
echo "   ✅ Spotify (spotify-launcher)"
echo "   ✅ Rambox (rambox-bin)"
echo "   ✅ qBittorrent"
echo "   ✅ Virtual keyboard disabled at login"
echo "   ✅ All keybinds and customizations"
echo ""
echo "🔑 Keybind reminder:"
echo "   • SUPER + SHIFT + K - Search keybinds"
echo "   • SUPER + Return - Terminal"
echo "   • SUPER + A - App launcher"
echo ""
echo "📱 Apps installed:"
echo "   • Spotify: Launch from app menu or terminal with 'spotify'"
echo "   • Rambox: Messaging app for multiple services"
echo "   • qBittorrent: Torrent client"
echo ""
echo "⚠️  IMPORTANT:"
echo "   • Log out and log back in if SDDM didn't restart automatically"
echo "   • Virtual keyboard is now disabled at login screen"
echo "   • All configurations are backed up with .backup extension"
echo ""
echo "🎯 Support:"
echo "   • GitHub: https://github.com/scezian/nixos-configuration"
echo "   • Issues: Report problems on GitHub repository"
echo ""
