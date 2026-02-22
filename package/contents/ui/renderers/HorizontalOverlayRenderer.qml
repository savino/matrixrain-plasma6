// HorizontalOverlayRenderer.qml  (v4 – MQTT Inline / substitution mode)
//
// ─────────────────────────────────────────────────────────────────
// PURPOSE
//   Render mode 3 – "MQTT Inline".
//   Classic vertical Matrix rain runs continuously at all times.
//   Incoming MQTT messages appear as readable text blocks that
//   REPLACE (not overlay) the rain characters at their position.
//
// ─────────────────────────────────────────────────────────────────
// SUBSTITUTION vs OVERLAY – key design distinction
//
//   OVERLAY  (old): rain draws katakana → MQTT text drawn on top.
//            Result: both visible simultaneously, characters "stack".
//
//   SUBSTITUTION (this version): within an active message block...
//     • renderColumnContent() SKIPS the rain char (returns immediately).
//     • renderOverlay() clears the block area to black, then draws the
//       MQTT text. No rain char ever appears at an MQTT cell.
//   Result: MQTT text cleanly replaces rain chars. The block area looks
//   like a dark terminal window embedded in the Matrix rain.
//   When the message expires the block area transitions naturally back
//   to rain (new drop heads fill the cells over the next few frames).
//
// ─────────────────────────────────────────────────────────────────
// RENDERING PIPELINE  (two passes per frame, driven by MatrixCanvas)
//
//   Pass 1 – renderColumnContent(ctx, col, x, y, drops)
//     Called once per column per frame at the drop-head position.
//     • If the drop head is inside an active message block → RETURN.
//       (isCellActive check: O(maxMessages) = O(5) per call)
//     • Otherwise → draw a random Katakana char (classic rain).
//     Drops ALWAYS advance unconditionally.
//
//   Pass 2 – renderOverlay(ctx)
//     Called ONCE per frame by MatrixCanvas after the rain loop.
//     For each active message:
//       a. Fill the block rectangle with opaque black (clears accumulated
//          rain chars – guarantees clean substitution on first frame).
//       b. Draw each text line with one ctx.fillText call.
//
// ─────────────────────────────────────────────────────────────────
// MESSAGE LIFECYCLE
//
//   assignMessage() ← called by main.qml on every non-blacklisted message
//     1. Build + truncate text lines (topic + pretty-print payload)
//     2. Find low-overlap position (rectangle AABB test, 12 random tries)
//     3. Enforce hard cap: drop oldest message if maxMessages is reached
//     4. Push { lines, col, row, blockCols, expiry } to activeMessages
//
//   Timer (1 Hz) ← purgeExpired()
//     Removes messages past their expiry.
//     NEVER called inside render functions (hot path).
//
// ─────────────────────────────────────────────────────────────────
// PERFORMANCE BUDGET
//   maxMessages  =  5  → at most 5 blocks active simultaneously
//   maxLines     = 12  → at most 60 fillText calls per frame (pass 2)
//   isCellActive     → O(5) per column per frame (pass 1)
//   purgeExpired     → O(5) once per second
//   No flat cell map, no Object.keys(), no per-character fillText.
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

    // ── Tunable ───────────────────────────────────────────────────
    property int displayDuration: 3000  // ms each block remains visible

    // ── Hard performance limits (intentionally conservative) ─────────────
    readonly property int maxMessages: 5   // concurrent blocks on screen
    readonly property int maxLines:    12  // text lines per block (incl. topic)
    readonly property int maxLineLen:  60  // characters per line

    // ── Internal state ───────────────────────────────────────────────
    // Each entry: { lines:[string], col:int, row:int, blockCols:int, expiry:int }
    // Sorted oldest-first (index 0 = oldest). shift() removes the oldest.
    property var activeMessages: []

    // ================================================================
    // PRIVATE: resolve base colour for grid column `col`.
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
    // Called once per column per frame from renderColumnContent.
    // Cost: O(maxMessages) = O(5) simple integer comparisons – negligible.
    // ================================================================
    function isCellActive(col, row) {
        var now = Date.now()
        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]
            if (msg.expiry <= now) continue   // expired; Timer will purge
            // Rectangle containment test
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
    //   Line 0  = MQTT topic
    //   Lines 1+ = payload (pretty-printed JSON or plain text)
    // Lines and characters are truncated to maxLines / maxLineLen.
    // ================================================================
    function buildLines(topic, payload) {
        var lines   = []
        var ellipsis = "\u2026"

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
                // Valid JSON object/array → indent with 2 spaces
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
            // Not valid JSON – show as plain text
            rawLines.push(p)
        }

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
    // overlap any active message block.
    //
    // Uses AABB (axis-aligned bounding-box) non-overlap test:
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
    // Called ONLY from the 1-Hz Timer. Never from render functions.
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

        // Grid dimensions (cells)
        var gridCols = Math.floor(canvasWidth  / fontSize)
        var gridRows = Math.floor(canvasHeight / fontSize)
        if (gridCols <= 0 || gridRows <= 0) return

        // Maximum top-left corner keeping the block fully on screen
        var maxCol = Math.max(0, gridCols - blockCols)
        var maxRow = Math.max(0, gridRows - blockRows)

        // Try up to 12 random positions; take the first fully-free one.
        // If no free position found, the last candidate is used anyway
        // (partial overlap is preferable to silently dropping the message).
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

        // Hard cap: discard the oldest entry when the list is full
        var newList = activeMessages.slice()
        if (newList.length >= maxMessages) {
            newList.shift()   // FIFO – oldest is at index 0
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
    // If the drop head lands on a cell occupied by an active message
    // block, we SKIP drawing (return immediately). The cell will be
    // handled exclusively by renderOverlay (pass 2).
    //
    // This is the core of the substitution mechanism:
    // rain chars and MQTT chars never share the same cell.
    //
    // Cost: isCellActive is O(maxMessages) = O(5) per call.
    // ================================================================
    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        // Determine which grid row the drop head is currently at
        var gridRow = Math.floor(y / fontSize)

        // If this cell belongs to an active MQTT block, skip rain char.
        // renderOverlay will draw the correct MQTT char here.
        if (isCellActive(columnIndex, gridRow)) return

        // Normal rain: random Katakana character
        var color    = columnColor(columnIndex)
        var isGlitch = (Math.random() < glitchChance / 100)
        var ch       = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
        ctx.fillStyle = isGlitch ? "#ffffff" : color
        ctx.fillText(ch, x, y)
    }

    // ================================================================
    // Pass 2 – Inline message rendering.
    //
    // Called ONCE per frame by MatrixCanvas after the rain loop.
    // For each active message:
    //   Step A – Fill the block rectangle with opaque black.
    //            This immediately clears any rain chars that may have
    //            accumulated in this area before the message arrived,
    //            and ensures a clean background every frame.
    //   Step B – Draw each text line with one ctx.fillText per line.
    //            Monospace font keeps characters grid-aligned.
    //
    // Pixel coordinate convention (consistent with MatrixCanvas rain):
    //   x = col * fontSize
    //   y = (row + 1) * fontSize   ← text baseline (textBaseline="alphabetic")
    //   The block fill covers [row*fontSize … (row+lines.length)*fontSize]
    //   vertically, which matches the visual extent of the text.
    //
    // Max cost: maxMessages × maxLines = 5 × 12 = 60 fillText calls/frame.
    // ================================================================
    function renderOverlay(ctx) {
        if (activeMessages.length === 0) return

        var now = Date.now()

        for (var m = 0; m < activeMessages.length; m++) {
            var msg = activeMessages[m]

            // Skip messages that the Timer hasn't purged yet
            if (msg.expiry <= now) continue

            // ── Step A: clear the block area to opaque black ────────────────
            // This erases any previously drawn rain chars inside the
            // block and guarantees clean substitution from the first frame.
            // When the message later expires, rain drops will naturally
            // fill the black area back in over the next few frames.
            ctx.fillStyle = "rgb(0,0,0)"
            ctx.fillRect(
                msg.col * fontSize,               // x: left edge
                msg.row * fontSize,               // y: top edge
                msg.blockCols * fontSize,         // width
                msg.lines.length * fontSize       // height
            )

            // ── Step B: draw text lines ────────────────────────────────
            var msgColor = columnColor(msg.col)

            for (var r = 0; r < msg.lines.length; r++) {
                var line = msg.lines[r]
                if (!line || line.length === 0) continue

                // Topic (r=0): dimmer accent colour to distinguish from payload.
                // Payload (r>0): bright, high contrast against black background.
                ctx.fillStyle = (r === 0)
                    ? ColorUtils.lightenColor(msgColor, 0.35)   // topic
                    : ColorUtils.lightenColor(msgColor, 0.80)   // payload

                // One fillText per line; monospace font aligns chars to the grid
                ctx.fillText(
                    line,
                    msg.col * fontSize,
                    (msg.row + r + 1) * fontSize   // baseline of row (msg.row + r)
                )
            }
        }
    }

    // ================================================================
    // Column wrap callback – no per-column state needed.
    // ================================================================
    function onColumnWrap(columnIndex) { /* no-op */ }

    // ================================================================
    // Initialization – called by MatrixCanvas whenever drops are reset.
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

        // Clear active blocks on re-init (resize / mode switch)
        activeMessages = []
    }

    // ================================================================
    // 1-Hz expiry timer. Keep interval ≥ 1000 ms to avoid
    // redundant iterations on an already-small array.
    // ================================================================
    Timer {
        interval:  1000
        running:   true
        repeat:    true
        onTriggered: renderer.purgeExpired()
    }
}
