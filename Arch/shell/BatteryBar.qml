import QtQuick
import Quickshell.Io
import "theme"

BarChip {
    id: root
    required property var shellState

    property var battery: ({ present: false, percent: 100, charging: false })
    readonly property bool low: battery.percent <= 20 && !battery.charging
    readonly property int notifCount: shellState ? shellState.notifCount : 0

    // Always shown: this chip is also the notification centre.
    implicitWidth: holderWidth + hPadding * 2
    readonly property int holderWidth: iconText.implicitWidth + pctText.implicitWidth
        + (badge.visible ? badge.implicitWidth + spacing : 0) + spacing

    active: shellState ? shellState.isOpen("BatteryNotifications") : false
    onActivated: if (shellState) shellState.open("BatteryNotifications")

    Text {
        id: iconText
        anchors.verticalCenter: parent.verticalCenter
        text: root.battery.present
            ? (root.battery.charging ? Icons.batteryCharging : Icons.battery)
            : (shellState && shellState.dnd ? Icons.bellOff : Icons.bell)
        font.family: ArchTheme.fontFamily
        font.pixelSize: 15
        color: root.low ? ArchTheme.danger
             : root.battery.charging ? ArchTheme.success
             : (root.active ? ArchTheme.accent : ArchTheme.textPrimary)
    }

    Text {
        id: pctText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.battery.present || root.notifCount > 0
        text: root.battery.present
            ? (root.battery.percent + "%")
            : (root.notifCount > 0 ? String(root.notifCount) : "")
        font.family: ArchTheme.fontFamily
        font.pixelSize: ArchTheme.sizeSmall
        color: root.low ? ArchTheme.danger : ArchTheme.textSecondary
    }

    Rectangle {
        id: badge
        visible: root.battery.present && root.notifCount > 0
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.max(14, badgeText.implicitWidth + 6)
        implicitHeight: 14
        radius: 7
        color: ArchTheme.accent

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.notifCount > 9 ? "9+" : String(root.notifCount)
            font.family: ArchTheme.fontFamily
            font.pixelSize: 9
            font.weight: Font.DemiBold
            color: ArchTheme.textOnAccent
        }
    }

    Process {
        id: fetchProc
        command: ["bash", shellState.scriptsPath + "/battery_state.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.battery = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    Component.onCompleted: fetchProc.running = true
}
