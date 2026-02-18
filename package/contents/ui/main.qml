import QtQuick 2.15
import QtQuick.Controls 2.15
import QtWebSockets
import org.kde.plasma.plasmoid 2.0
// Using WorkerScript with mqtt.min.js (mqttworker.mjs)

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

    // MQTT settings (zigbee2mqtt via websocket)
    property bool mqttEnable: main.configuration.mqttEnable !== undefined ? main.configuration.mqttEnable : false
    property string mqttHost: main.configuration.mqttHost !== undefined ? main.configuration.mqttHost : "homeassistant.lan"
    property int mqttPort: main.configuration.mqttPort !== undefined ? main.configuration.mqttPort : 1883
    property string mqttPath: main.configuration.mqttPath !== undefined ? main.configuration.mqttPath : "/mqtt"
    property string mqttTopic: main.configuration.mqttTopic !== undefined ? main.configuration.mqttTopic : "zigbee2mqtt/#"

    property string mqttUsername: main.configuration.mqttUsername || ""
    property string mqttPassword: (main.configuration.mqttPassword !== undefined && main.configuration.mqttPassword !== null) ? main.configuration.mqttPassword : ""

    // message queue and rendering state
    property var messageChars: []
    property int messageTick: 0
    property bool mqttConnected: false
    property string lastTopic: ""
    property string lastPayload: ""
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    property bool mqttConnecting: false

    WorkerScript {
        id: mqttWorker
        source: "../code/mqttworker.js"

        // queue messages until the worker is ready
        property var _pending: []

        function _flushPending() {
            for (var i = 0; i < mqttWorker._pending.length; i++) {
                try { mqttWorker.sendMessage(mqttWorker._pending[i]) } catch(e) { return }
            }
            mqttWorker._pending = []
        }
        // In some Plasma/QML versions WorkerScript.running change handler
        // may not be available; pending flush is handled by a top-level Timer.


    
        onMessage: function(msg) {
            if (!msg) return
            if (msg.type === 'debug') {
                main.writeLog(msg.message)
            } else if (msg.type === 'connected') {
                main.writeLog("✅ MQTT Connected")
                main.mqttConnected = true
                // subscribe after connected
                sendToWorker({ action: 'subscribe', topic: main.mqttTopic })
            } else if (msg.type === 'message') {
                main.writeLog("📨 [" + msg.topic + "] " + msg.payload)
                main.messageChars = []
                for (var k = 0; k < msg.payload.length; k++) main.messageChars.push(msg.payload.charAt(k))
                main.lastTopic = msg.topic
                main.lastPayload = msg.payload
                canvas.requestPaint()
            } else if (msg.type === 'suback') {
                main.writeLog("🔔 SUBACK received: " + JSON.stringify(msg.granted || msg.packet || msg))
            } else if (msg.type === 'error') {
                main.writeLog("❌ " + msg.message)
            } else if (msg.type === 'disconnected') {
                main.writeLog("⚠️ MQTT disconnected")
                main.mqttConnected = false
            }
        }
    }

    function sendToWorker(obj) {
        try {
            mqttWorker.sendMessage(obj)
        } catch (e) {
            // queue and attempt later
            mqttWorker._pending.push(obj)
            // schedule a flush
            Qt.callLater(function() { try { mqttWorker._flushPending() } catch(e) {} })
        }
    }

    // Use the included JS MQTT helper (mqttClient.js)
    // semaphore to avoid duplicate immediate connects
    property bool _mqttConnectInProgress: false

    function mqttConnect() {
        if (!main.mqttEnable) {
            main.writeLog("MQTT disabled, not connecting")
            main.mqttConnected = false
            try { sendToWorker({ action: 'disconnect' }) } catch (e) {}
            return
        }
        if (main._mqttConnectInProgress) { main.writeLog("Connect already in progress, skipping") ; return }
        main._mqttConnectInProgress = true

        var url = "ws://" + main.mqttHost + ":" + main.mqttPort + main.mqttPath
        main.writeLog("MQTT Worker connecting to: " + url)

        sendToWorker({
            action: 'connect',
            url: url,
            options: {
                clientId: "mqttrain-" + Date.now(),
                username: main.mqttUsername,
                password: main.mqttPassword,
                clean: true,
                reconnectPeriod: 2000
            }
        })

        // allow a small window for connect attempts, then clear semaphore
        Qt.callLater(function() { main._mqttConnectInProgress = false })
    }

    property var palettes: [
        ["#00ff00","#ff00ff","#00ffff","#ff0000","#ffff00","#0000ff"],
        ["#ff0066","#33ff99","#ffcc00","#6600ff","#00ccff","#ff3300"],
        ["#ff00ff","#00ffcc","#cc00ff","#ffcc33","#33ccff","#ccff00"]
    ]

    function writeLog(msg) {
        console.log("[MQTTRain] " + msg)
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        property var drops: []

        Timer {
            id: reconnectTimer
            interval: 2000
            repeat: false
            running: false
            onTriggered: {
                main.writeLog("Reconnect timer triggered, attempting mqttConnect()")
                mqttConnect()
            }
        }

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

        // Timer to flush pending messages to WorkerScript (placed inside Canvas)
        Timer {
            id: pendingFlushTimer
            interval: 500
            repeat: true
            running: false
            onTriggered: {
                if (!mqttWorker._pending || mqttWorker._pending.length === 0) { running = false; return }
                var newPending = []
                for (var i = 0; i < mqttWorker._pending.length; i++) {
                    try {
                        mqttWorker.sendMessage(mqttWorker._pending[i])
                    } catch (e) {
                        newPending.push(mqttWorker._pending[i])
                    }
                }
                mqttWorker._pending = newPending
                if (mqttWorker._pending.length === 0) running = false
            }
        }

        // Provide a minimal QML WebSocket object for the JS helper to use.
        WebSocket {
            id: mqttSocket
            active: false
            url: ""
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
                // glitch chance percent
                if (Math.random() < main.glitchChance / 100) {
                    ctx.fillStyle = "#ffffff"
                } else {
                    ctx.fillStyle = color
                }
                ctx.font = main.fontSize + "px monospace"

                var ch = null
                if (main.mqttEnable) {
                    // when MQTT is enabled, only render incoming message characters
                    if (main.messageChars && main.messageChars.length > 0) {
                        var idx = (drops[i] + main.messageTick) % main.messageChars.length
                        ch = main.messageChars[idx]
                        ctx.fillText(ch, x, y)
                    } else {
                        // no message loaded yet: draw nothing for MQTT-enabled mode
                    }
                } else {
                    if (main.messageChars && main.messageChars.length > 0) {
                        // render message characters cyclically
                        var idx = (drops[i] + main.messageTick) % main.messageChars.length
                        ch = main.messageChars[idx]
                    }
                    if (!ch) {
                        ch = String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96))
                    }
                    ctx.fillText(ch, x, y)
                }
                // advance with jitter
                drops[i] = (drops[i] + 1 + Math.random() * main.jitter) % (h / main.fontSize)

            }
            // advance message tick so characters shift over time
            if (main.messageChars && main.messageChars.length > 0) main.messageTick = (main.messageTick + 1) % 1000000

            // draw debug overlay
            if (main.debugOverlay) {
                var boxW = 400
                var boxH = 100
                ctx.fillStyle = "rgba(0,0,0,0.7)"
                ctx.fillRect(8, 8, boxW, boxH)
                ctx.fillStyle = "#00ff00"
                ctx.font = "11px monospace"
                var statusText = "MQTT: " + (main.mqttConnected ? "CONNECTED" : "disconnected")
                ctx.fillText(statusText, 14, 26)
                ctx.fillText("Host: " + main.mqttHost + ":" + main.mqttPort, 14, 40)
                ctx.fillText("Topic: " + main.mqttTopic, 14, 54)
                var last = main.lastPayload ? main.lastPayload.toString() : "(waiting for message)"
                if (last.length > 45) last = last.substring(0, 42) + "..."
                ctx.fillText("Last msg: " + last, 14, 68)
                ctx.fillText("Chars loaded: " + main.messageChars.length, 14, 82)
                ctx.fillText("Status code: " + main.mqttConnected, 14, 96)
            }
        }

        Component.onCompleted: initDrops()
    }

    onFontSizeChanged: { canvas.initDrops(); canvas.requestPaint(); }
    onSpeedChanged: timer.interval = 1000 / main.speed;
    onColorModeChanged: canvas.requestPaint();
    onSingleColorChanged: canvas.requestPaint();
    onPaletteIndexChanged: canvas.requestPaint();
    onJitterChanged: canvas.requestPaint();
    onGlitchChanceChanged: canvas.requestPaint();
    onMqttEnableChanged: mqttConnect();
    onMqttHostChanged: mqttConnect();
    onMqttPortChanged: mqttConnect();
    onMqttPathChanged: mqttConnect();
    onMqttTopicChanged: mqttConnect();
    onDebugOverlayChanged: canvas.requestPaint();

    Component.onCompleted: { 
        main.writeLog("Wallpaper component completed, initializing...")
        canvas.initDrops()
        main.writeLog("Canvas drops initialized, mqttEnable=" + main.mqttEnable)
        mqttConnect()
    }
}
