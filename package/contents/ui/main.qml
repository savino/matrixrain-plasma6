import QtQuick 2.15
import QtQuick.Controls 2.15
import org.kde.plasma.plasmoid 2.0
import ObsidianReq.MQTTRain 1.0

WallpaperItem {
    id: main
    anchors.fill: parent

    property int fontSize: main.configuration.fontSize !== undefined ? main.configuration.fontSize : 16
    property int speed: main.configuration.speed !== undefined ? main.configuration.speed : 50
    property int colorMode: main.configuration.colorMode !== undefined ? main.configuration.colorMode : 0
    property color singleColor: main.configuration.singleColor !== undefined ? main.configuration.singleColor : "#00ff00"
    property int paletteIndex: main.configuration.paletteIndex !== undefined ? main.configuration.paletteIndex : 0
    property real jitter: main.configuration.jitter !== undefined ? main.configuration.jitter : 0
    property int glitchChance: main.configuration.glitchChance !== undefined ? main.configuration.glitchChance : 1

    // MQTT settings
    property bool mqttEnable: main.configuration.mqttEnable !== undefined ? main.configuration.mqttEnable : false
    property string mqttHost: (main.configuration.mqttHost !== undefined ? main.configuration.mqttHost : "homeassistant.lan").trim()
    property int mqttPort: main.configuration.mqttPort !== undefined ? main.configuration.mqttPort : 1883
    property string mqttTopic: (main.configuration.mqttTopic !== undefined ? main.configuration.mqttTopic : "zigbee2mqtt/#").trim()
    property string mqttUsername: (main.configuration.mqttUsername || "").trim()
    property string mqttPassword: (main.configuration.mqttPassword !== undefined && main.configuration.mqttPassword !== null) ? main.configuration.mqttPassword : ""
    property bool mqttDebug: main.configuration.mqttDebug !== undefined ? main.configuration.mqttDebug : false

    // State
    //
    // messageHistory:     [{topic, payload}, ...]  newest first, max maxHistory
    // messageHistoryChars: [[{ch,isValue},...], ...]  parallel array of tagged
    //                      char arrays, one per history slot.
    //
    // Paint rule: column i  ->  slot = i % messageHistoryChars.length
    //             char idx  ->  (floor(drops[i]) + i) % slotChars.length
    property var messageHistory:      []
    property var messageHistoryChars: []   // [[{ch,isValue}], ...]
    readonly property int maxHistory: 5
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property int messagesReceived: 0

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    // -----------------------------------------------------------------------
    // lightenColor: blend a hex colour towards white by `factor`
    // Handles #rrggbb and Qt's #aarrggbb. Returns original on parse failure.
    // -----------------------------------------------------------------------
    function lightenColor(hexColor, factor) {
        var src = hexColor.toString()
        var hex = src.replace(/^#/, "")
        if (hex.length === 8) hex = hex.substring(2)
        var r = parseInt(hex.substring(0, 2), 16)
        var g = parseInt(hex.substring(2, 4), 16)
        var b = parseInt(hex.substring(4, 6), 16)
        if (isNaN(r) || isNaN(g) || isNaN(b)) return src
        r = Math.min(255, Math.round(r + (255 - r) * factor))
        g = Math.min(255, Math.round(g + (255 - g) * factor))
        b = Math.min(255, Math.round(b + (255 - b) * factor))
        return "rgb(" + r + "," + g + "," + b + ")"
    }

    // -----------------------------------------------------------------------
    // colorJsonChars: tag each char of a valid JSON string as key/value.
    // isValue=false : keys, structural chars, whitespace
    // isValue=true  : value strings (quotes incl.), numbers, bool, null
    // -----------------------------------------------------------------------
    function colorJsonChars(json, result) {
        if (!json || json.length === 0) return

        var ST_STRUCT     = 0
        var ST_IN_KEY     = 1
        var ST_IN_VAL_STR = 2
        var ST_IN_VAL_NUM = 3

        var state = ST_STRUCT, afterColon = false, arrayDepth = 0, escaped = false
        var i = 0
        try {
            for (; i < json.length; i++) {
                var ch = json.charAt(i)
                if (state === ST_STRUCT) {
                    if (ch === '"') {
                        if (afterColon || arrayDepth > 0) {
                            state = ST_IN_VAL_STR; afterColon = false; escaped = false
                            result.push({ ch: ch, isValue: true })
                        } else {
                            state = ST_IN_KEY; escaped = false
                            result.push({ ch: ch, isValue: false })
                        }
                    } else if (ch === '[') {
                        arrayDepth++; afterColon = false; result.push({ ch: ch, isValue: false })
                    } else if (ch === ']') {
                        if (arrayDepth > 0) arrayDepth--; result.push({ ch: ch, isValue: false })
                    } else if (ch === '{' || ch === '}' || ch === ',') {
                        afterColon = false; result.push({ ch: ch, isValue: false })
                    } else if (ch === ':') {
                        afterColon = true; result.push({ ch: ch, isValue: false })
                    } else if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
                        result.push({ ch: ch, isValue: false })
                    } else if (afterColon || arrayDepth > 0) {
                        state = ST_IN_VAL_NUM; afterColon = false; result.push({ ch: ch, isValue: true })
                    } else {
                        result.push({ ch: ch, isValue: false })
                    }
                } else if (state === ST_IN_KEY) {
                    result.push({ ch: ch, isValue: false })
                    if (ch === '"' && !escaped) state = ST_STRUCT
                    escaped = (ch === '\\' && !escaped)
                } else if (state === ST_IN_VAL_STR) {
                    result.push({ ch: ch, isValue: true })
                    if (ch === '"' && !escaped) state = ST_STRUCT
                    escaped = (ch === '\\' && !escaped)
                } else if (state === ST_IN_VAL_NUM) {
                    if (ch === ',' || ch === '}' || ch === ']') {
                        state = ST_STRUCT; afterColon = false
                        if (ch === ']' && arrayDepth > 0) arrayDepth--
                        result.push({ ch: ch, isValue: false })
                    } else {
                        result.push({ ch: ch, isValue: true })
                    }
                }
            }
        } catch(e) {
            writeLog("colorJsonChars error at pos " + i + ": " + e)
            for (var k = i; k < json.length; k++)
                result.push({ ch: json.charAt(k), isValue: false })
        }
    }

    // -----------------------------------------------------------------------
    // buildDisplayChars: [{ch,isValue}] for "<topic>: <payload>/"
    // 3-level fallback: JSON -> plain string -> flat uncolored catch-all
    // -----------------------------------------------------------------------
    function buildDisplayChars(topic, payload) {
        var t = (topic   != null && topic   !== undefined) ? topic.toString()   : ""
        var p = (payload != null && payload !== undefined) ? payload.toString() : ""
        var result = []
        try {
            for (var i = 0; i < t.length; i++)
                result.push({ ch: t.charAt(i), isValue: false })
            result.push({ ch: ':', isValue: false })
            result.push({ ch: ' ', isValue: false })
            var parsed = null
            try { parsed = JSON.parse(p) } catch(e) {}
            if (parsed !== null && typeof parsed === "object") {
                colorJsonChars(p, result)
            } else {
                for (var j = 0; j < p.length; j++)
                    result.push({ ch: p.charAt(j), isValue: true })
            }
            result.push({ ch: '/', isValue: false })
        } catch(e) {
            writeLog("buildDisplayChars error: " + e)
            result = []
            var flat = t + ": " + p + "/"
            for (var k = 0; k < flat.length; k++)
                result.push({ ch: flat.charAt(k), isValue: false })
        }
        return result
    }

    // -----------------------------------------------------------------------
    // rebuildHistoryChars: rebuild the full messageHistoryChars array from
    // the current messageHistory. Called every time history changes.
    // -----------------------------------------------------------------------
    function rebuildHistoryChars() {
        var chars = []
        for (var s = 0; s < main.messageHistory.length; s++) {
            var e = main.messageHistory[s]
            if (e && e.topic !== undefined)
                chars.push(main.buildDisplayChars(e.topic, e.payload))
        }
        main.messageHistoryChars = chars
    }

    // -----------------------------------------------------------------------

    function writeLog(msg)   { console.log("[MQTTRain] " + msg) }
    function writeDebug(msg) { if (main.mqttDebug) console.log("[MQTTRain][debug] " + msg) }

    MQTTClient {
        id: mqttClient

        onConnectedChanged: {
            if (connected) {
                main.writeLog("✅ MQTT Connected")
            } else {
                main.writeLog("❌ MQTT Disconnected")
                if (main.mqttEnable) reconnectTimer.start()
            }
            canvas.requestPaint()
        }

        onMessageReceived: function(topic, payload) {
            var safeTopic   = (topic   != null && topic   !== undefined) ? topic.toString()   : ""
            var safePayload = (payload != null && payload !== undefined) ? payload.toString() : ""

            main.writeDebug("📨 [" + safeTopic + "] " + safePayload)
            main.messagesReceived++

            // Update history (newest first, max maxHistory)
            var hist = main.messageHistory.slice()
            hist.unshift({ topic: safeTopic, payload: safePayload })
            if (hist.length > main.maxHistory) hist = hist.slice(0, main.maxHistory)
            main.messageHistory = hist

            // Rebuild all slot char arrays to match the new history
            main.rebuildHistoryChars()

            canvas.requestPaint()
        }

        onConnectionError: function(error) { main.writeLog("❌ MQTT Error: " + error) }
    }

    function mqttConnect() {
        if (!main.mqttEnable) { mqttClient.disconnectFromHost(); return }
        main.writeLog("Connecting to " + main.mqttHost + ":" + main.mqttPort
                      + " topic=[" + main.mqttTopic + "]")
        mqttClient.host     = main.mqttHost.trim()
        mqttClient.port     = main.mqttPort
        mqttClient.username = main.mqttUsername.trim()
        mqttClient.password = main.mqttPassword
        mqttClient.topic    = main.mqttTopic.trim()
        mqttClient.connectToHost()
    }

    Timer {
        id: reconnectTimer
        interval: 5000; repeat: false
        onTriggered: {
            if (main.mqttEnable && !mqttClient.connected) {
                main.writeLog("🔄 Reconnecting...")
                mqttConnect()
            }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        property var drops: []

        function initDrops() {
            drops = []
            var cols = Math.floor(canvas.width / main.fontSize)
            for (var j = 0; j < cols; j++)
                drops.push(Math.random() * canvas.height / main.fontSize)
        }

        Timer {
            id: timer
            interval: 1000 / main.speed
            running: true; repeat: true
            onTriggered: canvas.requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d")
            var w = width, h = height

            ctx.fillStyle = "rgba(0,0,0,0.05)"
            ctx.fillRect(0, 0, w, h)

            var histChars   = main.messageHistoryChars   // [[{ch,isValue}],...]
            var nSlots      = (main.mqttEnable && histChars && histChars.length > 0)
                              ? histChars.length : 0

            for (var i = 0; i < drops.length; i++) {
                var x = i * main.fontSize
                var y = drops[i] * main.fontSize

                var baseColor = (main.colorMode === 0)
                    ? main.singleColor.toString()
                    : main.palettes[main.paletteIndex][i % main.palettes[main.paletteIndex].length]

                var isGlitch = (Math.random() < main.glitchChance / 100)
                ctx.font = main.fontSize + "px monospace"

                var ch
                if (nSlots > 0) {
                    // Each column is assigned to a history slot by interleaving:
                    // col 0 -> slot 0 (newest), col 1 -> slot 1, ...
                    // col nSlots -> slot 0 again, and so on.
                    var slot      = i % nSlots
                    var slotChars = histChars[slot]
                    var slotLen   = (slotChars && slotChars.length > 0) ? slotChars.length : 0

                    if (slotLen > 0) {
                        var r   = Math.floor(drops[i])
                        var idx = (r + i) % slotLen

                        // Defensive entry check (FIX 4)
                        var entry = (idx >= 0 && idx < slotChars.length)
                                    ? slotChars[idx] : null

                        if (!entry || typeof entry.ch !== "string" || entry.ch.length === 0) {
                            ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                            ctx.fillStyle = isGlitch ? "#ffffff" : baseColor
                        } else {
                            ch = entry.ch
                            if (isGlitch) {
                                ctx.fillStyle = "#ffffff"
                            } else if (entry.isValue) {
                                ctx.fillStyle = main.lightenColor(baseColor, 0.55)
                            } else {
                                ctx.fillStyle = baseColor
                            }
                        }
                    } else {
                        // Slot exists but is empty: random katakana
                        ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                        ctx.fillStyle = isGlitch ? "#ffffff" : baseColor
                    }
                } else {
                    // No history yet: random katakana
                    ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                    ctx.fillStyle = isGlitch ? "#ffffff" : baseColor
                }

                ctx.fillText(ch, x, y)

                drops[i] += 1 + Math.random() * main.jitter / 100
                if (drops[i] * main.fontSize > h + main.fontSize)
                    drops[i] = 0
            }

            // Debug overlay
            if (main.debugOverlay) {
                var BOX_X = 8, BOX_Y = 8, BOX_W = 760, BOX_H = 222
                var TX = 14, LINE = 16

                ctx.fillStyle = "rgba(0,0,0,0.88)"
                ctx.fillRect(BOX_X, BOX_Y, BOX_W, BOX_H)

                ctx.font = "bold 13px monospace"
                ctx.fillStyle = "#00ff00"
                ctx.fillText("⚙️ MQTT Rain Debug", TX, 26)

                ctx.font = "12px monospace"
                ctx.fillStyle = mqttClient.connected ? "#00ff00" : "#ff4444"
                ctx.fillText("MQTT:   " + (mqttClient.connected ? "✅ CONNECTED" : "❌ DISCONNECTED"), TX, 46)
                ctx.fillStyle = "#00ccff"
                ctx.fillText("Broker: " + main.mqttHost + ":" + main.mqttPort, TX, 62)
                ctx.fillText("Topic:  " + main.mqttTopic, TX, 78)

                // Total chars across all active slots
                var totalChars = 0
                for (var s = 0; s < main.messageHistoryChars.length; s++)
                    if (main.messageHistoryChars[s]) totalChars += main.messageHistoryChars[s].length

                ctx.fillStyle = "#aaaaaa"
                ctx.fillText("Msgs:   " + main.messagesReceived
                             + "  |  Slots: " + main.messageHistoryChars.length
                             + "  |  Chars: " + totalChars, TX, 94)

                ctx.fillStyle = "#555555"
                ctx.fillRect(TX, 103, BOX_W - 20, 1)
                ctx.fillStyle = "#888888"
                ctx.fillText("Recent messages (newest first):", TX, 116)

                var alphas = ["#ffff00","#cccc00","#999900","#666600","#444400"]
                var hist = main.messageHistory
                var baseY = 132

                if (hist.length === 0) {
                    ctx.fillStyle = "#555555"
                    ctx.fillText("(waiting for messages...)", TX, baseY)
                } else {
                    for (var m = 0; m < hist.length; m++) {
                        var hEntry = hist[m]
                        if (!hEntry) continue
                        var line = (hEntry.topic || "") + ": " + (hEntry.payload || "")
                        if (line.length > 98) line = line.substring(0, 95) + "…"
                        ctx.fillStyle = alphas[m]
                        ctx.fillText(line, TX, baseY + m * LINE)
                    }
                }
            }
        }

        Component.onCompleted: initDrops()
    }

    onFontSizeChanged:     { canvas.initDrops(); canvas.requestPaint() }
    onSpeedChanged:        { timer.interval = 1000 / main.speed }
    onColorModeChanged:    canvas.requestPaint()
    onSingleColorChanged:  canvas.requestPaint()
    onPaletteIndexChanged: canvas.requestPaint()
    onJitterChanged:       canvas.requestPaint()
    onGlitchChanceChanged: canvas.requestPaint()
    onDebugOverlayChanged: canvas.requestPaint()

    onMqttEnableChanged: { mqttEnable ? mqttConnect() : mqttClient.disconnectFromHost() }
    onMqttHostChanged:   { if (mqttEnable) mqttConnect() }
    onMqttPortChanged:   { if (mqttEnable) mqttConnect() }
    onMqttTopicChanged:  { if (mqttEnable && mqttClient.connected) { mqttClient.disconnectFromHost(); mqttConnect() } }

    Component.onCompleted: {
        main.writeLog("=== Matrix Rain MQTT Wallpaper ===")
        main.writeLog("MQTT host=[" + main.mqttHost + "] port=" + main.mqttPort
                      + " topic=[" + main.mqttTopic + "]")
        canvas.initDrops()
        if (main.mqttEnable) Qt.callLater(mqttConnect)
        else main.writeLog("MQTT disabled — random Matrix characters")
    }

    Component.onDestruction: { mqttClient.disconnectFromHost() }
}
