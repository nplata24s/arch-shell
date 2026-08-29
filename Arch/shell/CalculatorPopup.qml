import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState
    implicitWidth: 340
    implicitHeight: 280

    property string resultText: ""

    function runCalc() {
        const expr = exprField.text.trim()
        if (!expr) return
        calcProc.command = ["qalc", "-t", expr]
        calcProc.running = true
    }

    Process {
        id: calcProc
        stdout: StdioCollector {
            onStreamFinished: root.resultText = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (!root.resultText && text.trim())
                    root.resultText = text.trim()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            text: "Calculator"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        FField {
            id: exprField
            Layout.fillWidth: true
            placeholderText: "e.g. 12 * 8 + 3"
            focus: true
            Keys.onReturnPressed: runCalc()
            Keys.onEnterPressed: runCalc()
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: resultText || "Result shows here"
            color: resultText ? ArchTheme.accent : ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeTitle
        }

        FBtn {
            text: "Calculate"
            highlighted: true
            Layout.fillWidth: true
            font.family: ArchTheme.fontFamily
            onClicked: runCalc()
        }
    }

    function focusSearch() {
        exprField.forceActiveFocus()
    }
}
