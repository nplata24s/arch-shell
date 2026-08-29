import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "theme"

Item {
    id: root
    implicitWidth: 480
    implicitHeight: 380

    required property var shellState

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Keyboard shortcuts"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Repeater {
            model: [
                ["Start menu", "Super"],
                ["Close popup", "Escape"],
                ["Desktop 1–9", "Super + 1–9"],
                ["Close window", "Super + X"],
                ["Task view", "Super + Tab"],
                ["Clipboard", "Super + V"],
                ["Notes", "Super + N"],
                ["Calculator", "Super + C"],
                ["Colour picker", "Super + Shift + C"],
                ["Terminal", "Super + Enter"],
                ["Audio", "Super + Shift + A"],
                ["Quick settings", "Super + Ctrl + A"],
                ["Agent Centre", "Super + A"],
                ["Cheat sheet", "Super + Shift + H"]
            ]
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Text { text: modelData[0]; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; Layout.preferredWidth: 180 }
                Text { text: modelData[1]; color: ArchTheme.textPrimary; font.family: ArchTheme.fontFamily }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Change these in Settings → Keybinds."
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        FBtn {
            text: "Open Settings"
            onClicked: shellState.open("Settings")
        }
    }
}
