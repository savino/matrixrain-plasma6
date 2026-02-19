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
    // messageChars: [{ch: string, isValue: bool}, ...]
    //   isValue=false -> base palette color  (JSON keys, structural chars)
    //   isValue=true  -> lightened color     (JSON values, plain payloads)
    property var messageChars: []
    property var messageHistory: []
    readonly property int maxHistory: 5
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property int messagesReceived: 0

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    // -----------------------------------------------------------------------
    // FIX 1 — lightenColor
    // Blend a hex colour towards white by `factor` (0.0=unchanged, 1.0=white).
    // Handles #rrggbb and Qt's #aarrggbb (strips alpha prefix).
    // ROBUSTNESS: if parseInt yields NaN (e.g. named CSS colour like "green")
    //             the original colour string is returned unchanged.
    // -----------------------------------------------------------------------
    function lightenColor(hexColor, factor) {
        var src = hexColor.toString()
        var hex = src.replace(/^#/, "")
        if (hex.length === 8) hex = hex.substring(2)   // strip Qt alpha prefix
        var r = parseInt(hex.substring(0, 2), 16)
        var g = parseInt(hex.substring(2, 4), 16)
        var b = parseInt(hex.substring(4, 6), 16)
        // FIX 1: bail out if any channel failed to parse
        if (isNaN(r) || isNaN(g) || isNaN(b)) return src
        r = Math.min(255, Math.round(r + (255 - r) * factor))
        g = Math.min(255, Math.round(g + (255 - g) * factor))
        b = Math.min(255, Math.round(b + (255 - b) * factor))
        return "rgb(" + r + "," + g + "," + b + ")"
    }

    // -----------------------------------------------------------------------
    // FIX 2 — colorJsonChars
    // Tag every character of a valid JSON string as key/structural or value.
    // ROBUSTNESS:
    //   - Returns immediately (no-op) if `json` is null, undefined or empty.
    //   - The entire loop is wrapped in try/catch: if the state machine hits
    //     an unexpected edge-case, the remaining characters are appended with
    //     isValue=false (base colour) so `result` is always fully populated.
    //
    // States:
    //   ST_STRUCT     between tokens
    //   ST_IN_KEY     inside an object-key string
    //   ST_IN_VAL_STR inside a value string
    //   ST_IN_VAL_NUM inside a number / bool / null
    //
    // isValue=false : keys, { } [ ] : , whitespace
    // isValue=true  : value strings (quotes included), numbers, bool, null
    // -----------------------------------------------------------------------
    function colorJsonChars(json, result) {
        // FIX 2a: guard against null / empty input
        if (!json || json.length === 0) return

        var ST_STRUCT     = 0
        var ST_IN_KEY     = 1
        var ST_IN_VAL_STR = 2
        var ST_IN_VAL_NUM = 3

        var state      = ST_STRUCT
        var afterColon = false
        var arrayDepth = 0
        var escaped    = false
        var i          = 0

        // FIX 2b: catch any unexpected exception mid-parse
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
                        arrayDepth++; afterColon = false
                        result.push({ ch: ch, isValue: false })
                    } else if (ch === ']') {
                        if (arrayDepth > 0) arrayDepth--
                        result.push({ ch: ch, isValue: false })
                    } else if (ch === '{' || ch === '}' || ch === ',') {
                        afterColon = false
                        result.push({ ch: ch, isValue: false })
                    } else if (ch === ':') {
                        afterColon = true
                        result.push({ ch: ch, isValue: false })
                    } else if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
                        result.push({ ch: ch, isValue: false })
                    } else if (afterColon || arrayDepth > 0) {
                        state = ST_IN_VAL_NUM; afterColon = false
                        result.push({ ch: ch, isValue: true })
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
            // FIX 2b: append any remaining characters as uncolored base
            writeLog("colorJsonChars error at pos " + i + ": " + e)
            for (var k = i; k < json.length; k++)
                result.push({ ch: json.charAt(k), isValue: false })
        }
    }

    // -----------------------------------------------------------------------
    // FIX 3 — buildDisplayChars
    // Build the [{ch, isValue}] array: "<topic>: <payload>/"
    // ROBUSTNESS:
    //   - topic / payload normalised to safe strings at entry.
    //   - 3-level fallback:
    //       L1  JSON object/array  -> colorJsonChars()
    //       L2  plain scalar       -> flat isValue=true loop
    //       L3  outer try/catch    -> fully flat isValue=false chars
    //     Each level is independent; a failure in L1 never corrupts L2/L3.
    // -----------------------------------------------------------------------
    function buildDisplayChars(topic, payload) {
        // FIX 3a: normalise inputs — never let null/undefined reach charAt()
        var t = (topic   != null && topic   !== undefined) ? topic.toString()   : ""
        var p = (payload != null && payload !== undefined) ? payload.toString() : ""

        var result = []

        // FIX 3b: outer catch-all — if anything below throws, return flat chars
        try {
            for (var i = 0; i < t.length; i++)
                result.push({ ch: t.charAt(i), isValue: false })
            result.push({ ch: ':', isValue: false })
            result.push({ ch: ' ', isValue: false })

            // FIX 3c: L1/L2 separation — JSON parse failure goes to L2, not L3
            var parsed = null
            try { parsed = JSON.parse(p) } catch(e) { /* non-JSON payload, use L2 */ }

            if (parsed !== null && typeof parsed === "object") {
                // L1: JSON object or array
                colorJsonChars(p, result)
            } else {
                // L2: plain scalar (string, number, bool) or non-JSON
                for (var j = 0; j < p.length; j++)
                    result.push({ ch: p.charAt(j), isValue: true })
            }

            result.push({ ch: '/', isValue: false })

        } catch(e) {
            // L3: unexpected failure — rebuild as flat uncolored chars
            writeLog("buildDisplayChars error: " + e)
            result = []
            var flat = t + ": " + p + "/"
            for (var k = 0; k < flat.length; k++)
                result.push({ ch: flat.charAt(k), isValue: false })
        }

        return result
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

        // FIX 5 — onMessageReceived
        // Normalise topic and payload to strings before any processing.
        // A null/undefined argument from a misbehaving broker can no longer
        // propagate into buildDisplayChars or the history array.
        onMessageReceived: function(topic, payload) {
            var safeTopic   = (topic   != null && topic   !== undefined) ? topic.toString()   : ""
            var safePayload = (payload != null && payload !== undefined) ? payload.toString() : ""

            main.writeDebug("📨 [" + safeTopic + "] " + safePayload)
            main.messagesReceived++

            // History: newest first, max 5 — always store safe strings
            var hist = main.messageHistory.slice()
            hist.unshift({ topic: safeTopic, payload: safePayload })
            if (hist.length > main.maxHistory) hist = hist.slice(0, main.maxHistory)
            main.messageHistory = hist

            // Build colour-tagged char array — buildDisplayChars handles its own errors
            main.messageChars = main.buildDisplayChars(safeTopic, safePayload)

            canvas.requestPaint()
        }

        onConnectionError: function(error) { main.writeLog("❌ MQTT Error: " + error) }
    }

    function mqttConnect() {
        if (!main.mqttEnable) { mqttClient.disconnectFromHost(); return }
        var host  = main.mqttHost.trim()
        var topic = main.mqttTopic.trim()
        var user  = main.mqttUsername.trim()
        main.writeLog("Connecting to " + host + ":" + main.mqttPort + " topic=[" + topic + "]")
        mqttClient.host     = host
        mqttClient.port     = main.mqttPort
        mqttClient.username = user
        mqttClient.password = main.mqttPassword
        mqttClient.topic    = topic
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

            var hasMqttChars = main.mqttEnable
                               && main.messageChars
                               && main.messageChars.length > 0
            var msgLen = hasMqttChars ? main.messageChars.length : 0

            for (var i = 0; i < drops.length; i++) {
                var x = i * main.fontSize
                var y = drops[i] * main.fontSize

                // Base colour as string so lightenColor() can parse it
                var baseColor = (main.colorMode === 0)
                    ? main.singleColor.toString()
                    : main.palettes[main.paletteIndex][i % main.palettes[main.paletteIndex].length]

                var isGlitch = (Math.random() < main.glitchChance / 100)
                ctx.font = main.fontSize + "px monospace"

                var ch
                if (hasMqttChars) {
                    var r   = Math.floor(drops[i])
                    var idx = (r + i) % msgLen

                    // FIX 4: defensive entry check before accessing .ch / .isValue
                    // messageChars could be partially replaced during a property
                    // update between frames; an undefined entry must never crash.
                    var entry = (idx >= 0 && idx < main.messageChars.length)
                                ? main.messageChars[idx]
                                : null

                    if (!entry || typeof entry.ch !== "string" || entry.ch.length === 0) {
                        // Fallback: random katakana in base colour (keeps animation alive)
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
                ctx.fillStyle = "#aaaaaa"
                ctx.fillText("Msgs:   " + main.messagesReceived + "  |  Chars in rain: " + main.messageChars.length, TX, 94)

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
                        var entry2 = hist[m]
                        if (!entry2) continue
                        var line = (entry2.topic || "") + ": " + (entry2.payload || "")
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
        main.writeLog("MQTT host=[" + main.mqttHost + "] port=" + main.mqttPort + " topic=[" + main.mqttTopic + "]")
        canvas.initDrops()
        if (main.mqttEnable) Qt.callLater(mqttConnect)
        else main.writeLog("MQTT disabled — random Matrix characters")
    }

    Component.onDestruction: { mqttClient.disconnectFromHost() }
}
