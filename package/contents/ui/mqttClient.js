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
    var connectFlags = [0x02]  // Clean session
    if (user && user.length > 0) connectFlags[0] |= 0x80
    if (pass && pass.length > 0) connectFlags[0] |= 0x40
    var keepAlive = [0x00, 0x3C]  // 60 seconds
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
    var payload = topicBytes.concat([0x00])  // QoS 0
    var vh = packetId
    var remaining = vh.concat(payload)
    var fixedHeader = [0x82]  // SUBSCRIBE with QoS 1
    var lenEncoded = mqttEncodeLength(remaining.length)
    var header = fixedHeader.concat(lenEncoded)
    var packet = new Uint8Array(header.concat(remaining))
    return packet.buffer
}

function arrayBufferToHex(buffer) {
    var arr = new Uint8Array(buffer)
    var hex = []
    for (var i = 0; i < Math.min(arr.length, 32); i++) {
        var byte = arr[i].toString(16).toUpperCase()
        hex.push(byte.length === 1 ? '0' + byte : byte)
    }
    if (arr.length > 32) hex.push('...')
    return hex.join(' ')
}

function handleBinaryMessage(data) {
    try {
        var arr = new Uint8Array(data)
        if (_currentOpts.onDebug) {
            _currentOpts.onDebug("📦 Binary packet received (" + arr.length + " bytes): " + arrayBufferToHex(data))
        }
        
        if (arr.length < 2) {
            if (_currentOpts.onDebug) _currentOpts.onDebug("⚠️ Packet too short")
            return
        }
        
        var header = mqttDecodeRemaining(arr)
        var packetType = arr[0] >> 4
        var packetTypeName = ["", "CONNECT", "CONNACK", "PUBLISH", "PUBACK", "PUBREC", "PUBREL", "PUBCOMP", "SUBSCRIBE", "SUBACK", "UNSUBSCRIBE", "UNSUBACK", "PINGREQ", "PINGRESP", "DISCONNECT"][packetType] || "UNKNOWN"
        
        if (_currentOpts.onDebug) {
            _currentOpts.onDebug("📋 Packet type: " + packetTypeName + " (" + packetType + "), remaining: " + header.remaining)
        }
        
        if (packetType === 2) {
            // CONNACK
            if (arr.length < 4) {
                if (_currentOpts.onDebug) _currentOpts.onDebug("⚠️ CONNACK too short")
                return
            }
            var sessionPresent = arr[2] & 0x01
            var returnCode = arr[3]
            var returnCodes = ["Connection Accepted", "Unacceptable protocol version", "Identifier rejected", "Server unavailable", "Bad username or password", "Not authorized"]
            var returnMsg = returnCodes[returnCode] || "Unknown error"
            
            if (_currentOpts.onDebug) {
                _currentOpts.onDebug("✅ CONNACK: " + returnMsg + " (code=" + returnCode + ", session=" + sessionPresent + ")")
            }
            
            if (returnCode === 0) {
                if (_currentOpts.onConnect) _currentOpts.onConnect()
            } else {
                if (_currentOpts.onError) _currentOpts.onError("CONNACK error: " + returnMsg)
            }
            
        } else if (packetType === 9) {
            // SUBACK
            if (_currentOpts.onDebug) _currentOpts.onDebug("✅ SUBACK received")
            
        } else if (packetType === 3) {
            // PUBLISH
            var topicLenIdx = 1 + header.lenBytes
            if (arr.length < topicLenIdx + 2) {
                if (_currentOpts.onDebug) _currentOpts.onDebug("⚠️ PUBLISH packet too short for topic")
                return
            }
            
            var topicLen = (arr[topicLenIdx] << 8) | arr[topicLenIdx + 1]
            var topicStart = topicLenIdx + 2
            
            if (arr.length < topicStart + topicLen) {
                if (_currentOpts.onDebug) _currentOpts.onDebug("⚠️ PUBLISH packet too short for topic data")
                return
            }
            
            var topic = ""
            for (var i = 0; i < topicLen; i++) {
                topic += String.fromCharCode(arr[topicStart + i])
            }
            
            var payloadStart = topicStart + topicLen
            var payload = ""
            for (var j = payloadStart; j < arr.length; j++) {
                payload += String.fromCharCode(arr[j])
            }
            
            if (_currentOpts.onDebug) {
                _currentOpts.onDebug("📨 PUBLISH topic=[" + topic + "] payload length=" + payload.length)
            }
            
            if (_currentOpts.onMessage) _currentOpts.onMessage(topic, payload)
            
        } else {
            if (_currentOpts.onDebug) {
                _currentOpts.onDebug("ℹ️ Unhandled packet type: " + packetTypeName)
            }
        }
    } catch (e) {
        if (_currentOpts.onError) _currentOpts.onError("Error parsing packet: " + e.toString())
    }
}

