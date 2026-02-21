# Matrix Rain Architecture

This document describes the component-based architecture of the Matrix Rain MQTT wallpaper.

## Directory Structure

```
package/contents/ui/
├── main.qml                      # Main orchestration (~220 lines)
├── config.qml                    # Configuration UI (tabbed)
├── components/                   # Reusable UI components
│   ├── MatrixCanvas.qml          # Canvas rendering base
│   └── MQTTDebugOverlay.qml      # Debug information overlay
├── renderers/                    # Render mode strategies
│   ├── ClassicRenderer.qml       # Pure random Matrix (MQTT-disabled)
│   ├── MixedModeRenderer.qml     # Mixed MQTT + random
│   ├── MqttOnlyRenderer.qml      # MQTT messages only
│   └── MqttDrivenRenderer.qml    # On-demand columns
└── utils/                        # JavaScript utilities
    ├── ColorUtils.js             # Color manipulation
    └── MatrixRainLogic.js        # Message processing
```

## Component Responsibilities

### main.qml
- Configuration management
- MQTT client lifecycle
- Renderer selection and instantiation
- Component orchestration
- Event routing
- Automatic fallback to ClassicRenderer when MQTT disabled

### MatrixCanvas.qml
- Renderer-agnostic canvas
- Drop animation timing
- Fade overlay rendering
- Delegates column content to active renderer
- Handles resize and initialization

### MQTTDebugOverlay.qml
- Connection status display
- Message history visualization
- Statistics tracking
- Toggleable overlay

## Renderer Strategy Pattern

Renderers implement a common interface:

```qml
Item {
    // State
    property var columnAssignments: []
    property int columns: 0
    
    // Configuration
    property int fontSize
    property color baseColor
    property real jitter
    property int glitchChance
    // ... etc
    
    // Interface methods
    function assignMessage(topic, payload)
    function renderColumnContent(ctx, columnIndex, x, y, drops)
    function onColumnWrap(columnIndex)
    function initializeColumns(numColumns)
}
```

## Available Renderers

### ClassicRenderer
**Behavior**: Pure Matrix rain with random characters (MQTT-disabled fallback).

- Automatic fallback when `mqttEnable` is false
- All columns display random Katakana characters
- No MQTT dependency, always works
- Respects color/glitch/jitter settings
- Classic green falling characters effect
- Best for: Testing, demonstration, or pure aesthetic use

### MixedModeRenderer
**Behavior**: Default MQTT mode combining messages with random characters.

- MQTT messages assigned to random free columns
- Free columns display random Katakana characters
- Messages display for 3 passes then column freed
- Best for: General use, high message volume

### MqttOnlyRenderer
**Behavior**: All columns always show MQTT messages (loop from pool).

- Maintains pool of recent messages (default 20)
- All columns assigned messages from pool (round-robin)
- No random characters, only received messages
- Shows placeholder dots until first message
- Best for: Monitoring specific data streams, low message volume

### MqttDrivenRenderer
**Behavior**: Columns activate only when messages arrive.

- Columns inactive (blank) by default
- Activate random inactive column on message arrival
- Display message for 3 passes then deactivate
- Creates dramatic "message burst" effect distributed across screen
- Best for: Event notifications, sparse message patterns

## Renderer Selection Logic

The active renderer is determined by MQTT enable state:

```qml
activeRenderer: {
    // Fallback to Classic if MQTT disabled
    if (!main.mqttEnable) {
        return classicRenderer
    }
    
    // MQTT enabled: select based on render mode
    switch(main.mqttRenderMode) {
        case 0: return mixedRenderer      // Mixed MQTT + random
        case 1: return mqttOnlyRenderer   // MQTT only
        case 2: return mqttDrivenRenderer // On-demand
        default: return mixedRenderer
    }
}
```

**Key points:**
- ClassicRenderer always active when MQTT disabled
- MQTT render mode selection only applies when MQTT enabled
- Ensures wallpaper always displays something, never blank
- Switching MQTT on/off triggers renderer change automatically

## Utility Modules

### ColorUtils.js
```javascript
function lightenColor(hexColor, factor)
```
Blends colors towards white for value highlighting.

