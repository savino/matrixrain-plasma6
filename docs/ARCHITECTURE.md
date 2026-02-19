# MatrixRain MQTT Wallpaper — Architecture

This document describes the internal architecture of the MatrixRain Plasma 6 wallpaper with a focus on the rendering pipeline, multi-stream logic, JSON color-tagging state machine, and robustness patterns.

---

## 1. High-Level Architecture

### Components

```
┌──────────────────────────────────────────────────────┐
│                  KDE Plasma Shell                    │
│  (systemd --user service, reads environment.d)      │
└────────────────────┬─────────────────────────────────┘
                     │
                     │ QML Plugin Import
                     ├─────────────────────────────────┐
                     │                                 │
         ┌───────────▼───────────┐       ┌────────────▼────────────┐
         │   C++ MQTT Plugin     │       │   QML Wallpaper UI      │
         │ (libmqttrainplugin.so)│◄──────┤   (main.qml)            │
         │                       │       │                         │
         │ - MQTTClient class    │       │ - Canvas renderer       │
         │ - Qt6 Mqtt module     │       │ - Multi-stream logic    │
         │ - TCP/WebSocket       │       │ - JSON color-tagging    │
         │ - Signal/slot bridge  │       │ - Config binding        │
         └───────────┬───────────┘       └─────────────────────────┘
                     │
                     │ MQTT Protocol (TCP 1883 or WS)
                     │
         ┌───────────▼───────────┐
         │   MQTT Broker         │
         │ (Mosquitto, HiveMQ..) │
         └───────────────────────┘
```

### Data Flow

1. **Configuration** (`main.xml`) → bound to properties in `main.qml` via `main.configuration.*`
2. **MQTT connection** initiated by `mqttConnect()` when `mqttEnable` is true
3. **Incoming messages** → C++ plugin emits `messageReceived(topic, payload)` signal
4. **QML handler** (`onMessageReceived`) → updates `messageHistory[]` → rebuilds `messageHistoryChars[][]`
5. **Paint loop** (Canvas `onPaint`) → reads from `messageHistoryChars[i % nSlots]` for each column
6. **User changes config** → triggers `on*Changed` handlers → `canvas.requestPaint()`

---

## 2. Multi-Stream Rendering

### Problem

The original design showed **one message** repeated across all columns. On a 1920px screen with 16px font, that's 120 columns all displaying the same 40-character string, repeated 3× horizontally.

### Solution: Interleaved Slot Assignment

Each of the last **5 messages** (stored in `messageHistory[]`) gets its own "slot". Columns are assigned to slots in round-robin fashion:

```
column  0 → slot 0 (newest message)
column  1 → slot 1
column  2 → slot 2
column  3 → slot 3
column  4 → slot 4 (oldest message)
column  5 → slot 0  ← repeats
column  6 → slot 1
...
```

### Implementation

```qml
// State
property var messageHistory: []           // [{topic, payload}, ...] max 5
property var messageHistoryChars: []      // [[{ch, isValue}, ...], ...]

// On new message
onMessageReceived: function(topic, payload) {
    var hist = messageHistory.slice()
    hist.unshift({ topic: safeTopic, payload: safePayload })  // newest first
    if (hist.length > maxHistory) hist = hist.slice(0, maxHistory)
    messageHistory = hist
    rebuildHistoryChars()  // regenerate all slot char arrays
}

// Paint loop
var slot = i % nSlots
var slotChars = messageHistoryChars[slot]
var idx = (Math.floor(drops[i]) + i) % slotChars.length
var entry = slotChars[idx]  // {ch, isValue}
```

### Advantages

- **Visual variety**: 5 different messages coexist on screen simultaneously
- **No seams**: interleaved columns prevent visible vertical bands between messages
- **Graceful fill-in**: when history has <5 slots, remaining columns show random katakana until more messages arrive

---

## 3. JSON Color-Tagging State Machine

### Goal

Distinguish **JSON keys/structure** (base palette color) from **values** (55% lighter) to make payloads readable.

### Payload Types

| Input | Parsing | Rendering |
|---|---|---|
| `{"state":"ON","battery":94}` | JSON object → `colorJsonChars()` | Keys dark, values bright |
| `"online"` | Plain string | All bright (entire payload is a value) |
| `null`, `42`, `true` | Scalar | All bright |
| Malformed JSON | Catch fallback | All dark (safe degradation) |

### State Machine: `colorJsonChars(json, result)`

```
ST_STRUCT       between tokens (whitespace, {, }, [, ], :, ,)
ST_IN_KEY       inside "key" string before :
ST_IN_VAL_STR   inside "value" string after :
ST_IN_VAL_NUM   inside number/bool/null after :
```

**Tagging rules:**

- `isValue: false` → keys, structural chars (`{`, `}`, `[`, `]`, `:`, `,`), whitespace
- `isValue: true` → value strings (including quotes), numbers, `true`, `false`, `null`

**Transition logic:**

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

**Special handling:**

