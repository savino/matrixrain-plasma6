// ColorUtils.js - Color manipulation utilities
.pragma library

/**
 * Blend a hex color towards white by a given factor
 * @param {string} hexColor - Color in #rrggbb or #aarrggbb format
 * @param {number} factor - Blend factor (0.0 = original, 1.0 = white)
 * @returns {string} RGB color string
 */
function lightenColor(hexColor, factor) {
    var src = hexColor.toString()
    var hex = src.replace(/^#/, "")
    
    // Handle #aarrggbb format (Qt)
    if (hex.length === 8) {
        hex = hex.substring(2)
    }
    
    var r = parseInt(hex.substring(0, 2), 16)
    var g = parseInt(hex.substring(2, 4), 16)
    var b = parseInt(hex.substring(4, 6), 16)
    
    // Parse failure fallback
    if (isNaN(r) || isNaN(g) || isNaN(b)) {
        return src
    }
    
    // Blend towards white
    r = Math.min(255, Math.round(r + (255 - r) * factor))
    g = Math.min(255, Math.round(g + (255 - g) * factor))
    b = Math.min(255, Math.round(b + (255 - b) * factor))
    
    return "rgb(" + r + "," + g + "," + b + ")"
}
