// MatrixRainLogic.js - Core Matrix Rain message processing
.pragma library

/**
 * Tag each character of a JSON string as key or value
 * @param {string} json - JSON string to process
 * @param {Array} result - Output array of {ch, isValue} objects
 */
function colorJsonChars(json, result) {
    if (!json || json.length === 0) return
    
    var ST_STRUCT = 0, ST_IN_KEY = 1, ST_IN_VAL_STR = 2, ST_IN_VAL_NUM = 3
    var state = ST_STRUCT, afterColon = false, arrayDepth = 0, escaped = false
    var i = 0
    
    try {
        for (; i < json.length; i++) {
            var ch = json.charAt(i)
            
            if (state === ST_STRUCT) {
                if (ch === '"') {
                    if (afterColon || arrayDepth > 0) {
                        state = ST_IN_VAL_STR
                        afterColon = false
                        escaped = false
                        result.push({ ch: ch, isValue: true })
                    } else {
                        state = ST_IN_KEY
                        escaped = false
                        result.push({ ch: ch, isValue: false })
                    }
                } else if (ch === '[') {
                    arrayDepth++
                    afterColon = false
                    result.push({ ch: ch, isValue: false })
                } else if (ch === ']') {
                    if (arrayDepth > 0) arrayDepth--
                    result.push({ ch: ch, isValue: false })
                } else if (ch === '{' || ch === '}' || ch === ',') {
                    afterColon = false
                    result.push({ ch: ch, isValue: false })
                } else if (ch === ':') {
                    afterColon = true
                    result.push({ ch: ch, isValue: false })
                } else if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
                    result.push({ ch: ch, isValue: false })
                } else if (afterColon || arrayDepth > 0) {
                    state = ST_IN_VAL_NUM
                    afterColon = false
                    result.push({ ch: ch, isValue: true })
                } else {
                    result.push({ ch: ch, isValue: false })
                }
            } else if (state === ST_IN_KEY) {
                result.push({ ch: ch, isValue: false })
                if (ch === '"' && !escaped) state = ST_STRUCT
                escaped = (ch === '\\' && !escaped)
            } else if (state === ST_IN_VAL_STR) {
                result.push({ ch: ch, isValue: true })
                if (ch === '"' && !escaped) state = ST_STRUCT
                escaped = (ch === '\\' && !escaped)
            } else if (state === ST_IN_VAL_NUM) {
                if (ch === ',' || ch === '}' || ch === ']') {
                    state = ST_STRUCT
                    afterColon = false
                    if (ch === ']' && arrayDepth > 0) arrayDepth--
                    result.push({ ch: ch, isValue: false })
                } else {
                    result.push({ ch: ch, isValue: true })
                }
            }
        }
    } catch(e) {
        console.log("[MatrixRainLogic] colorJsonChars error at pos " + i + ": " + e)
        // Append remaining chars as uncolored
        for (var k = i; k < json.length; k++) {
            result.push({ ch: json.charAt(k), isValue: false })
        }
    }
}

/**
 * Build display character array from MQTT message
 * @param {string} topic - MQTT topic (not displayed)
 * @param {string} payload - Message payload
 * @returns {Array} Array of {ch, isValue} objects
 */
function buildDisplayChars(topic, payload) {
    var p = (payload != null && payload !== undefined) ? payload.toString() : ""
    var result = []
    
    try {
        var parsed = null
        try { parsed = JSON.parse(p) } catch(e) {}
        
        if (parsed !== null && typeof parsed === "object") {
            // Valid JSON: colorize
            colorJsonChars(p, result)
        } else {
            // Plain string: all as value
            for (var j = 0; j < p.length; j++) {
                result.push({ ch: p.charAt(j), isValue: true })
            }
        }
        
        // Append separator
        result.push({ ch: '/', isValue: false })
    } catch(e) {
        console.log("[MatrixRainLogic] buildDisplayChars error: " + e)
        // Fallback: flat uncolored
        result = []
        var flat = p + "/"
        for (var k = 0; k < flat.length; k++) {
            result.push({ ch: flat.charAt(k), isValue: false })
        }
    }
    
    return result
}

/**
 * Assign message to a random free column
 * @param {Array} chars - Character array from buildDisplayChars
 * @param {Array} columnAssignments - Column assignment array (mutated)
 * @param {number} passesLeft - Number of passes before freeing (default 3)
 */
function assignMessageToColumn(chars, columnAssignments, passesLeft) {
    if (!columnAssignments || columnAssignments.length === 0) return
    if (passesLeft === undefined) passesLeft = 3
    
    var nCols = columnAssignments.length
    var freeCols = []
    
    // Find free columns
    for (var k = 0; k < nCols; k++) {
        if (columnAssignments[k] === null) {
            freeCols.push(k)
        }
    }
    
    var targetCol
    if (freeCols.length > 0) {
        // Prefer free column
        targetCol = freeCols[Math.floor(Math.random() * freeCols.length)]
    } else {
        // All busy: pick random
        targetCol = Math.floor(Math.random() * nCols)
    }
    
    columnAssignments[targetCol] = { 
        chars: chars, 
        passesLeft: passesLeft 
    }
}
