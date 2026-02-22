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
//     This is what creates the "fading trail" of the rain.
//     Alpha = fadeStrength (configurable, typically 0.03–0.10).
//
//   Step 2 – Rain drop loop
//     For each column i:
//       a. Call activeRenderer.renderColumnContent() at the drop head.
//       b. Advance drops[i] unconditionally (jitter applies).
//       c. Wrap drops[i] to 0 and notify renderer via onColumnWrap().
//
//   Step 3 – Optional overlay pass
//     If activeRenderer exposes renderOverlay(), call it once.
//     This is used by HorizontalOverlayRenderer to redraw message
//     text at full brightness on top of the rain chars.
//
// ─────────────────────────────────────────────────────────────────
// RENDERER INTERFACE  (methods activeRenderer must implement)
//
//   initializeColumns(numColumns)           – reset state for new col count
//   renderColumnContent(ctx, i, x, y, drops) – draw one char at drop head
//   onColumnWrap(columnIndex)               – drop wrapped; update state
//   renderOverlay(ctx)              [opt.]  – second draw pass per frame
//
//   Properties read by MatrixCanvas:
//   jitter       – extra random drop-speed variance (0–100)
//   canvasWidth  [opt.] – set before initializeColumns if renderer needs it
//   canvasHeight [opt.]
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

    // ── Drop state: one float per column, in grid-row units ──────────
    property var drops: []

    // ================================================================
    // Initialize drops array and the active renderer.
    // Must be called whenever fontSize, canvas size, or renderer changes.
    // Sets canvasWidth/Height on the renderer BEFORE initializeColumns
    // so the renderer has accurate dimensions from the very first call.
    // ================================================================
    function initDrops() {
        // Guard: canvas may not have its final size yet on first call
        if (canvas.width <= 0 || canvas.height <= 0) return

        var cols = Math.floor(canvas.width / fontSize)
        var newDrops = []
        for (var j = 0; j < cols; j++) {
            // Randomise initial drop positions for a natural stagger
            newDrops.push(Math.random() * canvas.height / fontSize)
        }
        drops = newDrops

        if (activeRenderer) {
            // Pass pixel dimensions BEFORE initializeColumns so the renderer
            // can compute grid rows from the start (e.g. HorizontalOverlayRenderer)
            if (activeRenderer.canvasWidth !== undefined) {
                activeRenderer.canvasWidth  = canvas.width
                activeRenderer.canvasHeight = canvas.height
            }
            activeRenderer.initializeColumns(cols)
        }
    }

    // ================================================================
    // React when the renderer is swapped (mode switch from main.qml).
    // Reinitialises the new renderer immediately so it is ready to
    // render on the very next paint tick, even before main.qml's
    // onMqttRenderModeChanged handler calls initDrops() explicitly.
    // ================================================================
    onActiveRendererChanged: {
        if (activeRenderer && canvas.width > 0 && canvas.height > 0) {
            if (activeRenderer.canvasWidth !== undefined) {
                activeRenderer.canvasWidth  = canvas.width
                activeRenderer.canvasHeight = canvas.height
            }
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
    // Main rendering loop – executes Steps 1–3 described above.
    // ================================================================
    onPaint: {
        var ctx = getContext("2d")
        var w   = canvas.width
        var h   = canvas.height

        if (!activeRenderer) return

        // ── Step 1: fade overlay ──────────────────────────────────────
        ctx.fillStyle = "rgba(0,0,0," + fadeStrength + ")"
        ctx.fillRect(0, 0, w, h)

        // Set font once per frame (same for all renderers)
        ctx.font = fontSize + "px monospace"

        // ── Step 2: rain drop loop ────────────────────────────────────
        for (var i = 0; i < drops.length; i++) {
            var x = i * fontSize
            var y = drops[i] * fontSize

            // Delegate character rendering to the active renderer
            activeRenderer.renderColumnContent(ctx, i, x, y, drops)

            // Advance drop unconditionally – never paused by overlay logic.
            // jitter adds a small random speed variation per column.
            drops[i] += 1 + Math.random() * activeRenderer.jitter / 100

            // Wrap drop back to the top when it exits the bottom of the canvas
            if (drops[i] * fontSize > h + fontSize) {
                drops[i] = 0
                activeRenderer.onColumnWrap(i)
            }
        }

        // ── Step 3: optional overlay pass ────────────────────────────
        // Only renderers that implement renderOverlay() use this pass.
        // Other renderers (ClassicRenderer, MixedModeRenderer, etc.) do not
        // define the function, so the check is false and nothing happens.
        if (typeof activeRenderer.renderOverlay === "function") {
            activeRenderer.renderOverlay(ctx)
        }
    }

    // ── Resize / init handlers ────────────────────────────────────────
    onWidthChanged:  initDrops()
    onHeightChanged: initDrops()

    Component.onCompleted: initDrops()
}
