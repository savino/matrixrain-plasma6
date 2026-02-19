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
    // lightenColor: blend a hex colour towards white by `factor`
    //   0.0 = no change   1.0 = pure white
    //   Handles both #rrggbb and Qt's #aarrggbb (strips alpha prefix).
    // -----------------------------------------------------------------------
    function lightenColor(hexColor, factor) {
        var hex = hexColor.toString().replace(/^#/, "")
        if (hex.length === 8) hex = hex.substring(2)   // strip Qt alpha prefix
        var r = parseInt(hex.substring(0, 2), 16)
        var g = parseInt(hex.substring(2, 4), 16)
        var b = parseInt(hex.substring(4, 6), 16)
        r = Math.min(255, Math.round(r + (255 - r) * factor))
        g = Math.min(255, Math.round(g + (255 - g) * factor))
        b = Math.min(255, Math.round(b + (255 - b) * factor))
        return "rgb(" + r + "," + g + "," + b + ")"
    }

    // -----------------------------------------------------------------------
    // colorJsonChars: push {ch, isValue} entries into `result` for every
    // character of the JSON string `json`.
    //
    // States:
    //   ST_STRUCT     - between tokens (structural chars, whitespace)
    //   ST_IN_KEY     - inside a string that is an object key
    //   ST_IN_VAL_STR - inside a string that is a value
    //   ST_IN_VAL_NUM - inside a number / bool / null value
    //
    // isValue=false : keys, {,},[,],:,, and whitespace
    // isValue=true  : value strings (incl. quotes), numbers, booleans, null
    // -----------------------------------------------------------------------
    function colorJsonChars(json, result) {
        var ST_STRUCT     = 0
        var ST_IN_KEY     = 1
        var ST_IN_VAL_STR = 2
        var ST_IN_VAL_NUM = 3

        var state      = ST_STRUCT
        var afterColon = false
        var arrayDepth = 0
        var escaped    = false

        for (var i = 0; i < json.length; i++) {
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
    }

    // -----------------------------------------------------------------------
    // buildDisplayChars: build the [{ch, isValue}] array for the rain.
    //   Format rendered: "<topic>: <payload>/"
    //   - topic    -> all isValue=false
    //   - ": "     -> isValue=false
    //   - payload  -> colorJsonChars() if JSON object/array,
    //                 all isValue=true for plain strings (e.g. "online")
    //   - "/"      -> isValue=false  (loop separator)
    // -----------------------------------------------------------------------
    function buildDisplayChars(topic, payload) {
        var result = []

        for (var i = 0; i < topic.length; i++)
            result.push({ ch: topic.charAt(i), isValue: false })
        result.push({ ch: ':', isValue: false })
        result.push({ ch: ' ', isValue: false })

        var parsed = null
        try { parsed = JSON.parse(payload) } catch(e) {}

        if (parsed !== null && typeof parsed === "object") {
            colorJsonChars(payload, result)
        } else {
            for (var j = 0; j < payload.length; j++)
                result.push({ ch: payload.charAt(j), isValue: true })
        }

        result.push({ ch: '/', isValue: false })
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

        onMessageReceived: function(topic, payload) {
            main.writeDebug("📨 [" + topic + "] " + payload)
            main.messagesReceived++

            // History: newest first, max 5
            var hist = main.messageHistory.slice()
            hist.unshift({ topic: topic, payload: payload })
            if (hist.length > main.maxHistory) hist = hist.slice(0, main.maxHistory)
            main.messageHistory = hist

            // Build colour-tagged char array for the rain
            main.messageChars = main.buildDisplayChars(topic, payload)

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
                    var entry = main.messageChars[idx]   // {ch, isValue}
                    ch = entry.ch

                    if (isGlitch) {
                        ctx.fillStyle = "#ffffff"
                    } else if (entry.isValue) {
                        // Value chars: blend 55% towards white for brightness
                        ctx.fillStyle = main.lightenColor(baseColor, 0.55)
                    } else {
                        // Key / structural chars: raw palette colour
                        ctx.fillStyle = baseColor
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
                        var line = hist[m].topic + ": " + hist[m].payload
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
