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

    // MQTT settings — always trim to remove accidental spaces/newlines from config
    property bool mqttEnable: main.configuration.mqttEnable !== undefined ? main.configuration.mqttEnable : false
    property string mqttHost: (main.configuration.mqttHost !== undefined ? main.configuration.mqttHost : "homeassistant.lan").trim()
    property int mqttPort: main.configuration.mqttPort !== undefined ? main.configuration.mqttPort : 1883
    property string mqttTopic: (main.configuration.mqttTopic !== undefined ? main.configuration.mqttTopic : "zigbee2mqtt/#").trim()
    property string mqttUsername: (main.configuration.mqttUsername || "").trim()
    property string mqttPassword: (main.configuration.mqttPassword !== undefined && main.configuration.mqttPassword !== null) ? main.configuration.mqttPassword : ""

    // MQTT state
    property var messageChars: []
    property int messageTick: 0
    property string lastTopic: ""
    property string lastPayload: ""
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property int messagesReceived: 0
    property bool mqttInitialized: false

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    function writeLog(msg) {
        console.log("[MQTTRain] " + msg)
    }

    MQTTClient {
        id: mqttClient

        onConnectedChanged: {
            if (connected) {
                main.writeLog("✅ MQTT Connected")
                subscribeTimer.start()
            } else {
                main.writeLog("❌ MQTT Disconnected")
                if (main.mqttInitialized && main.mqttEnable)
                    reconnectTimer.start()
            }
            canvas.requestPaint()
        }

        onMessageReceived: function(topic, payload) {
            main.writeLog("📨 [" + topic + "] " + payload.substring(0, 80))
            main.lastTopic = topic
            main.lastPayload = payload
            main.messagesReceived++
            main.messageChars = []
            for (var i = 0; i < payload.length; i++)
                main.messageChars.push(payload.charAt(i))
            canvas.requestPaint()
        }

        onConnectionError: function(error) {
            main.writeLog("❌ MQTT Error: " + error)
        }
    }

    function mqttConnect() {
        if (!main.mqttEnable) {
            main.writeLog("MQTT disabled")
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

    // Initial connection timer — 2000ms to be safe
    Timer {
        id: initTimer
        interval: 2000
        repeat: false
        onTriggered: {
            main.mqttInitialized = true
            if (main.mqttEnable) {
                main.writeLog("🚀 Starting MQTT connection...")
                mqttConnect()
            }
        }
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

    Timer {
        id: subscribeTimer
        interval: 100
        repeat: false
        onTriggered: {
            main.writeLog("Subscribed to: " + mqttClient.topic)
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
                drops.push(Math.floor(Math.random() * canvas.height / main.fontSize))
        }

        Timer {
            id: timer
            interval: 1000 / main.speed
            running: true
            repeat: true
            onTriggered: canvas.requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d"), w = width, h = height
            ctx.fillStyle = "rgba(0,0,0,0.05)"
            ctx.fillRect(0, 0, w, h)

            for (var i = 0; i < drops.length; i++) {
                var x = i * main.fontSize
                var y = drops[i] * main.fontSize
                var color = main.colorMode === 0
                    ? main.singleColor
                    : main.palettes[main.paletteIndex][i % main.palettes[main.paletteIndex].length]

                ctx.fillStyle = (Math.random() < main.glitchChance / 100) ? "#ffffff" : color
                ctx.font = main.fontSize + "px monospace"

                var ch = null
                if (main.mqttEnable) {
                    if (main.messageChars && main.messageChars.length > 0) {
                        var idx = (drops[i] + main.messageTick) % main.messageChars.length
                        ch = main.messageChars[idx]
                        ctx.fillText(ch, x, y)
                    }
                } else {
                    if (main.messageChars && main.messageChars.length > 0) {
                        var idx = (drops[i] + main.messageTick) % main.messageChars.length
                        ch = main.messageChars[idx]
                    }
                    if (!ch)
                        ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                    ctx.fillText(ch, x, y)
                }

                drops[i] = (drops[i] + 1 + Math.random() * main.jitter / 100) % (h / main.fontSize)
            }

            if (main.messageChars && main.messageChars.length > 0)
                main.messageTick = (main.messageTick + 1) % 1000000

            if (main.debugOverlay) {
                ctx.fillStyle = "rgba(0,0,0,0.85)"
                ctx.fillRect(8, 8, 480, 130)
                ctx.font = "bold 13px monospace"
                ctx.fillStyle = "#00ff00"
                ctx.fillText("⚙️ MQTT Rain Debug", 14, 26)
                ctx.font = "12px monospace"
                ctx.fillStyle = main.mqttInitialized ? "#00ff00" : "#ffaa00"
                ctx.fillText("Init: " + (main.mqttInitialized ? "✅ Ready" : "⏳ Waiting..."), 14, 46)
                ctx.fillStyle = mqttClient.connected ? "#00ff00" : "#ff4444"
                ctx.fillText("MQTT: " + (mqttClient.connected ? "✅ CONNECTED" : "❌ DISCONNECTED"), 14, 62)
                ctx.fillStyle = "#00ccff"
                ctx.fillText("Broker: " + main.mqttHost + ":" + main.mqttPort, 14, 78)
                ctx.fillText("Topic:  [" + main.mqttTopic + "]", 14, 94)
                ctx.fillStyle = "#ffff00"
                var last = (main.lastPayload || "(waiting...)").toString()
                ctx.fillText("Last:   " + (last.length > 52 ? last.substring(0, 49) + "..." : last), 14, 110)
                ctx.fillText("Msgs: " + main.messagesReceived + "  |  Chars: " + main.messageChars.length, 14, 126)
            }
        }

        Component.onCompleted: initDrops()
    }

    onFontSizeChanged: { canvas.initDrops(); canvas.requestPaint() }
    onSpeedChanged: timer.interval = 1000 / main.speed
    onColorModeChanged: canvas.requestPaint()
    onSingleColorChanged: canvas.requestPaint()
    onPaletteIndexChanged: canvas.requestPaint()
    onJitterChanged: canvas.requestPaint()
    onGlitchChanceChanged: canvas.requestPaint()
    onDebugOverlayChanged: canvas.requestPaint()

    onMqttEnableChanged: { if (main.mqttInitialized) { mqttEnable ? mqttConnect() : mqttClient.disconnectFromHost() } }
    onMqttHostChanged:   { if (main.mqttInitialized && mqttEnable) mqttConnect() }
    onMqttPortChanged:   { if (main.mqttInitialized && mqttEnable) mqttConnect() }
    onMqttTopicChanged:  { if (main.mqttInitialized && mqttEnable && mqttClient.connected) { mqttClient.disconnectFromHost(); mqttConnect() } }

    Component.onCompleted: {
        main.writeLog("=== Matrix Rain MQTT Wallpaper ===")
        main.writeLog("MQTT host=[" + main.mqttHost + "] port=" + main.mqttPort + " topic=[" + main.mqttTopic + "]")
        canvas.initDrops()
        if (main.mqttEnable) {
            main.writeLog("⏳ Waiting 2000ms before connecting...")
            initTimer.start()
        } else {
            main.writeLog("MQTT disabled — random Matrix characters")
            main.mqttInitialized = true
        }
    }

    Component.onDestruction: { mqttClient.disconnectFromHost() }
}
