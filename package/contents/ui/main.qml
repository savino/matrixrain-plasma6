import QtQuick 2.15
import QtQuick.Controls 2.15
import QtWebSockets
import org.kde.plasma.plasmoid 2.0
import "mqttClient.js" as MQTTClient

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
    property string mqttPath: main.configuration.mqttPath !== undefined ? main.configuration.mqttPath : "/mqtt"
    property string mqttTopic: main.configuration.mqttTopic !== undefined ? main.configuration.mqttTopic : "zigbee2mqtt/#"
    property string mqttUsername: main.configuration.mqttUsername || ""
    property string mqttPassword: (main.configuration.mqttPassword !== undefined && main.configuration.mqttPassword !== null) ? main.configuration.mqttPassword : ""

    // MQTT state
    property var messageChars: []
    property int messageTick: 0
    property bool mqttConnected: false       // True only after CONNACK
    property bool websocketConnected: false  // True when WebSocket is open
    property string lastTopic: ""
    property string lastPayload: ""
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property bool mqttConnecting: false
    property int messagesReceived: 0

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    function writeLog(msg) {
        console.log("[MQTTRain] " + msg)
    }

    // WebSocket for MQTT-over-WebSocket
    // CRITICAL: Mosquitto requires the 'mqtt' subprotocol in the
    // WebSocket handshake (Sec-WebSocket-Protocol: mqtt header).
    // Without this, Mosquitto silently drops the connection.
    // Paho Python sets this automatically; QML requires explicit declaration.
    WebSocket {
        id: mqttSocket
        active: false
        url: ""
        subprotocols: ["mqtt"]
    }

    // Wire up WebSocket signals via Connections (QML best practice;
    // signal handler properties are read-only and cannot be set from JS)
    Connections {
        target: mqttSocket

        function onStatusChanged() {
            var status = mqttSocket.status
            var statusNames = ["Closed", "Connecting", "Open", "Closing", "Error"]
            main.writeLog("🔌 WebSocket status: " + (statusNames[status] || "Unknown") + " (" + status + ")")

            if (status === WebSocket.Open) {
                main.writeLog("✅ WebSocket open - sending MQTT CONNECT")
                main.websocketConnected = true
                main.mqttConnecting = false
                MQTTClient.sendConnectPacket()

            } else if (status === WebSocket.Closed || status === WebSocket.Error) {
                if (mqttSocket.errorString)
                    main.writeLog("❌ WebSocket error: " + mqttSocket.errorString)
                main.websocketConnected = false
                main.mqttConnected = false
                main.mqttConnecting = false
                if (main.mqttEnable && !reconnectTimer.running)
                    reconnectTimer.start()
            }
        }

        function onTextMessageReceived(message) {
            main.writeLog("📨 Text message received: " + message.substring(0, 100))
            _handlePayload("", message)
        }

        function onBinaryMessageReceived(message) {
            MQTTClient.handleBinaryMessage(message)
        }
    }

    // Called by MQTTClient callbacks and text handler
    function _handlePayload(topic, payload) {
        main.lastTopic = topic
        main.lastPayload = payload
        main.messagesReceived++
        main.messageChars = []
        for (var i = 0; i < payload.length; i++)
            main.messageChars.push(payload.charAt(i))
        canvas.requestPaint()
    }

    // MQTT connection management
    property bool _mqttConnectInProgress: false

    function mqttConnect() {
        if (!main.mqttEnable) {
            main.writeLog("MQTT disabled")
            mqttDisconnect()
            return
        }
        if (main._mqttConnectInProgress) {
            main.writeLog("Connect already in progress, skipping")
            return
        }

        main._mqttConnectInProgress = true
        main.mqttConnecting = true

        MQTTClient.connect({
            host: main.mqttHost,
            port: main.mqttPort,
            path: main.mqttPath,
            useSsl: false,
            socket: mqttSocket,
            clientIdPrefix: "mqttrain-",
            username: main.mqttUsername,
            password: main.mqttPassword,
            topic: main.mqttTopic,

            onConnect: function() {
                main.writeLog("✅ MQTT CONNACK OK — subscribing to '" + main.mqttTopic + "'")
                main.mqttConnected = true
                main._mqttConnectInProgress = false
                // Wait briefly then subscribe
                subscribeTimer.start()
            },

            onDisconnect: function() {
                main.writeLog("⚠️ MQTT disconnected")
                main.mqttConnected = false
                main._mqttConnectInProgress = false
            },

            onMessage: function(topic, payload) {
                main.writeLog("📨 MQTT [" + topic + "] " + payload.substring(0, 80))
                _handlePayload(topic, payload)
            },

            onError: function(error) {
                main.writeLog("❌ MQTT error: " + error)
                main._mqttConnectInProgress = false
            },

            onDebug: function(msg) {
                main.writeLog(msg)
            }
        })

        // Clear semaphore after a short window
        Qt.callLater(function() {
            if (main._mqttConnectInProgress && !main.websocketConnected)
                main._mqttConnectInProgress = false
        })
    }

    function mqttDisconnect() {
        try { MQTTClient.disconnect() } catch(e) {}
        main.mqttConnected = false
        main.websocketConnected = false
        main.mqttConnecting = false
    }

    // Subscribe AFTER receiving CONNACK
    Timer {
        id: subscribeTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (main.mqttConnected) {
                main.writeLog("🔔 Sending SUBSCRIBE for '" + main.mqttTopic + "'")
                MQTTClient.sendSubscribePacket(main.mqttTopic)
            }
        }
    }

    // Auto-reconnect on unexpected disconnection
    Timer {
        id: reconnectTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (main.mqttEnable && !main.websocketConnected && !main.mqttConnecting) {
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
                ctx.fillRect(8, 8, 480, 130)
                ctx.font = "bold 13px monospace"
                ctx.fillStyle = "#00ff00"
                ctx.fillText("⚙️ MQTT Rain Debug", 14, 26)
                ctx.font = "12px monospace"
                ctx.fillStyle = main.websocketConnected ? "#00ff00" : "#ff4444"
                ctx.fillText("WS: " + (main.websocketConnected ? "✅ OPEN" : "❌ CLOSED"), 14, 46)
                ctx.fillStyle = main.mqttConnected ? "#00ff00" : "#ff9900"
                ctx.fillText("MQTT: " + (main.mqttConnected ? "✅ CONNECTED" : main.mqttConnecting ? "🔄 CONNECTING" : "❌ DISCONNECTED"), 14, 62)
                ctx.fillStyle = "#00ccff"
                ctx.fillText("Broker: " + main.mqttHost + ":" + main.mqttPort + main.mqttPath, 14, 78)
                ctx.fillText("Topic:  " + main.mqttTopic, 14, 94)
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

    onMqttEnableChanged: mqttEnable ? mqttConnect() : mqttDisconnect()
    onMqttHostChanged:   { if (mqttEnable) mqttConnect() }
    onMqttPortChanged:   { if (mqttEnable) mqttConnect() }
    onMqttPathChanged:   { if (mqttEnable) mqttConnect() }
    onMqttTopicChanged:  { if (mqttEnable && mqttConnected) mqttConnect() }

    Component.onCompleted: {
        main.writeLog("=== Matrix Rain MQTT Wallpaper Started ===")
        canvas.initDrops()
        if (main.mqttEnable) {
            main.writeLog("MQTT enabled — broker: " + main.mqttHost + ":" + main.mqttPort + main.mqttPath)
            Qt.callLater(mqttConnect)
        } else {
            main.writeLog("MQTT disabled — random Matrix characters")
        }
    }

    Component.onDestruction: { mqttDisconnect() }
}
