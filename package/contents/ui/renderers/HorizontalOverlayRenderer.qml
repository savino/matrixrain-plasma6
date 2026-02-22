// HorizontalOverlayRenderer.qml  (v3)
//
// ─────────────────────────────────────────────────────────────────
// PURPOSE
//   Render mode 3 – "Horizontal Overlay (Readable)".
//   Classic vertical Matrix rain runs continuously at all times.
//   Incoming MQTT messages appear as readable horizontal text blocks
//   overlaid on the rain for a configurable duration (default 3 s).
//
// ─────────────────────────────────────────────────────────────────
// RENDERING PIPELINE  (two passes per frame, driven by MatrixCanvas)
//
//   Pass 1 – renderColumnContent(ctx, col, x, y, drops)
//     Called once per column per frame at the drop-head position.
//     Draws a random Katakana character – identical to ClassicRenderer.
//     Drops ALWAYS advance unconditionally; this function never pauses them.
//
//   Pass 2 – renderOverlay(ctx)
//     Called ONCE per frame by MatrixCanvas after the rain loop.
//     Iterates activeMessages (≤ maxMessages) and redraws every line
//     at full brightness with one ctx.fillText call per line.
//     Because it fires every frame, overlay chars "resist" the canvas
//     fade-rectangle and stay visible until the message expires.
//     After expiry the chars stop being redrawn and fade naturally.
//
// ─────────────────────────────────────────────────────────────────
// MESSAGE LIFECYCLE
//
//   assignMessage() ← called by main.qml on every non-blacklisted message
//     1. Build + truncate text lines (topic line + pretty-print payload)
//     2. Find low-overlap position (rectangle overlap test, 12 random tries)
//     3. Enforce hard cap: drop oldest message when maxMessages is reached
//     4. Push { lines, col, row, blockCols, expiry } to activeMessages
//
//   Timer (1 Hz) ← purgeExpired()
//     Removes messages past their expiry timestamp.
//     NEVER called from inside render functions (hot path).
//
// ─────────────────────────────────────────────────────────────────
// PERFORMANCE BUDGET  (why this implementation is CPU-safe)
//
//   maxMessages  =  5  → at most 5 messages active simultaneously
//   maxLines     = 12  → at most 60 lines rendered per frame
//   renderOverlay: at most 60 ctx.fillText calls per frame
//   purgeExpired:  1 call per second, O(maxMessages)
//   No flat cell map, no Object.keys(), no per-character fillText loop.
// ─────────────────────────────────────────────────────────────────

