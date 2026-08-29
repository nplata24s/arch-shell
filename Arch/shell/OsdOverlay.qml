import QtQuick
import Quickshell
import Quickshell.Wayland
import "theme"

PanelWindow {
    id: root
    required property var shellState

    screen: Quickshell.screens.length ? Quickshell.screens[0] : null
    visible: showing
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: false
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "arch-shell-osd"

    property bool showing: false
    property int hideMs: 1400

    readonly property bool barOnTop: {
        const _ = shellState ? shellState.settingsRev : 0
        const t = shellState && shellState.settings.taskbar
            ? shellState.settings.taskbar : {}
        return (t.position || "top") !== "bottom"
    }
    readonly property int barReserve: {
        const _ = shellState ? shellState.settingsRev : 0
        const t = shellState && shellState.settings.taskbar
            ? shellState.settings.taskbar : {}
        const h = t.height || 48
        const m = t.margins || {}
        const gap = barOnTop
            ? (m.top !== undefined ? m.top : 6)
            : (m.bottom !== undefined ? m.bottom : 6)
        return h + gap
    }

    anchors {
        left: true
        right: true
        bottom: !barOnTop
        top: barOnTop
    }
    margins {
        bottom: barOnTop ? 0 : barReserve + 16
        top: barOnTop ? barReserve + 16 : 0
    }

    implicitHeight: 72
    implicitWidth: 280

    Connections {
        target: shellState
        function onOsdTickChanged() {
            if (!shellState || !shellState.osdKind)
                return
            root.showing = true
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: root.hideMs
        onTriggered: root.showing = false
    }

    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.barOnTop ? parent.top : undefined
        anchors.bottom: root.barOnTop ? undefined : parent.bottom
        width: 280
        height: 64

        Rectangle {
            anchors.fill: parent
            radius: ArchTheme.radiusLarge
            color: ArchTheme.mica
            border.width: 1
            border.color: ArchTheme.border

            Row {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const k = shellState ? shellState.osdKind : ""
                        if (k === "brightness") return Icons.brightness
                        if (k === "mic")
                            return (shellState && shellState.osdMuted) ? Icons.micOff : Icons.mic
                        if (k === "caps") return Icons.keyboard
                        return (shellState && shellState.osdMuted) ? Icons.volumeOff : Icons.volume
                    }
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: 22
                    color: ArchTheme.textPrimary
                    width: 28
                    horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    visible: shellState && shellState.osdKind !== "caps"
                    anchors.verticalCenter: parent.verticalCenter
                    width: 168
                    height: 6
                    radius: 3
                    color: ArchTheme.layer

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1,
                            (shellState ? shellState.osdValue : 0) / 100))
                        height: parent.height
                        radius: 3
                        color: (shellState && shellState.osdMuted)
                            ? ArchTheme.textTertiary : ArchTheme.accent
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    text: {
                        if (!shellState) return ""
                        if (shellState.osdKind === "caps") return "Caps"
                        if (shellState.osdMuted && shellState.osdKind !== "brightness")
                            return "Mute"
                        return String(shellState.osdValue) + "%"
                    }
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textSecondary
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
