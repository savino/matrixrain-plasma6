// MqttOnlyRenderer.qml
// Render mode: MQTT messages only (no random characters)
// All columns display messages from a rotating pool

import QtQuick 2.15
import "../utils/MatrixRainLogic.js" as Logic
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer
    
    // Column state
    property var columnAssignments: []
    property int columns: 0
    
    // Message pool for rotation
    property var messagePool: []
    property int messagePoolSize: 20
    
    // Rendering configuration
    property int fontSize: 16
    property color baseColor: "#00ff00"
    property real jitter: 0
    property int glitchChance: 1
    property var palettes: []
    property int paletteIndex: 0
    property int colorMode: 0
    
    /**
     * Assign incoming MQTT message to pool and redistribute
     */
    function assignMessage(topic, payload) {
        var chars = Logic.buildDisplayChars(topic, payload)
        
        // Add to message pool
        messagePool.push({
            topic: topic,
            payload: payload,
            chars: chars
        })
        
        // Limit pool size
        if (messagePool.length > messagePoolSize) {
            messagePool.shift() // Remove oldest
        }
        
        // Redistribute messages across all columns
        redistributeMessages()
    }
    
    /**
     * Distribute messages from pool to all columns
     */
    function redistributeMessages() {
        if (messagePool.length === 0) return
        
        for (var i = 0; i < columns; i++) {
            var msgIndex = i % messagePool.length
            columnAssignments[i] = {
                chars: messagePool[msgIndex].chars,
                passesLeft: 999999 // Never free
            }
        }
    }
    
    /**
     * Render content for a single column
     */
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var assignment = columnAssignments[columnIndex]
        
        // Determine base color
        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]
        
        var isGlitch = (Math.random() < glitchChance / 100)
        
        if (assignment !== null && assignment.chars && assignment.chars.length > 0) {
            // Render from message chars
            var slotChars = assignment.chars
            var r = Math.floor(drops[columnIndex])
            var idx = (r + columnIndex) % slotChars.length
            var entry = slotChars[idx]
            
            var ch = (entry && entry.ch) ? entry.ch : "?"
            
            if (isGlitch) {
                ctx.fillStyle = "#ffffff"
            } else if (entry && entry.isValue) {
                ctx.fillStyle = ColorUtils.lightenColor(color, 0.55)
            } else {
                ctx.fillStyle = color
            }
            
            ctx.fillText(ch, x, y)
        } else {
            // No messages yet: show placeholder
            ctx.fillStyle = "#333333"
            ctx.fillText("·", x, y)
        }
    }
    
    /**
     * Called when column wraps (no-op in this mode)
     */
    function onColumnWrap(columnIndex) {
        // Never free columns in MQTT-only mode
    }
    
    /**
     * Initialize column assignments
     */
    function initializeColumns(numColumns) {
        var newCA = []
        for (var i = 0; i < numColumns; i++) {
            newCA.push(null)
        }
        columnAssignments = newCA
        columns = numColumns
        
        // Redistribute existing messages if any
        if (messagePool.length > 0) {
            redistributeMessages()
        }
    }
}