import QtQuick 2.15
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    // ── Interface required by MatrixCanvas ──────────────────────────
    property var columnAssignments: []   // compatibility; not used for logic
    property int columns: 0              // grid column count, set by initializeColumns

    // ── Visual config (bound from main.qml) ─────────────────────────
    property int   fontSize:     16
    property color baseColor:    "#00ff00"
    property real  jitter:       0
    property int   glitchChance: 1
    property var   palettes:     []
    property int   paletteIndex: 0
    property int   colorMode:    0

    // ── Canvas pixel dimensions (set by MatrixCanvas.initDrops) ─────
    // Must be set BEFORE initializeColumns() is called.
    property int canvasWidth:  0
    property int canvasHeight: 0

    // ── Tunable ─────────────────────────────────────────────────────
    // Duration each overlay block remains visible (milliseconds)
    property int displayDuration: 3000

    // ── Hard performance limits (change with care) ───────────────────
    readonly property int maxMessages: 5   // concurrent overlay blocks
    readonly property int maxLines:    12  // text lines per block (incl. topic)
    readonly property int maxLineLen:  60  // characters per line

    // ── Internal state ───────────────────────────────────────────────
    // Each entry: { lines:[string], col:int, row:int, blockCols:int, expiry:int }
    property var activeMessages: []

    // ================================================================
    // PRIVATE: resolve the base colour for a given grid column.
    // ================================================================
    function columnColor(col) {
        if (colorMode === 0 || !palettes || !palettes[paletteIndex])
            return baseColor.toString()
        return palettes[paletteIndex][col % palettes[paletteIndex].length]
    }

    // ================================================================
    // PRIVATE: build the array of display lines from topic + payload.
    //
    // Line 0  = MQTT topic
    // Lines 1+ = payload (pretty-printed if valid JSON, plain otherwise)
    // Lines and characters are truncated to maxLines / maxLineLen.
    // ================================================================
    function buildLines(topic, payload) {
        var lines = []
        var ellipsis = "\u2026"  // Unicode ellipsis character

        // ── Topic line ──
        var topicStr = (topic !== null && topic !== undefined) ? topic.toString() : ""
        lines.push(topicStr.length > maxLineLen
                   ? topicStr.substring(0, maxLineLen - 1) + ellipsis
                   : topicStr)

        // ── Payload lines ──
        var p = (payload !== null && payload !== undefined) ? payload.toString().trim() : ""
        if (p.length === 0) return lines

        var rawLines = []
        try {
            var parsed = JSON.parse(p)
            if (parsed !== null && typeof parsed === "object") {
                // Valid JSON → pretty-print with 2-space indent
                var pretty = JSON.stringify(parsed, null, 2)
                var split  = pretty.split("\n")
                for (var s = 0; s < split.length; s++) {
                    if (split[s].trim().length > 0)
                        rawLines.push(split[s])
                }
            } else {
                rawLines.push(p)
            }
        } catch(e) {
            // Not JSON – display as plain text
            rawLines.push(p)
        }

        // Append payload lines up to the limit
        var remaining = maxLines - lines.length   // slots left after topic
        for (var i = 0; i < rawLines.length && remaining > 0; i++) {
            var line = rawLines[i]
            if (line.length > maxLineLen)
                line = line.substring(0, maxLineLen - 1) + ellipsis
            lines.push(line)
            remaining--
        }

        return lines
    }

    // ================================================================
    // PRIVATE: true when rectangle (col, row, nCols, nRows) does NOT
    // overlap any currently active message block.
    //
    // Uses standard axis-aligned bounding-box non-overlap test:
    //   two rectangles A and B do NOT overlap when
    //   A.right <= B.left  OR  A.left >= B.right  OR
    //   A.bottom <= B.top  OR  A.top >= B.bottom
    // ================================================================
    function isRectFree(col, row, nCols, nRows) {
        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]
            var separated = (col + nCols <= msg.col) ||
                            (col >= msg.col + msg.blockCols) ||
                            (row + nRows <= msg.row) ||
                            (row >= msg.row + msg.lines.length)
            if (!separated) return false
        }
        return true
    }

    // ================================================================
    // PRIVATE: remove expired messages.
    // Called ONLY from the 1-Hz Timer – never from render functions.
    // ================================================================
    function purgeExpired() {
        var now  = Date.now()
        var prev = activeMessages.length
        var kept = []
        for (var i = 0; i < activeMessages.length; i++) {
            if (activeMessages[i].expiry > now)
                kept.push(activeMessages[i])
        }
        if (kept.length !== prev) {
            activeMessages = kept
            console.log("[HorizontalOverlayRenderer] purged "
                        + (prev - kept.length) + " expired, "
                        + kept.length + " remaining")
        }
    }

    // ================================================================
    // PUBLIC: called by main.qml when an MQTT message is received.
    // ================================================================
    function assignMessage(topic, payload) {
        // Guard: renderer must be initialized before accepting messages
        if (columns === 0 || canvasWidth === 0 || canvasHeight === 0) {
            console.log("[HorizontalOverlayRenderer] assignMessage: not ready "
                        + "(columns=" + columns
                        + " canvas=" + canvasWidth + "x" + canvasHeight + ")")
            return
        }

        var lines = buildLines(topic, payload)
        if (lines.length === 0) return

        // Measure block extent in grid cells
        var blockCols = 0
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].length > blockCols) blockCols = lines[i].length
        }
        var blockRows = lines.length

        // Grid dimensions in cells
        var gridCols = Math.floor(canvasWidth  / fontSize)
        var gridRows = Math.floor(canvasHeight / fontSize)
        if (gridCols <= 0 || gridRows <= 0) return

        // Maximum top-left corner that keeps the block on screen
        var maxCol = Math.max(0, gridCols - blockCols)
        var maxRow = Math.max(0, gridRows - blockRows)

        // Try up to 12 random positions; pick the first that is fully free.
        // If none is found, use the last candidate anyway (overlap preferred
        // over dropping the message silently).
        var bestCol = Math.floor(Math.random() * (maxCol + 1))
        var bestRow = Math.floor(Math.random() * (maxRow + 1))

        for (var a = 0; a < 12; a++) {
            var tryCol = Math.floor(Math.random() * (maxCol + 1))
            var tryRow = Math.floor(Math.random() * (maxRow + 1))
            if (isRectFree(tryCol, tryRow, blockCols, blockRows)) {
                bestCol = tryCol
                bestRow = tryRow
                break
            }
        }

        // Enforce hard cap: discard oldest message when at limit
        var newList = activeMessages.slice()
        if (newList.length >= maxMessages) {
            newList.shift()   // FIFO – remove the oldest entry
        }

        newList.push({
            lines:     lines,
            col:       bestCol,
            row:       bestRow,
            blockCols: blockCols,
            expiry:    Date.now() + displayDuration
        })
        activeMessages = newList

        console.log("[HorizontalOverlayRenderer] placed "
                    + blockCols + "x" + blockRows
                    + " at (" + bestCol + "," + bestRow + ")"
                    + "  active=" + newList.length + "/" + maxMessages)
    }

    // ================================================================
    // Pass 1 – Classic rain character at the drop head.
    //
    // This function is called N times per frame (once per column).
    // It must remain as cheap as possible: one random char, one fillText.
    // NO overlay logic, NO purgeExpired, NO state mutation here.
    // ================================================================
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var color    = columnColor(columnIndex)
        var isGlitch = (Math.random() < glitchChance / 100)
        var ch       = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
        ctx.fillStyle = isGlitch ? "#ffffff" : color
        ctx.fillText(ch, x, y)
    }

    // ================================================================
    // Pass 2 – Overlay: redraw active message lines at full brightness.
    //
    // Called ONCE per frame by MatrixCanvas after the rain loop.
    // Total cost: at most maxMessages × maxLines = 5 × 12 = 60 fillText
    // calls per frame, regardless of message content length.
    //
    // Coordinate mapping:
    //   pixel x = col  * fontSize
    //   pixel y = (row + 1) * fontSize   ← text baseline (alphabetic)
    //   This matches the rain convention: when drops[i] = r the rain char
    //   baseline is at r * fontSize, making grid row (r-1) visible.
    //   Overlay row 0 baseline at 1*fontSize → same visual row as drops[i]=1.
    // ================================================================
    function renderOverlay(ctx) {
        if (activeMessages.length === 0) return

        var now = Date.now()

        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]

            // Skip messages that expired since the last Timer tick.
            // (Timer will clean them up; we just skip rendering here.)
            if (msg.expiry <= now) continue

            // Base colour anchored to the message's leftmost column
            var msgColor = columnColor(msg.col)

            for (var r = 0; r < msg.lines.length; r++) {
                var line = msg.lines[r]
                if (!line || line.length === 0) continue

                // Topic line (r=0): slightly dimmer to distinguish from payload
                // Payload lines (r>0): bright so values are easy to read
                ctx.fillStyle = (r === 0)
                    ? ColorUtils.lightenColor(msgColor, 0.35)
                    : ColorUtils.lightenColor(msgColor, 0.80)

                // One fillText per line – monospace font keeps chars grid-aligned
                ctx.fillText(line,
                             msg.col * fontSize,
                             (msg.row + r + 1) * fontSize)
            }
        }
    }

    // ================================================================
    // Column wrap callback – no per-column state to manage here.
    // ================================================================
    function onColumnWrap(columnIndex) { /* no-op */ }

    // ================================================================
    // Initialization – called by MatrixCanvas whenever drops are reset
    // (screen resize, mode switch, or first load).
    // ================================================================
    function initializeColumns(numColumns) {
        console.log("[HorizontalOverlayRenderer] initializeColumns: "
                    + numColumns + " cols"
                    + "  canvas=" + canvasWidth + "x" + canvasHeight + "px")

        // Rebuild compatibility array (required by MatrixCanvas interface)
        var newCA = []
        for (var i = 0; i < numColumns; i++) newCA.push(null)
        columnAssignments = newCA
        columns           = numColumns

        // Clear all overlays on re-init (fresh start after resize / mode switch)
        activeMessages = []
    }

    // ================================================================
    // Expiry timer – fires once per second.
    // Keeping interval at 1000 ms means messages may linger up to
    // 1 extra second beyond displayDuration. Acceptable for UX.
    // ================================================================
    Timer {
        interval:  1000
        running:   true
        repeat:    true
        onTriggered: renderer.purgeExpired()
    }
}
