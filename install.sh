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

RC_FILE="$(detect_shell_rc)"

# Check 1: is QML_BASE_DIR already written in the rc file?
RC_HAS_PATH=false
if [[ -f "${RC_FILE}" ]] && grep -qF "${QML_BASE_DIR}" "${RC_FILE}" 2>/dev/null; then
    RC_HAS_PATH=true
fi

# Check 2: is it active in the current session?
SESSION_HAS_PATH=false
if [[ ":${QML2_IMPORT_PATH:-}:" == *":${QML_BASE_DIR}:"* ]]; then
    SESSION_HAS_PATH=true
fi

if [[ "${RC_HAS_PATH}" == true && "${SESSION_HAS_PATH}" == true ]]; then
    # All good — nothing to do
    echo "✅ QML2_IMPORT_PATH already configured (${RC_FILE} + current session)"

elif [[ "${RC_HAS_PATH}" == true && "${SESSION_HAS_PATH}" == false ]]; then
    # Written in rc but not active yet (fresh install, not relogged yet)
    echo "✅ QML2_IMPORT_PATH already present in ${RC_FILE}"
    echo "ℹ️  Setting it for the current session as well..."
    export QML2_IMPORT_PATH="${QML_BASE_DIR}:${QML2_IMPORT_PATH:-}"
    echo "✅ Set for current session: ${QML2_IMPORT_PATH}"
    echo ""
    echo "⚠️  Remember: a KDE session logout/relogin is needed for plasmashell"
    echo "   to pick it up automatically on next boot."

else
    # Not in rc file — ask the user
    if [[ "${SESSION_HAS_PATH}" == false ]]; then
        echo "⚠️  QML2_IMPORT_PATH does not contain ${QML_BASE_DIR}"
    else
        echo "⚠️  QML2_IMPORT_PATH is set in the current session but not in ${RC_FILE}"
        echo "   (it would be lost on next login)"
    fi
    echo ""
    echo "ℹ️  The C++ QML plugin is installed in:"
    echo "     ${QML_BASE_DIR}"
    echo "   KDE Plasma (plasmashell) needs this path set before it starts."
    echo ""
    echo "   The following line would be added to ${RC_FILE}:"
    echo "     export QML2_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML2_IMPORT_PATH:-}\""
    echo ""
    read -r -p "   Add it automatically to ${RC_FILE}? [y/N] " REPLY
    echo ""

    if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
        append_env_to_rc "${RC_FILE}"
        echo "✅ Added QML2_IMPORT_PATH to ${RC_FILE}"
        echo ""
        echo "⚠️  IMPORTANT: A KDE session logout/relogin (or reboot) is required"
        echo "   for plasmashell to start with the new variable."
        echo "   Running 'source ${RC_FILE}' in a terminal is NOT enough."
    else
        echo "ℹ️  Skipped. Add it manually:"
        echo "     echo 'export QML2_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML2_IMPORT_PATH:-}\"' >> ${RC_FILE}"
    fi

    # Always export for the current session regardless of user choice
    export QML2_IMPORT_PATH="${QML_BASE_DIR}:${QML2_IMPORT_PATH:-}"
    echo ""
    echo "ℹ️  QML2_IMPORT_PATH set for the current shell session:"
    echo "     ${QML2_IMPORT_PATH}"
    echo "   You can test immediately with: plasmashell --replace &"
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
