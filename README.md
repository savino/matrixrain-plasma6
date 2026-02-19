# Matrix Rain MQTT Wallpaper for KDE Plasma 6

An MQTT-enabled "code rainfall" background wallpaper for Plasma 6 that displays incoming MQTT messages as falling Matrix-style characters with **JSON syntax highlighting** and **per-message stream rendering**. Perfect for visualizing IoT data, home automation events, or any MQTT stream in real-time on your desktop.

![screenshot.png](screenshot.png)

## Features

### Visual Effects
- **Adjustable font size** - Scale characters from 8px to 48px
- **Color modes** - Single color or multi-color with 3 pre-defined palettes (Neon, Cyberpunk, Synthwave)
- **Customizable speed** - Control the drop speed from slow to fast
- **Fade strength** - Adjust trail length (0.01–0.20, independent of speed)
- **Jitter effect** - Add randomness to character movement
- **Glitch chance** - Random bright white characters for that authentic Matrix feel
- **JSON syntax highlighting** - Automatically highlights JSON values brighter than keys/structure
- **Multi-stream rendering** - Each MQTT message gets its own set of interleaved columns (up to 5 messages visible simultaneously)

### MQTT Integration
- **Native MQTT protocol** - Direct TCP connection using Qt6 Mqtt module
- **Live message display** - Incoming MQTT messages appear as falling characters
- **Message history** - Last 5 messages rendered as separate interleaved streams
- **Flexible configuration** - Set custom host, port, topic, and credentials
- **Auto-reconnection** - Automatically reconnects on connection loss
- **Debug overlay** - Optional on-screen debugging with last 5 messages, connection status, slot/char counts
- **High performance** - C++ plugin with Qt6 integration
- **Full MQTT spec compliance** - QoS levels, authentication, wildcard topics
- **Robust parsing** - Handles malformed JSON, null payloads, race conditions gracefully

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
5. **Configure systemd user environment** for QML plugin discovery (see below)

---

## ⚠️ Critical: QML Plugin Path (systemd environment.d)

This wallpaper uses a **native C++ QML plugin** (`libmqttrainplugin.so`) installed in
`~/.local/lib/qt6/qml/`. KDE Plasma's `plasmashell` is launched by **systemd --user**
and does NOT read shell rc files like `~/.bashrc` or `~/.zshrc`.

The plugin path must be declared in **`~/.config/environment.d/99-mqttrain-qt.conf`**
so systemd loads it before starting any user service.

### What the install script does

The script creates:
```bash
~/.config/environment.d/99-mqttrain-qt.conf
```
with content:
```bash
QML_IMPORT_PATH=/home/user/.local/lib/qt6/qml${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}
QML2_IMPORT_PATH=/home/user/.local/lib/qt6/qml${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}
```

Then runs `systemctl --user daemon-reexec` to reload the systemd user manager.

### Why you must log out/reboot

`plasmashell` inherits its environment from the systemd user session, which is created
at login time. After the environment.d file is written, you must:

- **Log out and log back in**, or
- **Reboot**

Running `source ~/.bashrc` in a terminal is **NOT sufficient** — the change must
propagate to systemd itself.

### Testing immediately without logout

To test the wallpaper in the current session before logging out:
```bash
export QML_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML_IMPORT_PATH:-}"
export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:${QML2_IMPORT_PATH:-}"
plasmashell --replace &
```

### Troubleshooting: "module not installed"

If you see:
```
module "ObsidianReq.MQTTRain" is not installed
```

1. Check the environment.d file exists:
   ```bash
   cat ~/.config/environment.d/99-mqttrain-qt.conf
   ```
2. Verify plugin files:
   ```bash
   ls ~/.local/lib/qt6/qml/ObsidianReq/MQTTRain/
   ```
3. **Log out and log back in** (or reboot)
4. Check systemd picked up the variable:
   ```bash
   systemctl --user show-environment | grep QML
   ```

---

## Configuration

### Visual Settings

1. **Font Size** - Character size in pixels (8–48)
2. **Speed** - Drop speed in fps (1–100)
3. **Fade Strength** - Trail fade alpha per frame (0.01–0.20, default 0.05)
   - Lower = longer trails
   - Higher = shorter, snappier trails
