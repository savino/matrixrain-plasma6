pragma ComponentBehavior: Bound
import QtQuick 2.15
import QtQuick.Controls 2.15 as QC
import QtQuick.Layouts 1.15
import org.kde.kirigami.layouts 2.0 as KirigamiLayouts

ColumnLayout {
    id: root
    
    // Property aliases for configuration binding
    property alias cfg_fontSize:      fontSpin.value
    property alias cfg_speed:         speedSpin.value
    property alias cfg_fadeStrength:  fadeSpin.value
    property alias cfg_colorMode:     modeCombo.currentIndex
    property alias cfg_singleColor:   colorField.text
    property alias cfg_paletteIndex:  paletteCombo.currentIndex
    property alias cfg_jitter:        jitterSpin.value
    property alias cfg_glitchChance:  glitchSpin.value
    property alias cfg_mqttEnable:    mqttEnable.checked
    property alias cfg_mqttHost:      mqttHost.text
    property alias cfg_mqttPort:      mqttPort.value
    property alias cfg_mqttPath:      mqttPath.text
    property alias cfg_mqttTopic:     mqttTopic.text
    property alias cfg_mqttUsername:  mqttUsername.text
    property alias cfg_mqttPassword:  mqttPassword.text
    property alias cfg_mqttReconnectInterval: mqttReconnectIntervalSpin.value
    property alias cfg_mqttRenderMode: mqttRenderModeCombo.currentIndex
    property alias cfg_debugOverlay:  debugOverlay.checked
    property alias cfg_mqttDebug:     mqttDebug.checked
    
    // Tab bar
    QC.TabBar {
        id: tabBar
        Layout.fillWidth: true
        
        QC.TabButton {
            text: qsTr("Appearance")
            icon.name: "preferences-desktop-theme"
        }
        QC.TabButton {
            text: qsTr("MQTT & Network")
            icon.name: "network-connect"
        }
    }
    
    // Tab content
    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: tabBar.currentIndex
        
        // ========== TAB 1: APPEARANCE ==========
        KirigamiLayouts.FormLayout {
            QC.Label {
                text: qsTr("Matrix Rain Visual Settings")
                font.bold: true
                KirigamiLayouts.FormData.isSection: true
            }
            
            QC.SpinBox {
                id: fontSpin
                from: 8
                to: 48
                stepSize: 1
                KirigamiLayouts.FormData.label: qsTr("Font Size")
            }
            
            QC.SpinBox {
                id: speedSpin
                from: 1
                to: 100
                stepSize: 1
                KirigamiLayouts.FormData.label: qsTr("Speed")
            }
            
            // fadeStrength: stored as integer 1-20, displayed as 0.01-0.20
            QC.SpinBox {
                id: fadeSpin
                from: 1
                to: 20
                stepSize: 1
                KirigamiLayouts.FormData.label: qsTr("Fade Strength")
                textFromValue: function(v) { return (v / 100).toFixed(2) }
                valueFromText: function(t) { return Math.round(parseFloat(t) * 100) }
                validator: DoubleValidator { bottom: 0.01; top: 0.20; decimals: 2 }
            }
            
            QC.Label {
                text: qsTr("Colors & Effects")
                font.bold: true
                KirigamiLayouts.FormData.isSection: true
            }
            
            QC.ComboBox {
                id: modeCombo
                model: [qsTr("Single Color"), qsTr("Multi Color")]
                KirigamiLayouts.FormData.label: qsTr("Color Mode")
            }
            
            QC.TextField {
                id: colorField
                visible: modeCombo.currentIndex === 0
                KirigamiLayouts.FormData.label: qsTr("Single Color")
            }
            
            QC.Button {
                text: qsTr("Reset to Default")
                visible: modeCombo.currentIndex === 0
                onClicked: colorField.text = "#00ff00"
            }
            
            QC.ComboBox {
                id: paletteCombo
                model: [qsTr("Neon"), qsTr("Cyberpunk"), qsTr("Synthwave")]
                visible: modeCombo.currentIndex === 1
                KirigamiLayouts.FormData.label: qsTr("Palette")
            }
            
            QC.SpinBox {
                id: jitterSpin
                from: 0
                to: 100
                stepSize: 1
                KirigamiLayouts.FormData.label: qsTr("Jitter (%)")
            }
            
            QC.SpinBox {
                id: glitchSpin
                from: 0
                to: 100
                stepSize: 1
                KirigamiLayouts.FormData.label: qsTr("Glitch Chance (%)")
            }
        }
        
        // ========== TAB 2: MQTT & NETWORK ==========
        KirigamiLayouts.FormLayout {
            QC.Label {
                text: qsTr("MQTT Connection")
                font.bold: true
                KirigamiLayouts.FormData.isSection: true
            }
            
            QC.CheckBox {
                id: mqttEnable
                KirigamiLayouts.FormData.label: qsTr("Enable MQTT")
            }
            
            QC.TextField {
                id: mqttHost
                enabled: mqttEnable.checked
                placeholderText: "homeassistant.lan"
                KirigamiLayouts.FormData.label: qsTr("MQTT Host")
            }
            
            QC.SpinBox {
                id: mqttPort
                from: 1
                to: 65535
                stepSize: 1
                enabled: mqttEnable.checked
                KirigamiLayouts.FormData.label: qsTr("MQTT Port")
            }
            
            QC.TextField {
                id: mqttPath
                enabled: mqttEnable.checked
                placeholderText: "/"
                KirigamiLayouts.FormData.label: qsTr("WebSocket Path")
            }
            
            QC.TextField {
                id: mqttTopic
                enabled: mqttEnable.checked
                placeholderText: "zigbee2mqtt/#"
                KirigamiLayouts.FormData.label: qsTr("MQTT Topic")
            }
            
            QC.Label {
                text: qsTr("Authentication (Optional)")
                font.bold: true
                KirigamiLayouts.FormData.isSection: true
            }
            
            QC.TextField {
                id: mqttUsername
                enabled: mqttEnable.checked
                placeholderText: qsTr("Leave empty if no auth")
                KirigamiLayouts.FormData.label: qsTr("Username")
            }
            
            QC.TextField {
                id: mqttPassword
                enabled: mqttEnable.checked
                echoMode: TextInput.Password
                placeholderText: qsTr("Leave empty if no auth")
                KirigamiLayouts.FormData.label: qsTr("Password")
            }
            
            QC.Label {
                text: qsTr("Behavior & Rendering")
                font.bold: true
                KirigamiLayouts.FormData.isSection: true
            }
            
            QC.SpinBox {
                id: mqttReconnectIntervalSpin
                from: 1
                to: 600
                stepSize: 5
                enabled: mqttEnable.checked
                KirigamiLayouts.FormData.label: qsTr("Reconnect interval (s)")
            }
            
            QC.ComboBox {
                id: mqttRenderModeCombo
                model: [
                    qsTr("Mixed (MQTT + Random)"),
                    qsTr("MQTT Only (Loop messages)"),
                    qsTr("MQTT Driven (On message)")
                ]
                enabled: mqttEnable.checked
                KirigamiLayouts.FormData.label: qsTr("Render Mode")
            }
            
            QC.Label {
                text: qsTr("Debug & Diagnostics")
                font.bold: true
                KirigamiLayouts.FormData.isSection: true
            }
            
            QC.CheckBox {
                id: debugOverlay
                text: qsTr("Show on-screen debug info")
                KirigamiLayouts.FormData.label: qsTr("Debug Overlay")
            }
            
            QC.CheckBox {
                id: mqttDebug
                text: qsTr("Log all MQTT messages to journal")
                enabled: mqttEnable.checked
                KirigamiLayouts.FormData.label: qsTr("Verbose Logging")
            }
        }
    }
}
