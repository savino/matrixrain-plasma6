// MatrixCanvas.qml
//
// Base canvas component for Matrix rain rendering.
// Renderer-agnostic: all visual decisions are delegated to activeRenderer.
//
// ─────────────────────────────────────────────────────────────────
// RENDERING PIPELINE (executed every timer tick)
//
//   Step 1 – Fade overlay
//     Fill the whole canvas with a low-alpha black rectangle.
//     Creates the trailing-light / fade effect of the rain.
//     Alpha = fadeStrength (configurable, typically 0.03–0.10).
//
//   Step 2 – Rain drop loop
//     For each column i:
//       a. Call activeRenderer.renderColumnContent() at the drop head.
//       b. Advance drops[i] unconditionally (+ jitter variance).
//       c. Wrap drops[i] to 0 and notify renderer via onColumnWrap().
//
//   Step 3 – Optional overlay pass
//     If activeRenderer exposes renderOverlay(ctx), call it once.
//     Used by HorizontalOverlayRenderer (MQTT Inline mode) to draw
//     message text on top of the rain without interfering with drops.
//
// ─────────────────────────────────────────────────────────────────
// RENDERER INTERFACE  (methods activeRenderer must implement)
//
//   initializeColumns(numColumns)            – reset for new column count
//   renderColumnContent(ctx, i, x, y, drops) – draw one char at drop head
//   onColumnWrap(columnIndex)                – drop wrapped; update state
//   renderOverlay(ctx)               [opt.]  – second draw pass per frame
//
//   Properties read/set by MatrixCanvas on the renderer (if they exist):
//     jitter       – extra random drop-speed variance (0–100)
//     canvasWidth  – canvas pixel width (set before initializeColumns)
//     canvasHeight – canvas pixel height (set before initializeColumns)
//     fadeStrength – same value used in step 1 (for ghost-clear tuning)
// ─────────────────────────────────────────────────────────────────

import QtQuick 2.15

Canvas {
    id: canvas
    anchors.fill: parent

    // ── Visual configuration (bound from main.qml) ───────────────────
    property int  fontSize:     16
    property int  speed:        50
    property real fadeStrength: 0.05
    property bool mqttEnable:   false

    // ── Active renderer (injected from main.qml via property binding) ─
    property var activeRenderer: null

    // ── Drop state: one float per column (in grid-row units) ──────────
    property var drops: []

    // ================================================================
    // Initialize drops array and the active renderer.
    // Sets canvasWidth/Height and fadeStrength on the renderer BEFORE
    // calling initializeColumns so the renderer has all context it needs.
    // ================================================================
    function initDrops() {
        // Guard: canvas may not have its final size on the first call
        if (canvas.width <= 0 || canvas.height <= 0) return

        var cols = Math.floor(canvas.width / fontSize)

        // Randomise initial drop positions for a natural stagger
        var newDrops = []
        for (var j = 0; j < cols; j++) {
            newDrops.push(Math.random() * canvas.height / fontSize)
        }
        drops = newDrops

        if (activeRenderer) {
            // Pass canvas context to renderer BEFORE initializeColumns
            if (activeRenderer.canvasWidth  !== undefined) activeRenderer.canvasWidth  = canvas.width
            if (activeRenderer.canvasHeight !== undefined) activeRenderer.canvasHeight = canvas.height
            if (activeRenderer.fadeStrength !== undefined) activeRenderer.fadeStrength = canvas.fadeStrength
            activeRenderer.initializeColumns(cols)
        }
    }

    // ================================================================
    // React when the renderer is swapped (render mode switch).
    // Initialises the new renderer immediately so it is ready to paint
    // on the very next tick, before main.qml’s explicit initDrops() call.
    // ================================================================
    onActiveRendererChanged: {
        if (activeRenderer && canvas.width > 0 && canvas.height > 0) {
            if (activeRenderer.canvasWidth  !== undefined) activeRenderer.canvasWidth  = canvas.width
            if (activeRenderer.canvasHeight !== undefined) activeRenderer.canvasHeight = canvas.height
            if (activeRenderer.fadeStrength !== undefined) activeRenderer.fadeStrength = canvas.fadeStrength
            activeRenderer.initializeColumns(Math.floor(canvas.width / fontSize))
        }
    }

    // ================================================================
    // Animation timer – triggers a repaint at the configured speed.
    // ================================================================
    Timer {
        id:       timer
        interval: 1000 / canvas.speed
        running:  true
        repeat:   true
        onTriggered: canvas.requestPaint()
    }

    // ================================================================
    // Main rendering loop – executes Steps 1–3 described in the header.
    // ================================================================
    onPaint: {
        var ctx = getContext("2d")
        var w   = canvas.width
        var h   = canvas.height

        if (!activeRenderer) return

        // ── Step 1: global fade overlay ────────────────────────────────
        ctx.fillStyle = "rgba(0,0,0," + fadeStrength + ")"
        ctx.fillRect(0, 0, w, h)

        // Set font once per frame (shared by all renderers)
        ctx.font = fontSize + "px monospace"

        // ── Step 2: rain drop loop ────────────────────────────────────
        for (var i = 0; i < drops.length; i++) {
            var x = i * fontSize
            var y = drops[i] * fontSize

            // Renderer decides what char to draw (or skips) at drop head
            activeRenderer.renderColumnContent(ctx, i, x, y, drops)

            // Drop advances unconditionally – never paused by overlay logic
            drops[i] += 1 + Math.random() * activeRenderer.jitter / 100

            // Wrap to top when drop exits bottom of canvas
            if (drops[i] * fontSize > h + fontSize) {
                drops[i] = 0
                activeRenderer.onColumnWrap(i)
            }
        }

        // ── Step 3: optional overlay pass ────────────────────────────
        // Only called for renderers that implement renderOverlay().
        // Other renderers (Classic, Mixed, etc.) don’t define it,
        // so typeof returns "undefined" and the call is skipped.
        if (typeof activeRenderer.renderOverlay === "function") {
            activeRenderer.renderOverlay(ctx)
        }
    }

    // ── Resize / init handlers ────────────────────────────────────────
    onWidthChanged:  initDrops()
    onHeightChanged: initDrops()

    Component.onCompleted: initDrops()
}
