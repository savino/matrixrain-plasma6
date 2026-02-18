#!/usr/bin/env bash
set -euo pipefail

echo "====================================================="
echo "  Matrix Rain MQTT Wallpaper - Installation Script"
echo "====================================================="
echo ""

# Directories
PLUGIN_DIR="plugin"
PACKAGE_DIR="package"
BUILD_DIR="${PLUGIN_DIR}/build"
QML_INSTALL_DIR="${HOME}/.local/lib/qt6/qml/ObsidianReq/MQTTRain"

# Check required tools
echo "[1/5] Checking dependencies..."

if ! command -v cmake >/dev/null 2>&1; then
    echo "❌ Error: cmake not found. Install with:"
    echo "   Arch/Manjaro: sudo pacman -S cmake"
    echo "   Debian/Ubuntu: sudo apt install cmake"
    exit 1
fi

if ! command -v qmake6 >/dev/null 2>&1 && ! command -v qmake >/dev/null 2>&1; then
    echo "❌ Error: Qt6 not found. Install with:"
    echo "   Arch/Manjaro: sudo pacman -S qt6-base qt6-declarative"
    echo "   Debian/Ubuntu: sudo apt install qt6-base-dev qt6-declarative-dev"
    exit 1
fi

# Check for Qt6 Mqtt module
if ! ldconfig -p | grep -q libQt6Mqtt && ! find /usr/lib* -name "libQt6Mqtt.so*" 2>/dev/null | grep -q .; then
    echo "❌ Error: Qt6 Mqtt module not found. Install with:"
    echo "   Arch/Manjaro: sudo pacman -S qt6-mqtt"
    echo "   Debian/Ubuntu: sudo apt install libqt6mqtt6-dev"
    echo "   Fedora: sudo dnf install qt6-qtmqtt-devel"
    exit 1
fi

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "❌ Error: kpackagetool6 not found. Install KDE Plasma 6."
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Build C++ plugin
echo "[2/5] Building C++ MQTT plugin..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${HOME}/.local"
if [ $? -ne 0 ]; then
    echo "❌ CMake configuration failed"
    exit 1
fi

make -j$(nproc)
if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

cd ../..
echo "✅ Plugin built successfully"
echo ""

# Install C++ plugin
echo "[3/5] Installing C++ plugin..."
mkdir -p "${QML_INSTALL_DIR}"
cp "${BUILD_DIR}/libmqttrainplugin.so" "${QML_INSTALL_DIR}/"
cp "${PLUGIN_DIR}/qmldir" "${QML_INSTALL_DIR}/"
echo "✅ Plugin installed to ${QML_INSTALL_DIR}"
echo ""

# Install wallpaper package
echo "[4/5] Installing wallpaper package..."
kpackagetool6 --type Plasma/Wallpaper --remove obsidianreq.plasma.wallpaper.mqttrain 2>/dev/null || true
kpackagetool6 --type Plasma/Wallpaper --install "${PACKAGE_DIR}" || \
    kpackagetool6 --type Plasma/Wallpaper --upgrade "${PACKAGE_DIR}"

if [ $? -ne 0 ]; then
    echo "❌ Wallpaper installation failed"
    exit 1
fi
echo "✅ Wallpaper package installed"
echo ""

# Restart Plasma (optional)
echo "[5/5] Installation complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Right-click on desktop → Configure Desktop and Wallpaper"
echo "  2. Select 'Matrix Rain MQTT' from the wallpaper list"
echo "  3. Configure MQTT settings (host, port, topic, credentials)"
echo "  4. Enable debug overlay to verify connection"
echo ""
echo "🔧 To restart Plasma Shell (if wallpaper doesn't appear):"
echo "   kquitapp6 plasmashell && kstart plasmashell &"
echo ""
echo "📖 Configuration:"
echo "   Host: homeassistant.lan (or your MQTT broker)"
echo "   Port: 1883 (standard MQTT port)"
echo "   Topic: zigbee2mqtt/# (or your desired topic)"
echo ""
echo "💡 Note: Uses Qt6 Mqtt module (not WebSocket)"
echo "   Connects directly to standard MQTT port 1883"
echo ""
echo "✅ Installation successful!"
