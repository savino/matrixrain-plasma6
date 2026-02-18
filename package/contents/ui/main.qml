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
    property bool mqttConnected: false
    property string lastTopic: ""
    property string lastPayload: ""
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property bool mqttConnecting: false

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    function writeLog(msg) {
        console.log("[MQTTRain] " + msg)
    }

    // WebSocket for MQTT connection
    WebSocket {
        id: mqttSocket
        active: false
        url: ""
    }

    // Connections component to handle WebSocket signals (QML best practice)
    Connections {
        target: mqttSocket
        
        function onStatusChanged() {
            var status = mqttSocket.status
            
            if (status === WebSocket.Open) {
                main.writeLog("✅ WebSocket Connected")
                main.mqttConnecting = false
                
                // Send MQTT CONNECT packet
                MQTTClient.sendConnectPacket()
                
                // Subscribe after a short delay to allow CONNACK
                subscribeTimer.start()
                
            } else if (status === WebSocket.Closed || status === WebSocket.Error) {
                main.writeLog("⚠️ WebSocket Closed")
                main.mqttConnected = false
                main.mqttConnecting = false
                
                // Auto-reconnect if MQTT is still enabled
                if (main.mqttEnable) {
                    reconnectTimer.start()
                }
            }
        }
        
        function onTextMessageReceived(message) {
            // Some brokers might send text messages
            main.writeLog("📨 Text message: " + message)
            main.lastPayload = message
            main.messageChars = []
            for (var i = 0; i < message.length; i++) {
                main.messageChars.push(message.charAt(i))
            }
            canvas.requestPaint()
        }
        
        function onBinaryMessageReceived(message) {
            // Handle MQTT binary packets
            MQTTClient.handleBinaryMessage(message)
        }
        
        function onErrorStringChanged() {
            if (mqttSocket.errorString) {
                main.writeLog("❌ WebSocket Error: " + mqttSocket.errorString)
            }
        }
    }

    // Timer to send SUBSCRIBE after CONNECT
    Timer {
        id: subscribeTimer
        interval: 200
        repeat: false
        onTriggered: {
            main.writeLog("🔔 Subscribing to topic: " + main.mqttTopic)
            MQTTClient.sendSubscribePacket(main.mqttTopic)
        }
    }

    // MQTT connection management
    property bool _mqttConnectInProgress: false

    function mqttConnect() {
        if (!main.mqttEnable) {
            main.writeLog("MQTT disabled, disconnecting if connected")
            main.mqttConnected = false
            MQTTClient.disconnect()
            return
        }

        if (main._mqttConnectInProgress) {
            main.writeLog("Connect already in progress, skipping")
            return
        }

        main._mqttConnectInProgress = true
        main.mqttConnecting = true

        try {
            var clientIdPrefix = "mqttrain-" + Date.now()
            
            MQTTClient.connect({
                host: main.mqttHost,
                port: main.mqttPort,
                path: main.mqttPath,
                useSsl: false,
                socket: mqttSocket,
                clientIdPrefix: clientIdPrefix,
                username: main.mqttUsername,
                password: main.mqttPassword,
                topic: main.mqttTopic,
                
                onConnect: function() {
                    main.writeLog("✅ MQTT CONNACK received")
                    main.mqttConnected = true
                    main._mqttConnectInProgress = false
                },
                
                onDisconnect: function() {
                    main.writeLog("⚠️ MQTT Disconnected")
                    main.mqttConnected = false
                    main._mqttConnectInProgress = false
                },
                
                onMessage: function(topic, payload) {
                    main.writeLog("📨 [" + topic + "] " + payload)
                    main.lastTopic = topic
                    main.lastPayload = payload
                    
                    // Convert payload to character array
                    main.messageChars = []
                    for (var i = 0; i < payload.length; i++) {
                        main.messageChars.push(payload.charAt(i))
                    }
                    canvas.requestPaint()
                },
                
                onError: function(error) {
                    main.writeLog("❌ MQTT Error: " + error)
                    main._mqttConnectInProgress = false
                },
                
                onDebug: function(msg) {
                    main.writeLog("🔍 " + msg)
                }
            })
            
            // Clear the semaphore after a short delay
            Qt.callLater(function() { 
                if (main._mqttConnectInProgress && !main.mqttConnected) {
                    main._mqttConnectInProgress = false
                }
            })
        } catch (e) {
            main.writeLog("❌ Exception during connect: " + e.toString())
            main.mqttConnecting = false
            main._mqttConnectInProgress = false
        }
    }

    function mqttDisconnect() {
        try {
            MQTTClient.disconnect()
            main.mqttConnected = false
            main.mqttConnecting = false
        } catch (e) {
            main.writeLog("Error disconnecting: " + e.toString())
        }
    }

    // Auto-reconnect timer
    Timer {
        id: reconnectTimer
        interval: 5000
        repeat: false
        running: false
        onTriggered: {
            if (main.mqttEnable && !main.mqttConnected && !main.mqttConnecting) {
                main.writeLog("Attempting reconnection...")
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
            for (var j = 0; j < cols; j++) {
                drops.push(Math.floor(Math.random() * canvas.height / main.fontSize))
            }
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
            ctx.fillRect(0,0,w,h)
            
            for (var i = 0; i < drops.length; i++) {
                var x = i * main.fontSize
                var y = drops[i] * main.fontSize
                var color = main.colorMode === 0
                    ? main.singleColor
                    : main.palettes[main.paletteIndex][i % main.palettes[main.paletteIndex].length]
                
                // Glitch effect
                if (Math.random() < main.glitchChance / 100) {
                    ctx.fillStyle = "#ffffff"
                } else {
                    ctx.fillStyle = color
                }
                
                ctx.font = main.fontSize + "px monospace"

                var ch = null
                if (main.mqttEnable) {
                    // When MQTT is enabled, render incoming message characters
                    if (main.messageChars && main.messageChars.length > 0) {
                        var idx = (drops[i] + main.messageTick) % main.messageChars.length
                        ch = main.messageChars[idx]
                        ctx.fillText(ch, x, y)
                    }
                    // Don't render random characters when MQTT is enabled but no message received
                } else {
                    // Default Matrix-style random characters
                    if (main.messageChars && main.messageChars.length > 0) {
                        var idx = (drops[i] + main.messageTick) % main.messageChars.length
                        ch = main.messageChars[idx]
                    }
                    if (!ch) {
                        ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                    }
                    ctx.fillText(ch, x, y)
                }
                
                // Advance drop with jitter effect
                drops[i] = (drops[i] + 1 + Math.random() * main.jitter / 100) % (h / main.fontSize)
            }
            
            // Advance message tick for animation
            if (main.messageChars && main.messageChars.length > 0) {
                main.messageTick = (main.messageTick + 1) % 1000000
            }

            // Debug overlay
            if (main.debugOverlay) {
                var boxW = 420
                var boxH = 110
                ctx.fillStyle = "rgba(0,0,0,0.8)"
                ctx.fillRect(8, 8, boxW, boxH)
                ctx.fillStyle = "#00ff00"
                ctx.font = "12px monospace"
                
                var statusText = "MQTT: " + (main.mqttConnected ? "✅ CONNECTED" : main.mqttConnecting ? "🔄 CONNECTING..." : "❌ DISCONNECTED")
                ctx.fillText(statusText, 14, 26)
                ctx.fillText("Host: " + main.mqttHost + ":" + main.mqttPort + main.mqttPath, 14, 42)
                ctx.fillText("Topic: " + main.mqttTopic, 14, 58)
                
                var last = main.lastPayload ? main.lastPayload.toString() : "(waiting for message)"
                if (last.length > 50) last = last.substring(0, 47) + "..."
                ctx.fillText("Last: " + last, 14, 74)
                ctx.fillText("Chars: " + main.messageChars.length + " | Drops: " + drops.length, 14, 90)
            }
        }

        Component.onCompleted: initDrops()
    }

    // Property change handlers
    onFontSizeChanged: { canvas.initDrops(); canvas.requestPaint(); }
    onSpeedChanged: timer.interval = 1000 / main.speed
    onColorModeChanged: canvas.requestPaint()
    onSingleColorChanged: canvas.requestPaint()
    onPaletteIndexChanged: canvas.requestPaint()
    onJitterChanged: canvas.requestPaint()
    onGlitchChanceChanged: canvas.requestPaint()
    onDebugOverlayChanged: canvas.requestPaint()
    
    // MQTT configuration changes trigger reconnection
    onMqttEnableChanged: {
        if (mqttEnable) {
            mqttConnect()
        } else {
            mqttDisconnect()
        }
    }
    onMqttHostChanged: { if (mqttEnable) mqttConnect() }
    onMqttPortChanged: { if (mqttEnable) mqttConnect() }
    onMqttPathChanged: { if (mqttEnable) mqttConnect() }
    onMqttTopicChanged: {
        if (mqttEnable && mqttConnected) {
            // Resubscribe to new topic
            mqttConnect()
        }
    }

    Component.onCompleted: { 
        main.writeLog("Matrix Rain Wallpaper initialized")
        canvas.initDrops()
        
        if (main.mqttEnable) {
            main.writeLog("MQTT enabled, connecting...")
            // Delay initial connection slightly to ensure UI is ready
            Qt.callLater(mqttConnect)
        } else {
            main.writeLog("MQTT disabled")
        }
    }
    
    Component.onDestruction: {
        mqttDisconnect()
    }
}
