// HorizontalInlineRenderer.qml  (v1 – Matrix Inject / Horizontal Inline)
//
// ─────────────────────────────────────────────────────────────────
// PURPOSE
//   Render mode 3 – "Horizontal Inline" (also called "Matrix Inject").
//   Classic Matrix rain runs continuously. When an MQTT message
//   arrives, its characters are injected directly into the rain
//   matrix grid, readable horizontally.
//
//   The MQTT chars ARE matrix chars – they live at specific (col, row)
//   grid positions, rain drops skip them without overwriting, and they
//   fade naturally when the message expires.
//
// ─────────────────────────────────────────────────────────────────
// GRID MODEL
//
//   cols = floor(canvasWidth  / fontSize)
//   rows = floor(canvasHeight / fontSize)
//
//   Cell (col, row) maps to pixel rect:
//     x ∈ [col*fontSize, (col+1)*fontSize)
//     y ∈ [row*fontSize, (row+1)*fontSize)
//
//   Rain drops and MQTT chars share the same grid.
//
// ─────────────────────────────────────────────────────────────────
// RENDERING PIPELINE  (two passes per frame, driven by MatrixCanvas)
//
//   Pass 1 – renderColumnContent(ctx, col, x, y, drops)
//     Called once per column per frame at the drop-head position.
//     • If (col, gridRow) is occupied by an active message → SKIP.
//       No char drawn; drop advances normally (rain rhythm unchanged).
//     • Otherwise → draw a random Katakana char (normal rain).
//
//   Pass 2 – renderInlineChars(ctx)
//     Called once per frame by MatrixCanvas after the rain loop.
//     For each active, non-expired message: draw all text lines with
//     one ctx.fillText per line. No background fill.
//     Chars are redrawn at high brightness every frame to resist the
//     global canvas fade and remain readable until expiry.
//     After expiry: stop redrawing → chars fade naturally with the rain.
//
// ─────────────────────────────────────────────────────────────────
// MESSAGE QUEUE
//
//   assignMessage():
//     1. Build display lines (topic + pretty-print payload)
//     2. Measure block: blockCols = longest line, blockRows = line count
//     3. Find random non-overlapping position (up to 12 attempts)
//     4. Enqueue. If queue.length >= maxMessages, drop oldest (FIFO)
//
//   Timer (1 Hz) → purgeExpired():
//     Remove messages past their expiry. Never called from render path.
//
// ─────────────────────────────────────────────────────────────────
// PERFORMANCE BUDGET
//   maxMessages (default 15) × maxLines (12) = 180 fillText max/frame
//   isCellOccupied → O(maxMessages) per column per frame  (pass 1)
//   renderInlineChars → O(maxMessages × maxLines)          (pass 2)
//   purgeExpired     → O(maxMessages) once per second
//   No flat cell map, no Object.keys(), no per-char fillText loop.
// ─────────────────────────────────────────────────────────────────

