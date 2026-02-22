// MatrixCanvas.qml
// Base canvas component for Matrix rain rendering
// Renderer-agnostic: delegates column content to activeRenderer
//
// Rendering pipeline each frame:
//   1. Fill fade overlay (rgba black with low alpha → trail effect)
//   2. For each drop: call activeRenderer.renderColumnContent() at drop head
//      and advance drop normally (always, regardless of renderer type)
//   3. If renderer exposes renderOverlay(): call it once for overlay pass

import QtQuick 2.15

Canvas {
    id: canvas
    anchors.fill: parent

    // Visual configuration
    property int  fontSize:     16
    property int  speed:        50
    property real fadeStrength: 0.05
    property bool mqttEnable:   false

    // Active renderer (injected from main.qml)
    property var activeRenderer: null

    // Drop positions (per column, in grid units)
    property var drops: []

    // -----------------------------------------------------------------
    // Initialize drops and renderer
    // -----------------------------------------------------------------
    function initDrops() {
        drops = []
        var cols = Math.floor(canvas.width / fontSize)

        for (var j = 0; j < cols; j++) {
            drops.push(Math.random() * canvas.height / fontSize)
        }

        if (activeRenderer) {
            // Pass canvas pixel dimensions BEFORE initializeColumns
            // so the renderer knows the screen size from the start
            if (activeRenderer.canvasWidth !== undefined) {
                activeRenderer.canvasWidth  = canvas.width
                activeRenderer.canvasHeight = canvas.height
            }
            activeRenderer.initializeColumns(cols)
        }
    }

    // -----------------------------------------------------------------
    // Animation timer
    // -----------------------------------------------------------------
    Timer {
        id: timer
        interval:  1000 / canvas.speed
        running:   true
        repeat:    true
        onTriggered: canvas.requestPaint()
    }

    // -----------------------------------------------------------------
    // Main rendering loop
    // -----------------------------------------------------------------
    onPaint: {
        var ctx = getContext("2d")
        var w   = width
        var h   = height

        // --- Step 1: fade overlay (creates the trailing-light effect) ---
        ctx.fillStyle = "rgba(0,0,0," + fadeStrength + ")"
        ctx.fillRect(0, 0, w, h)

        if (!activeRenderer) return

        ctx.font = fontSize + "px monospace"

        // --- Step 2: rain loop – one char per column at drop head ---
        for (var i = 0; i < drops.length; i++) {
            var x = i * fontSize
            var y = drops[i] * fontSize

            // Renderer draws whatever char belongs at this position
            activeRenderer.renderColumnContent(ctx, i, x, y, drops)

            // Drops ALWAYS advance – never paused by overlay logic
            drops[i] += 1 + Math.random() * activeRenderer.jitter / 100

            // Wrap drop back to top
            if (drops[i] * fontSize > h + fontSize) {
                drops[i] = 0
                activeRenderer.onColumnWrap(i)
            }
        }

        // --- Step 3: overlay pass (optional, renderer-specific) ---
        // Called ONCE per frame. Renderers that support a second draw
        // pass (e.g. HorizontalOverlayRenderer) expose renderOverlay().
        if (typeof activeRenderer.renderOverlay === "function") {
            activeRenderer.renderOverlay(ctx)
        }
    }

    // -----------------------------------------------------------------
    // Resize handlers
    // -----------------------------------------------------------------
    onWidthChanged:  initDrops()
    onHeightChanged: requestPaint()

    Component.onCompleted: initDrops()
}
