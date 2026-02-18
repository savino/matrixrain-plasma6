pragma ComponentBehavior: Bound
import QtQuick 2.15
import QtQuick.Controls 2.15 as QC
import QtQuick.Layouts 1.15
import org.kde.kirigami.layouts 2.0 as KirigamiLayouts

KirigamiLayouts.FormLayout {
    anchors.fill: parent

    property alias cfg_fontSize: fontSpin.value
    property alias cfg_speed: speedSpin.value
    property alias cfg_colorMode: modeCombo.currentIndex
    property alias cfg_singleColor: colorField.text
    property alias cfg_paletteIndex: paletteCombo.currentIndex
    property alias cfg_jitter: jitterSpin.value
    property alias cfg_glitchChance: glitchSpin.value
    property alias cfg_mqttEnable: mqttEnable.checked
    property alias cfg_mqttHost: mqttHost.text
    property alias cfg_mqttPort: mqttPort.value
    property alias cfg_mqttPath: mqttPath.text
    property alias cfg_mqttTopic: mqttTopic.text
    property alias cfg_mqttUsername: mqttUsername.text
    property alias cfg_mqttPassword: mqttPassword.text
    property alias cfg_debugOverlay: debugEnable.checked

    QC.SpinBox {
        id: fontSpin; from:8; to:48; stepSize:1
        KirigamiLayouts.FormData.label: qsTr("Font Size")
    }
    QC.SpinBox {
        id: speedSpin; from:1; to:100; stepSize:1
        KirigamiLayouts.FormData.label: qsTr("Speed")
    }
    QC.ComboBox {
        id: modeCombo; model:[qsTr("Single Color"), qsTr("Multi Color")]
        KirigamiLayouts.FormData.label: qsTr("Color Mode")
    }
    QC.TextField {
        id: colorField
        visible: modeCombo.currentIndex === 0
        KirigamiLayouts.FormData.label: qsTr("Single Color")
    }
    QC.Button {
        text: qsTr("Default"); visible: modeCombo.currentIndex === 0
        onClicked: colorField.text = "#00ff00"
    }
    QC.ComboBox {
        id: paletteCombo; model:[qsTr("Neon"), qsTr("Cyberpunk"), qsTr("Synthwave")]
        visible: modeCombo.currentIndex === 1
        KirigamiLayouts.FormData.label: qsTr("Palette")
    }
    QC.SpinBox {
        id: jitterSpin; from:0; to:100; stepSize:1
        KirigamiLayouts.FormData.label: qsTr("Jitter (%)")
    }
    QC.SpinBox {
        id: glitchSpin; from:0; to:100; stepSize:1
        KirigamiLayouts.FormData.label: qsTr("Glitch Chance (%)")
    }
    QC.CheckBox {
        id: mqttEnable
        KirigamiLayouts.FormData.label: qsTr("Enable MQTT (WebSocket)")
    }
    QC.TextField {
        id: mqttHost
        KirigamiLayouts.FormData.label: qsTr("MQTT Host")
    }
    QC.SpinBox {
        id: mqttPort; from:1; to:65535; stepSize:1
        KirigamiLayouts.FormData.label: qsTr("MQTT Port (WebSocket)")
    }
    QC.TextField {
        id: mqttPath
        KirigamiLayouts.FormData.label: qsTr("WebSocket Path")
    }
    QC.TextField {
        id: mqttTopic
        KirigamiLayouts.FormData.label: qsTr("MQTT Topic")
    }
    QC.TextField {
        id: mqttUsername
        KirigamiLayouts.FormData.label: qsTr("MQTT Username (optional)")
    }
    QC.TextField {
        id: mqttPassword
        echoMode: TextInput.Password
        KirigamiLayouts.FormData.label: qsTr("MQTT Password (optional)")
    }
    QC.CheckBox {
        id: debugEnable
        KirigamiLayouts.FormData.label: qsTr("Show Debug Overlay")
    }
}
