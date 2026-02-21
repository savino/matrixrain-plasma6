# Matrix Rain Architecture

This document describes the component-based architecture of the Matrix Rain MQTT wallpaper.

## Directory Structure

```
package/contents/ui/
├── main.qml                      # Main orchestration (200 lines)
├── config.qml                    # Configuration UI
├── components/                   # Reusable UI components
│   ├── MatrixCanvas.qml          # Canvas rendering base
│   └── MQTTDebugOverlay.qml      # Debug information overlay
├── renderers/                    # Render mode strategies
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

### MixedModeRenderer
**Behavior**: Default mode combining MQTT messages with random Matrix characters.

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
- Activate column on message arrival
- Display message for 3 passes then deactivate
- Creates dramatic "message burst" effect
- Best for: Event notifications, sparse message patterns

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
4. Property binding updates renderer
5. Canvas requests repaint

## Message Flow

1. MQTT message arrives → `mqttClient.onMessageReceived`
2. Update message history for debug
3. Call `activeRenderer.assignMessage(topic, payload)`
4. Renderer processes via `MatrixRainLogic.buildDisplayChars()`
5. Renderer updates `columnAssignments` array
6. Canvas repaints → calls `renderer.renderColumnContent()` per column

## Performance Considerations

- **JS modules use `.pragma library`**: Single instance, faster
- **Direct array mutation**: Avoid property notifications in hot loops
- **Renderer delegation**: Canvas doesn't know message format
- **Fade overlay**: Single fillRect, not per-character alpha
- **Column wrapping**: Batch wrap notifications, not per-frame

## Best Practices

1. **Keep renderers stateless**: All config via properties
2. **Use utility modules**: Don't duplicate logic
3. **Avoid console.log in hot paths**: Use `mqttDebug` flag
4. **Test all three modes**: Ensure renderer interface compliance
5. **Document render behavior**: Update this file for new modes

## Debugging

- Enable **Debug Overlay** for live statistics
- Enable **Debug MQTT logging** for message inspection
- Check console for `[MQTTRain]` prefixed logs
- Verify renderer selection: Look for "🎭 Render mode changed to: ..."

## Future Extensions

- Additional renderers (e.g., columnar JSON, binary mode)
- Renderer-specific configuration
- Animation transition between modes
- Custom character sets per renderer
- Message filtering/routing to specific columns
