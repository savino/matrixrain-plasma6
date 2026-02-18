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
    property string mqttHost: main.configuration.mqttHost !== undefined ? main.configuration.mqttHost : "homeassistant.lan"
    property int mqttPort: main.configuration.mqttPort !== undefined ? main.configuration.mqttPort : 1883
    property string mqttTopic: main.configuration.mqttTopic !== undefined ? main.configuration.mqttTopic : "zigbee2mqtt/#"
    property string mqttUsername: main.configuration.mqttUsername || ""
    property string mqttPassword: (main.configuration.mqttPassword !== undefined && main.configuration.mqttPassword !== null) ? main.configuration.mqttPassword : ""

    // MQTT state
    property var messageChars: []
    property int messageTick: 0
    property string lastTopic: ""
    property string lastPayload: ""
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

    // Native C++ MQTT Client (Qt6 Mqtt)
    MQTTClient {
        id: mqttClient

        onConnectedChanged: {
            if (connected) {
                main.writeLog("✅ MQTT Connected")
                // Subscribe after connection
                subscribeTimer.start()
            } else {
                main.writeLog("❌ MQTT Disconnected")
                // Auto-reconnect
                if (main.mqttEnable) {
                    reconnectTimer.start()
                }
            }
            canvas.requestPaint()
        }

        onMessageReceived: function(topic, payload) {
            main.writeLog("📨 [" + topic + "] " + payload.substring(0, 80))
            main.lastTopic = topic
            main.lastPayload = payload
            main.messagesReceived++

            // Convert payload to character array for Matrix effect
            main.messageChars = []
            for (var i = 0; i < payload.length; i++)
                main.messageChars.push(payload.charAt(i))

            canvas.requestPaint()
        }

        onConnectionError: function(error) {
            main.writeLog("❌ MQTT Error: " + error)
        }
    }

    // MQTT connection management
    function mqttConnect() {
        if (!main.mqttEnable) {
            main.writeLog("MQTT disabled")
            mqttClient.disconnectFromHost()
            return
        }

        main.writeLog("Connecting to " + main.mqttHost + ":" + main.mqttPort + "...")
        
        // Set connection parameters
        mqttClient.host = main.mqttHost
        mqttClient.port = main.mqttPort
        mqttClient.username = main.mqttUsername
        mqttClient.password = main.mqttPassword
        mqttClient.topic = main.mqttTopic
        
        // Connect
        mqttClient.connectToHost()
    }

    // Auto-reconnect on unexpected disconnection
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

    // Subscribe after connection established
    Timer {
        id: subscribeTimer
        interval: 100
        repeat: false
        onTriggered: {
            main.writeLog("Subscribing to: " + mqttClient.topic)
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
                    // blank canvas while waiting for first MQTT message
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

            // Debug overlay
            if (main.debugOverlay) {
                ctx.fillStyle = "rgba(0,0,0,0.85)"
                ctx.fillRect(8, 8, 480, 110)
                ctx.font = "bold 13px monospace"
                ctx.fillStyle = "#00ff00"
                ctx.fillText("⚙️ MQTT Rain Debug (Qt6 Mqtt)", 14, 26)
                ctx.font = "12px monospace"
                ctx.fillStyle = mqttClient.connected ? "#00ff00" : "#ff4444"
                ctx.fillText("MQTT: " + (mqttClient.connected ? "✅ CONNECTED" : "❌ DISCONNECTED"), 14, 46)
                ctx.fillStyle = "#00ccff"
                ctx.fillText("Broker: " + main.mqttHost + ":" + main.mqttPort + " (Qt6 Mqtt)", 14, 62)
                ctx.fillText("Topic:  " + main.mqttTopic, 14, 78)
                ctx.fillStyle = "#ffff00"
                var last = (main.lastPayload || "(waiting...)").toString()
                ctx.fillText("Last:   " + (last.length > 52 ? last.substring(0, 49) + "..." : last), 14, 94)
                ctx.fillText("Msgs: " + main.messagesReceived + "  |  Chars: " + main.messageChars.length, 14, 110)
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

    onMqttEnableChanged: mqttEnable ? mqttConnect() : mqttClient.disconnectFromHost()
    onMqttHostChanged:   { if (mqttEnable) mqttConnect() }
    onMqttPortChanged:   { if (mqttEnable) mqttConnect() }
    onMqttTopicChanged:  { if (mqttEnable && mqttClient.connected) { mqttClient.disconnectFromHost(); mqttConnect() } }

    Component.onCompleted: {
        main.writeLog("=== Matrix Rain MQTT Wallpaper (Qt6 Mqtt) ===")
        main.writeLog("Qt version: " + Qt.version)
        canvas.initDrops()
        if (main.mqttEnable) {
            main.writeLog("MQTT enabled — broker: " + main.mqttHost + ":" + main.mqttPort + " (Qt6 native)")
            Qt.callLater(mqttConnect)
        } else {
            main.writeLog("MQTT disabled — random Matrix characters")
        }
    }

    Component.onDestruction: { mqttClient.disconnectFromHost() }
}
