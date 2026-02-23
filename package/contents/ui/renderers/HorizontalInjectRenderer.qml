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
        // Non rimuoviamo le celle scadute - lasciamole fare fade naturale
        // Verranno rimosse solo quando un drop Katakana ci passa sopra
    }

    function isAreaFree(startCol, startRow, width, height, nowMs) {
        // Controlla se l'area rettangolare è libera da celle MQTT attive
        for (var r = startRow; r < startRow + height && r < rows; r++) {
            for (var c = startCol; c < startCol + width && c < columns; c++) {
                var key = cellKey(c, r)
                var cell = mqttCells[key]
                if (cell && cell.expiresAt > nowMs) {
                    return false  // Area occupata da cella attiva
                }
            }
        }
        return true
    }

    function assignMessage(topic, payload) {
        if (columns <= 0) return

        ensureGridMetrics()

        var safePayload = (payload != null && payload !== undefined) ? payload.toString() : ""
        if (safePayload.trim().length === 0) return

        cleanupExpiredCells(Date.now())

        var safeTopic = (topic != null && topic !== undefined) ? topic.toString() : ""

        // Tenta pretty print JSON
        var displayText = safePayload
        var isJson = false
        try {
            var parsed = JSON.parse(safePayload)
            if (parsed !== null && typeof parsed === "object") {
                displayText = JSON.stringify(parsed, null, 2)
                isJson = true
            }
        } catch(e) {
            // Non JSON valido, usa payload originale
        }

        // Costruisci righe (topic + payload)
        var lines = []
        if (safeTopic.length > 0) {
            lines.push({ text: "topic: " + safeTopic, isJson: false })
        }
        var payloadLines = displayText.split('\n')
        for (var i = 0; i < payloadLines.length; i++) {
            lines.push({ text: payloadLines[i], isJson: isJson })
        }

        var maxLineLength = 0
        for (var j = 0; j < lines.length; j++) {
            if (lines[j].text.length > maxLineLength) {
                maxLineLength = lines[j].text.length
            }
        }

        var msgHeight = lines.length
        var msgWidth = Math.min(maxLineLength, columns)

        // Cerca posizione libera (max 10 tentativi)
        var placed = false
        var startRow, startCol
        var now = Date.now()
        var expiresAt = now + mqttCellLifetimeMs

        for (var attempt = 0; attempt < 10 && !placed; attempt++) {
            startRow = Math.floor(Math.random() * Math.max(1, rows - msgHeight + 1))
            startCol = Math.floor(Math.random() * Math.max(1, columns - msgWidth + 1))
            
            if (isAreaFree(startCol, startRow, msgWidth, msgHeight, now)) {
                placed = true
            }
        }

        // Se non trovato spazio, usa ultima posizione comunque
        if (!placed) {
            startRow = Math.floor(Math.random() * rows)
            startCol = Math.floor(Math.random() * Math.max(1, columns - msgWidth + 1))
        }

        // Piazza le celle per ogni riga del messaggio
        for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
            var line = lines[lineIdx]
            var row = startRow + lineIdx
            if (row >= rows) break

            // Converti la linea in array di char con colorazione JSON
            var lineChars = []
            if (line.isJson) {
                Logic.colorJsonChars(line.text, lineChars)
            }
            if (lineChars.length === 0) {
                for (var k = 0; k < line.text.length; k++) {
                    lineChars.push({ ch: line.text.charAt(k), isValue: false })
                }
            }

            for (var charIdx = 0; charIdx < lineChars.length && charIdx < msgWidth; charIdx++) {
                var col = (startCol + charIdx) % columns
                setCell(col, row, lineChars[charIdx], expiresAt)
            }
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
                return  // Salto ostacolo: cella MQTT ancora attiva
            }
            // Cella scaduta: applica fade accelerato (equivalente a ~30 frame di fade naturale)
            for (var i = 0; i < 30; i++) {
                ctx.fillStyle = "rgba(0,0,0," + fadeStrength + ")"
                ctx.fillRect(x, y - fontSize, fontSize, fontSize)
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
            
            // Non ridisegnare celle scadute (lasciale fare fade naturale)
            if (cell.expiresAt <= now) continue

            var color = (colorMode === 0)
                ? baseColor.toString()
                : palettes[paletteIndex][0]

            var x = cell.col * fontSize
            var y = cell.row * fontSize

            ctx.fillStyle = cell.isValue
                ? ColorUtils.lightenColor(color, 0.55)
                : color
            ctx.fillText(cell.ch, x, y)
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