- **Arrays**: `arrayDepth` counter tracks `[`/`]` nesting; inside arrays, strings are values
- **Escape sequences**: `escaped` flag prevents `\"` from terminating a string prematurely
- **Error recovery**: entire loop wrapped in `try/catch`; if exception at position `i`, remaining chars are appended with `isValue: false`

### Usage in `buildDisplayChars(topic, payload)`

```js
var parsed = null
try { parsed = JSON.parse(payload) } catch(e) {}

if (parsed !== null && typeof parsed === "object") {
    colorJsonChars(payload, result)  // JSON object/array
} else {
    // Plain string/scalar → all isValue:true
    for (var j = 0; j < payload.length; j++)
        result.push({ ch: payload.charAt(j), isValue: true })
}
```

### Rendering: `lightenColor(baseColor, 0.55)`

```js
if (entry.isValue) {
    ctx.fillStyle = lightenColor(baseColor, 0.55)  // blend 55% towards white
} else {
    ctx.fillStyle = baseColor  // raw palette color
}
```

Result: keys and structural chars in `#00ff00`, values in `rgb(140,255,140)` (55% lighter).

---

## 4. Robustness Patterns

Five layers of defensive coding ensure the wallpaper never crashes or stalls, even with malformed/unexpected input.

### 4.1 `lightenColor`: NaN Guard

**Problem**: Named CSS colors (`"green"`, `"transparent"`) or malformed hex produce `NaN` after `parseInt()`.

**Fix**:
```js
var r = parseInt(hex.substring(0, 2), 16)
if (isNaN(r) || isNaN(g) || isNaN(b)) return src  // return original
```

### 4.2 `colorJsonChars`: Null Guard + Try/Catch with Recovery

**Problem**: State machine can hit unexpected edge cases (unbalanced quotes, nested escapes).

**Fix**:
```js
if (!json || json.length === 0) return  // early exit
try {
    // state machine loop
} catch(e) {
    writeLog("colorJsonChars error at pos " + i + ": " + e)
    for (var k = i; k < json.length; k++)
        result.push({ ch: json.charAt(k), isValue: false })  // append remaining
}
```

Result is **always fully populated** with all characters, even if parsing fails mid-way.

### 4.3 `buildDisplayChars`: 3-Level Fallback

**Problem**: Multiple failure points (null topic/payload, JSON.parse exception, colorJsonChars failure).

**Fix**:
```js
// Normalize inputs
var t = (topic != null) ? topic.toString() : ""
var p = (payload != null) ? payload.toString() : ""

try {
    // L1: JSON object/array → colorJsonChars()
    // L2: scalar/non-JSON → plain loop with isValue:true
    // L3: outer catch-all
} catch(e) {
    // L3: rebuild as flat uncolored chars
    result = []
    var flat = t + ": " + p + "/"
    for (var k = 0; k < flat.length; k++)
        result.push({ ch: flat.charAt(k), isValue: false })
}
```

Each level is independent; a failure in L1 never corrupts L2/L3.

### 4.4 Paint Loop: Defensive Entry Check

**Problem**: During property updates, `messageHistoryChars[slot]` can be partially replaced, causing `entry` to be `undefined`.

**Fix**:
```js
var entry = (idx >= 0 && idx < slotChars.length) ? slotChars[idx] : null

if (!entry || typeof entry.ch !== "string" || entry.ch.length === 0) {
    // Fallback: random katakana in base color
    ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
    ctx.fillStyle = isGlitch ? "#ffffff" : baseColor
}
```

Animation never stalls; invalid entries gracefully degrade to random characters.

### 4.5 `onMessageReceived`: Null Normalization at Entry

**Problem**: A misbehaving broker could send `null` for topic or payload.

**Fix**:
```js
var safeTopic   = (topic   != null) ? topic.toString()   : ""
var safePayload = (payload != null) ? payload.toString() : ""
```

All downstream functions receive guaranteed strings.

---

## 5. Configuration System

### Files

```
package/contents/config/main.xml    ← schema (keys, types, defaults, ranges)
package/contents/ui/config.qml      ← UI (SpinBox, TextField, CheckBox)
package/contents/ui/main.qml        ← binding (main.configuration.*)
```

### Flow

1. User changes slider in `config.qml` → `property alias cfg_speed: speedSpin.value`
2. Plasma writes to `~/.config/plasma-org.kde.plasma.desktop-appletsrc`
3. `main.qml` reads via `main.configuration.speed`
4. `onSpeedChanged` handler triggers `timer.interval = 1000 / main.speed`

### Example: Adding a New Config Option

**Step 1: main.xml**
```xml
<Entry key="myOption" type="Int">
    <Default>42</Default>
    <Range min="0" max="100"/>
</Entry>
```

**Step 2: config.qml**
```qml
property alias cfg_myOption: mySpin.value

QC.SpinBox {
    id: mySpin; from: 0; to: 100
    KirigamiLayouts.FormData.label: qsTr("My Option")
}
```

**Step 3: main.qml**
```qml
property int myOption: main.configuration.myOption !== undefined
                       ? main.configuration.myOption : 42

onMyOptionChanged: {
    // react to change
    canvas.requestPaint()
}
```

