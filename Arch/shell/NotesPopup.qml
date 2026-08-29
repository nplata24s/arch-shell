import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState
    implicitWidth: 420
    implicitHeight: 360

    property string notesPath: Quickshell.env("HOME") + "/.config/arch-shell/notes.txt"

    FileView {
        id: notesFile
        path: root.notesPath
        watchChanges: true
        onLoaded: {
            if (noteArea.text.length === 0)
                noteArea.text = text()
        }
        onLoadFailed: { }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Quick notes"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                id: noteArea
                wrapMode: TextEdit.Wrap
                font.family: ArchTheme.fontFamily
                color: ArchTheme.textPrimary
                placeholderText: "Type a note…"
                background: Rectangle {
                    radius: ArchTheme.radiusCard
                    color: ArchTheme.layer
                    border.width: 1
                    border.color: noteArea.activeFocus ? ArchTheme.accent : ArchTheme.border
                }
            }
        }

        FBtn {
            text: "Save"
            Layout.alignment: Qt.AlignRight
            font.family: ArchTheme.fontFamily
            onClicked: {
                notesFile.setText(noteArea.text)
                shellState.close()
            }
        }
    }
}
