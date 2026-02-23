// HorizontalInjectRenderer.qml
// Render mode: Horizontal Inject
// MQTT chars are injected as horizontal, time-limited obstacle cells.

import QtQuick 2.15
import "../utils/MatrixRainLogic.js" as Logic
import "../utils/ColorUtils.js" as ColorUtils

Item {
    id: renderer

    property var columnAssignments: []
    property int columns: 0

    property int fontSize: 16
    property color baseColor: "#00ff00"
    property real jitter: 0
    property int glitchChance: 1
    property var palettes: []
    property int paletteIndex: 0
    property int colorMode: 0

    property int canvasWidth: 0
    property int canvasHeight: 0
    property real fadeStrength: 0.05

    property int rows: 0
    property int mqttCellLifetimeMs: 3000

    property var mqttCells: ({})
    property var activeCellCountByColumn: []

    function cellKey(col, row) {
        return col + ":" + row
    }

    function rowCountFromCanvas() {
        if (fontSize <= 0 || canvasHeight <= 0) return 1
        return Math.max(1, Math.floor(canvasHeight / fontSize))
    }

    function ensureGridMetrics() {
        rows = rowCountFromCanvas()
    }

    function updateColumnActive(columnIndex) {
        var isActive = activeCellCountByColumn[columnIndex] > 0
        var newCA = columnAssignments.slice()
        newCA[columnIndex] = isActive ? { active: true } : null
        columnAssignments = newCA
    }

    function removeCellByKey(key) {
        var existing = mqttCells[key]
        if (!existing) return

        delete mqttCells[key]

        var col = existing.col
        if (col >= 0 && col < activeCellCountByColumn.length) {
            activeCellCountByColumn[col] = Math.max(0, activeCellCountByColumn[col] - 1)
            updateColumnActive(col)
        }
    }

    function setCell(col, row, entry, expiresAt) {
        var key = cellKey(col, row)
        var existing = mqttCells[key]

        if (!existing) {
            activeCellCountByColumn[col] += 1
            updateColumnActive(col)
        }

        mqttCells[key] = {
            col: col,
            row: row,
            ch: (entry && entry.ch) ? entry.ch : " ",
            isValue: !!(entry && entry.isValue),
            expiresAt: expiresAt
        }
    }

    function cleanupExpiredCells(nowMs) {
        var keys = Object.keys(mqttCells)
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]
            var cell = mqttCells[key]
            if (!cell || cell.expiresAt <= nowMs) {
                removeCellByKey(key)
            }
        }
    }

    function assignMessage(topic, payload) {
        if (columns <= 0) return

        ensureGridMetrics()

        var chars = Logic.buildDisplayChars(topic, payload)
        if (!chars || chars.length === 0) return

        cleanupExpiredCells(Date.now())

        var row = Math.floor(Math.random() * rows)
        var startCol = Math.floor(Math.random() * columns)
        var expiresAt = Date.now() + mqttCellLifetimeMs

        for (var i = 0; i < chars.length; i++) {
            var col = (startCol + i) % columns
            setCell(col, row, chars[i], expiresAt)
        }
    }

    function renderColumnContent(ctx, columnIndex, x, y, drops) {
        ensureGridMetrics()

        var row = Math.floor(drops[columnIndex])
        if (row < 0 || row >= rows) return

        var key = cellKey(columnIndex, row)
        var cell = mqttCells[key]
        if (cell) {
            if (cell.expiresAt > Date.now()) {
                return
            }
            removeCellByKey(key)
        }

        var color = (colorMode === 0)
            ? baseColor.toString()
            : palettes[paletteIndex][columnIndex % palettes[paletteIndex].length]

        var isGlitch = (Math.random() < glitchChance / 100)
        var ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))

        ctx.fillStyle = isGlitch ? "#ffffff" : color
        ctx.fillText(ch, x, y)
    }

    function onColumnWrap(columnIndex) {
        // No-op: MQTT cells are time-based, not pass-based.
    }

    function renderInlineChars(ctx) {
        ensureGridMetrics()

        var now = Date.now()
        cleanupExpiredCells(now)

        var keys = Object.keys(mqttCells)
        for (var i = 0; i < keys.length; i++) {
            var cell = mqttCells[keys[i]]
            if (!cell) continue

            var color = (colorMode === 0)
                ? baseColor.toString()
                : palettes[paletteIndex][cell.col % palettes[paletteIndex].length]

            var brightColor = cell.isValue
                ? ColorUtils.lightenColor(color, 0.70)
                : ColorUtils.lightenColor(color, 0.55)

            ctx.fillStyle = brightColor
            ctx.fillText(cell.ch, cell.col * fontSize, cell.row * fontSize)
        }
    }

    function initializeColumns(numColumns) {
        ensureGridMetrics()

        columns = numColumns

        var newCA = []
        var newCounts = []
        for (var i = 0; i < numColumns; i++) {
            newCA.push(null)
            newCounts.push(0)
        }

        columnAssignments = newCA
        activeCellCountByColumn = newCounts
        mqttCells = ({})
    }
}