### MatrixRainLogic.js
```javascript
function colorJsonChars(json, result)
function buildDisplayChars(topic, payload)
function assignMessageToColumn(chars, columnAssignments, passesLeft)
```
JSON parsing, character tagging, column assignment logic.

## Adding a New Renderer

1. **Create renderer file**: `renderers/MyRenderer.qml`
2. **Implement interface**:
   ```qml
   import QtQuick 2.15
   import "../utils/MatrixRainLogic.js" as Logic
   import "../utils/ColorUtils.js" as ColorUtils
   
   Item {
       // Properties and interface methods
   }
   ```
3. **Add to main.qml**:
   ```qml
   MyRenderer {
       id: myRenderer
       // ... property bindings
   }
   ```
4. **Update renderer selection**:
   ```qml
   activeRenderer: {
       if (!main.mqttEnable) return classicRenderer
       
       switch(main.mqttRenderMode) {
           case 3: return myRenderer  // New mode
           // ... existing cases
       }
   }
   ```
5. **Update config**: Add option to `main.xml` and `config.qml`

## Configuration Flow

1. User changes setting in `config.qml`
2. Value saved to `main.xml` schema
3. `main.qml` reads via `main.configuration.*`
4. Property binding updates renderer (including Classic fallback)
5. Canvas requests repaint

## Message Flow

1. MQTT message arrives → `mqttClient.onMessageReceived`
2. Update message history for debug
3. Call `activeRenderer.assignMessage(topic, payload)` (only if MQTT enabled)
4. Renderer processes via `MatrixRainLogic.buildDisplayChars()`
5. Renderer updates `columnAssignments` array
6. Canvas repaints → calls `renderer.renderColumnContent()` per column

**Note:** ClassicRenderer ignores `assignMessage()` calls since it only renders random characters.

## Performance Considerations

- **JS modules use `.pragma library`**: Single instance, faster
- **Array cloning for property changes**: See QML gotchas below
- **Renderer delegation**: Canvas doesn't know message format
- **Fade overlay**: Single fillRect, not per-character alpha
- **Column wrapping**: Batch wrap notifications, not per-frame
- **Classic mode**: Zero MQTT overhead, pure random rendering

## QML Property System Gotchas

### ⚠️ CRITICAL: Array Mutation Does Not Trigger Property Changes

QML's property binding system **does NOT detect** array mutations by index:

