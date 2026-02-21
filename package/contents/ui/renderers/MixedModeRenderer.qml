// MixedModeRenderer.qml
// Render mode: Mixed MQTT messages + random Matrix characters
// MQTT messages are assigned to random columns; other columns show random chars

import QtQuick 2.15
import "../utils/MatrixRainLogic.js" as Logic
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer
    
    // Column state
    property var columnAssignments: []
    property int columns: 0
    
    // Rendering configuration
    property int fontSize: 16
    property color baseColor: "#00ff00"
    property real jitter: 0
    property int glitchChance: 1
    property var palettes: []
    property int paletteIndex: 0
    property int colorMode: 0
    
    /**
     * Assign incoming MQTT message to a random free column
     */
    function assignMessage(topic, payload) {
        var chars = Logic.buildDisplayChars(topic, payload)
        Logic.assignMessageToColumn(chars, columnAssignments, 3)
    }
    
    /**
     * Render content for a single column
     * @param ctx - Canvas 2D context
     * @param columnIndex - Column index
     * @param x - X position
     * @param y - Y position
     * @param drops - Drops array
     */
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var assignment = columnAssignments[columnIndex]
        var ch
        
        // Determine base color
        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]
        
        var isGlitch = (Math.random() < glitchChance / 100)
        
        if (assignment !== null) {
            // Column has MQTT message
            var slotChars = assignment.chars
            var slotLen = slotChars ? slotChars.length : 0
            
            if (slotLen > 0) {
                var r = Math.floor(drops[columnIndex])
                var idx = (r + columnIndex) % slotLen
                var entry = (idx >= 0 && idx < slotLen) ? slotChars[idx] : null
                
                if (entry && typeof entry.ch === "string" && entry.ch.length > 0) {
                    ch = entry.ch
                    
                    if (isGlitch) {
                        ctx.fillStyle = "#ffffff"
                    } else if (entry.isValue) {
                        // Lighten value characters
                        ctx.fillStyle = ColorUtils.lightenColor(color, 0.55)
                    } else {
                        ctx.fillStyle = color
                    }
                } else {
                    // Fallback to random
                    ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                    ctx.fillStyle = isGlitch ? "#ffffff" : color
                }
            } else {
                // Empty assignment: random
                ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                ctx.fillStyle = isGlitch ? "#ffffff" : color
            }
        } else {
            // Free column: random Matrix characters
            ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
            ctx.fillStyle = isGlitch ? "#ffffff" : color
        }
        
        ctx.fillText(ch, x, y)
    }
    
    /**
     * Called when a column wraps to top
     * @param columnIndex - Column that wrapped
     */
    function onColumnWrap(columnIndex) {
        if (columnAssignments[columnIndex] !== null) {
            columnAssignments[columnIndex].passesLeft -= 1
            if (columnAssignments[columnIndex].passesLeft <= 0) {
                // Free the column
                columnAssignments[columnIndex] = null
            }
        }
    }
    
    /**
     * Initialize column assignments
     * @param numColumns - Number of columns
     */
    function initializeColumns(numColumns) {
        var newCA = []
        for (var i = 0; i < numColumns; i++) {
            newCA.push(null)
        }
        columnAssignments = newCA
        columns = numColumns
    }
}
