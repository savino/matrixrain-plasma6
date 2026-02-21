// ClassicRenderer.qml
// Classic Matrix rain renderer - no MQTT, pure random characters
// Used as fallback when MQTT is disabled

import QtQuick 2.15
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer
    
    // Column state (not used, but required for interface compatibility)
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
     * Classic mode doesn't process MQTT messages
     */
    function assignMessage(topic, payload) {
        // No-op: classic mode ignores MQTT
    }
    
    /**
     * Render random Matrix character for column
     */
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        // Determine base color
        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]
        
        // Random glitch effect
        var isGlitch = (Math.random() < glitchChance / 100)
        
        // Random Katakana character (U+30A0 to U+30FF)
        var ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
        
        // Set color
        ctx.fillStyle = isGlitch ? "#ffffff" : color
        
        // Render character
        ctx.fillText(ch, x, y)
    }
    
    /**
     * Column wrap - no special behavior in classic mode
     */
    function onColumnWrap(columnIndex) {
        // No-op: no message tracking in classic mode
    }
    
    /**
     * Initialize columns
     */
    function initializeColumns(numColumns) {
        console.log("[ClassicRenderer] initializeColumns: numColumns=" + numColumns)
        
        // Create placeholder array for interface compatibility
        var newCA = []
        for (var i = 0; i < numColumns; i++) {
            newCA.push(null)
        }
        columnAssignments = newCA
        columns = numColumns
    }
}
