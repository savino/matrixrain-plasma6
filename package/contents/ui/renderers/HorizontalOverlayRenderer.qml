// HorizontalOverlayRenderer.qml  (v5 – MQTT Inline, no background box)
//
// ─────────────────────────────────────────────────────────────────
// PURPOSE
//   Render mode 3 – "MQTT Inline".
//   Classic vertical Matrix rain runs continuously at all times.
//   When an MQTT message arrives, its characters REPLACE the rain
//   characters at a random screen position – no background box,
//   no overlay UI widget. The MQTT chars look like part of the rain.
//
// ─────────────────────────────────────────────────────────────────
// VISUAL DESIGN INTENT
//
//   The MQTT text should look like it BELONGS to the rain:
//   • No black background rectangle (that would look like a UI popup).
//   • MQTT chars drawn at high brightness – they stand out from the
//     fading rain chars around them, as if the rain "mutated" to spell
//     out the message.
//   • Old rain chars in the message area are ghost-cleared quickly
//     (within ~5 frames / 100 ms) so the MQTT text reads cleanly.
//   • After expiry the MQTT chars fade away naturally with the normal
//     canvas fade, and rain drops refill the area.
//
// ─────────────────────────────────────────────────────────────────
// RENDERING PIPELINE  (two passes per frame, driven by MatrixCanvas)
//
//   Pass 1 – renderColumnContent(ctx, col, x, y, drops)
//     Called once per column per frame at the drop-head position.
//
//     CASE A – drop head is OUTSIDE any active message block:
//       → Draw a random Katakana char (classic rain). No change.
//
//     CASE B – drop head is INSIDE an active message block:
//       → Apply an accelerated per-cell black fade rectangle.
//         Alpha = fadeStrength * GHOST_CLEAR_MULTIPLIER (default 8×).
//         This is NOT opaque – it is a fast but gradual darkening that
//         clears ghost rain chars in ~5 frames without creating a
//         visible rectangular border.
//       → Return without drawing a Katakana char.
//         (The MQTT char for this cell is drawn by renderOverlay.)
//
//   Pass 2 – renderOverlay(ctx)
//     Called ONCE per frame by MatrixCanvas after the rain loop.
//     For each active message, draw each text line with one fillText.
//     NO fillRect background – chars only, on top of the (fading) rain.
//     MQTT chars are drawn at high brightness so they dominate visually.
//
// ─────────────────────────────────────────────────────────────────
// MESSAGE LIFECYCLE
//
//   assignMessage() ← called by main.qml on every non-blacklisted message
//     1. Build + truncate text lines (topic + pretty-print payload)
//     2. Find low-overlap position (AABB test, 12 random tries)
//     3. Enforce hard cap: drop oldest if maxMessages is reached
//     4. Push { lines, col, row, blockCols, expiry } to activeMessages
//
//   Timer (1 Hz) ← purgeExpired()
//     Removes messages past their expiry.
//     NEVER called inside render functions (hot path).
//
// ─────────────────────────────────────────────────────────────────
// PERFORMANCE BUDGET
//   maxMessages =  5 → ≤5 blocks active simultaneously
//   maxLines    = 12 → ≤60 fillText calls/frame (pass 2)
//   isCellActive   → O(maxMessages)=O(5) per column per frame (pass 1)
//   purgeExpired   → O(5) once per second
//   Ghost clearing → 1 fillRect per MQTT drop-head hit (rare, fast)
// ─────────────────────────────────────────────────────────────────

