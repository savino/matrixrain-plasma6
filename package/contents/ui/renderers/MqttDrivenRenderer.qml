// MqttDrivenRenderer.qml
// Render mode: MQTT-driven (on-demand columns)
// Columns are inactive by default; activate only on message arrival

import QtQuick 2.15
import "../utils/MatrixRainLogic.js" as Logic
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer
    
    // Column state
    property var columnAssignments: []
    property int columns: 0
    
    // Track active columns for quick lookup
    property var activeColumns: []
    
    // Rendering configuration
    property int fontSize: 16
    property color baseColor: "#00ff00"
    property real jitter: 0
    property int glitchChance: 1
    property var palettes: []
    property int paletteIndex: 0
    property int colorMode: 0
    
    /**
     * Assign incoming MQTT message to an available column
     * Activates a dormant column or reuses least recent
     */
    function assignMessage(topic, payload) {
        var chars = Logic.buildDisplayChars(topic, payload)
        var targetCol = findAvailableColumn()
        
        if (targetCol !== -1) {
            columnAssignments[targetCol] = {
                chars: chars,
                passesLeft: 3,
                active: true
            }
            
            // Track as active
            if (activeColumns.indexOf(targetCol) === -1) {
                activeColumns.push(targetCol)
            }
        }
    }
    
    /**
     * Find an available column (inactive or least recent)
     */
    function findAvailableColumn() {
        // First pass: find inactive column
        for (var i = 0; i < columns; i++) {
            if (columnAssignments[i] === null || !columnAssignments[i].active) {
                return i
            }
        }
        
        // All active: pick random to replace
        return Math.floor(Math.random() * columns)
    }
    
    /**
     * Render content for a single column
     */
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var assignment = columnAssignments[columnIndex]
        
        // Skip inactive columns (render nothing)
        if (assignment === null || !assignment.active) {
            return
        }
        
        // Determine base color
        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]
        
        var isGlitch = (Math.random() < glitchChance / 100)
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
    }
    
    /**
     * Called when column wraps
     * Decrements passes and deactivates when done
     */
    function onColumnWrap(columnIndex) {
        if (columnAssignments[columnIndex] !== null && columnAssignments[columnIndex].active) {
            columnAssignments[columnIndex].passesLeft -= 1
            
            if (columnAssignments[columnIndex].passesLeft <= 0) {
                // Deactivate column
                columnAssignments[columnIndex].active = false
                
                // Remove from active tracking
                var idx = activeColumns.indexOf(columnIndex)
                if (idx !== -1) {
                    activeColumns.splice(idx, 1)
                }
            }
        }
    }
    
    /**
     * Initialize column assignments (all inactive)
     */
    function initializeColumns(numColumns) {
        var newCA = []
        for (var i = 0; i < numColumns; i++) {
            newCA.push(null)
        }
        columnAssignments = newCA
        columns = numColumns
        activeColumns = []
    }
}
