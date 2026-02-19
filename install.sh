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
QML_BASE_DIR="${HOME}/.local/lib/qt6/qml"

# systemd environment.d file for this plugin
ENV_D_DIR="${HOME}/.config/environment.d"
ENV_D_FILE="${ENV_D_DIR}/99-mqttrain-qt.conf"

# ---------------------------------------------------------------------------
# [1/6] Check required tools
# ---------------------------------------------------------------------------
echo "[1/6] Checking dependencies..."

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

# ---------------------------------------------------------------------------
# [2/6] Build C++ plugin
# ---------------------------------------------------------------------------
echo "[2/6] Building C++ MQTT plugin..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${HOME}/.local"
make -j$(nproc)

cd ../..
echo "✅ Plugin built successfully"
echo ""

# ---------------------------------------------------------------------------
# [3/6] Install C++ plugin
# ---------------------------------------------------------------------------
echo "[3/6] Installing C++ plugin..."
mkdir -p "${QML_INSTALL_DIR}"
cp "${BUILD_DIR}/libmqttrainplugin.so" "${QML_INSTALL_DIR}/"
cp "${PLUGIN_DIR}/qmldir" "${QML_INSTALL_DIR}/"
echo "✅ Plugin installed to ${QML_INSTALL_DIR}"
echo ""

# ---------------------------------------------------------------------------
# [4/6] Install wallpaper package
# ---------------------------------------------------------------------------
echo "[4/6] Installing wallpaper package..."
kpackagetool6 --type Plasma/Wallpaper --remove obsidianreq.plasma.wallpaper.mqttrain 2>/dev/null || true
kpackagetool6 --type Plasma/Wallpaper --install "${PACKAGE_DIR}" || \
    kpackagetool6 --type Plasma/Wallpaper --upgrade "${PACKAGE_DIR}"
echo "✅ Wallpaper package installed"
echo ""

# ---------------------------------------------------------------------------
# [5/6] QML import path — systemd user environment
#
# plasmashell is launched by systemd --user and does NOT read ~/.bashrc or
# ~/.zshrc. The correct way to set environment variables for systemd user
# services is via ~/.config/environment.d/*.conf, which systemd reads before
# starting any user service.
# ---------------------------------------------------------------------------
echo "[5/6] Configuring QML import path for systemd user services..."

mkdir -p "${ENV_D_DIR}"

# Check if the path is already present in the environment.d file
if [[ -f "${ENV_D_FILE}" ]] && grep -qF "${QML_BASE_DIR}" "${ENV_D_FILE}" 2>/dev/null; then
    echo "✅ ${ENV_D_FILE} already contains ${QML_BASE_DIR} — nothing to do"
else
    echo ""
    echo "⚠️  The C++ QML plugin must be discoverable by plasmashell at startup."
    echo "   plasmashell is started by systemd --user and does NOT read your shell"
    echo "   rc files (∾zshrc, ∾bashrc, etc.), so the path must be declared in:"
    echo "     ${ENV_D_FILE}"
    echo ""
    echo "   The following lines would be written to that file:"
    echo "     QML_IMPORT_PATH=${QML_BASE_DIR}:\${QML_IMPORT_PATH:+:\${QML_IMPORT_PATH}}"
    echo "     QML2_IMPORT_PATH=${QML_BASE_DIR}:\${QML2_IMPORT_PATH:+:\${QML2_IMPORT_PATH}}"
    echo ""
    read -r -p "   Write ${ENV_D_FILE}? [y/N] " REPLY
    echo ""

    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        cat > "${ENV_D_FILE}" << EOF
# Added by matrixrain-plasma6 install.sh
# Expose user-installed Qt QML plugins to systemd user services (plasmashell).
# QML_IMPORT_PATH is the current Qt 6 variable; QML2_IMPORT_PATH is kept for compatibility.
QML_IMPORT_PATH=${QML_BASE_DIR}\${QML_IMPORT_PATH:+:\${QML_IMPORT_PATH}}
QML2_IMPORT_PATH=${QML_BASE_DIR}\${QML2_IMPORT_PATH:+:\${QML2_IMPORT_PATH}}
EOF
        echo "✅ Written ${ENV_D_FILE}"
        echo ""

        echo "ℹ️  Reloading systemd user manager..."
        systemctl --user daemon-reexec 2>/dev/null && echo "✅ daemon-reexec done" || echo "⚠️  daemon-reexec failed (non-fatal)"
        echo ""
        echo "⚠️  IMPORTANT: You must log out and log back in (or reboot) so that"
        echo "   plasmashell restarts with the updated environment."
        echo "   Running 'source ~/.zshrc' in a terminal is NOT enough."
    else
        echo "ℹ️  Skipped. To fix manually:"
        echo "   mkdir -p ${ENV_D_DIR}"
        echo "   cat >> ${ENV_D_FILE} << 'EOF'"
        echo "   QML_IMPORT_PATH=${QML_BASE_DIR}\${QML_IMPORT_PATH:+:\${QML_IMPORT_PATH}}"
        echo "   QML2_IMPORT_PATH=${QML_BASE_DIR}\${QML2_IMPORT_PATH:+:\${QML2_IMPORT_PATH}}"
        echo "   EOF"
        echo "   systemctl --user daemon-reexec"
    fi
fi

# Always export both variables for the current shell session so you can test
# immediately without logging out (e.g. plasmashell --replace &)
export QML_IMPORT_PATH="${QML_BASE_DIR}:${QML_IMPORT_PATH:-}"
export QML2_IMPORT_PATH="${QML_BASE_DIR}:${QML2_IMPORT_PATH:-}"
echo ""
echo "ℹ️  Set for the CURRENT shell session:"
echo "   QML_IMPORT_PATH=${QML_IMPORT_PATH}"
echo "   You can test immediately with: plasmashell --replace &"

echo ""

# ---------------------------------------------------------------------------
# [6/6] Done
# ---------------------------------------------------------------------------
echo "[6/6] Installation complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Right-click on desktop → Configure Desktop and Wallpaper"
echo "  2. Select 'Matrix Rain MQTT' from the wallpaper list"
echo "  3. Configure MQTT settings (host, port, topic, credentials)"
echo "  4. Enable debug overlay to verify connection"
echo ""
echo "🔧 To restart Plasma Shell manually:"
echo "   kquitapp6 plasmashell && kstart plasmashell &"
echo ""
echo "✅ Installation successful!"
