import QtQuick
import QtQuick.Layouts
import "theme"

Item {
    id: root

    property var rules: []
    property var presets: [
        "ask-before-commit", "ask-before-shell", "ask-before-network",
        "no-destructive", "stay-in-repo", "report-to-lead"
    ]

    signal edited(var next)

    implicitHeight: col.implicitHeight
    implicitWidth: 240

    readonly property var chips: {
        const extra = (rules || []).filter(r => presets.indexOf(r) < 0)
        return presets.concat(extra)
    }

    function has(rule) {
        return (rules || []).indexOf(rule) >= 0
    }

    function toggle(rule) {
        const cur = (rules || []).slice()
        const i = cur.indexOf(rule)
        if (i >= 0)
            cur.splice(i, 1)
        else
            cur.push(rule)
        edited(cur)
    }

    function addCustom(text) {
        const t = (text || "").trim()
        if (!t || has(t))
            return
        edited((rules || []).concat([t]))
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        Flow {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.chips
                delegate: Rectangle {
                    required property string modelData
                    height: 24
                    width: lab.implicitWidth + 16
                    radius: ArchTheme.radius
                    color: root.has(modelData) ? ArchTheme.accentMuted : ArchTheme.layer
                    border.width: 1
                    border.color: root.has(modelData) ? ArchTheme.accentLine : ArchTheme.border

                    Text {
                        id: lab
                        anchors.centerIn: parent
                        text: modelData
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: root.has(modelData) ? ArchTheme.accent : ArchTheme.textSecondary
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(modelData)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            FField {
                id: custom
                Layout.fillWidth: true
                placeholderText: "Custom rule"
                font.pixelSize: ArchTheme.sizeCaption
                implicitHeight: 28
                onAccepted: {
                    root.addCustom(text)
                    text = ""
                }
            }
            FIconBtn {
                glyph: Icons.plus
                diameter: 28
                enabled: custom.text.trim() !== ""
                onClicked: {
                    root.addCustom(custom.text)
                    custom.text = ""
                }
            }
        }
    }
}
