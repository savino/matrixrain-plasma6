# Matrix Rain MQTT Wallpaper for KDE Plasma 6

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
- **Native MQTT protocol** - Direct TCP connection using libmosquitto (no WebSocket overhead)
- **Live message display** - Incoming MQTT messages appear as falling characters
- **Flexible configuration** - Set custom host, port, topic, and credentials
- **Auto-reconnection** - Automatically reconnects on connection loss
- **Debug overlay** - Optional on-screen debugging information
- **High performance** - C++ plugin with Qt6 integration
- **Full MQTT spec compliance** - QoS levels, authentication, wildcard topics

## Installation

### Dependencies

Install the following packages for your distribution:

**Arch Linux / Manjaro:**
```bash
sudo pacman -S cmake qt6-base qt6-declarative mosquitto kpackage
```

**Debian / Ubuntu:**
```bash
sudo apt install cmake qt6-base-dev qt6-declarative-dev libmosquitto-dev kf6-kpackage
```

**Fedora:**
```bash
sudo dnf install cmake qt6-qtbase-devel qt6-qtdeclarative-devel mosquitto-devel kf6-kpackage
```

### Build and Install

The installation script will automatically build the C++ plugin and install everything:

```bash
git clone https://github.com/savino/matrixrain-plasma6.git
cd matrixrain-plasma6
chmod +x install.sh
./install.sh
```

The script will:
1. Check all dependencies
2. Build the C++ MQTT plugin
3. Install the plugin to `~/.local/lib/qt6/qml/`
4. Install the wallpaper package

### Post-Installation

Restart Plasma Shell to load the new wallpaper:

```bash
kquitapp6 plasmashell && kstart plasmashell &
```

Then open **System Settings → Appearance → Wallpaper** and select **"Matrix Rain MQTT"**.

## Configuration

### MQTT Settings

1. **Enable MQTT** - Toggle MQTT integration on/off
2. **MQTT Host** - Hostname or IP of your MQTT broker (e.g., `homeassistant.lan`, `192.168.1.100`)
3. **MQTT Port** - MQTT TCP port (default: `1883`, NOT the WebSocket port)
4. **MQTT Topic** - Topic to subscribe to (supports wildcards like `zigbee2mqtt/#`)
5. **Username/Password** - Optional authentication credentials
6. **Debug Overlay** - Show connection status and last message on screen

### Example Configurations

**Home Assistant with Mosquitto:**
```
Host: homeassistant.lan
Port: 1883
Topic: zigbee2mqtt/#
Username: mqtt_user
Password: your_password
```

**Local Mosquitto (no auth):**
```
Host: localhost
Port: 1883
Topic: test/topic
```

**Public MQTT Broker (testing):**
```
Host: test.mosquitto.org
Port: 1883
Topic: test/#
```

### Example Use Cases

- **Home Automation**: Subscribe to `zigbee2mqtt/#` or `homeassistant/#` to see all your smart home events
- **IoT Monitoring**: Display sensor data from connected devices in real-time
- **Development**: Debug MQTT applications visually
- **Art Installation**: Create dynamic visual displays from live data streams
- **System Monitoring**: Publish system stats to MQTT and visualize them

## Technical Details

### Architecture

The wallpaper consists of two components:

1. **C++ MQTT Plugin** (`plugin/`)
   - Native Qt6 QML plugin
   - Uses libmosquitto for MQTT protocol implementation
   - Exposes `MQTTClient` type to QML
   - Thread-safe signal/slot communication
   - Automatic event loop integration via QTimer

2. **QML Wallpaper** (`package/`)
   - Canvas-based Matrix rain rendering
   - Connects to C++ plugin via QML imports
   - Real-time character updates from MQTT messages
   - Configurable visual effects

### Requirements

- **KDE Plasma 6**
- **Qt 6.x** (Core, Qml modules)
- **libmosquitto** (MQTT client library)
- **CMake 3.16+** (for building)
- **MQTT broker** (e.g., Mosquitto, HiveMQ, EMQX)

### Building Manually

If you prefer to build the plugin separately:

```bash
cd plugin
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local
make -j$(nproc)
make install
```

## Troubleshooting

### Enable Debug Logging

Monitor wallpaper logs in real-time:

```bash
journalctl -f | grep -i mqttrain
```

Or view logs from current boot:

```bash
journalctl -b -0 | grep -i mqttrain
```

### Common Issues

**Plugin not found / Import error:**
```
module "ObsidianReq.MQTTRain" is not installed
```
- Verify plugin was built: `ls ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/`
- Check for `libmqttrainplugin.so` and `qmldir`
- Re-run `./install.sh`

**Connection fails:**
- Enable debug overlay to see connection status
- Verify MQTT broker is running: `mosquitto_sub -h <host> -p 1883 -t '#' -v`
- Check firewall allows TCP port 1883
- Verify credentials if authentication is enabled
- Check broker logs for connection attempts

**Build errors:**
- Ensure all dependencies are installed
- Check Qt6 version: `qmake6 --version` (requires 6.0+)
- Verify libmosquitto: `ldconfig -p | grep mosquitto`
- Check CMake output for missing packages

**No characters appearing:**
- Enable debug overlay to verify messages are being received
- Check that you're subscribed to an active topic with messages
- Test topic with: `mosquitto_sub -h <host> -p 1883 -t <topic> -v`
- Verify MQTT credentials match broker configuration

**Port confusion:**
- Use port **1883** (native MQTT), NOT 1884/9001 (WebSocket ports)
- The C++ implementation uses direct TCP, not WebSocket

## Development

### Project Structure

```
matrixrain-plasma6/
├── plugin/              # C++ MQTT plugin
│   ├── CMakeLists.txt   # Build configuration
│   ├── mqttclient.h     # MQTTClient class header
│   ├── mqttclient.cpp   # Implementation
│   ├── qmldir           # QML module definition
│   └── build/           # Build output (created by cmake)
├── package/             # Plasma wallpaper package
│   ├── metadata.json    # Package metadata
│   └── contents/
│       └── ui/
│           ├── main.qml           # Main wallpaper logic
│           └── config.qml         # Settings UI
├── install.sh           # Installation script
└── README.md
```

### Adding Features

**To modify MQTT behavior:**
- Edit `plugin/mqttclient.cpp` (C++ implementation)
- Rebuild: `cd plugin/build && make && make install`

**To modify visual effects:**
- Edit `package/contents/ui/main.qml`
- Reload wallpaper: Right-click desktop → Configure Desktop and Wallpaper

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
   - Output of `./install.sh` if build-related

## License

GPL v3 - See [LICENSE](LICENSE) file

## Credits

Original Matrix Rain wallpaper by [obsidianreq](https://github.com/obsidianreq)  
Native MQTT integration (C++ plugin) by [savino](https://github.com/savino)

## Acknowledgments

- [libmosquitto](https://mosquitto.org/) - Eclipse Mosquitto MQTT client library
- [Qt Project](https://www.qt.io/) - Qt framework
- [KDE Plasma](https://kde.org/plasma-desktop/) - Desktop environment
