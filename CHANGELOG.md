# Changelog

## [2.0.0] - 2026-02-18

### Changed - Major Architectural Refactoring

#### Migration from libmosquitto to Qt6 Mqtt Module

**Breaking Changes:**
- Replaced libmosquitto C library with Qt6::Mqtt module
- Plugin now requires `qt6-mqtt` package instead of `mosquitto`
- Build system updated (CMakeLists.txt)

**Benefits:**
- ✅ Official Qt Project library (active maintenance)
- ✅ No external C library dependencies
- ✅ Available in standard package repos (Arch, Ubuntu, Fedora)
- ✅ Native Qt C++ API with signals/slots
- ✅ Better Qt event loop integration
- ✅ Cleaner code architecture
- ✅ Full MQTT 3.1, 3.1.1, and 5.0 support

#### Files Modified

**Plugin Implementation:**
- `plugin/mqttclient.h` - Updated to use `QMqttClient` and `QMqttSubscription`
- `plugin/mqttclient.cpp` - Complete rewrite using Qt6 Mqtt API
- `plugin/plugin.cpp` - QML plugin registration (new file)
- `plugin/CMakeLists.txt` - Changed from `find_library(mosquitto)` to `find_package(Qt6 Mqtt)`
- `plugin/qmldir` - QML module definition

**Installation & Documentation:**
- `install.sh` - Updated dependency check for qt6-mqtt
- `README.md` - Updated installation instructions and technical details
- `.gitignore` - Added build artifacts and temp files
- `CHANGELOG.md` - This file

### Installation Instructions

**For Arch/Manjaro users:**
```bash
sudo pacman -S qt6-mqtt
```

**For Ubuntu/Debian users:**
```bash
sudo apt install libqt6mqtt6-dev
```

**For Fedora users:**
```bash
sudo dnf install qt6-qtmqtt-devel
```

Then:
```bash
git pull origin main
./install.sh
```

### Technical Details

**Old Architecture:**
- C library: libmosquitto (Eclipse Mosquitto)
- Manual event loop integration with QTimer
- Direct C API calls
- Custom threading management

**New Architecture:**
- Qt module: Qt6::Mqtt (official Qt Project)
- Native Qt event loop integration
- Qt signals/slots pattern
- Automatic threading via Qt framework

### API Compatibility

QML interface remains **100% compatible**. No changes required in:
- `package/contents/ui/main.qml`
- `package/contents/ui/config.qml`
- Wallpaper configuration
- User settings

The same properties and signals are exposed:
```qml
MQTTClient {
    host: "homeassistant.lan"
    port: 1883
    topic: "zigbee2mqtt/#"
    username: "user"
    password: "pass"
    
    onMessageReceived: (topic, payload) => { ... }
    onConnectionError: (error) => { ... }
}
```

---

## [1.0.0] - 2026-02-17

### Added
- Initial C++ plugin implementation using libmosquitto
- MQTT integration with native TCP protocol
- Matrix rain visual effects
- Configurable wallpaper settings
- Debug overlay
- Auto-reconnection logic
