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
- **Native MQTT protocol** - Direct TCP connection using Qt6 Mqtt module
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
sudo pacman -S cmake qt6-base qt6-declarative qt6-mqtt kpackage
```

**Debian / Ubuntu:**
```bash
sudo apt install cmake qt6-base-dev qt6-declarative-dev libqt6mqtt6-dev kf6-kpackage
```

**Fedora:**
```bash
sudo dnf install cmake qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtmqtt-devel kf6-kpackage
```

### Build and Install

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
5. **Check and configure `QML2_IMPORT_PATH`** (see below)

---

## ⚠️ Critical: QML2_IMPORT_PATH

This wallpaper uses a **native C++ QML plugin** (`libmqttrainplugin.so`) installed in a
non-standard path (`~/.local/lib/qt6/qml/`). KDE Plasma's `plasmashell` must be told
where to look for it via the `QML2_IMPORT_PATH` environment variable.

**Without this variable set before `plasmashell` starts, the wallpaper will fail with:**
```
module "ObsidianReq.MQTTRain" is not installed
```

### Why it's needed

Qt's QML engine searches for plugins only in its built-in paths by default.
User-installed plugins under `~/.local/` are not included unless explicitly declared.
`QML2_IMPORT_PATH` extends this search path at runtime.

### Setting it permanently

The `install.sh` script will detect if the variable is missing or incomplete and offer
to add it automatically to your shell config. If you prefer to do it manually:

**bash / zsh:**
```bash
echo 'export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"' >> ~/.bashrc
# or for zsh:
echo 'export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"' >> ~/.zshrc
```

**fish:**
```fish
echo 'set -gx QML2_IMPORT_PATH $HOME/.local/lib/qt6/qml $QML2_IMPORT_PATH' >> ~/.config/fish/config.fish
```

### Why a logout/relogin is required

`plasmashell` is launched by the **KDE session manager** (`startplasma-wayland` /
`startplasma-x11`) before any shell rc file (`.bashrc`, `.zshrc`) is sourced.
Simply running `source ~/.bashrc` in a terminal is **not enough**.

After adding the variable you must either:
- **Log out and log back in** to your KDE session, or
- **Reboot**

For an immediate test in the current session without rebooting:
```bash
export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"
plasmashell --replace &
```

### KDE Plasma environment file (alternative)

For a more robust solution that survives shell changes, you can also add the variable
to KDE's own environment file — this is sourced by the session manager directly:
```bash
mkdir -p ~/.config/plasma-workspace/env
cat >> ~/.config/plasma-workspace/env/qml2importpath.sh << 'EOF'
export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"
EOF
chmod +x ~/.config/plasma-workspace/env/qml2importpath.sh
```
This approach works regardless of which shell you use and does not require editing
`.bashrc` or `.zshrc`.

---

## Configuration

### MQTT Settings

1. **Enable MQTT** - Toggle MQTT integration on/off
2. **MQTT Host** - Hostname or IP of your MQTT broker (e.g., `homeassistant.lan`, `192.168.1.100`)
3. **MQTT Port** - MQTT TCP port (default: `1883`)
4. **MQTT Topic** - Topic to subscribe to (supports wildcards like `zigbee2mqtt/#`)
5. **Username/Password** - Optional authentication credentials
6. **Debug Overlay** - Show connection status and last message on screen
7. **Debug MQTT logging** - Print full MQTT messages to the system journal (off by default)

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
   - Uses **Qt6 Mqtt module** for MQTT protocol implementation
   - Exposes `MQTTClient` type to QML
   - Direct TCP connection using `QTcpSocket` as `IODevice` transport

2. **QML Wallpaper** (`package/`)
   - Canvas-based Matrix rain rendering
   - Connects to C++ plugin via QML imports
   - Real-time character updates from MQTT messages
   - Configurable visual effects

### Requirements

- **KDE Plasma 6**
- **Qt 6.x** (Core, Qml, Mqtt modules)
- **CMake 3.16+** (for building)
- **MQTT broker** (e.g., Mosquitto, HiveMQ, EMQX)

### Building Manually

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

Enable **"Debug MQTT logging"** in the wallpaper settings to see full MQTT message
payloads in the journal.

### Common Issues

**Plugin not found / Import error:**
```
module "ObsidianReq.MQTTRain" is not installed
```
- Check `QML2_IMPORT_PATH` — see the [Critical: QML2_IMPORT_PATH](#️-critical-qml2_import_path) section
- Verify plugin files: `ls ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/`
- Re-run `./install.sh`

**Connection fails / no characters:**
- Enable debug overlay to see connection status on screen
- Enable "Debug MQTT logging" and check `journalctl -f | grep MQTTRain`
- Test broker directly: `mosquitto_sub -h <host> -p 1883 -t '#' -v`
- Verify credentials and firewall rules

**Build errors:**
- Ensure `qt6-mqtt` is installed
- Check Qt6 version: `qmake6 --version`
- Verify Qt6 Mqtt: `find /usr/lib* -name "libQt6Mqtt.so*"`

## Development

### Project Structure

```
matrixrain-plasma6/
├── plugin/              # C++ MQTT plugin
│   ├── CMakeLists.txt
│   ├── plugin.cpp
│   ├── mqttclient.h
│   ├── mqttclient.cpp
│   ├── qmldir
│   └── build/
├── package/
│   ├── metadata.json
│   └── contents/
│       ├── config/
│       │   └── main.xml         # Config keys and defaults
│       └── ui/
│           ├── main.qml         # Wallpaper logic + Matrix rendering
│           └── config.qml       # Settings UI
├── install.sh
├── .gitignore
└── README.md
```

### Adding Features

**To modify MQTT behavior:** edit `plugin/mqttclient.cpp`, then rebuild:
```bash
cd plugin/build && make -j$(nproc)
cp libmqttrainplugin.so ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/
```

**To modify visual effects:** edit `package/contents/ui/main.qml`, then reload
the wallpaper from the desktop right-click menu.

## License

GPL v3 - See [LICENSE](LICENSE) file

## Credits

Original Matrix Rain wallpaper by [obsidianreq](https://github.com/obsidianreq)  
Native MQTT integration (C++ plugin) by [savino](https://github.com/savino)

## Acknowledgments

- [Qt MQTT](https://doc.qt.io/qt-6/qtmqtt-index.html) - Qt MQTT module
- [Qt Project](https://www.qt.io/) - Qt framework
- [KDE Plasma](https://kde.org/plasma-desktop/) - Desktop environment
