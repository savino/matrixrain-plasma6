#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "====================================================="
echo "  Matrix Rain MQTT Wallpaper - Installation Script"
echo "====================================================="
echo ""

INSTALL_ENV=true
ASSUME_YES=false
for arg in "$@"; do
    case "${arg}" in
        --no-env-setup) INSTALL_ENV=false ;;
        --yes|-y) ASSUME_YES=true ;;
        --help|-h)
            echo "Usage: $0 [--yes] [--no-env-setup]"
            echo "  --yes            Configure the systemd user environment without prompting"
            echo "  --no-env-setup   Skip persistent QML import path configuration"
            exit 0
            ;;
        *)
            echo "Error: unknown option '${arg}'" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 2
            ;;
    esac
done

# Directories
PLUGIN_DIR="plugin"
PACKAGE_DIR="package"
PLUGIN_SOURCE_DIR="$(cd -- "${PLUGIN_DIR}" && pwd -P)"
BUILD_DIR="${PLUGIN_SOURCE_DIR}/build"
QML_BASE_DIR="${HOME}/.local/lib/qt6/qml"
PACKAGE_ID="obsidianreq.plasma.wallpaper.mqttrain"

# A build tree cannot be reused after its source tree has moved. Preserve a
# stale in-tree cache and use a checkout-specific cache under the user's cache.
if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
    CACHED_SOURCE_DIR="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "${BUILD_DIR}/CMakeCache.txt")"
    CACHED_BUILD_DIR="$(sed -n 's/^CMAKE_CACHEFILE_DIR:INTERNAL=//p' "${BUILD_DIR}/CMakeCache.txt")"
    if [[ "${CACHED_SOURCE_DIR}" != "${PLUGIN_SOURCE_DIR}" ||
          "${CACHED_BUILD_DIR}" != "${BUILD_DIR}" ]]; then
        BUILD_KEY="$(printf '%s' "${PLUGIN_SOURCE_DIR}" | sha256sum)"
        BUILD_KEY="${BUILD_KEY%% *}"
        BUILD_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/matrixrain-plasma6/build-${BUILD_KEY:0:16}"
        echo "⚠️  Ignoring a CMake cache from another checkout location."
        echo "   Using a fresh build directory: ${BUILD_DIR}"
    fi
fi

# systemd environment.d file for this plugin
ENV_D_DIR="${HOME}/.config/environment.d"
ENV_D_FILE="${ENV_D_DIR}/99-mqttrain-qt.conf"

# ---------------------------------------------------------------------------
# [1/6] Check required tools
# ---------------------------------------------------------------------------
echo "[1/6] Checking dependencies..."

if ! command -v cmake >/dev/null 2>&1; then
    echo "Error: cmake not found. Install with:"
    echo "   Arch/Manjaro: sudo pacman -S cmake"
    echo "   Debian/Ubuntu: sudo apt install cmake"
    exit 1
fi

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "Error: kpackagetool6 not found. Install KDE Plasma 6."
    exit 1
fi

echo "Build tools found. CMake will verify the Qt6 development dependencies."
echo ""

# ---------------------------------------------------------------------------
# [2/6] Build C++ plugin
# ---------------------------------------------------------------------------
echo "[2/6] Building C++ MQTT plugin..."
cmake -S "${PLUGIN_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${HOME}/.local" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DQT_QML_INSTALL_DIR=lib/qt6/qml
cmake --build "${BUILD_DIR}" --parallel
echo "✅ Plugin built successfully"
echo ""

# ---------------------------------------------------------------------------
# [3/6] Install C++ plugin
# ---------------------------------------------------------------------------
echo "[3/6] Installing C++ plugin..."
cmake --install "${BUILD_DIR}" --component Plugin
echo "✅ Plugin installed under ${QML_BASE_DIR}"
echo ""

# ---------------------------------------------------------------------------
# [4/6] Install wallpaper package
# ---------------------------------------------------------------------------
echo "[4/6] Installing wallpaper package..."
if kpackagetool6 --type Plasma/Wallpaper --show "${PACKAGE_ID}" >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Wallpaper --upgrade "${PACKAGE_DIR}" || {
        echo "Error: failed to upgrade wallpaper package '${PACKAGE_ID}'." >&2
        exit 1
    }
else
    kpackagetool6 --type Plasma/Wallpaper --install "${PACKAGE_DIR}" || {
        echo "Error: failed to install wallpaper package '${PACKAGE_ID}'." >&2
        exit 1
    }
fi
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

if [[ "${INSTALL_ENV}" != true ]]; then
    echo "ℹ️  Skipped persistent systemd environment setup (--no-env-setup)"
else
    NEEDS_ENV_UPDATE=false
    for variable in QML_IMPORT_PATH QML2_IMPORT_PATH; do
        if [[ ! -f "${ENV_D_FILE}" ]] ||
           ! grep -F "${variable}=" "${ENV_D_FILE}" | grep -Fq "${QML_BASE_DIR}"; then
            NEEDS_ENV_UPDATE=true
            break
        fi
    done

    if [[ "${NEEDS_ENV_UPDATE}" != true ]]; then
        echo "✅ ${ENV_D_FILE} already contains ${QML_BASE_DIR}"
    elif [[ "${ASSUME_YES}" == true ]] || {
        read -r -p "   Add ${QML_BASE_DIR} to ${ENV_D_FILE}? [y/N] " REPLY
        [[ "${REPLY}" =~ ^[Yy]$ ]]
    }; then
        mkdir -p "${ENV_D_DIR}"
        touch "${ENV_D_FILE}"
        printf '\n' >> "${ENV_D_FILE}"
        for variable in QML_IMPORT_PATH QML2_IMPORT_PATH; do
            if ! grep -F "${variable}=" "${ENV_D_FILE}" | grep -Fq "${QML_BASE_DIR}"; then
                printf '%s=%s${%s:+:${%s}}\n' \
                    "${variable}" "${QML_BASE_DIR}" "${variable}" "${variable}" >> "${ENV_D_FILE}"
            fi
        done
        echo "✅ Updated ${ENV_D_FILE} without replacing its existing contents"
        echo ""
        if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reexec; then
            echo "✅ systemd user manager reloaded"
        else
            echo "⚠️  Could not reload the systemd user manager; log out and back in to apply the environment change."
        fi
        echo ""
        echo "⚠️  Log out and back in (or reboot) for plasmashell to inherit the updated environment."
    else
        echo "ℹ️  Skipped persistent environment setup."
        echo "   Re-run with --yes or configure ${ENV_D_FILE} manually."
    fi
fi

echo ""
CURRENT_SHELL="${SHELL##*/}"
PARENT_SHELL="$(ps -p "${PPID}" -o comm= 2>/dev/null | tr -d '[:space:]' || true)"
case "${PARENT_SHELL}" in
    bash|fish|zsh) CURRENT_SHELL="${PARENT_SHELL}" ;;
esac

echo "ℹ️  To test immediately in this terminal (${CURRENT_SHELL:-unknown} syntax), run:"
if [[ "${CURRENT_SHELL}" == fish ]]; then
    echo "   set -gx QML_IMPORT_PATH \"${QML_BASE_DIR}:\$QML_IMPORT_PATH\""
    echo "   set -gx QML2_IMPORT_PATH \"${QML_BASE_DIR}:\$QML2_IMPORT_PATH\""
else
    echo "   export QML_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML_IMPORT_PATH:-}\""
    echo "   export QML2_IMPORT_PATH=\"${QML_BASE_DIR}:\${QML2_IMPORT_PATH:-}\""
fi
echo "   plasmashell --replace &"

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
