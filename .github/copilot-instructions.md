# Copilot Instructions for MatrixRain MQTT Wallpaper (KDE Plasma 6)

## Overview

This project provides a Matrix-style "code rainfall" wallpaper for KDE Plasma 6 with **native MQTT integration** via a **C++ QML plugin**. MQTT messages are displayed as falling characters with **JSON syntax highlighting** (values brighter than keys) and **multi-stream rendering** (up to 5 messages visible simultaneously on interleaved columns).

## Architecture

### Components

1. **C++ MQTT Plugin** (`plugin/`)
   - Qt6 QML plugin exposing `MQTTClient` type
   - Uses Qt6 Mqtt module for MQTT protocol (TCP/WebSocket)
   - Compiled to `libmqttrainplugin.so` + `qmldir`
   - Installed to `~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/`
   - **Critical**: Must be discoverable via `QML_IMPORT_PATH` / `QML2_IMPORT_PATH`

2. **QML Wallpaper** (`package/`)
   - `main.qml`: Canvas-based Matrix rain renderer, multi-stream logic, JSON color-tagging state machine
   - `config.qml`: Settings UI (font size, speed, fade strength, MQTT config, debug overlay)
   - `main.xml`: Configuration schema (keys, types, defaults, ranges)

3. **systemd environment.d**
   - `~/.config/environment.d/99-mqttrain-qt.conf` declares plugin path
   - systemd user manager sources this before starting `plasmashell`
   - **Shell rc files (.bashrc, .zshrc) are NOT read by plasmashell**

### Data Flow

```
MQTT Broker
    ↓
C++ Plugin (MQTTClient)
    ↓ messageReceived(topic, payload) signal
QML onMessageReceived handler
    ↓ push to messageHistory[] (max 5, newest first)
rebuildHistoryChars()
    ↓ buildDisplayChars(topic, payload) → [{ch, isValue}, ...]
    ↓ colorJsonChars() state machine tags JSON values
messageHistoryChars[][] (one slot per message)
    ↓
Canvas paint loop
    ↓ column i reads from slot i % nSlots
    ↓ isValue:false → base color, isValue:true → lightenColor(base, 0.55)
Screen
```

## Developer Workflows

### Installation

```bash
./install.sh
```

**What it does:**
1. Checks dependencies (cmake, qt6-base, qt6-declarative, qt6-mqtt, kpackagetool6)
2. Builds C++ plugin with CMake
3. Installs plugin to `~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/`
4. Installs wallpaper package with `kpackagetool6`
5. **Creates `~/.config/environment.d/99-mqttrain-qt.conf`** with QML_IMPORT_PATH
6. Runs `systemctl --user daemon-reexec`
7. **Requires logout/reboot** for plasmashell to pick up the new environment

### Building Plugin Manually

```bash
cd plugin/build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local
make -j$(nproc)
cp libmqttrainplugin.so ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/
```

### Testing Changes

**C++ plugin changes:**
```bash
cd plugin/build && make -j$(nproc)
cp libmqttrainplugin.so ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/
plasmashell --replace &
```

**QML changes:**
```bash
cp package/contents/ui/main.qml ~/.local/share/plasma/wallpapers/obsidianreq.plasma.wallpaper.mqttrain/contents/ui/
plasmashell --replace &
```

**Config changes (main.xml or config.qml):**
```bash
kpackagetool6 --type Plasma/Wallpaper --upgrade package
# Then reopen wallpaper settings
```

### Debugging

**Enable debug logging:**
1. Turn on "Debug MQTT logging" in wallpaper settings
2. Monitor journal: `journalctl -f | grep -i mqttrain`

**Test MQTT connection:**
```bash
mosquitto_sub -h <host> -p 1883 -t '#' -v
mosquitto_pub -h <host> -t test/topic -m '{"state":"ON","value":42}'
```

**Check plugin discovery:**
```bash
cat ~/.config/environment.d/99-mqttrain-qt.conf
systemctl --user show-environment | grep QML
ls ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/
```

## Project Conventions

### Configuration Management

1. **Schema**: `package/contents/config/main.xml`
   - Define key, type (`Int`, `String`, `Bool`, `Double`), default, range
2. **UI**: `package/contents/ui/config.qml`
   - Bind with `property alias cfg_<key>: controlId.value`
3. **Read**: `package/contents/ui/main.qml`
   - Access via `main.configuration.<key>`
   - Add `on<Key>Changed` handler if needed

**Example:**
```xml
<!-- main.xml -->
<Entry key="myValue" type="Int"><Default>10</Default><Range min="1" max="100"/></Entry>
```
```qml
// config.qml
property alias cfg_myValue: mySpin.value
QC.SpinBox { id: mySpin; from: 1; to: 100 }
```
```qml
// main.qml
property int myValue: main.configuration.myValue !== undefined ? main.configuration.myValue : 10
onMyValueChanged: canvas.requestPaint()
```

### Multi-Stream Rendering

**State:**
- `messageHistory: [{topic, payload}, ...]` — last 5 messages, newest first
- `messageHistoryChars: [[{ch, isValue}, ...], ...]` — one slot per message

**Column assignment:**
```qml
var slot = i % nSlots  // interleaved: col 0→slot 0, col 1→slot 1, ..., col 5→slot 0 again
```

**Why interleaved?** Prevents vertical seams; each message distributed evenly across screen width.

### JSON Color-Tagging State Machine

**Goal**: Tag each character as key/structure (`isValue: false`) or value (`isValue: true`).

**States:**
- `ST_STRUCT` — between tokens (whitespace, `{`, `}`, `[`, `]`, `:`, `,`)
- `ST_IN_KEY` — inside `"key"` string before `:`
- `ST_IN_VAL_STR` — inside `"value"` string after `:`
- `ST_IN_VAL_NUM` — inside number/bool/null after `:`

