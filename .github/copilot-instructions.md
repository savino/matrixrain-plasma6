# Copilot Instructions — matrixrain-plasma6

## Big Picture
- This project is a KDE Plasma 6 wallpaper with a native Qt QML plugin for MQTT (`plugin/`) and QML UI/renderers (`package/contents/ui/`).
- Runtime path: MQTT broker → `MQTTClient` (C++) → `messageReceived(topic, payload)` → active QML renderer → `MatrixCanvas` paint loop.
- Main orchestration is in `package/contents/ui/main.qml`; `MatrixCanvas.qml` is renderer-agnostic and delegates drawing to `activeRenderer`.
- Renderer strategy files live in `package/contents/ui/renderers/` (`Classic`, `Mixed`, `MqttOnly`, `MqttDriven`).

## Critical Runtime Constraint
- QML plugin discovery depends on systemd user environment, not shell rc files.
- `install.sh` writes `~/.config/environment.d/99-mqttrain-qt.conf` with `QML_IMPORT_PATH`/`QML2_IMPORT_PATH` and runs `systemctl --user daemon-reexec`.
- A fresh login/reboot is required for plasmashell to inherit that environment.

## Developer Workflows
- Full install: `./install.sh` (builds plugin, installs wallpaper package, configures environment.d).
- Rebuild plugin only: `cd plugin/build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local && make -j$(nproc)`.
- Reload package after QML/config changes: `kpackagetool6 --type Plasma/Wallpaper --upgrade package`.
- Debug checks: `./debug.sh`, `journalctl -f | grep -i mqttrain`, `systemctl --user show-environment | grep QML`.

## Project Conventions (Important)
- Config changes are 3-part and must stay aligned:
  1) schema in `package/contents/config/main.xml`
  2) `cfg_*` alias in `package/contents/ui/config.qml`
  3) property + `on*Changed` handling in `package/contents/ui/main.qml`
- Render-mode indices must stay synchronized between:
  - `main.qml` (`renderModeNames` + `activeRenderer` switch)
  - `config.qml` (`mqttRenderModeCombo.model` order)
  - `main.xml` (`mqttRenderMode` range/default)
- In renderers, avoid in-place array mutation for QML properties. Use clone → mutate → reassign for `columnAssignments` (see `package/contents/ui/ARCHITECTURE.md`).

## Data/Rendering Patterns
- Message parsing and JSON key/value highlighting are centralized in `package/contents/ui/utils/MatrixRainLogic.js` (`buildDisplayChars`, `colorJsonChars`).
- Value highlighting is done by `isValue` tags + `ColorUtils.lightenColor(...)`.
- `MatrixCanvas.qml` controls frame timing/fade and calls renderer interface methods:
  - `initializeColumns`, `renderColumnContent`, `onColumnWrap`, optional `renderInlineChars`.

## Integration Points
- QML import URI is fixed: `ObsidianReq.MQTTRain 1.0` (`plugin/plugin.cpp`, `plugin/qmldir`).
- `MQTTClient` API surface is defined in `plugin/mqttclient.h` (host/port/topic/auth/reconnectInterval + connection/message signals).
- External deps: Qt6 Core/Qml/Mqtt, CMake, KDE `kpackagetool6`, and an MQTT broker.

## Safe Change Checklist
- Keep logging prefixes and behavior consistent (`[MQTTRain]`, `[MQTTRain][debug]`).
- Preserve null/parse guards in message processing paths (defensive handling is intentional).
- After renderer/config edits, verify mode switching with MQTT enabled and disabled (Classic fallback must still work).