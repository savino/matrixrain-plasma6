// HorizontalOverlayRenderer.qml  v2
// Render mode: Classic Matrix rain + horizontal readable MQTT messages
//
// Architecture (two-pass rendering):
//   Pass 1 – renderColumnContent(): pure classic rain char at drop head.
//             Drops always advance normally. No overlay logic here.
//   Pass 2 – renderOverlay(): called ONCE per frame by MatrixCanvas after
//             the rain loop. Redraws all active message cells at full
//             brightness, overriding the fade effect only on those cells.
//
// Message lifecycle:
//   - assignMessage()  : finds a free random position, stores the block
//   - Timer (1 s)      : purges expired messages and rebuilds cell map
//   - renderOverlay()  : redraws bright chars every frame until expiry
//   After expiry the cells are no longer redrawn, so the fade overlay
//   of the canvas naturally wipes them out over the next few frames.

import QtQuick 2.15
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    // ---- Interface compatibility ----
    property var columnAssignments: []
    property int columns: 0

    // ---- Visual config (bound from main.qml) ----
    property int   fontSize:     16
    property color baseColor:    "#00ff00"
    property real  jitter:       0
    property int   glitchChance: 1
    property var   palettes:     []
    property int   paletteIndex: 0
    property int   colorMode:    0

    // ---- Tunable ----
    // How long (ms) each message block stays at full brightness
    property int displayDuration: 3000

    // ---- Canvas dimensions (set by MatrixCanvas.initDrops) ----
    property int canvasWidth:  0
    property int canvasHeight: 0

    // ---- Internal state ----
    // activeMessages: [{ lines:[str], col:int, row:int, expiry:int }]
    property var activeMessages: []

    // overlayMap: { "col,row": { ch:str, isValue:bool } }
    // Rebuilt whenever activeMessages changes.
    property var overlayMap: ({})

    // =================================================================
    // PRIVATE: pretty-print topic + payload → array of strings
    // =================================================================
    function prettyLines(topic, payload) {
        var lines = []
        lines.push(topic)

        var p = (payload !== null && payload !== undefined) ? payload.toString() : ""
        if (p.trim().length === 0) {
            lines.push("(empty)")
            return lines
        }

        try {
            var parsed = JSON.parse(p)
            if (parsed !== null && typeof parsed === "object") {
                var pretty = JSON.stringify(parsed, null, 2)
                var jsonLines = pretty.split("\n")
                for (var i = 0; i < jsonLines.length; i++) {
                    // Skip blank lines to save screen space
                    if (jsonLines[i].trim().length > 0)
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

    // =================================================================
    // PRIVATE: rebuild overlayMap from activeMessages
    // Called only after activeMessages changes (assign or purge).
    // =================================================================
    function rebuildOverlayMap() {
        var map = {}
        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]
            for (var r = 0; r < msg.lines.length; r++) {
                var line = msg.lines[r]
                for (var c = 0; c < line.length; c++) {
                    var key = (msg.col + c) + "," + (msg.row + r)
                    map[key] = { ch: line.charAt(c), isValue: (r > 0) }
                }
            }
        }
        overlayMap = map
    }

    // =================================================================
    // PRIVATE: remove expired messages and rebuild map.
    // Called ONLY from the Timer (once per second).
    // =================================================================
    function purgeExpired() {
        var now  = Date.now()
        var kept = []
        for (var i = 0; i < activeMessages.length; i++) {
            if (activeMessages[i].expiry > now)
                kept.push(activeMessages[i])
        }
        if (kept.length !== activeMessages.length) {
            activeMessages = kept
            rebuildOverlayMap()
        }
    }

    // =================================================================
    // PUBLIC: called by main.qml when an MQTT message arrives.
    // Finds a low-overlap random position and adds the message block.
    // =================================================================
    function assignMessage(topic, payload) {
        var lines = prettyLines(topic, payload)
        if (lines.length === 0) return

        // Measure block extent in grid cells
        var blockCols = 0
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].length > blockCols) blockCols = lines[i].length
        }
        var blockRows = lines.length

        // Grid size (prefer canvasWidth; fall back to columns property)
        var gridCols = (canvasWidth  > 0 && fontSize > 0)
                       ? Math.floor(canvasWidth  / fontSize) : columns
        var gridRows = (canvasHeight > 0 && fontSize > 0)
                       ? Math.floor(canvasHeight / fontSize) : 40

        if (gridCols <= 0 || gridRows <= 0) return

        // Constrain so block fits on screen
        var maxCol = Math.max(0, gridCols - blockCols)
        var maxRow = Math.max(0, gridRows - blockRows)

        // Pick position with lowest overlap with existing messages
        var bestCol = Math.floor(Math.random() * (maxCol + 1))
        var bestRow = Math.floor(Math.random() * (maxRow + 1))
        var minOverlap = 999999

        for (var a = 0; a < 12; a++) {
            var tryCol = Math.floor(Math.random() * (maxCol + 1))
            var tryRow = Math.floor(Math.random() * (maxRow + 1))
            var overlap = 0
            for (var r = 0; r < blockRows; r++) {
                for (var c = 0; c < blockCols; c++) {
                    if (overlayMap[(tryCol + c) + "," + (tryRow + r)] !== undefined)
                        overlap++
                }
            }
            if (overlap < minOverlap) {
                minOverlap = overlap
                bestCol = tryCol
                bestRow = tryRow
            }
            if (overlap === 0) break
        }

        var newList = activeMessages.slice()
        newList.push({
            lines:  lines,
            col:    bestCol,
            row:    bestRow,
            expiry: Date.now() + displayDuration
        })
        activeMessages = newList
        rebuildOverlayMap()

        console.log("[HorizontalOverlayRenderer] placed " + blockCols + "x" + blockRows
                    + " at (" + bestCol + "," + bestRow + ")")
    }

    // =================================================================
    // Pass 1 – Classic rain char at the drop head.
    // This is called N times per frame (once per column).
    // NO overlay logic, NO purgeExpired here.
    // =================================================================
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]

        var isGlitch = (Math.random() < glitchChance / 100)
        var ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
        ctx.fillStyle = isGlitch ? "#ffffff" : color
        ctx.fillText(ch, x, y)
    }

    // =================================================================
    // Pass 2 – Overlay: called ONCE per frame by MatrixCanvas after the
    // rain loop. Redraws every active message cell at full brightness.
    // Because it runs every frame, it "fights" the fade overlay and keeps
    // chars visible for the full displayDuration.
    // =================================================================
    function renderOverlay(ctx) {
        var keys = Object.keys(overlayMap)
        if (keys.length === 0) return

        for (var k = 0; k < keys.length; k++) {
            var key   = keys[k]
            var sep   = key.indexOf(",")
            var col   = parseInt(key.substring(0, sep))
            var row   = parseInt(key.substring(sep + 1))
            var cell  = overlayMap[key]

            // Per-column colour in multi-colour mode
            var color = (colorMode === 0)
                ? baseColor.toString()
                : palettes[paletteIndex][col % palettes[paletteIndex].length]

            // Brighter for payload lines, slightly dimmer for topic line
            ctx.fillStyle = cell.isValue
                ? ColorUtils.lightenColor(color, 0.75)
                : ColorUtils.lightenColor(color, 0.45)

            // Pixel position: x = col*fontSize, y baseline = (row+1)*fontSize
            ctx.fillText(cell.ch, col * fontSize, (row + 1) * fontSize)
        }
    }

    // =================================================================
    // Called when a column wraps to top – nothing needed here
    // =================================================================
    function onColumnWrap(columnIndex) { /* no-op */ }

    // =================================================================
    // Initialize (called by MatrixCanvas.initDrops)
    // =================================================================
    function initializeColumns(numColumns) {
        console.log("[HorizontalOverlayRenderer] init cols=" + numColumns
                    + " canvas=" + canvasWidth + "x" + canvasHeight)
        var newCA = []
        for (var i = 0; i < numColumns; i++) newCA.push(null)
        columnAssignments = newCA
        columns           = numColumns
        activeMessages    = []
        overlayMap        = ({})
    }

    // Expiry timer – runs once per second, NOT per frame
    Timer {
        interval:  1000
        running:   true
        repeat:    true
        onTriggered: renderer.purgeExpired()
    }
}
