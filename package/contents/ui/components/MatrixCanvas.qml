// MatrixCanvas.qml
// Base canvas component for Matrix rain rendering
// Renderer-agnostic: delegates column content to activeRenderer

import QtQuick 2.15

Canvas {
    id: canvas
    anchors.fill: parent

    // Visual configuration
    property int  fontSize:     16
    property int  speed:        50
    property real fadeStrength: 0.05
    property bool mqttEnable:   false

    // Active renderer (injected)
    property var activeRenderer: null

    // Drop positions (per column)
    property var drops: []

    /**
     * Initialize drops array and renderer columns
     */
    function initDrops() {
        drops = []
        var cols = Math.floor(canvas.width / fontSize)

        for (var j = 0; j < cols; j++) {
            drops.push(Math.random() * canvas.height / fontSize)
        }

        // Pass canvas dimensions to renderer when available
        if (activeRenderer && activeRenderer.canvasWidth !== undefined) {
            activeRenderer.canvasWidth  = canvas.width
            activeRenderer.canvasHeight = canvas.height
        }

        // Initialize renderer
        if (activeRenderer) {
            activeRenderer.initializeColumns(cols)
        }
    }

    /**
     * Animation timer
     */
    Timer {
        id: timer
        interval: 1000 / canvas.speed
        running:  true
        repeat:   true
        onTriggered: canvas.requestPaint()
    }

    /**
     * Main rendering loop
     */
    onPaint: {
        var ctx = getContext("2d")
        var w = width
        var h = height

        // Fade overlay (creates trail effect)
        ctx.fillStyle = "rgba(0,0,0," + fadeStrength + ")"
        ctx.fillRect(0, 0, w, h)

        // Verify renderer is available
        if (!activeRenderer) return

        // Setup font
        ctx.font = fontSize + "px monospace"

        // Render each column
        for (var i = 0; i < drops.length; i++) {
            var x = i * fontSize
            var y = drops[i] * fontSize

            // Delegate column rendering to active renderer
            // The renderer decides what to draw (rain char or overlay char)
            activeRenderer.renderColumnContent(ctx, i, x, y, drops)

            // Only advance the drop if the current cell is NOT protected
            var gridRow = Math.floor(y / fontSize)
            var cellProtected = (typeof activeRenderer.isCellProtected === "function")
                ? activeRenderer.isCellProtected(i, gridRow)
                : false

            if (!cellProtected) {
                drops[i] += 1 + Math.random() * activeRenderer.jitter / 100
            }

            // Wrap at bottom
            if (drops[i] * fontSize > h + fontSize) {
                drops[i] = 0
                activeRenderer.onColumnWrap(i)
            }
        }
    }

    /**
     * Handle resize
     */
    onWidthChanged: initDrops()
    onHeightChanged: requestPaint()

    /**
     * Initialize on creation
     */
    Component.onCompleted: initDrops()
}