4. **Color Mode** - Single color or multi-color palette
5. **Palette** - Neon / Cyberpunk / Synthwave (multi-color mode only)
6. **Jitter (%)** - Random horizontal drift (0–100)
7. **Glitch Chance (%)** - White flash probability per character (0–100)

### MQTT Settings

1. **Enable MQTT** - Toggle MQTT integration on/off
2. **MQTT Host** - Hostname or IP of your MQTT broker (e.g., `homeassistant.lan`, `192.168.1.100`)
3. **MQTT Port** - MQTT TCP port (default: `1883`)
4. **MQTT Topic** - Topic to subscribe to (supports wildcards like `zigbee2mqtt/#`)
5. **Username/Password** - Optional authentication credentials
6. **Debug Overlay** - Show connection status, message history, slot/char counts on screen
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

- **Home Automation**: Subscribe to `zigbee2mqtt/#` or `homeassistant/#` to see all your smart home events with JSON values highlighted
- **IoT Monitoring**: Display sensor data from connected devices in real-time with color-coded payloads
- **Development**: Debug MQTT applications visually with syntax-highlighted JSON
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
   - Emits `messageReceived(topic, payload)` signals to QML

2. **QML Wallpaper** (`package/`)
   - Canvas-based Matrix rain rendering
   - Multi-stream architecture: each history slot owns interleaved columns
   - JSON syntax highlighting state machine
   - Configurable visual effects with real-time updates
   - Robust error handling for malformed payloads

**See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full technical details.**

### Rendering Pipeline

1. MQTT message arrives → `onMessageReceived(topic, payload)`
2. Message pushed to `messageHistory[]` (max 5, newest first)
3. `rebuildHistoryChars()` generates `messageHistoryChars[][]`
   - Each slot = `buildDisplayChars(topic, payload)` → `[{ch, isValue}, ...]`
   - JSON payloads → `colorJsonChars()` state machine tags values as `isValue: true`
4. Paint loop: column `i` reads from slot `i % nSlots`
   - `isValue: false` → base palette color (keys, structural chars)
   - `isValue: true` → `lightenColor(baseColor, 0.55)` (values)

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
- Check `~/.config/environment.d/99-mqttrain-qt.conf` exists and contains correct path
- **Log out and log back in** (or reboot)
- Verify with: `systemctl --user show-environment | grep QML`
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

**JSON not highlighted / values same color as keys:**
- This is a feature, not a bug! Check that color mode is set correctly
- JSON values should be ~55% brighter than keys/structure
- Try different palettes (Neon/Cyberpunk/Synthwave) to see the effect more clearly

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
├── docs/
│   ├── mqtt-specs.md            # MQTT payload format specs (HA, Z2M)
│   └── ARCHITECTURE.md          # Full technical architecture
├── .github/
│   └── copilot-instructions.md  # AI agent guidelines
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

**To modify visual effects:** edit `package/contents/ui/main.qml`, then:
```bash
cp package/contents/ui/main.qml ~/.local/share/plasma/wallpapers/obsidianreq.plasma.wallpaper.mqttrain/contents/ui/
plasmashell --replace &
```

**To add config options:**
1. Add entry to `package/contents/config/main.xml`
2. Add UI control to `package/contents/ui/config.qml` with `cfg_<key>` alias
3. Read in `main.qml` via `main.configuration.<key>`
4. Reinstall: `kpackagetool6 --type Plasma/Wallpaper --upgrade package`

## License

GPL v3 - See [LICENSE](LICENSE) file

## Credits

Original Matrix Rain wallpaper by [obsidianreq](https://github.com/obsidianreq)  
Native MQTT integration, JSON highlighting, multi-stream rendering by [savino](https://github.com/savino)

## Acknowledgments

- [Qt MQTT](https://doc.qt.io/qt-6/qtmqtt-index.html) - Qt MQTT module
- [Qt Project](https://www.qt.io/) - Qt framework
- [KDE Plasma](https://kde.org/plasma-desktop/) - Desktop environment