**❌ WRONG** (property change not detected, canvas won't repaint):
```qml
function assignMessage(topic, payload) {
    var chars = Logic.buildDisplayChars(topic, payload)
    columnAssignments[5] = { chars: chars, passesLeft: 3 }  // ❌ Mutation not detected!
}
```

**✅ CORRECT** (property change detected, canvas repaints):
```qml
function assignMessage(topic, payload) {
    var chars = Logic.buildDisplayChars(topic, payload)
    var newCA = columnAssignments.slice()  // Clone array
    newCA[5] = { chars: chars, passesLeft: 3 }  // Mutate clone
    columnAssignments = newCA  // Reassign triggers property change ✅
}
```

**Why this matters:**
- `MatrixCanvas` binds to `activeRenderer.columnAssignments`
- When `columnAssignments` changes, canvas knows to repaint
- Index mutations (`array[i] = value`) don't trigger property signals
- **Must clone → mutate → reassign** to trigger change notification

**Pattern for all renderers:**
```qml
// Read-only access: direct use is fine
var assignment = columnAssignments[columnIndex]

// Write/mutation: always clone-mutate-reassign
var newCA = columnAssignments.slice()  // or Array.from(columnAssignments)
newCA[columnIndex] = newValue
columnAssignments = newCA  // Triggers property change
```

**This applies to:**
- `assignMessage()` - Adding messages to columns
- `onColumnWrap()` - Decrementing passesLeft or freeing columns
- `redistributeMessages()` - Batch column updates
- Any function that modifies `columnAssignments` array

### ⚠️ CRITICAL: Randomize Column Selection

When selecting columns for messages, **always randomize** from available columns:

**❌ WRONG** (all messages go to column 0):
```qml
function findAvailableColumn() {
    for (var i = 0; i < columns; i++) {
        if (columnAssignments[i] === null) {
            return i  // ❌ Always returns first inactive (usually 0)
        }
    }
    return -1
}
```

**✅ CORRECT** (messages distributed randomly):
```qml
function findAvailableColumn() {
    // Build list of ALL inactive columns
    var inactiveCols = []
    for (var i = 0; i < columns; i++) {
        if (columnAssignments[i] === null || !columnAssignments[i].active) {
            inactiveCols.push(i)
        }
    }
    
    // Pick RANDOM from inactive list
    if (inactiveCols.length > 0) {
        var randomIdx = Math.floor(Math.random() * inactiveCols.length)
        return inactiveCols[randomIdx]  // ✅ Random distribution
    }
    
    // All active: pick random to replace
    return Math.floor(Math.random() * columns)
}
```

**Why this matters:**
- Sequential search (i=0, i=1...) always finds column 0 first
- Messages stack on same column, defeating visual effect
- Randomization spreads messages across screen
- Creates more dramatic "burst" or "cascade" effect

## Best Practices

1. **Keep renderers stateless**: All config via properties
2. **Use utility modules**: Don't duplicate logic
3. **Clone before mutating arrays**: Always use slice() → mutate → reassign pattern
4. **Randomize column selection**: Build list → pick random, not first match
5. **Handle MQTT-disabled gracefully**: ClassicRenderer always available
6. **Avoid console.log in hot paths**: Use `mqttDebug` flag for conditional logging
7. **Test all modes including Classic**: Ensure renderer interface compliance
8. **Document render behavior**: Update this file for new modes

## Debugging

- Enable **Debug Overlay** for live statistics and mode confirmation
- Enable **Debug MQTT logging** for message inspection
- Check console for renderer-specific logs:
  - `[ClassicRenderer]`
  - `[MixedModeRenderer]`
  - `[MqttOnlyRenderer]`
  - `[MqttDrivenRenderer]`
- Verify renderer selection: Look for "🎭 Render mode changed to: ..." or "🎭 Classic mode"
- **Black screen with messages arriving?** → Check array cloning pattern in renderer
- **All messages in column 0?** → Check column selection randomization
- **Black screen with MQTT disabled?** → Verify ClassicRenderer is selected

## Common Issues

### Black screen / no columns rendering
**Symptom**: Debug shows messages arriving, but no Matrix characters appear.

**Cause**: Renderer mutating `columnAssignments` without triggering property change.

**Solution**: Ensure all array modifications use clone-mutate-reassign pattern:
```qml
var newCA = columnAssignments.slice()
// ... modify newCA ...
columnAssignments = newCA  // Don't forget this!
```

### Black screen when MQTT disabled
**Symptom**: Disabling MQTT checkbox results in blank wallpaper.

**Cause**: Renderer selection not falling back to ClassicRenderer.

**Solution**: Verify `activeRenderer` binding includes MQTT enable check:
```qml
activeRenderer: {
    if (!main.mqttEnable) return classicRenderer
    // ... MQTT mode selection
}
```

### All messages appear in column 0 only
**Symptom**: Multiple messages arrive but all stack on leftmost column.

**Cause**: Column selection uses sequential search (`for i=0...`) instead of randomization.

**Solution**: Build list of available columns, pick random:
```qml
var available = []
for (var i = 0; i < columns; i++) {
    if (columnAssignments[i] === null) available.push(i)
}
if (available.length > 0) {
    return available[Math.floor(Math.random() * available.length)]
}
```

### Messages not updating after first message
**Symptom**: First message appears, subsequent messages don't update.

**Cause**: `assignMessage()` or `onColumnWrap()` mutating array directly.

**Solution**: Review all functions that modify `columnAssignments` for proper cloning.

### Render mode switch broken
**Symptom**: Switching modes doesn't change behavior.

**Cause**: `activeRenderer` binding not updating or wrong index in switch.

**Solution**: Check `mqttRenderMode` value in debug overlay and verify switch statement.

## Future Extensions

- Additional renderers (e.g., columnar JSON, binary mode, wave effects)
- Renderer-specific configuration UI
- Animation transition between modes
- Custom character sets per renderer
- Message filtering/routing to specific columns
- Per-column color schemes
- Time-based renderer switching
