#!/usr/bin/env bash

echo "====================================================="
echo "  MQTT Rain Plugin - Debug Information"
echo "====================================================="
echo ""

USER_PLUGIN_DIR="${HOME}/.local/lib/qt6/qml/ObsidianReq/MQTTRain"
SYSTEM_QML_DIR=""
if command -v qmake6 >/dev/null 2>&1; then
    SYSTEM_QML_DIR="$(qmake6 -query QT_INSTALL_QML 2>/dev/null || true)"
fi

PLUGIN_DIR="${USER_PLUGIN_DIR}"
for candidate in \
    "${USER_PLUGIN_DIR}" \
    "${SYSTEM_QML_DIR}/ObsidianReq/MQTTRain" \
    "/usr/lib/qt6/qml/ObsidianReq/MQTTRain" \
    "/usr/lib/x86_64-linux-gnu/qt6/qml/ObsidianReq/MQTTRain"; do
    if [ -d "${candidate}" ]; then
        PLUGIN_DIR="${candidate}"
        break
    fi
done

echo "[1] Plugin Installation"
echo "────────────────────────────────────────────────────"
if [ -d "$PLUGIN_DIR" ]; then
    echo "✅ Plugin directory exists: $PLUGIN_DIR"
    echo ""
    echo "Files:"
    ls -lah "$PLUGIN_DIR"
    echo ""
else
    echo "❌ Plugin directory NOT found: $PLUGIN_DIR"
    echo "   Run ./install.sh first"
    exit 1
fi

echo "[2] Plugin Library Check"
echo "────────────────────────────────────────────────────"
if [ -f "$PLUGIN_DIR/libmqttrainplugin.so" ]; then
    echo "✅ libmqttrainplugin.so found"
    
    echo "   Permissions: $(stat -c '%A' "$PLUGIN_DIR/libmqttrainplugin.so")"
    echo "   Size: $(stat -c '%s' "$PLUGIN_DIR/libmqttrainplugin.so") bytes"
    echo ""
    
    echo "   Library dependencies:"
    ldd "$PLUGIN_DIR/libmqttrainplugin.so" | grep -E '(Qt6|mosquitto)' || echo "   (showing Qt6 and mqtt deps only)"
    echo ""
else
    echo "❌ libmqttrainplugin.so NOT found"
fi

if [ -f "$PLUGIN_DIR/qmldir" ]; then
    echo "✅ qmldir found"
    echo "   Contents:"
    cat "$PLUGIN_DIR/qmldir" | sed 's/^/      /'
    echo ""
else
    echo "❌ qmldir NOT found"
fi

echo "[3] QML Import Paths"
echo "────────────────────────────────────────────────────"
echo "QML2_IMPORT_PATH environment variable:"
if [ -z "$QML2_IMPORT_PATH" ]; then
    echo "   (not set - using Qt defaults)"
else
    echo "   $QML2_IMPORT_PATH"
fi
echo ""

echo "Standard QML import locations:"
for path in "$HOME/.local/lib/qt6/qml" "$SYSTEM_QML_DIR" \
    "/usr/lib/qt6/qml" "/usr/lib/x86_64-linux-gnu/qt6/qml" "/usr/local/lib/qt6/qml"; do
    [ -n "$path" ] || continue
    if [ -d "$path" ]; then
        echo "   ✅ $path"
    else
        echo "   ❌ $path (doesn't exist)"
    fi
done
echo ""

echo "[4] Qt6 Configuration"
echo "────────────────────────────────────────────────────"
if command -v qmake6 >/dev/null 2>&1; then
    echo "qmake6 version:"
    qmake6 --version | sed 's/^/   /'
    echo ""
    echo "Qt6 QML path:"
    qmake6 -query QT_INSTALL_QML | sed 's/^/   /'
else
    echo "❌ qmake6 not found"
fi
echo ""

echo "[5] Qt6 Mqtt Module"
echo "────────────────────────────────────────────────────"
if ldconfig -p | grep -q libQt6Mqtt; then
    echo "✅ Qt6 Mqtt library found:"
    ldconfig -p | grep libQt6Mqtt | sed 's/^/   /'
else
    echo "❌ Qt6 Mqtt library NOT found"
    echo "   Install with: sudo pacman -S qt6-mqtt"
fi
echo ""

echo "[6] Wallpaper Package"
echo "────────────────────────────────────────────────────"
WALLPAPER_DIR="${HOME}/.local/share/plasma/wallpapers/obsidianreq.plasma.wallpaper.mqttrain"
if [ ! -d "$WALLPAPER_DIR" ] && [ -d "/usr/share/plasma/wallpapers/obsidianreq.plasma.wallpaper.mqttrain" ]; then
    WALLPAPER_DIR="/usr/share/plasma/wallpapers/obsidianreq.plasma.wallpaper.mqttrain"
fi
if [ -d "$WALLPAPER_DIR" ]; then
    echo "✅ Wallpaper installed: $WALLPAPER_DIR"
    if [ -f "$WALLPAPER_DIR/contents/ui/main.qml" ]; then
        echo "   Main QML found"
        echo "   Import statement:"
        grep -n "import ObsidianReq.MQTTRain" "$WALLPAPER_DIR/contents/ui/main.qml" | sed 's/^/      /'
    fi
else
    echo "❌ Wallpaper NOT installed"
fi
echo ""

echo "[7] Suggested Actions"
echo "────────────────────────────────────────────────────"
if [ ! -f "$PLUGIN_DIR/libmqttrainplugin.so" ] || [ ! -f "$PLUGIN_DIR/qmldir" ]; then
    echo "⚠️  Plugin files missing. Run: ./install.sh"
fi

if ! ldconfig -p | grep -q libQt6Mqtt; then
    echo "⚠️  Qt6 Mqtt not installed. Run: sudo pacman -S qt6-mqtt"
fi

if [ -f "$PLUGIN_DIR/libmqttrainplugin.so" ]; then
    perms=$(stat -c '%a' "$PLUGIN_DIR/libmqttrainplugin.so")
    if [ "$perms" != "755" ] && [ "$perms" != "775" ]; then
        echo "⚠️  Fix plugin permissions: chmod 755 $PLUGIN_DIR/libmqttrainplugin.so"
    fi
fi

echo ""
echo "💡 To test QML import manually:"
echo "   export QML2_IMPORT_PATH=$HOME/.local/lib/qt6/qml:\$QML2_IMPORT_PATH"
echo "   kquitapp6 plasmashell && kstart plasmashell &"
echo ""
echo "📋 View plasma logs:"
echo "   journalctl -f --user | grep -i 'mqttrain\|ObsidianReq'"
echo ""
