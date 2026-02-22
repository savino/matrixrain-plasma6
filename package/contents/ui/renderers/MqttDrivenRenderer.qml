// MqttDrivenRenderer.qml
// Render mode 2: MQTT-driven columns.
//
// Columns are inactive (render nothing) by default.
// When an MQTT message arrives it is assigned to a randomly-chosen
// inactive column, which then scrolls the message characters top-to-bottom
// for a fixed number of passes before going inactive again.
//
// NOTE: columns that are inactive render nothing (transparent), so the
// canvas fade-overlay will gradually clear any previous content in those
// columns. This is intentional – it creates the "wipe" effect.

import QtQuick 2.15
import "../utils/MatrixRainLogic.js" as Logic
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    // ── Interface required by MatrixCanvas ──────────────────────────
    property var columnAssignments: []
    property int columns: 0

    // ── Visual config (bound from main.qml) ─────────────────────────
    property int   fontSize:     16
    property color baseColor:    "#00ff00"
    property real  jitter:       0
    property int   glitchChance: 1
    property var   palettes:     []
    property int   paletteIndex: 0
    property int   colorMode:    0

    // ── Internal tracking ────────────────────────────────────────────
    // Kept in sync with columnAssignments for O(1) inactive-column lookup
    property var activeColumnSet: []   // list of currently active column indices

    // ================================================================
    // PUBLIC: called by main.qml when an MQTT message is received.
    // ================================================================
    function assignMessage(topic, payload) {
        // Guard: renderer must be initialised before it can accept messages.
        // This can happen if a message arrives before the canvas is ready.
        if (columns === 0) {
            console.log("[MqttDrivenRenderer] assignMessage: not ready (columns=0)")
            return
        }

        var chars = Logic.buildDisplayChars(topic, payload)
        if (chars.length === 0) {
            console.log("[MqttDrivenRenderer] skipping empty message")
            return
        }

        var targetCol = findTargetColumn()
        if (targetCol < 0 || targetCol >= columns) {
            console.log("[MqttDrivenRenderer] no valid column found")
            return
        }

        var newCA = columnAssignments.slice()
        newCA[targetCol] = { chars: chars, passesLeft: 3, active: true }
        columnAssignments = newCA

        // Track in activeColumnSet if not already present
        if (activeColumnSet.indexOf(targetCol) === -1) {
            var newSet = activeColumnSet.slice()
            newSet.push(targetCol)
            activeColumnSet = newSet
        }

        console.log("[MqttDrivenRenderer] assigned to column " + targetCol
                    + "  active=" + activeColumnSet.length)
    }

    // ================================================================
    // PRIVATE: choose a column for the next message.
    // Prefers inactive columns; falls back to any random column when all
    // are active. Returns -1 only when columns === 0 (guarded above).
    // ================================================================
    function findTargetColumn() {
        // Collect inactive column indices
        var inactive = []
        for (var i = 0; i < columns; i++) {
            var a = columnAssignments[i]
            if (a === null || a === undefined || !a.active)
                inactive.push(i)
        }

        if (inactive.length > 0) {
            // Pick a random inactive column
            return inactive[Math.floor(Math.random() * inactive.length)]
        }

        // All columns active: overwrite a random one
        return Math.floor(Math.random() * columns)
    }

    // ================================================================
    // Pass 1 – render one character at the drop head.
    // Inactive columns render nothing; the fade overlay clears them.
    // ================================================================
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var assignment = columnAssignments[columnIndex]

        // Inactive column: draw nothing (let the fade clear the column)
        if (!assignment || !assignment.active) return

        var color    = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]
        var isGlitch = (Math.random() < glitchChance / 100)

        // Pick the character from the message string based on drop position
        var slotChars = assignment.chars
        var r   = Math.floor(drops[columnIndex])
        var idx = (r + columnIndex) % slotChars.length
        var entry = slotChars[idx]
        var ch    = (entry && entry.ch) ? entry.ch : "?"

        if (isGlitch) {
            ctx.fillStyle = "#ffffff"
        } else if (entry && entry.isValue) {
            ctx.fillStyle = ColorUtils.lightenColor(color, 0.55)
        } else {
            ctx.fillStyle = color
        }

        ctx.fillText(ch, x, y)
    }

    // ================================================================
    // Called when a drop reaches the bottom and wraps to the top.
    // Decrements the pass counter; deactivates the column when done.
    // ================================================================
    function onColumnWrap(columnIndex) {
        var assignment = columnAssignments[columnIndex]
        if (!assignment || !assignment.active) return

        var newCA = columnAssignments.slice()
        newCA[columnIndex].passesLeft -= 1

        if (newCA[columnIndex].passesLeft <= 0) {
            // Column has scrolled enough – deactivate it
            newCA[columnIndex].active = false
            columnAssignments = newCA

            // Remove from active set
            var idx = activeColumnSet.indexOf(columnIndex)
            if (idx !== -1) {
                var newSet = activeColumnSet.slice()
                newSet.splice(idx, 1)
                activeColumnSet = newSet
            }
            console.log("[MqttDrivenRenderer] column " + columnIndex
                        + " deactivated, active remaining: " + activeColumnSet.length)
        } else {
            columnAssignments = newCA
        }
    }

    // ================================================================
    // Initialization – reset all columns to inactive state.
    // ================================================================
    function initializeColumns(numColumns) {
        console.log("[MqttDrivenRenderer] initializeColumns: " + numColumns)
        var newCA = []
        for (var i = 0; i < numColumns; i++) newCA.push(null)
        columnAssignments = newCA
        columns           = numColumns
        activeColumnSet   = []
    }
}