import QtQuick 2.15
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    // ── Interface required by MatrixCanvas ──────────────────────────
    property var columnAssignments: []   // compatibility stub; not used for logic
    property int columns: 0              // grid column count, set by initializeColumns

    // ── Visual config (bound from main.qml) ─────────────────────────
    property int   fontSize:     16
    property color baseColor:    "#00ff00"
    property real  jitter:       0
    property int   glitchChance: 1
    property var   palettes:     []
    property int   paletteIndex: 0
    property int   colorMode:    0

    // ── Canvas pixel dimensions (set by MatrixCanvas BEFORE initializeColumns) ─
    property int canvasWidth:  0
    property int canvasHeight: 0

    // ── fadeStrength mirror (set by MatrixCanvas, same value used in onPaint) ─
    // Used to compute the accelerated ghost-clearing alpha in pass 1.
    property real fadeStrength: 0.05

    // ── Tunable ─────────────────────────────────────────────────────
    property int displayDuration: 3000   // ms each block stays on screen

    // How much faster to fade ghost rain chars inside an MQTT block.
    // 8 means 8× the normal canvas fade alpha is applied to that cell
    // each time the rain drop head passes through it.
    // Higher = faster ghost clear, but must stay well below 1.0 to
    // avoid a visible rectangular edge artifact.
    // At fadeStrength=0.05: 8 × 0.05 = 0.40 alpha → ghosts gone in ~5 frames.
    readonly property real GHOST_CLEAR_MULTIPLIER: 8.0

    // ── Hard performance limits (intentionally conservative) ─────────────
    readonly property int maxMessages: 5   // concurrent blocks on screen
    readonly property int maxLines:    12  // text lines per block (incl. topic)
    readonly property int maxLineLen:  60  // characters per line

    // ── Internal state ───────────────────────────────────────────────
    // Each entry: { lines:[string], col:int, row:int, blockCols:int, expiry:int }
    // Array is FIFO: index 0 = oldest. shift() removes the oldest.
    property var activeMessages: []

    // ================================================================
    // PRIVATE: resolve base colour for grid column `col`.
    // In colorMode 0, all columns use baseColor.
    // In multi-colour modes, each column cycles through the palette.
    // ================================================================
    function columnColor(col) {
        if (colorMode === 0 || !palettes || !palettes[paletteIndex])
            return baseColor.toString()
        return palettes[paletteIndex][col % palettes[paletteIndex].length]
    }

    // ================================================================
    // PRIVATE: true when grid cell (col, row) falls inside any active
    // (non-expired) message block.
    //
    // Called once per column per frame from renderColumnContent (pass 1).
    // Cost: O(maxMessages) = O(5) integer comparisons – negligible.
    // ================================================================
    function isCellActive(col, row) {
        var now = Date.now()
        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]
            if (msg.expiry <= now) continue       // expired; Timer will clean up
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
    //   Line 0  = MQTT topic (always present)
    //   Lines 1+ = payload, pretty-printed if valid JSON, else plain
    // Both line count and char count are hard-capped.
    // ================================================================
    function buildLines(topic, payload) {
        var lines    = []
        var ellipsis = "\u2026"   // Unicode horizontal ellipsis

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
                // Pretty-print JSON with 2-space indent, skip blank lines
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
    // PRIVATE: true when the candidate rectangle (col, row, nCols, nRows)
    // does NOT overlap any currently active message block.
    //
    // Standard AABB non-overlap test:
    //   A and B do NOT overlap ⇔
    //   A.right ≤ B.left  ∨  A.left ≥ B.right  ∨
    //   A.bottom ≤ B.top  ∨  A.top ≥ B.bottom
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
    // PRIVATE: remove messages past their expiry timestamp.
    // Called ONLY from the 1-Hz Timer. NEVER from render functions.
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
            console.log("[MQTTInlineRenderer] purged "
                        + (prev - kept.length) + " expired, "
                        + kept.length + " remaining")
        }
    }

    // ================================================================
    // PUBLIC: called by main.qml when an MQTT message is received.
    // ================================================================
    function assignMessage(topic, payload) {
        // Guard: renderer must be initialised before accepting messages
        if (columns === 0 || canvasWidth === 0 || canvasHeight === 0) {
            console.log("[MQTTInlineRenderer] assignMessage: not ready "
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

        // Compute grid dimensions from canvas pixel size
        var gridCols = Math.floor(canvasWidth  / fontSize)
        var gridRows = Math.floor(canvasHeight / fontSize)
        if (gridCols <= 0 || gridRows <= 0) return

        // Constrain block so it stays fully on screen
        var maxCol = Math.max(0, gridCols - blockCols)
        var maxRow = Math.max(0, gridRows - blockRows)

        // Try up to 12 random positions; use the first fully-free one.
        // Fallback: use last candidate (partial overlap beats silent drop).
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

        // Hard cap: evict oldest message when list is full (FIFO)
        var newList = activeMessages.slice()
        if (newList.length >= maxMessages) {
            newList.shift()   // index 0 = oldest
        }

        newList.push({
            lines:     lines,
            col:       bestCol,
            row:       bestRow,
            blockCols: blockCols,
            expiry:    Date.now() + displayDuration
        })
        activeMessages = newList

        console.log("[MQTTInlineRenderer] placed "
                    + blockCols + "x" + blockRows
                    + " at (" + bestCol + "," + bestRow + ")"
                    + "  active=" + newList.length + "/" + maxMessages)
    }

    // ================================================================
    // Pass 1 – Rain character at the drop head.
    //
    // CASE A – drop head is OUTSIDE any active message block:
    //   Draw a random Katakana char (classic rain behaviour).
    //
    // CASE B – drop head is INSIDE an active message block:
    //   Apply an accelerated per-cell fade rectangle to quickly clear
    //   ghost rain chars without creating a visible box border:
    //     alpha = fadeStrength × GHOST_CLEAR_MULTIPLIER
    //   This darkens the cell faster than the global fade overlay but
    //   is still semi-transparent, so no sharp rectangular edge appears.
    //   After ~5 frames the old ghost chars are effectively invisible.
    //   Then return without drawing a Katakana – renderOverlay handles
    //   the MQTT char for this cell.
    //
    // The drop ALWAYS advances (no pausing), so rain rhythm is preserved.
    // ================================================================
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        var gridRow = Math.floor(y / fontSize)

        if (isCellActive(columnIndex, gridRow)) {
            // Accelerated ghost-clear: semi-transparent black over this cell.
            // Only applied when the drop head sweeps through, which happens
            // once per column per pass – very low cost.
            var clearAlpha = Math.min(0.95, fadeStrength * GHOST_CLEAR_MULTIPLIER)
            ctx.fillStyle = "rgba(0,0,0," + clearAlpha + ")"
            ctx.fillRect(columnIndex * fontSize, gridRow * fontSize,
                         fontSize, fontSize)   // one cell only, not the whole block
            return
            // renderOverlay will draw the MQTT char here each frame
        }

        // Classic rain: random Katakana character at the drop head
        var color    = columnColor(columnIndex)
        var isGlitch = (Math.random() < glitchChance / 100)
        var ch       = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
        ctx.fillStyle = isGlitch ? "#ffffff" : color
        ctx.fillText(ch, x, y)
    }

    // ================================================================
    // Pass 2 – MQTT text rendering.
    //
    // Called ONCE per frame by MatrixCanvas after the rain loop.
    // Draws each active message’s text lines at high brightness.
    //
    // NO fillRect background – chars only, on the (fading) canvas.
    // MQTT chars are bright enough to visually dominate the faded rain
    // chars underneath them, giving the appearance of replacement.
    //
    // Coordinate convention (consistent with MatrixCanvas / rain):
    //   pixel x = col * fontSize
    //   pixel y = (row + 1) * fontSize  ← text baseline (alphabetic)
    //
    // Max cost: maxMessages × maxLines = 5 × 12 = 60 fillText / frame.
    // ================================================================
    function renderOverlay(ctx) {
        if (activeMessages.length === 0) return

        var now = Date.now()

        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]
            if (msg.expiry <= now) continue   // expired; skip until Timer purges

            // Anchor colour to the message’s leftmost column
            var msgColor = columnColor(msg.col)

            for (var r = 0; r < msg.lines.length; r++) {
                var line = msg.lines[r]
                if (!line || line.length === 0) continue

                // Topic line (r=0): moderately bright, same palette as rain.
                // Payload lines (r>0): very bright so values are easy to read
                //   and clearly stand out from surrounding rain chars.
                ctx.fillStyle = (r === 0)
                    ? ColorUtils.lightenColor(msgColor, 0.40)   // topic
                    : ColorUtils.lightenColor(msgColor, 0.85)   // payload values

                // One fillText per line; monospace font aligns chars to the grid.
                // NO background fill – the bright chars are drawn directly over
                // the (fading) canvas content.
                ctx.fillText(
                    line,
                    msg.col * fontSize,
                    (msg.row + r + 1) * fontSize   // baseline at bottom of grid row r
                )
            }
        }
    }

    // ================================================================
    // Column wrap callback – no per-column state needed here.
    // ================================================================
    function onColumnWrap(columnIndex) { /* no-op */ }

    // ================================================================
    // Initialization – called by MatrixCanvas whenever drops are reset
    // (first load, screen resize, or render mode switch).
    // Canvas dimensions MUST be set on this object before this call.
    // ================================================================
    function initializeColumns(numColumns) {
        console.log("[MQTTInlineRenderer] initializeColumns: "
                    + numColumns + " cols"
                    + "  canvas=" + canvasWidth + "x" + canvasHeight + "px")
        var newCA = []
        for (var i = 0; i < numColumns; i++) newCA.push(null)
        columnAssignments = newCA
        columns           = numColumns
        activeMessages    = []   // clear overlays on re-init
    }

    // ================================================================
    // 1-Hz expiry timer. Low frequency is intentional: purgeExpired
    // is O(maxMessages)=O(5), so even running at the render rate would
    // be fine – but there is no benefit to doing it more than once/sec.
    // ================================================================
    Timer {
        interval:  1000
        running:   true
        repeat:    true
        onTriggered: renderer.purgeExpired()
    }
}
