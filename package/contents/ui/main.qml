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
    property var messageChars: []

    // Ring-buffer di 5 slot fissi: null = slot vuoto, {topic, payload} = messaggio
    property var messageHistory: [null, null, null, null, null]
    readonly property int maxHistory: 5
    // Punta allo slot che riceverà il prossimo messaggio (= posizione del più vecchio)
    property int mqttNextSlot: 0

    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property int messagesReceived: 0

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    function writeLog(msg) {
        console.log("[MQTTRain] " + msg)
    }
    function writeDebug(msg) {
        if (main.mqttDebug)
            console.log("[MQTTRain][debug] " + msg)
    }

    MQTTClient {
        id: mqttClient

        onConnectedChanged: {
            if (connected) {
                main.writeLog("✅ MQTT Connected")
            } else {
                main.writeLog("❌ MQTT Disconnected")
                if (main.mqttEnable)
                    reconnectTimer.start()
            }
            canvas.requestPaint()
        }

        onMessageReceived: function(topic, payload) {
            main.writeDebug("📨 [" + topic + "] " + payload)
            main.messagesReceived++

            // Ring-buffer: scrivi nello slot più vecchio, poi avanza il puntatore
            var hist = main.messageHistory.slice()
            hist[main.mqttNextSlot] = { topic: topic, payload: payload }
            main.mqttNextSlot = (main.mqttNextSlot + 1) % main.maxHistory
            main.messageHistory = hist

            // Build the display string for the rain: "topic: payload/"
            var display = topic + ": " + payload + "/"
            var chars = []
            for (var i = 0; i < display.length; i++)
                chars.push(display.charAt(i))
            main.messageChars = chars

            canvas.requestPaint()
        }

        onConnectionError: function(error) {
            main.writeLog("❌ MQTT Error: " + error)
        }
    }

    function mqttConnect() {
        if (!main.mqttEnable) {
            mqttClient.disconnectFromHost()
            return
        }
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
        interval: 5000
        repeat: false
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
            running: true
            repeat: true
            onTriggered: canvas.requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d")
            var w = width, h = height

            // Fade previous frame to create trailing effect
            ctx.fillStyle = "rgba(0,0,0,0.05)"
            ctx.fillRect(0, 0, w, h)

            var hasMqttChars = main.mqttEnable
                               && main.messageChars
                               && main.messageChars.length > 0
            var msgLen = hasMqttChars ? main.messageChars.length : 0

            for (var i = 0; i < drops.length; i++) {
                var x = i * main.fontSize
                var y = drops[i] * main.fontSize

                var color = main.colorMode === 0
                    ? main.singleColor
                    : main.palettes[main.paletteIndex][i % main.palettes[main.paletteIndex].length]

                ctx.fillStyle = (Math.random() < main.glitchChance / 100) ? "#ffffff" : color
                ctx.font = main.fontSize + "px monospace"

                var ch
                if (hasMqttChars) {
                    var r = Math.floor(drops[i])
                    ch = main.messageChars[(r + i) % msgLen]
                } else {
                    ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                }

                ctx.fillText(ch, x, y)

                drops[i] += 1 + Math.random() * main.jitter / 100
                if (drops[i] * main.fontSize > h + main.fontSize)
                    drops[i] = 0
            }

            // ----------------------------------------------------------------
            // Debug overlay — ring-buffer: 5 slot fissi, nessuno scroll
            // Layout (y positions):
            //   26  — titolo
            //   46  — stato MQTT
            //   62  — broker
            //   78  — topic
            //   94  — contatore messaggi
            //  103  — separatore
            //  116  — etichetta sezione messaggi
            //  132…196 — 5 slot fissi (LINE=16px), posizioni invarianti
            // ----------------------------------------------------------------
            if (main.debugOverlay) {
                var BOX_X = 8
                var BOX_Y = 8
                var BOX_W = 760
                var BOX_H = 222
                var TX    = 14   // margine sinistro testo
                var LINE  = 16   // altezza riga slot messaggi

                ctx.fillStyle = "rgba(0,0,0,0.88)"
                ctx.fillRect(BOX_X, BOX_Y, BOX_W, BOX_H)

                // Titolo
                ctx.font = "bold 13px monospace"
                ctx.fillStyle = "#00ff00"
                ctx.fillText("⚙️ MQTT Rain Debug", TX, 26)

                ctx.font = "12px monospace"

                // Stato MQTT
                ctx.fillStyle = mqttClient.connected ? "#00ff00" : "#ff4444"
                ctx.fillText("MQTT:   " + (mqttClient.connected ? "✅ CONNECTED" : "❌ DISCONNECTED"), TX, 46)

                // Broker / topic
                ctx.fillStyle = "#00ccff"
                ctx.fillText("Broker: " + main.mqttHost + ":" + main.mqttPort, TX, 62)
                ctx.fillText("Topic:  " + main.mqttTopic, TX, 78)

                // Contatore
                ctx.fillStyle = "#aaaaaa"
                ctx.fillText("Msgs:   " + main.messagesReceived + "  |  Chars in rain: " + main.messageChars.length, TX, 94)

                // Separatore
                ctx.fillStyle = "#555555"
                ctx.fillRect(TX, 103, BOX_W - 20, 1)
                ctx.fillStyle = "#888888"
                ctx.fillText("Messaggi MQTT — ring-buffer (il più vecchio viene sovrascritto):", TX, 116)

                // 5 slot fissi — nessuna sfumatura, colore uniforme
                // Lo slot scritto più di recente = (mqttNextSlot - 1 + maxHistory) % maxHistory
                var hist     = main.messageHistory
                var baseY    = 132
                var newestSlot = (main.mqttNextSlot - 1 + main.maxHistory) % main.maxHistory

                for (var m = 0; m < main.maxHistory; m++) {
                    var entry = hist[m]
                    var prefix = "[" + m + "] "
                    if (!entry) {
                        ctx.fillStyle = "#555555"
                        ctx.fillText(prefix + "(vuoto)", TX, baseY + m * LINE)
                    } else {
                        var line = entry.topic + ": " + entry.payload
                        if (line.length > 95)
                            line = line.substring(0, 92) + "…"
                        // Slot più recente in bianco, gli altri in giallo pieno — nessuna sfumatura
                        ctx.fillStyle = (m === newestSlot) ? "#ffffff" : "#ffff00"
                        ctx.fillText(prefix + line, TX, baseY + m * LINE)
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
        if (main.mqttEnable)
            Qt.callLater(mqttConnect)
        else
            main.writeLog("MQTT disabled — random Matrix characters")
    }

    Component.onDestruction: { mqttClient.disconnectFromHost() }
}
