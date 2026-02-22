// HorizontalOverlayRenderer.qml
// Render mode: Classic Matrix rain + MQTT messages displayed horizontally
//
// MQTT messages appear as readable horizontal text blocks overlaid on the
// classic rain. Each message occupies a rectangular region on screen.
// While the message is visible (displayDuration ms), falling drops skip
// protected cells so the message stays legible. After the timer expires
// the message fades out and the rain reclaims those cells.

import QtQuick 2.15
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    // ---- Interface compatibility ----
    property var columnAssignments: []
    property int columns: 0

    // ---- Visual config (injected by main.qml) ----
    property int   fontSize:    16
    property color baseColor:   "#00ff00"
    property real  jitter:      0
    property int   glitchChance: 1
    property var   palettes:    []
    property int   paletteIndex: 0
    property int   colorMode:   0

    // ---- Tunable ----
    // How long (ms) each message stays on screen
    property int displayDuration: 3000

    // ---- Internal state ----
    // activeMessages: list of overlay objects
    //   { lines: [string], col: int, row: int, cols: int, rows: int, expiry: int }
    property var activeMessages: []

    // protectedCells: Set-like object { "col,row": {ch, isValue} }
    // Rebuilt whenever activeMessages changes
    property var protectedCells: ({})

    // ---- Canvas dimensions (set by initializeColumns) ----
    property int canvasWidth:  0
    property int canvasHeight: 0

    // ------------------------------------------------------------------
    // Pretty-print a payload string (JSON → indented, plain → as-is)
    // Returns an array of strings (lines)
    // ------------------------------------------------------------------
    function prettyLines(topic, payload) {
        var lines = []
        // First line: topic (shortened if needed)
        var topicLine = topic
        lines.push(topicLine)

        var p = (payload !== null && payload !== undefined) ? payload.toString() : ""
        if (p.trim().length === 0) {
            lines.push("(empty)")
            return lines
        }

        try {
            var parsed = JSON.parse(p)
            if (parsed !== null && typeof parsed === "object") {
                // Pretty-print JSON, split into lines
                var pretty = JSON.stringify(parsed, null, 2)
                var jsonLines = pretty.split("\n")
                for (var i = 0; i < jsonLines.length; i++) {
                    lines.push(jsonLines[i])
                }
            } else {
                lines.push(p)
            }
        } catch(e) {
            lines.push(p)
        }

        return lines
    }

    // ------------------------------------------------------------------
    // Rebuild the protectedCells map from activeMessages
    // ------------------------------------------------------------------
    function rebuildProtectedCells() {
        var cells = {}
        var msgs = activeMessages
        for (var m = 0; m < msgs.length; m++) {
            var msg = msgs[m]
            for (var r = 0; r < msg.lines.length; r++) {
                var line = msg.lines[r]
                for (var c = 0; c < line.length; c++) {
                    var gc = msg.col + c   // grid column
                    var gr = msg.row + r   // grid row
                    if (gc >= 0 && gr >= 0) {
                        var isValue = (r > 0)  // topic line uses key colour, rest value
                        cells[gc + "," + gr] = { ch: line.charAt(c), isValue: isValue }
                    }
                }
            }
        }
        protectedCells = cells
    }

    // ------------------------------------------------------------------
    // Purge expired messages and rebuild cells
    // ------------------------------------------------------------------
    function purgeExpired() {
        var now = Date.now()
        var msgs = activeMessages
        var kept = []
        for (var i = 0; i < msgs.length; i++) {
            if (msgs[i].expiry > now) {
                kept.push(msgs[i])
            }
        }
        if (kept.length !== msgs.length) {
            activeMessages = kept
            rebuildProtectedCells()
        }
    }

    // ------------------------------------------------------------------
    // Called by main.qml when an MQTT message arrives
    // ------------------------------------------------------------------
    function assignMessage(topic, payload) {
        purgeExpired()

        var lines = prettyLines(topic, payload)
        if (lines.length === 0) return

        // Measure block size in grid cells
        var blockCols = 0
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].length > blockCols) blockCols = lines[i].length
        }
        var blockRows = lines.length

        // Total grid dimensions
        var gridCols = (canvasWidth  > 0 && fontSize > 0) ? Math.floor(canvasWidth  / fontSize) : columns
        var gridRows = (canvasHeight > 0 && fontSize > 0) ? Math.floor(canvasHeight / fontSize) : 20

        if (gridCols <= 0 || gridRows <= 0) return

        // Clamp block so it fits on screen
        var maxCol = Math.max(0, gridCols - blockCols)
        var maxRow = Math.max(0, gridRows - blockRows)

        // Try to find a position that doesn't heavily overlap existing messages
        var bestCol = Math.floor(Math.random() * (maxCol + 1))
        var bestRow = Math.floor(Math.random() * (maxRow + 1))
        var attempts = 12
        var minOverlap = 999999

        for (var a = 0; a < attempts; a++) {
            var tryCol = Math.floor(Math.random() * (maxCol + 1))
            var tryRow = Math.floor(Math.random() * (maxRow + 1))
            var overlap = 0
            for (var r = 0; r < blockRows; r++) {
                for (var c = 0; c < blockCols; c++) {
                    if (protectedCells[(tryCol + c) + "," + (tryRow + r)] !== undefined) {
                        overlap++
                    }
                }
            }
            if (overlap < minOverlap) {
                minOverlap = overlap
                bestCol = tryCol
                bestRow = tryRow
            }
            if (overlap === 0) break
        }

        var newMsg = {
            lines:  lines,
            col:    bestCol,
            row:    bestRow,
            cols:   blockCols,
            rows:   blockRows,
            expiry: Date.now() + displayDuration
        }

        var newList = activeMessages.slice()
        newList.push(newMsg)
        activeMessages = newList
        rebuildProtectedCells()

        console.log("[HorizontalOverlayRenderer] placed message at col=" + bestCol +
                    " row=" + bestRow + " size=" + blockCols + "x" + blockRows)
    }

    // ------------------------------------------------------------------
    // Called by MatrixCanvas for every drop position
    // Returns true if this cell is protected (caller skips normal char)
    // ------------------------------------------------------------------
    function isCellProtected(gridCol, gridRow) {
        return protectedCells[gridCol + "," + gridRow] !== undefined
    }

    // ------------------------------------------------------------------
    // Render a single drop cell
    // gridRow = Math.floor(y / fontSize)
    // ------------------------------------------------------------------
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        purgeExpired()

        var gridRow = Math.floor(y / fontSize)
        var key = columnIndex + "," + gridRow
        var cell = protectedCells[key]

        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]

        if (cell !== undefined) {
            // Draw the overlay character
            var bright = cell.isValue
                ? ColorUtils.lightenColor(color, 0.7)
                : ColorUtils.lightenColor(color, 0.4)
            ctx.fillStyle = bright
            ctx.fillText(cell.ch, x, y)
        } else {
            // Normal rain character
            var isGlitch = (Math.random() < glitchChance / 100)
            var ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
            ctx.fillStyle = isGlitch ? "#ffffff" : color
            ctx.fillText(ch, x, y)
        }
    }

    // ------------------------------------------------------------------
    // Called when a column wraps – nothing special needed here
    // ------------------------------------------------------------------
    function onColumnWrap(columnIndex) {
        // No per-column tracking needed
    }

    // ------------------------------------------------------------------
    // Initialize
    // ------------------------------------------------------------------
    function initializeColumns(numColumns) {
        console.log("[HorizontalOverlayRenderer] initializeColumns: " + numColumns)
        var newCA = []
        for (var i = 0; i < numColumns; i++) newCA.push(null)
        columnAssignments = newCA
        columns = numColumns
        activeMessages = []
        protectedCells = ({})
    }

    // Expiry timer – checks every second
    Timer {
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: renderer.purgeExpired()
    }
}
