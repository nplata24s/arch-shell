import QtQuick
import QtQuick.Controls
import "theme"

SpinBox {
    id: root

    font.family: ArchTheme.fontFamily
    font.pixelSize: ArchTheme.sizeSmall
    implicitHeight: 32
    implicitWidth: 108
    editable: false

    background: Rectangle {
        radius: ArchTheme.radiusCard
        color: ArchTheme.layer
        border.width: 1
        border.color: root.activeFocus ? ArchTheme.accent : ArchTheme.border
    }

    contentItem: Text {
        text: root.textFromValue(root.value, root.locale)
        font: root.font
        color: ArchTheme.textPrimary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    up.indicator: Rectangle {
        x: root.width - width - 4
        y: 4
        width: 24
        height: root.height - 8
        radius: ArchTheme.radius
        color: root.up.pressed ? ArchTheme.pressed
             : (root.up.hovered ? ArchTheme.layerHover : "transparent")
        Text {
            anchors.centerIn: parent
            text: "+"
            font.family: ArchTheme.fontFamily
            font.pixelSize: 14
            color: root.up.hovered ? ArchTheme.accent : ArchTheme.textSecondary
        }
    }

    down.indicator: Rectangle {
        x: 4
        y: 4
        width: 24
        height: root.height - 8
        radius: ArchTheme.radius
        color: root.down.pressed ? ArchTheme.pressed
             : (root.down.hovered ? ArchTheme.layerHover : "transparent")
        Text {
            anchors.centerIn: parent
            text: "−"
            font.family: ArchTheme.fontFamily
            font.pixelSize: 14
            color: root.down.hovered ? ArchTheme.accent : ArchTheme.textSecondary
        }
    }
}