function connect(opts) {
    _currentOpts = opts || {}
    var url = (_currentOpts.useSsl ? "wss://" : "ws://") + _currentOpts.host + ":" + _currentOpts.port + (_currentOpts.path || "")
    if (_currentOpts.onDebug) _currentOpts.onDebug("🔌 Connecting to: " + url)
    
    try {
        // Close existing connection if any
        if (_ws) { 
            try { _ws.active = false } catch(e) {} 
            _ws = null 
        }
        
        var socketObj = _currentOpts.socket
        if (!socketObj) {
            if (_currentOpts.onError) _currentOpts.onError("No WebSocket object provided")
            return
        }

        _ws = socketObj
        _ws.url = url
        _ws.active = true

        // Note: Signal handlers must be connected in QML using Connections component
        // We cannot assign them from JavaScript as they are read-only properties
        // The QML code must handle: onStatusChanged, onTextMessageReceived, onBinaryMessageReceived
        
    } catch (e) {
        if (_currentOpts.onError) _currentOpts.onError(e.toString())
    }
}

function sendConnectPacket() {
    if (!_ws) {
        if (_currentOpts.onDebug) _currentOpts.onDebug("⚠️ Cannot send CONNECT: no socket")
        return
    }
    try {
        var clientId = (_currentOpts.clientIdPrefix || "mqttrain-") + Math.random().toString(36).substring(2, 10)
        var connPkt = mqttBuildConnectPacket(clientId, _currentOpts.username || "", _currentOpts.password || "")
        
        if (_currentOpts.onDebug) {
            _currentOpts.onDebug("📤 Sending CONNECT packet (" + connPkt.byteLength + " bytes): " + arrayBufferToHex(connPkt))
        }
        
        _ws.sendBinaryMessage(connPkt)
        if (_currentOpts.onDebug) _currentOpts.onDebug("✅ CONNECT packet sent")
    } catch(e) {
        if (_currentOpts.onError) _currentOpts.onError("Error sending CONNECT: " + e.toString())
    }
}

function sendSubscribePacket(topic) {
    if (!_ws) {
        if (_currentOpts.onDebug) _currentOpts.onDebug("⚠️ Cannot send SUBSCRIBE: no socket")
        return
    }
    try {
        var subPkt = mqttBuildSubscribePacket(topic || _currentOpts.topic || "")
        
        if (_currentOpts.onDebug) {
            _currentOpts.onDebug("📤 Sending SUBSCRIBE packet (" + subPkt.byteLength + " bytes): " + arrayBufferToHex(subPkt))
        }
        
        _ws.sendBinaryMessage(subPkt)
        if (_currentOpts.onDebug) _currentOpts.onDebug("✅ SUBSCRIBE packet sent for topic: " + (topic || _currentOpts.topic))
    } catch(e) {
        if (_currentOpts.onError) _currentOpts.onError("Error sending SUBSCRIBE: " + e.toString())
    }
}

function disconnect() { 
    if (_ws) { 
        try { 
            if (_currentOpts.onDebug) _currentOpts.onDebug("🔌 Disconnecting WebSocket")
            _ws.active = false 
        } catch(e) {} 
        _ws = null 
    } 
}

function subscribe(topic) { 
    sendSubscribePacket(topic)
}

function getSocket() {
    return _ws
}

function getOptions() {
    return _currentOpts
}