---

## 6. systemd User Environment (QML Plugin Discovery)

### Problem

`plasmashell` is launched by systemd user manager, which does NOT source shell rc files. The C++ plugin in `~/.local/lib/qt6/qml/` is invisible unless explicitly declared.

### Solution: `~/.config/environment.d/*.conf`

systemd reads all `*.conf` files in this directory before starting any user service.

**File: `~/.config/environment.d/99-mqttrain-qt.conf`**
```bash
QML_IMPORT_PATH=/home/user/.local/lib/qt6/qml${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}
QML2_IMPORT_PATH=/home/user/.local/lib/qt6/qml${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}
```

### Verification

```bash
# Check file exists
cat ~/.config/environment.d/99-mqttrain-qt.conf

# Check systemd picked it up
systemctl --user show-environment | grep QML

# Expected output:
QML_IMPORT_PATH=/home/user/.local/lib/qt6/qml
QML2_IMPORT_PATH=/home/user/.local/lib/qt6/qml
```

### Why Logout is Required

The systemd user session is initialized once at login. Variables set in environment.d
files take effect only in **new sessions**. Existing processes (including plasmashell)
continue with the old environment until they are restarted by a fresh systemd instance.

---

## 7. Performance Considerations

### Canvas Rendering

- **Fade overlay** (`rgba(0,0,0,α)`) painted once per frame → O(1)
- **Character loop** → O(cols), typically 60–120 on 1920px screen
- **Per-character operations**: modulo, array access, string index → all O(1)
- **Total**: ~100–200 draw calls/frame at 50fps → ~10k ops/sec, negligible CPU usage

### JSON Parsing

- `JSON.parse()` called once per message → amortized over message rate (e.g. 1/sec for IoT)
- `colorJsonChars()` state machine → O(n) where n = payload length (typically 50–500 chars)
- Result cached in `messageHistoryChars[][]` → no re-parsing per frame

### Memory Footprint

- `messageHistory[]`: 5 entries × ~200 bytes/entry = ~1 KB
- `messageHistoryChars[][]`: 5 slots × 100 chars × 24 bytes/object = ~12 KB
- `drops[]`: 120 floats = 0.5 KB
- **Total state**: <20 KB

---

## 8. Future Extensions

### 8.1 Per-Topic Color Palettes

**Idea**: Assign a fixed palette index to each MQTT topic prefix.

```qml
property var topicColorMap: {
    "zigbee2mqtt/": 0,  // Neon
    "homeassistant/": 1, // Cyberpunk
    "system/": 2         // Synthwave
}

function getColorForTopic(topic) {
    for (var prefix in topicColorMap)
        if (topic.startsWith(prefix)) return topicColorMap[prefix]
    return paletteIndex  // default
}
```

### 8.2 Configurable History Depth

**Implementation**: Add `maxHistory` slider (1–10) to config, regenerate `messageHistoryChars` when changed.

### 8.3 Value-Specific Color Rules

**Idea**: Highlight specific values in custom colors.

```qml
if (entry.isValue) {
    var val = entry.ch  // or reconstruct full value
    if (val === "ON" || val === "true")
        ctx.fillStyle = "#00ff00"  // green
    else if (val === "OFF" || val === "false")
        ctx.fillStyle = "#ff0000"  // red
    else
        ctx.fillStyle = lightenColor(baseColor, 0.55)
}
```

### 8.4 WebSocket Support

**Status**: Plugin already has `mqttPath` config for WebSocket path.

**TODO**: Implement WebSocket transport in `mqttclient.cpp` as alternative to TCP.

---

## 9. Debugging Tips

### Enable All Debug Features

1. **Debug Overlay**: shows connection status, slots/chars counts, last 5 messages
2. **Debug MQTT logging**: prints every message to journal
3. **Journal monitoring**: `journalctl -f | grep MQTTRain`

### Common Symptoms

| Symptom | Likely Cause | Fix |
|---|---|---|
| No characters falling | MQTT disconnected | Check broker, credentials, firewall |
| All random katakana | No messages received yet | Publish test message |
| Plugin not found error | environment.d not loaded | Log out/in, check systemd env |
| Values same color as keys | JSON parse failed | Check debug log for malformed payload |
| Glitchy/stuttering | `speed` too high (>80) | Lower speed or increase fade strength |

### Testing with Dummy Data

```bash
# Publish test JSON to local broker
mosquitto_pub -h localhost -t test/topic -m '{"state":"ON","temp":21.5}'

# Subscribe to see what the wallpaper receives
mosquitto_sub -h localhost -t '#' -v
```

---

## 10. References

- **MQTT Specs**: `docs/mqtt-specs.md` — payload format for Zigbee2MQTT and Home Assistant
- **Qt MQTT Docs**: https://doc.qt.io/qt-6/qtmqtt-index.html
- **KDE Plasma Wallpaper API**: https://develop.kde.org/docs/plasma/
- **systemd environment.d**: `man 5 environment.d`
