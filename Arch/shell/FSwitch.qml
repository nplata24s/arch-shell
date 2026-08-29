import QtQuick
import QtQuick.Controls
import "theme"

Switch {
    id: root

    font.family: ArchTheme.fontFamily
    font.pixelSize: ArchTheme.sizeSmall
    implicitHeight: 28
    implicitWidth: root.text ? textItem.implicitWidth + 48 : 40
    padding: 0

    indicator: Rectangle {
        id: knobTrack
        width: 40
        height: 20
        x: root.text ? root.width - width : 0
        y: (root.height - height) / 2
        radius: height / 2
        color: root.checked ? ArchTheme.accent : ArchTheme.layer
        border.width: root.checked ? 0 : 1
        border.color: root.hovered ? ArchTheme.textSecondary : ArchTheme.textTertiary
        Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

        Rectangle {
            width: root.checked ? 12 : 10
            height: width
            radius: width / 2
            x: root.checked ? parent.width - width - 4 : 5
            anchors.verticalCenter: parent.verticalCenter
            color: root.checked ? ArchTheme.textOnAccent : ArchTheme.textSecondary
            Behavior on x { NumberAnimation { duration: ArchTheme.animFast; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: ArchTheme.animFast } }
        }
    }

    contentItem: Text {
        id: textItem
        text: root.text
        font: root.font
        color: ArchTheme.textPrimary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        width: root.text ? root.width - 48 : 0
    }
}
