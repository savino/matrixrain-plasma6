// main.qml
// Matrix Rain MQTT Wallpaper - Main orchestration
// Component-based architecture with pluggable renderers

import QtQuick 2.15
import QtQuick.Controls 2.15
import org.kde.plasma.plasmoid 2.0
import ObsidianReq.MQTTRain 1.0
import "components"
import "renderers"

WallpaperItem {
    id: main
    anchors.fill: parent
    
    // ===== Configuration Properties =====
    property int fontSize: main.configuration.fontSize !== undefined ? main.configuration.fontSize : 16
    property int speed: main.configuration.speed !== undefined ? main.configuration.speed : 50
    property real fadeStrength: (main.configuration.fadeStrength !== undefined ? main.configuration.fadeStrength : 5) / 100.0
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
    property int mqttReconnectInterval: main.configuration.mqttReconnectInterval !== undefined ? main.configuration.mqttReconnectInterval : 30
    property int mqttRenderMode: main.configuration.mqttRenderMode !== undefined ? main.configuration.mqttRenderMode : 0
    
    // Debug
    property bool debugOverlay: main.configuration.debugOverlay !== undefined ? main.configuration.debugOverlay : false
    
    // State tracking
    property var messageHistory: []
    property int messagesReceived: 0
    readonly property int maxHistory: 5
    
    // Color palettes
    property var palettes: [
        ["#00ff00", "#ff00ff", "#00ffff", "#ff0000", "#ffff00", "#0000ff"],
        ["#ff0066", "#33ff99", "#ffcc00", "#6600ff", "#00ccff", "#ff3300"],
        ["#ff00ff", "#00ffcc", "#cc00ff", "#ffcc33", "#33ccff", "#ccff00"]
    ]
    
    // Render mode names for debug
    readonly property var renderModeNames: ["Mixed", "MQTT-Only", "MQTT-Driven"]
    
    // ===== Utility Functions =====
    function writeLog(msg) { console.log("[MQTTRain] " + msg) }
    function writeDebug(msg) { if (mqttDebug) console.log("[MQTTRain][debug] " + msg) }
    
    // Current effective render mode name (including Classic)
    function getEffectiveRenderMode() {
        if (!mqttEnable) return "Classic"
        return renderModeNames[mqttRenderMode]
    }
    
    // ===== MQTT Client =====
    MQTTClient {
        id: mqttClient
        reconnectInterval: main.mqttReconnectInterval * 1000
        
        onConnectedChanged: {
            if (connected) {
                writeLog("✅ MQTT Connected")
            } else {
                writeLog("❌ MQTT Disconnected")
            }
        }
        
        onReconnecting: {
            writeLog("🔄 MQTT reconnecting in " + main.mqttReconnectInterval + "s...")
        }
        
        onMessageReceived: function(topic, payload) {
            var safeTopic = (topic != null && topic !== undefined) ? topic.toString() : ""
            var safePayload = (payload != null && payload !== undefined) ? payload.toString() : ""
            
            writeDebug("📨 [" + safeTopic + "] " + safePayload)
            messagesReceived++
            
            // Update message history for debug overlay
            var hist = messageHistory.slice()
            hist.unshift({ topic: safeTopic, payload: safePayload })
            if (hist.length > maxHistory) {
                hist = hist.slice(0, maxHistory)
            }
            messageHistory = hist
            
            // Delegate to active renderer (only if MQTT enabled)
            if (mqttEnable && matrixCanvas.activeRenderer) {
                matrixCanvas.activeRenderer.assignMessage(safeTopic, safePayload)
                matrixCanvas.requestPaint()
            }
        }
        
        onConnectionError: function(error) {
            writeLog("❌ MQTT Error: " + error)
        }
    }
    
    // ===== MQTT Connection Management =====
    function mqttConnect() {
        if (!mqttEnable) {
            mqttClient.disconnectFromHost()
            return
        }
        
        writeLog("Connecting to " + mqttHost + ":" + mqttPort + " topic=[" + mqttTopic + "]")
        mqttClient.host = mqttHost.trim()
        mqttClient.port = mqttPort
        mqttClient.username = mqttUsername.trim()
        mqttClient.password = mqttPassword
        mqttClient.topic = mqttTopic.trim()
        mqttClient.connectToHost()
    }
    
    // ===== Renderer Instances =====
    // ClassicRenderer: used when MQTT is disabled
    ClassicRenderer {
        id: classicRenderer
        fontSize: main.fontSize
        baseColor: main.singleColor
        jitter: main.jitter
        glitchChance: main.glitchChance
        palettes: main.palettes
        paletteIndex: main.paletteIndex
        colorMode: main.colorMode
    }
    
    // MQTT-based renderers: used when MQTT is enabled
    MixedModeRenderer {
        id: mixedRenderer
        fontSize: main.fontSize
        baseColor: main.singleColor
        jitter: main.jitter
        glitchChance: main.glitchChance
        palettes: main.palettes
        paletteIndex: main.paletteIndex
        colorMode: main.colorMode
    }
    
    MqttOnlyRenderer {
        id: mqttOnlyRenderer
        fontSize: main.fontSize
        baseColor: main.singleColor
        jitter: main.jitter
        glitchChance: main.glitchChance
        palettes: main.palettes
        paletteIndex: main.paletteIndex
        colorMode: main.colorMode
        messagePoolSize: 20
    }
    
    MqttDrivenRenderer {
        id: mqttDrivenRenderer
        fontSize: main.fontSize
        baseColor: main.singleColor
        jitter: main.jitter
        glitchChance: main.glitchChance
        palettes: main.palettes
        paletteIndex: main.paletteIndex
        colorMode: main.colorMode
    }
    
    // ===== Matrix Canvas =====
    MatrixCanvas {
        id: matrixCanvas
        anchors.fill: parent
        
        fontSize: main.fontSize
        speed: main.speed
        fadeStrength: main.fadeStrength
        mqttEnable: main.mqttEnable
        
        // Select active renderer: Classic if MQTT disabled, otherwise based on mode
        activeRenderer: {
            if (!main.mqttEnable) {
                return classicRenderer
            }
            
            switch(main.mqttRenderMode) {
                case 0: return mixedRenderer
                case 1: return mqttOnlyRenderer
                case 2: return mqttDrivenRenderer
                default: return mixedRenderer
            }
        }
    }
    
    // ===== Debug Overlay =====
    MQTTDebugOverlay {
        id: debugOverlay
        anchors.fill: parent
        
        debugEnabled: main.debugOverlay
        mqttConnected: mqttClient.connected
        mqttHost: main.mqttHost
        mqttPort: main.mqttPort
        mqttTopic: main.mqttTopic
        reconnectInterval: main.mqttReconnectInterval
        messagesReceived: main.messagesReceived
        fadeStrength: main.fadeStrength
        renderMode: main.getEffectiveRenderMode()
        messageHistory: main.messageHistory
        
        // Calculate active columns from renderer
        activeColumns: {
            if (!matrixCanvas.activeRenderer) return 0
            var ca = matrixCanvas.activeRenderer.columnAssignments
            if (!ca) return 0
            var count = 0
            for (var i = 0; i < ca.length; i++) {
                if (ca[i] !== null && (ca[i].active !== false)) count++
            }
            return count
        }
        
        totalColumns: matrixCanvas.activeRenderer ? matrixCanvas.activeRenderer.columns : 0
    }
    
    // ===== Configuration Change Handlers =====
    onFontSizeChanged: matrixCanvas.initDrops()
    onSpeedChanged: matrixCanvas.requestPaint()
    onFadeStrengthChanged: matrixCanvas.requestPaint()
    onColorModeChanged: matrixCanvas.requestPaint()
    onSingleColorChanged: matrixCanvas.requestPaint()
    onPaletteIndexChanged: matrixCanvas.requestPaint()
    onJitterChanged: matrixCanvas.requestPaint()
    onGlitchChanceChanged: matrixCanvas.requestPaint()
    onDebugOverlayChanged: matrixCanvas.requestPaint()
    
    onMqttRenderModeChanged: {
        if (mqttEnable) {
            writeLog("🎭 Render mode changed to: " + renderModeNames[mqttRenderMode])
            matrixCanvas.initDrops()
            matrixCanvas.requestPaint()
        }
    }
    
    onMqttEnableChanged: {
        if (mqttEnable) {
            writeLog("🎭 Switching to MQTT mode: " + renderModeNames[mqttRenderMode])
            mqttConnect()
        } else {
            writeLog("🎭 Switching to Classic mode (MQTT disabled)")
            mqttClient.disconnectFromHost()
        }
        matrixCanvas.initDrops()
        matrixCanvas.requestPaint()
    }
    
    onMqttHostChanged: { if (mqttEnable) mqttConnect() }
    onMqttPortChanged: { if (mqttEnable) mqttConnect() }
    onMqttTopicChanged: {
        if (mqttEnable && mqttClient.connected) {
            mqttClient.disconnectFromHost()
            mqttConnect()
        }
    }
    
    // ===== Initialization =====
    Component.onCompleted: {
        writeLog("=== Matrix Rain MQTT Wallpaper ===")
        
        if (mqttEnable) {
            writeLog("MQTT host=[" + mqttHost + "] port=" + mqttPort + " topic=[" + mqttTopic + "]")
            writeLog("🔄 Reconnect interval: " + mqttReconnectInterval + "s")
            writeLog("🎭 Render mode: " + renderModeNames[mqttRenderMode])
            Qt.callLater(mqttConnect)
        } else {
            writeLog("🎭 Classic mode: Pure Matrix rain (MQTT disabled)")
        }
        
        matrixCanvas.initDrops()
    }
    
    Component.onDestruction: {
        mqttClient.disconnectFromHost()
    }
}
