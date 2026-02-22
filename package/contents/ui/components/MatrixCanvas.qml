// MatrixCanvas.qml
//
// Base canvas component for Matrix rain rendering.
// Renderer-agnostic: all visual decisions are delegated to activeRenderer.
//
// ─────────────────────────────────────────────────────────────────
// RENDERING PIPELINE (executed every timer tick)
//
//   Step 1 – Fade
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
//   Step 3 – Optional inline-chars pass (renderInlineChars)
//     If activeRenderer exposes renderInlineChars(ctx), call it once.
//     Used by HorizontalInlineRenderer to redraw active MQTT message
//     chars at full brightness every frame, keeping them visible until
//     their expiry time despite the global fade of Step 1.
//
// ─────────────────────────────────────────────────────────────────
// RENDERER INTERFACE  (methods activeRenderer must implement)
//
//   initializeColumns(numColumns)            – reset for new column count
//   renderColumnContent(ctx, i, x, y, drops) – draw one char at drop head
//   onColumnWrap(columnIndex)                – drop wrapped; update state
//   renderInlineChars(ctx)           [opt.]  – second draw pass per frame
//
//   Properties read/set by MatrixCanvas on the renderer (if they exist):
//     jitter       – extra random drop-speed variance (0–100)
//     canvasWidth  – canvas pixel width (set before initializeColumns)
//     canvasHeight – canvas pixel height (set before initializeColumns)
//     fadeStrength – same value used in step 1 (available for renderer use)
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
    // calling initializeColumns so the renderer has full context.
    // ================================================================
    function initDrops() {
        if (canvas.width <= 0 || canvas.height <= 0) return

        var cols = Math.floor(canvas.width / fontSize)

        var newDrops = []
        for (var j = 0; j < cols; j++) {
            newDrops.push(Math.random() * canvas.height / fontSize)
        }
        drops = newDrops

        if (activeRenderer) {
            if (activeRenderer.canvasWidth  !== undefined) activeRenderer.canvasWidth  = canvas.width
            if (activeRenderer.canvasHeight !== undefined) activeRenderer.canvasHeight = canvas.height
            if (activeRenderer.fadeStrength !== undefined) activeRenderer.fadeStrength = canvas.fadeStrength
            activeRenderer.initializeColumns(cols)
        }
    }

    // ================================================================
    // React when the renderer is swapped (render mode switch).
    // Initialises the new renderer immediately on the next tick.
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
    // Main rendering loop – Steps 1–3.
    // ================================================================
    onPaint: {
        var ctx = getContext("2d")
        var w   = canvas.width
        var h   = canvas.height

        if (!activeRenderer) return

        // ── Step 1: global fade ────────────────────────────────────────
        ctx.fillStyle = "rgba(0,0,0," + fadeStrength + ")"
        ctx.fillRect(0, 0, w, h)

        // Font set once per frame (shared by all renderers)
        ctx.font = fontSize + "px monospace"

        // ── Step 2: rain drop loop ─────────────────────────────────────
        for (var i = 0; i < drops.length; i++) {
            var x = i * fontSize
            var y = drops[i] * fontSize

            activeRenderer.renderColumnContent(ctx, i, x, y, drops)

            drops[i] += 1 + Math.random() * activeRenderer.jitter / 100

            if (drops[i] * fontSize > h + fontSize) {
                drops[i] = 0
                activeRenderer.onColumnWrap(i)
            }
        }

        // ── Step 3: inline-chars pass (optional) ──────────────────────
        // Only called if the renderer implements renderInlineChars().
        // HorizontalInlineRenderer uses this to keep injected MQTT chars
        // visible at full brightness until their expiry time.
        if (typeof activeRenderer.renderInlineChars === "function") {
            activeRenderer.renderInlineChars(ctx)
        }
    }

    onWidthChanged:  initDrops()
    onHeightChanged: initDrops()
    Component.onCompleted: initDrops()
}
