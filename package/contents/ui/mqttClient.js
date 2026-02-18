// Lightweight MQTT-over-WebSocket helper for QML
// Exports functions: connect(opts), disconnect(), subscribe(topic)

var _ws = null
var _currentOpts = {}

function mqttBuildString(s) {
    var res = []
    res.push((s.length >> 8) & 0xFF)
    res.push(s.length & 0xFF)
    for (var i = 0; i < s.length; i++) res.push(s.charCodeAt(i))
    return res
}

function mqttEncodeLength(len) {
    var res = []
    do {
        var digit = len & 0x7F
        len = len >> 7
        if (len > 0) digit = digit | 0x80
        res.push(digit)
    } while (len > 0)
    return res
}

function mqttDecodeRemaining(arr) {
    var multiplier = 1
    var value = 0
    var i = 1
    var digit = 0
    do {
        digit = arr[i]
        value += (digit & 0x7F) * multiplier
        multiplier *= 128
        i++
        if (i > 5) break
    } while ((digit & 0x80) !== 0)
    return { remaining: value, lenBytes: i - 1 }
}

function mqttBuildConnectPacket(clientId, user, pass) {
    var protoName = mqttBuildString("MQTT")
    var protoLevel = [4]
    var connectFlags = [0x02]
    if (user && user.length > 0) connectFlags[0] |= 0x80
    if (pass && pass.length > 0) connectFlags[0] |= 0x40
    var keepAlive = [0x00, 0x3C]
    var payload = mqttBuildString(clientId)
    if (user && user.length > 0) payload = payload.concat(mqttBuildString(user))
    if (pass && pass.length > 0) payload = payload.concat(mqttBuildString(pass))
    var vh = protoName.concat(protoLevel, connectFlags, keepAlive)
    var remaining = vh.concat(payload)
    var fixedHeader = [0x10]
    var lenEncoded = mqttEncodeLength(remaining.length)
    var header = fixedHeader.concat(lenEncoded)
    var packet = new Uint8Array(header.concat(remaining))
    return packet.buffer
}

function mqttBuildSubscribePacket(topic) {
    var packetId = [0x00, 0x01]
    var topicBytes = mqttBuildString(topic)
    var payload = topicBytes.concat([0x00])
    var vh = packetId
    var remaining = vh.concat(payload)
    var fixedHeader = [0x82]
    var lenEncoded = mqttEncodeLength(remaining.length)
    var header = fixedHeader.concat(lenEncoded)
    var packet = new Uint8Array(header.concat(remaining))
    return packet.buffer
}

function _handleBinaryMessage(data) {
    try {
        var arr = new Uint8Array(data)
        if (arr.length < 2) return
        var header = mqttDecodeRemaining(arr)
        var packetType = arr[0] >> 4
        if (packetType === 2) {
            if (_currentOpts.onDebug) _currentOpts.onDebug("CONNACK received")
        } else if (packetType === 9) {
            if (_currentOpts.onDebug) _currentOpts.onDebug("SUBACK received")
        } else if (packetType === 3) {
            var topicLenIdx = 1 + header.lenBytes
            var topicLen = (arr[topicLenIdx] << 8) | arr[topicLenIdx + 1]
            var topicStart = topicLenIdx + 2
            var topic = ""
            for (var i = 0; i < topicLen; i++) topic += String.fromCharCode(arr[topicStart + i])
            var payloadStart = topicStart + topicLen
            var payload = ""
            for (var j = payloadStart; j < arr.length; j++) payload += String.fromCharCode(arr[j])
            if (_currentOpts.onMessage) _currentOpts.onMessage(topic, payload)
        }
    } catch (e) {
        if (_currentOpts.onError) _currentOpts.onError(e.toString())
    }
}

function connect(opts) {
    _currentOpts = opts || {}
    var url = (_currentOpts.useSsl ? "wss://" : "ws://") + _currentOpts.host + ":" + _currentOpts.port + (_currentOpts.path || "")
    if (_currentOpts.onDebug) _currentOpts.onDebug("Connecting to: " + url)
    try {
        // If a QML WebSocket object was provided use it; otherwise try to create one (best-effort)
        if (_ws) { try { _ws.close() } catch(e) {} _ws = null }
        var socketObj = _currentOpts.socket
        if (!socketObj) {
            // Try to create a QML WebSocket in the provided parent
            var parent = _currentOpts.parent || null
            if (!parent) throw new Error("No socket or parent provided for MQTT connect")
            var qmlStr = 'import QtWebSockets 1.0; WebSocket { id: mqttSocket; url: "' + url + '"; active: true }'
            try {
                socketObj = Qt.createQmlObject(qmlStr, parent, 'mqttSocket')
            } catch(e) {
                throw new Error('Failed to create QML WebSocket: ' + e)
            }
        } else {
            // set URL and activate
            socketObj.url = url
            socketObj.active = true
        }

        _ws = socketObj

        // wire up handlers on the QML WebSocket object
        _ws.onTextMessageReceived = function(message) {
            if (_currentOpts.onMessage) _currentOpts.onMessage(_currentOpts.topic || "", message)
        }
        _ws.onBinaryMessageReceived = function(message) {
            _handleBinaryMessage(message)
        }
        _ws.onStatusChanged = function() {
            try {
                var status = _ws.status
                // WebSocket.Open is available on the QML type
                if (status === WebSocket.Open || status === _ws.Open) {
                    if (_currentOpts.onConnect) _currentOpts.onConnect()
                } else {
                    if (_currentOpts.onDisconnect) _currentOpts.onDisconnect()
                }
            } catch (e) {
                if (_currentOpts.onDebug) _currentOpts.onDebug('status handler error: ' + e)
            }
        }
        _ws.onError = function() { if (_currentOpts.onError) _currentOpts.onError(_ws.errorString ? _ws.errorString : 'unknown error') }

        // Send CONNECT packet once socket is open; some QML WebSocket implementations
        // may already be open by the time we set handlers, so we attempt to send immediately
        try {
            var clientId = (_currentOpts.clientIdPrefix || "mqttrain-") + Math.random().toString(36).substring(2, 10)
            var connPkt = mqttBuildConnectPacket(clientId, _currentOpts.username || "", _currentOpts.password || "")
            _ws.sendBinaryMessage(connPkt)
            if (_currentOpts.topic) {
                var subPkt = mqttBuildSubscribePacket(_currentOpts.topic)
                // send after a short delay to allow CONNACK processing by broker
                Qt.callLater(function() { try { _ws.sendBinaryMessage(subPkt) } catch(e) {} })
            }
        } catch(e) {
            if (_currentOpts.onError) _currentOpts.onError(e.toString())
        }
    } catch (e) {
        if (_currentOpts.onError) _currentOpts.onError(e.toString())
    }
}

function disconnect() { if (_ws) { try { _ws.close() } catch(e) {} _ws = null } }

function subscribe(topic) { if (!_ws) return; try { var sub = mqttBuildSubscribePacket(topic); _ws.send(sub) } catch(e) { if (_currentOpts.onError) _currentOpts.onError(e.toString()) } }

