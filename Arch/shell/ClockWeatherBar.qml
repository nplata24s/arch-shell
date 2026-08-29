import QtQuick
import Quickshell.Io
import "theme"

// Merged clock + weather taskbar item: weather on the left, two-line
// time and date on the right, like the Windows 11 tray clock.
BarChip {
    id: root
    required property var shellState

    property var weather: ({ city: "", temp: null, description: "", code: 0 })
    property string timeText: ""
    property string dateText: ""

    readonly property string unit: {
        const _ = shellState ? shellState.settingsRev : 0
        return shellState && shellState.settings.weather
            ? (shellState.settings.weather.unit || "celsius") : "celsius"
    }

    active: shellState ? shellState.isOpen("ClockWeather") : false
    onActivated: if (shellState) shellState.open("ClockWeather")
    hPadding: 11
    spacing: 10

    WeatherGlyph {
        anchors.verticalCenter: parent.verticalCenter
        code: root.weather.code || 0
        font.pixelSize: 16
        visible: root.weather.temp !== null && root.weather.temp !== undefined
        color: root.active ? ArchTheme.accent : ArchTheme.textPrimary
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.weather.temp !== null && root.weather.temp !== undefined
        text: Math.round(root.weather.temp) + "°"
        font.family: ArchTheme.fontFamily
        font.pixelSize: ArchTheme.sizeSmall
        color: ArchTheme.textSecondary
    }

    Column {
        id: stamp
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        width: Math.max(timeLabel.implicitWidth, dateLabel.implicitWidth)

        Text {
            id: timeLabel
            width: stamp.width
            text: root.timeText
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
            color: ArchTheme.textPrimary
            horizontalAlignment: Text.AlignRight
        }

        Text {
            id: dateLabel
            width: stamp.width
            text: root.dateText
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeCaption
            color: ArchTheme.textTertiary
            horizontalAlignment: Text.AlignRight
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            root.timeText = Qt.formatTime(now, "HH:mm")
            root.dateText = Qt.formatDate(now, "ddd d MMM")
        }
    }

    Process {
        id: fetchProc
        command: ["bash", shellState.scriptsPath + "/weather_state.sh", root.unit]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.weather = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    onUnitChanged: fetchProc.running = true
    Component.onCompleted: fetchProc.running = true
}
