#!/bin/bash

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ KEYBIND TEST SCRIPT
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "🔧 Testing Keybinds..."
echo "====================="

# Test basic functionality
echo "📋 Testing basic keybind functionality..."

# Test web browser (SUPER+B)
echo "🌐 Testing SUPER+B (Web Browser)..."
if command -v xdg-open &> /dev/null; then
    echo "✅ xdg-open found - web browser keybind should work"
else
    echo "❌ xdg-open not found - web browser keybind may fail"
fi

# Test terminal
echo "💻 Testing terminal availability..."
if [ -n "$TERM" ]; then
    echo "✅ Terminal variable set: $TERM"
else
    echo "⚠️  TERM variable not set"
fi

# Test file manager
echo "📁 Testing file manager..."
if command -v thunar &> /dev/null; then
    echo "✅ Thunar found"
elif command -v nautilus &> /dev/null; then
    echo "✅ Nautilus found"
elif command -v dolphin &> /dev/null; then
    echo "✅ Dolphin found"
else
    echo "⚠️  No common file manager found"
fi

# Test scripts directory
echo "📂 Testing scripts directory..."
if [ -d "$HOME/.config/hypr/scripts" ]; then
    echo "✅ Scripts directory exists"
    script_count=$(find "$HOME/.config/hypr/scripts" -name "*.sh" | wc -l)
    echo "📄 Found $script_count shell scripts"
else
    echo "❌ Scripts directory not found"
fi

# Test QuickShell scripts
echo "🔧 Testing QuickShell manager script..."
if [ -f "$HOME/.config/hypr/scripts/qs_manager.sh" ]; then
    echo "✅ qs_manager.sh found"
else
    echo "❌ qs_manager.sh not found - QuickShell keybinds may fail"
fi

# Test common utility scripts
echo "🛠️  Testing utility scripts..."
scripts=(
    "Volume.sh"
    "ScreenShot.sh"
    "LockScreen.sh"
    "ThemeChanger.sh"
    "MediaCtrl.sh"
)

for script in "${scripts[@]}"; do
    if [ -f "$HOME/.config/hypr/scripts/$script" ]; then
        echo "✅ $script found"
    else
        echo "❌ $script not found"
    fi
done

# Test rofi
echo "🔍 Testing rofi..."
if command -v rofi &> /dev/null; then
    echo "✅ rofi found - app launcher and menus should work"
else
    echo "❌ rofi not found - many keybinds may fail"
fi

# Test swayosd-client
echo "🔊 Testing swayosd-client..."
if command -v swayosd-client &> /dev/null; then
    echo "✅ swayosd-client found - volume/brightness OSD should work"
else
    echo "❌ swayosd-client not found - OSD may not work"
fi

# Test playerctl
echo "🎵 Testing playerctl..."
if command -v playerctl &> /dev/null; then
    echo "✅ playerctl found - media controls should work"
else
    echo "❌ playerctl not found - media controls may fail"
fi

# Test hyprctl
echo "🖥️  Testing hyprctl..."
if command -v hyprctl &> /dev/null; then
    echo "✅ hyprctl found - Hyprland controls should work"
    # Test if Hyprland is running
    if pgrep -x "Hyprland" > /dev/null; then
        echo "✅ Hyprland is running"
    else
        echo "❌ Hyprland is not running"
    fi
else
    echo "❌ hyprctl not found - not in Hyprland environment"
fi

# Test firefox
echo "🦊 Testing firefox..."
if command -v firefox &> /dev/null; then
    echo "✅ firefox found - SUPER+F should work"
else
    echo "❌ firefox not found - SUPER+F may fail"
fi

# Test UserScripts directory
echo "📂 Testing UserScripts directory..."
if [ -d "$HOME/.config/hypr/UserScripts" ]; then
    echo "✅ UserScripts directory exists"
    user_script_count=$(find "$HOME/.config/hypr/UserScripts" -name "*.sh" | wc -l)
    echo "📄 Found $user_script_count user scripts"
else
    echo "❌ UserScripts directory not found"
fi

echo ""
echo "🎯 Keybind Summary:"
echo "=================="
echo "• SUPER+B = Web Browser (xdg-open)"
echo "• SUPER+A = App Launcher (rofi)"
echo "• SUPER+Return = Terminal"
echo "• SUPER+E = File Manager"
echo "• SUPER+Q = Close Window"
echo "• SUPER+F = Firefox"
echo "• Arrow Keys = Window Focus"
echo "• SUPER+Arrow = Move Window"
echo "• SUPER+SHIFT+Arrow = Resize Window"
echo "• Function Keys = Special Functions"
echo "• Media Keys = Volume/Media Control"
echo "• Print Screen = Screenshots"

echo ""
echo "📝 Test completed at $(date)"
echo "💡 If any tests failed, check the corresponding dependencies"
