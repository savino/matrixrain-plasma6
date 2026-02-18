// Classic worker script for MQTT.js (browser UMD bundle)
// Loads mqtt.min.js via importScripts and manages a client instance.

importScripts('../mqtt.min.js')

var client = null
var isConnecting = false

function now() {
    var d = new Date()
    return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0') + ' ' +
           String(d.getHours()).padStart(2,'0') + ':' + String(d.getMinutes()).padStart(2,'0') + ':' + String(d.getSeconds()).padStart(2,'0')
}

function sendDebug(msg) {
    postMessage({ type: 'debug', message: '[' + now() + '] ' + msg })
}

onmessage = function(e) {
    var data = e.data || {}
    var action = data.action

    if (action === 'connect') {
        if (isConnecting) { sendDebug('Connect request ignored, already connecting') ; return }
        isConnecting = true
        var url = data.url
        var options = data.options || {}
        options.reconnectPeriod = options.reconnectPeriod !== undefined ? options.reconnectPeriod : 2000

        try {
            if (client) {
                try { client.end(true) } catch(e) { sendDebug('Error ending previous client: ' + e) }
                client = null
            }

            sendDebug('Attempting connect to ' + url + ' (opts: ' + JSON.stringify({ clientId: options.clientId }) + ')')
            client = mqtt.connect(url, options)

            client.on('connect', function(connack) {
                isConnecting = false
                sendDebug('connect event - connack: ' + JSON.stringify(connack || {}))
                postMessage({ type: 'connected' })
            })

            client.on('reconnect', function() { sendDebug('reconnect event') })
            client.on('close', function() { sendDebug('close event'); postMessage({ type: 'disconnected' }) })
            client.on('offline', function() { sendDebug('offline event') })
            client.on('error', function(err) { sendDebug('error: ' + (err && err.message ? err.message : String(err))); postMessage({ type: 'error', message: (err && err.message) ? err.message : String(err) }) })

            client.on('message', function(topic, payload) {
                postMessage({ type: 'message', topic: topic, payload: payload.toString() })
            })

            client.on('packetsend', function(packet) { /* optional: sendDebug('packetsend: ' + (packet && packet.cmd)) */ })
            client.on('packetreceive', function(packet) {
                try {
                    if (packet && packet.cmd === 'suback') {
                        postMessage({ type: 'suback', packet: packet })
                    }
                } catch (e) {}
            })
        } catch (err) {
            isConnecting = false
            postMessage({ type: 'error', message: err && err.message ? err.message : String(err) })
        }
    }

    if (action === 'subscribe') {
        if (!client) { postMessage({ type: 'error', message: 'No client to subscribe' }); return }
        try {
            client.subscribe(data.topic, { qos: 0 }, function(err, granted) {
                if (err) postMessage({ type: 'error', message: err.message || String(err) })
                else postMessage({ type: 'suback', granted: granted })
            })
        } catch (e) { postMessage({ type: 'error', message: e.toString() }) }
    }

    if (action === 'disconnect') {
        try {
            if (client) { client.end(); client = null }
            postMessage({ type: 'disconnected' })
        } catch (e) { postMessage({ type: 'error', message: e.toString() }) }
    }
}
