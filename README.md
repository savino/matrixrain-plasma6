# MQTT Rain Wallpaper for KDE Plasma 6

An MQTT-enabled "code rainfall" background wallpaper for Plasma 6 that displays incoming MQTT messages as falling Matrix-style characters. Perfect for visualizing IoT data, home automation events, or any MQTT stream in real-time on your desktop.

![screenshot.png](screenshot.png)

## Features

### Visual Effects
- **Adjustable font size** - Scale characters from 8px to 48px
- **Color modes** - Single color or multi-color with 3 pre-defined palettes (Neon, Cyberpunk, Synthwave)
- **Customizable speed** - Control the drop speed from slow to fast
- **Jitter effect** - Add randomness to character movement
- **Glitch chance** - Random bright white characters for that authentic Matrix feel

### MQTT Integration
- **WebSocket MQTT support** - Connect to any MQTT broker via WebSocket
- **Live message display** - Incoming MQTT messages appear as falling characters
- **Flexible configuration** - Set custom host, port, path, topic, and credentials
- **Auto-reconnection** - Automatically reconnects on connection loss
- **Debug overlay** - Optional on-screen debugging information
- **Lightweight implementation** - Custom MQTT client with minimal dependencies

## Installation

Installation requires `kpackagetool6` which can be found in:
- **Arch-based distros**: `kpackage` package
- **SUSE-based distros**: `kpackagetool6` package  
- **Debian-based distros**: `kf6-kpackage` package

```bash
git clone https://github.com/savino/matrixrain-plasma6.git
cd matrixrain-plasma6
kpackagetool6 --type Plasma/Wallpaper --install package/
kquitapp6 plasmashell && kstart plasmashell
```

Then open System Settings > Appearance > Wallpaper and select "MQTT Rain Wallpaper".

## Configuration

### MQTT Settings

1. **Enable MQTT** - Toggle MQTT integration on/off
2. **MQTT Host** - Hostname or IP of your MQTT broker (e.g., `homeassistant.lan`, `192.168.1.100`)
3. **MQTT Port** - WebSocket port (typically `1883` or `9001`)
4. **WebSocket Path** - Path for WebSocket endpoint (e.g., `/mqtt`, `/ws`)
5. **MQTT Topic** - Topic to subscribe to (supports wildcards like `zigbee2mqtt/#`)
6. **Username/Password** - Optional authentication credentials
7. **Debug Overlay** - Show connection status and last message on screen

### Example Use Cases

- **Home Automation**: Subscribe to `zigbee2mqtt/#` to see all your smart home events
- **IoT Monitoring**: Display sensor data from connected devices
- **Development**: Debug MQTT applications in real-time
- **Art Installation**: Create dynamic visual displays from live data streams

## Technical Details

### Architecture

The wallpaper uses a lightweight, custom MQTT-over-WebSocket implementation (`mqttClient.js`) that:
- Constructs MQTT packets manually for minimal overhead
- Integrates directly with QML WebSocket for native Qt compatibility
- Runs in the main thread for reliable message delivery
- Supports QoS 0 subscriptions
- Handles CONNECT, SUBSCRIBE, and PUBLISH packets

### Requirements

- KDE Plasma 6
- Qt 6.x with QtWebSockets module
- MQTT broker with WebSocket support (e.g., Mosquitto with WebSocket listener)

## Troubleshooting

### Enable Debug Logging

Monitor wallpaper logs in real-time:

```bash
journalctl -f | grep -i --line-buffered mqttrain
```

Or view logs from current boot:

```bash
journalctl -b -0 | grep -i mqttrain
```

### Common Issues

**Connection fails**: 
- Verify your MQTT broker has WebSocket enabled
- Check that the WebSocket path is correct (often `/mqtt` or `/ws`)
- Ensure firewall allows connections to the MQTT port

**No characters appearing**:
- Enable the debug overlay to verify messages are being received
- Check that you're subscribed to an active topic
- Verify MQTT credentials if authentication is required

## Reporting Bugs

If you encounter issues:

1. Enable debug overlay in wallpaper settings
2. Start log monitoring: `journalctl -f | grep -i --line-buffered mqttrain`
3. Reproduce the issue
4. [Open an issue](https://github.com/savino/matrixrain-plasma6/issues) with:
   - Description of the problem
   - Steps to reproduce
   - Relevant log output
   - Your configuration (host, port, topic)

## License

GPL v3 - See [LICENSE](LICENSE) file

## Credits

Original Matrix Rain wallpaper by [obsidianreq](https://github.com/obsidianreq)  
MQTT integration and enhancements by [savino](https://github.com/savino)