**Key logic:**
```js
if (ch === '"') {
    if (afterColon || arrayDepth > 0) {
        state = ST_IN_VAL_STR  // value string
        result.push({ ch, isValue: true })
    } else {
        state = ST_IN_KEY      // key string
        result.push({ ch, isValue: false })
    }
}
```

**Rendering:**
```js
if (entry.isValue) {
    ctx.fillStyle = lightenColor(baseColor, 0.55)  // 55% brighter
} else {
    ctx.fillStyle = baseColor  // raw palette color
}
```

### Robustness Guidelines for AI Agents

**Always apply these patterns when modifying or extending code:**

1. **Null checks before `.toString()` / `.charAt()`**
   ```js
   var safe = (input != null && input !== undefined) ? input.toString() : ""
   ```

2. **NaN guards after `parseInt()`**
   ```js
   var val = parseInt(str, 16)
   if (isNaN(val)) return fallback
   ```

3. **Try/catch with recovery in parsing loops**
   ```js
   try {
       // state machine loop
   } catch(e) {
       // append remaining chars with safe default tagging
   }
   ```

4. **3-level fallback for data processing**
   - L1: optimistic parse (JSON.parse, colorJsonChars)
   - L2: degraded parse (plain string loop)
   - L3: outer catch-all (flat uncolored chars)

5. **Defensive array access in render loops**
   ```js
   var entry = (idx >= 0 && idx < arr.length) ? arr[idx] : null
   if (!entry || typeof entry.ch !== "string" || entry.ch.length === 0) {
       // fallback to random katakana
   }
   ```

**See `docs/ARCHITECTURE.md` § 4 for detailed examples.**

## Integration Points

### External Dependencies

- **Build**: CMake 3.16+, Qt6 (Core, Qml, Mqtt modules)
- **Runtime**: KDE Plasma 6, systemd (user session), MQTT broker

### Cross-Component Communication

**C++ → QML:**
- Signal `messageReceived(QString topic, QString payload)` emitted by `MQTTClient`
- QML handler `onMessageReceived` receives and processes

**QML → C++:**
- Properties set: `mqttClient.host`, `mqttClient.port`, `mqttClient.topic`, `mqttClient.username`, `mqttClient.password`
- Method call: `mqttClient.connectToHost()`

**Config → Render:**
- Config changes trigger `on*Changed` handlers
- Handlers call `canvas.requestPaint()` to trigger redraw

## Common Tasks for AI Agents

### Add a New Visual Effect

1. Add config entry to `main.xml`
2. Add UI control to `config.qml` with `cfg_` alias
3. Add property to `main.qml` reading from `main.configuration`
4. Modify `Canvas.onPaint` to use the new property
5. Add `on*Changed` handler calling `canvas.requestPaint()`

### Modify MQTT Message Processing

1. Edit `buildDisplayChars()` or `colorJsonChars()` in `main.qml`
2. Test with: `mosquitto_pub -h localhost -t test -m '{"test":123}'`
3. Enable debug overlay to see processed output

### Change Column Assignment Logic

1. Modify slot assignment in `Canvas.onPaint`:
   ```js
   var slot = i % nSlots  // current: interleaved
   // Alternative: var slot = Math.floor(i / (drops.length / nSlots))  // banded
   ```
2. Verify no visual seams or gaps

### Extend JSON Highlighting

1. Modify `colorJsonChars()` state machine
2. Add new states or tagging rules
3. Adjust `lightenColor()` factor or add conditional color rules in paint loop

## Troubleshooting for AI Agents

### "module not installed" error

**Diagnosis:**
```bash
ls ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/  # plugin exists?
systemctl --user show-environment | grep QML   # variable set?
```

**Fix:** User must log out/in or reboot after `install.sh` runs.

### No characters falling

**Diagnosis:**
- Check debug overlay: is MQTT connected?
- Check journal: `journalctl -f | grep MQTTRain`
- Test broker: `mosquitto_sub -h <host> -t '#'`

**Fix:** Verify broker, credentials, topic subscription, firewall.

### Values not highlighted

**Diagnosis:**
- Enable debug logging, check if payload is valid JSON
- Verify `colorJsonChars()` executed (check `messageHistoryChars` in debug)

**Fix:** If payload is plain string, it's working as designed (all `isValue:true`).

## Examples

### Changing Fade Behavior

**Current (linear fade per frame):**
```js
ctx.fillStyle = "rgba(0,0,0," + main.fadeStrength + ")"
```

**Alternative (exponential fade):**
```js
var alpha = 1 - Math.pow(1 - main.fadeStrength, 1 / main.speed)
ctx.fillStyle = "rgba(0,0,0," + alpha + ")"
```

### Adding Per-Topic Colors

```js
function getColorForTopic(topic) {
    if (topic.startsWith("zigbee2mqtt/")) return palettes[0]  // Neon
    if (topic.startsWith("homeassistant/")) return palettes[1] // Cyberpunk
    return palettes[paletteIndex]  // default
}

var baseColor = (colorMode === 0) ? singleColor : getColorForTopic(safeTopic)[i % 6]
```

## Conclusion

These instructions provide AI coding agents with a complete mental model of the MatrixRain MQTT wallpaper architecture, focusing on:

- **C++ plugin integration** via systemd environment.d
- **Multi-stream rendering** with interleaved slot assignment
- **JSON syntax highlighting** state machine
- **Robustness patterns** for defensive coding
- **Configuration flow** from XML → UI → QML properties

For full technical details, see `docs/ARCHITECTURE.md` and `docs/mqtt-specs.md`.