import QtQuick 2.15
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    // ── MatrixCanvas interface ─────────────────────────────────────────
    property var columnAssignments: []   // compatibility stub; not used for logic
    property int columns: 0              // grid column count, set by initializeColumns

    // ── Visual config (bound from main.qml) ───────────────────────────
    property int   fontSize:     16
    property color baseColor:    "#00ff00"
    property real  jitter:       0
    property int   glitchChance: 1
    property var   palettes:     []
    property int   paletteIndex: 0
    property int   colorMode:    0

    // ── Canvas dimensions (set by MatrixCanvas before initializeColumns) ─
    property int canvasWidth:  0
    property int canvasHeight: 0

    // ── Configurable parameters ────────────────────────────────────────
    // How long each message stays visible (milliseconds).
    property int displayDuration: 3000

    // Maximum number of messages in the queue at any one time.
    // When the queue is full, the oldest message is evicted (FIFO)
    // before the new one is added.
    property int maxMessages: 15

    // ── Hard limits ───────────────────────────────────────────────────
    readonly property int maxLines:   12   // max text lines per message
    readonly property int maxLineLen: 60   // max characters per line

    // ── Message queue ──────────────────────────────────────────────────
    // Each entry: { lines:[string], col:int, row:int,
    //               blockCols:int, expiry:int }
    // FIFO order: index 0 = oldest, last = newest.
    property var msgQueue: []

    // ================================================================
    // PRIVATE: resolve colour for grid column col.
    // colorMode 0  → all columns use baseColor.
    // colorMode >0 → column cycles through the active palette.
    // ================================================================
    function columnColor(col) {
        if (colorMode === 0 || !palettes || !palettes[paletteIndex])
            return baseColor.toString()
        return palettes[paletteIndex][col % palettes[paletteIndex].length]
    }

    // ================================================================
    // PRIVATE: returns true when grid cell (col, row) is occupied by
    // any active (non-expired) message in the queue.
    //
    // Called once per column per frame from renderColumnContent (pass 1).
    // Cost: O(maxMessages) integer comparisons per call – negligible.
    // ================================================================
    function isCellOccupied(col, row) {
        var now = Date.now()
        for (var m = 0; m < msgQueue.length; m++) {
            var msg = msgQueue[m]
            if (msg.expiry <= now) continue     // expired; Timer will remove
            if (col >= msg.col &&
                col <  msg.col + msg.blockCols &&
                row >= msg.row &&
                row <  msg.row + msg.lines.length) {
                return true
            }
        }
        return false
    }

    // ================================================================
    // PRIVATE: build display lines from topic + payload.
    //   Line 0   = MQTT topic (always present)
    //   Lines 1+ = payload – pretty-printed if valid JSON, else plain
    // Both line count and chars-per-line are hard-capped.
    // ================================================================
    function buildLines(topic, payload) {
        var lines    = []
        var ellipsis = "\u2026"   // '…'

        // Topic line
        var topicStr = (topic !== null && topic !== undefined) ? topic.toString() : ""
        lines.push(topicStr.length > maxLineLen
                   ? topicStr.substring(0, maxLineLen - 1) + ellipsis
                   : topicStr)

        // Payload lines
        var p = (payload !== null && payload !== undefined) ? payload.toString().trim() : ""
        if (p.length === 0) return lines

        var rawLines = []
        try {
            var parsed = JSON.parse(p)
            if (parsed !== null && typeof parsed === "object") {
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
            rawLines.push(p)   // not JSON – show as plain text
        }

        var remaining = maxLines - lines.length
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
    // PRIVATE: returns true when rectangle (col, row, nCols, nRows)
    // does NOT overlap any message currently in the queue.
    //
    // AABB non-overlap test:
    //   A and B do NOT overlap ⟺
    //   A.right ≤ B.left  ∨  A.left ≥ B.right  ∨
    //   A.bottom ≤ B.top  ∨  A.top ≥ B.bottom
    // ================================================================
    function isAreaFree(col, row, nCols, nRows) {
        for (var m = 0; m < msgQueue.length; m++) {
            var msg = msgQueue[m]
            var separated =
                (col + nCols <= msg.col)             ||
                (col >= msg.col + msg.blockCols)     ||
                (row + nRows <= msg.row)             ||
                (row >= msg.row + msg.lines.length)
            if (!separated) return false
        }
        return true
    }

    // ================================================================
    // PRIVATE: remove expired messages from the queue.
    // Called ONLY from the 1-Hz Timer – never from render functions.
    // ================================================================
    function purgeExpired() {
        var now  = Date.now()
        var prev = msgQueue.length
        var kept = []
        for (var i = 0; i < msgQueue.length; i++) {
            if (msgQueue[i].expiry > now) kept.push(msgQueue[i])
        }
        if (kept.length !== prev) {
            msgQueue = kept
            console.log("[HorizontalInlineRenderer] purged "
                        + (prev - kept.length) + " expired, "
                        + kept.length + " in queue")
        }
    }

    // ================================================================
    // PUBLIC: called by main.qml when an MQTT message arrives.
    // ================================================================
    function assignMessage(topic, payload) {
        if (columns === 0 || canvasWidth === 0 || canvasHeight === 0) {
            console.log("[HorizontalInlineRenderer] assignMessage: not ready"
                        + " (columns=" + columns
                        + " canvas=" + canvasWidth + "x" + canvasHeight + ")")
            return
        }

        var lines = buildLines(topic, payload)
        if (lines.length === 0) return

        // Block size in grid cells
        var blockCols = 0
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].length > blockCols) blockCols = lines[i].length
        }
        var blockRows = lines.length

        // Grid size
        var gridCols = Math.floor(canvasWidth  / fontSize)
        var gridRows = Math.floor(canvasHeight / fontSize)
        if (gridCols <= 0 || gridRows <= 0) return

        // Constrain so block stays fully on screen
        var maxCol = Math.max(0, gridCols - blockCols)
        var maxRow = Math.max(0, gridRows - blockRows)

        // Up to 12 random positions; take the first free one.
        // Fallback: use last attempted position (overlap > silent drop).
        var bestCol = Math.floor(Math.random() * (maxCol + 1))
        var bestRow = Math.floor(Math.random() * (maxRow + 1))
        for (var a = 0; a < 12; a++) {
            var tryCol = Math.floor(Math.random() * (maxCol + 1))
            var tryRow = Math.floor(Math.random() * (maxRow + 1))
            if (isAreaFree(tryCol, tryRow, blockCols, blockRows)) {
                bestCol = tryCol
                bestRow = tryRow
                break
            }
        }

        // Enforce max queue size – evict oldest first (FIFO)
        var newQueue = msgQueue.slice()
        while (newQueue.length >= maxMessages) {
            newQueue.shift()   // index 0 = oldest
        }

        newQueue.push({
            lines:     lines,
            col:       bestCol,
            row:       bestRow,
            blockCols: blockCols,
            expiry:    Date.now() + displayDuration
        })
        msgQueue = newQueue

        console.log("[HorizontalInlineRenderer] queued "
                    + blockCols + "x" + blockRows
                    + " at (" + bestCol + "," + bestRow + ")"
                    + "  queue=" + newQueue.length + "/" + maxMessages)
    }

    // ================================================================
    // Pass 1 – rain drop head.
    //
    // If the drop head lands on an occupied cell (active MQTT message),
    // return immediately without drawing. The drop still advances
    // normally so rain tempo is unaffected.
    //
    // Otherwise draw a random Katakana char (standard rain behaviour).
    // ================================================================
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var gridRow = Math.floor(y / fontSize)

        // Cell is occupied by an active message – skip.
        // renderInlineChars (pass 2) keeps it visible every frame.
        if (isCellOccupied(columnIndex, gridRow)) return

        // Normal rain: random Katakana at the drop head
        var color    = columnColor(columnIndex)
        var isGlitch = (Math.random() < glitchChance / 100)
        var ch       = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
        ctx.fillStyle = isGlitch ? "#ffffff" : color
        ctx.fillText(ch, x, y)
    }

    // ================================================================
    // Pass 2 – inject message chars into the matrix.
    //
    // Called once per frame by MatrixCanvas after the rain drop loop.
    // For each queued, non-expired message: draw every text line with
    // one ctx.fillText call per line. No background fill.
    //
    // Chars are drawn at high brightness every frame. This makes them
    // resist the global fade (Step 1 in MatrixCanvas) and remain
    // readable until expiry. After expiry they stop being drawn and
    // fade away naturally with the rest of the rain.
    //
    // Pixel coordinate convention (same as MatrixCanvas rain):
    //   pixel x  = col * fontSize
    //   pixel y  = (row + 1) * fontSize   ← text baseline (alphabetic)
    //
    // Max cost: maxMessages × maxLines = 15 × 12 = 180 fillText / frame.
    // ================================================================
    function renderInlineChars(ctx) {
        if (msgQueue.length === 0) return

        var now = Date.now()

        for (var m = 0; m < msgQueue.length; m++) {
            var msg = msgQueue[m]
            if (msg.expiry <= now) continue   // expired; skip until Timer purges

            var msgColor = columnColor(msg.col)

            for (var r = 0; r < msg.lines.length; r++) {
                var line = msg.lines[r]
                if (!line || line.length === 0) continue

                // Topic line (r=0): moderately bright – blends with rain palette.
                // Payload lines (r>0): high brightness – values are easy to read.
                ctx.fillStyle = (r === 0)
                    ? ColorUtils.lightenColor(msgColor, 0.40)   // topic
                    : ColorUtils.lightenColor(msgColor, 0.85)   // payload

                // One fillText per line; monospace font keeps chars grid-aligned.
                ctx.fillText(
                    line,
                    msg.col * fontSize,
                    (msg.row + r + 1) * fontSize   // baseline at bottom of row r
                )
            }
        }
    }

    // ================================================================
    // Column wrap callback – no per-column state to maintain.
    // ================================================================
    function onColumnWrap(columnIndex) { /* no-op */ }

    // ================================================================
    // Initialization – called by MatrixCanvas on first load, resize,
    // or render mode switch. Canvas dimensions must be set first.
    // ================================================================
    function initializeColumns(numColumns) {
        console.log("[HorizontalInlineRenderer] initializeColumns: "
                    + numColumns + " cols"
                    + "  canvas=" + canvasWidth + "x" + canvasHeight + "px")
        var newCA = []
        for (var i = 0; i < numColumns; i++) newCA.push(null)
        columnAssignments = newCA
        columns           = numColumns
        msgQueue          = []   // clear queue on re-init
    }

    // ================================================================
    // 1-Hz expiry timer. Purging once per second is sufficient;
    // displayDuration is in whole seconds (default 3 s).
    // ================================================================
    Timer {
        interval:  1000
        running:   true
        repeat:    true
        onTriggered: renderer.purgeExpired()
    }
}
