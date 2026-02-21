// MQTTDebugOverlay.qml
// Debug overlay showing MQTT connection status and recent messages

import QtQuick 2.15

Item {
    id: overlay
    anchors.fill: parent
    visible: debugEnabled
    
    // Configuration
    property bool debugEnabled: false
    
    // MQTT state
    property bool mqttConnected: false
    property string mqttHost: ""
    property int mqttPort: 1883
    property string mqttTopic: ""
    property int reconnectInterval: 30
    
    // Statistics
    property int messagesReceived: 0
    property int activeColumns: 0
    property int totalColumns: 0
    property real fadeStrength: 0.05
    property string renderMode: "Mixed"
    
    // Message history
    property var messageHistory: []
    
    Canvas {
        id: debugCanvas
        anchors.fill: parent
        
        onPaint: {
            var ctx = getContext("2d")
            var BOX_X = 8, BOX_Y = 8, BOX_W = 780, BOX_H = 254
            var TX = 14, LINE = 16
            
            // Semi-transparent background
            ctx.fillStyle = "rgba(0,0,0,0.88)"
            ctx.fillRect(BOX_X, BOX_Y, BOX_W, BOX_H)
            
            // Title
            ctx.font = "bold 13px monospace"
            ctx.fillStyle = "#00ff00"
            ctx.fillText("⚙️ MQTT Rain Debug", TX, 26)
            
            // Connection status
            ctx.font = "12px monospace"
            ctx.fillStyle = mqttConnected ? "#00ff00" : "#ff4444"
            ctx.fillText("MQTT:   " + (mqttConnected ? "✅ CONNECTED" : "❌ DISCONNECTED"), TX, 46)
            
            // Broker info
            ctx.fillStyle = "#00ccff"
            ctx.fillText("Broker: " + mqttHost + ":" + mqttPort, TX, 62)
            ctx.fillText("Topic:  " + mqttTopic, TX, 78)
            
            // Statistics line 1
            ctx.fillStyle = "#aaaaaa"
            ctx.fillText("Msgs:   " + messagesReceived
                         + "  |  Active cols: " + activeColumns
                         + "  |  Total cols: " + totalColumns
                         + "  |  Fade: " + fadeStrength.toFixed(2), TX, 94)
            
            // Statistics line 2
            ctx.fillStyle = "#ffaa00"
            ctx.fillText("🔄 Reconnect: " + reconnectInterval + "s"
                         + "  |  Mode: " + renderMode, TX, 110)
            
            // Separator
            ctx.fillStyle = "#555555"
            ctx.fillRect(TX, 119, BOX_W - 20, 1)
            
            // Recent messages header
            ctx.fillStyle = "#888888"
            ctx.fillText("Recent messages (newest first):", TX, 132)
            
            // Message list
            var alphas = ["#ffff00", "#cccc00", "#999900", "#666600", "#444400"]
            var hist = messageHistory
            var baseY = 148
            
            if (hist.length === 0) {
                ctx.fillStyle = "#555555"
                ctx.fillText("(waiting for messages...)", TX, baseY)
            } else {
                for (var m = 0; m < Math.min(hist.length, 5); m++) {
                    var hEntry = hist[m]
                    if (!hEntry) continue
                    
                    var line = (hEntry.topic || "") + ": " + (hEntry.payload || "")
                    if (line.length > 100) {
                        line = line.substring(0, 97) + "…"
                    }
                    
                    ctx.fillStyle = alphas[m]
                    ctx.fillText(line, TX, baseY + m * LINE)
                }
            }
        }
    }
    
    // Auto-refresh on property changes
    Connections {
        target: overlay
        function onMessageHistoryChanged() { debugCanvas.requestPaint() }
        function onMqttConnectedChanged() { debugCanvas.requestPaint() }
        function onMessagesReceivedChanged() { debugCanvas.requestPaint() }
        function onActiveColumnsChanged() { debugCanvas.requestPaint() }
        function onRenderModeChanged() { debugCanvas.requestPaint() }
    }
}
