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

# ---------------------------------------------------------------------------
# Helper: detect the user's shell rc file
# ---------------------------------------------------------------------------
detect_shell_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    case "${shell_name}" in
        zsh)  echo "${HOME}/.zshrc" ;;
        fish) echo "${HOME}/.config/fish/config.fish" ;;
        ksh)  echo "${HOME}/.kshrc" ;;
        *)    echo "${HOME}/.bashrc" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: append QML2_IMPORT_PATH export to a shell rc file
# ---------------------------------------------------------------------------
append_env_to_rc() {
    local rc_file="$1"
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"

    if [[ "${shell_name}" == "fish" ]]; then
        # fish uses set -gx instead of export
        echo "" >> "${rc_file}"
        echo "# Added by matrixrain-plasma6 install.sh" >> "${rc_file}"
        echo "set -gx QML2_IMPORT_PATH ${QML_BASE_DIR} \$QML2_IMPORT_PATH" >> "${rc_file}"
    else
        echo "" >> "${rc_file}"
        echo "# Added by matrixrain-plasma6 install.sh" >> "${rc_file}"
        echo "export QML2_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML2_IMPORT_PATH:-}\"" >> "${rc_file}"
    fi
}

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
# [5/6] QML2_IMPORT_PATH check
# ---------------------------------------------------------------------------
echo "[5/6] Checking QML2_IMPORT_PATH..."

NEEDS_ENV=false

# Check if the variable is set AND already contains our path
if [[ -z "${QML2_IMPORT_PATH:-}" ]]; then
    echo "⚠️  QML2_IMPORT_PATH is not set."
    NEEDS_ENV=true
elif [[ ":${QML2_IMPORT_PATH}:" != *":${QML_BASE_DIR}:"* ]]; then
    echo "⚠️  QML2_IMPORT_PATH is set but does not contain ${QML_BASE_DIR}."
    echo "   Current value: ${QML2_IMPORT_PATH}"
    NEEDS_ENV=true
else
    echo "✅ QML2_IMPORT_PATH already contains ${QML_BASE_DIR}"
fi

if [[ "${NEEDS_ENV}" == true ]]; then
    RC_FILE="$(detect_shell_rc)"
    echo ""
    echo "ℹ️  The C++ QML plugin is installed in:"
    echo "     ${QML_BASE_DIR}"
    echo ""
    echo "   KDE Plasma (plasmashell) must be started with:"
    echo "     export QML2_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML2_IMPORT_PATH}\""
    echo "   for the wallpaper plugin to be found."
    echo ""
    echo "   This line can be added to your shell config: ${RC_FILE}"
    echo ""
    read -r -p "   Add it automatically to ${RC_FILE}? [y/N] " REPLY
    echo ""

    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        append_env_to_rc "${RC_FILE}"
        echo "✅ Added QML2_IMPORT_PATH export to ${RC_FILE}"
        echo ""
        echo "⚠️  IMPORTANT: The new environment variable will only take effect"
        echo "   after you log out and back in to your KDE session (or reboot)."
        echo "   A simple 'source ${RC_FILE}' is NOT enough because plasmashell"
        echo "   is started by the KDE session manager before your shell rc is read."
    else
        echo "ℹ️  Skipped. You can add it manually:"
        echo "     echo 'export QML2_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML2_IMPORT_PATH:-}\"' >> ${RC_FILE}"
    fi

    # Always export for the current shell session so install can be tested immediately
    export QML2_IMPORT_PATH="${QML_BASE_DIR}:${QML2_IMPORT_PATH:-}"
    echo ""
    echo "ℹ️  QML2_IMPORT_PATH has been set for the CURRENT shell session:"
    echo "     ${QML2_IMPORT_PATH}"
    echo "   You can test the wallpaper now by running:"
    echo "     plasmashell --replace &"
    echo "   In a new terminal or after relogin it will work automatically."
fi

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
