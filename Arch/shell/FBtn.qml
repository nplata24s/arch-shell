import QtQuick
import QtQuick.Controls
import "theme"

Button {
    id: root

    property bool danger: false

    font.family: ArchTheme.fontFamily
    font.pixelSize: ArchTheme.sizeSmall
    implicitHeight: 32
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true

    background: Rectangle {
        implicitHeight: 32
        radius: ArchTheme.radiusCard
        color: {
            if (!root.enabled) return ArchTheme.pressed
            if (root.highlighted)
                return root.down ? ArchTheme.accentPressed
                     : (root.hovered ? ArchTheme.accentHover : ArchTheme.accent)
            if (root.down) return ArchTheme.pressed
            if (root.hovered) return ArchTheme.layerHover
            return ArchTheme.layer
        }
        border.width: root.highlighted ? 0 : 1
        border.color: root.hovered ? ArchTheme.borderStrong : ArchTheme.border

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: parent.radius
            anchors.rightMargin: parent.radius
            height: 1
            radius: 1
            visible: !root.highlighted && root.enabled
            color: ArchTheme.glassHighlight
            opacity: 0.6
        }

        Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }
    }

    contentItem: Text {
        text: root.text
        font: root.font
        color: {
            if (!root.enabled) return ArchTheme.textDisabled
            if (root.highlighted) return ArchTheme.textOnAccent
            if (root.danger) return ArchTheme.danger
            return ArchTheme.textPrimary
        }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
