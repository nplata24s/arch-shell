import QtQuick
import QtQuick.Controls
import "theme"

Button {
    id: root

    property string glyph: ""
    property int glyphSize: 15
    property int diameter: 34
    property bool circular: false

    implicitWidth: diameter
    implicitHeight: diameter
    hoverEnabled: true

    background: Rectangle {
        radius: root.circular ? root.diameter / 2 : ArchTheme.radiusCard
        color: {
            if (!root.enabled) return "transparent"
            if (root.highlighted)
                return root.down ? ArchTheme.accentPressed
                     : (root.hovered ? ArchTheme.accentHover : ArchTheme.accent)
            if (root.down) return ArchTheme.pressed
            if (root.hovered) return ArchTheme.layerHover
            return ArchTheme.layer
        }
        border.width: root.highlighted ? 0 : 1
        border.color: ArchTheme.border
        Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }
    }

    contentItem: Text {
        text: root.glyph
        font.family: ArchTheme.fontFamily
        font.pixelSize: root.glyphSize
        color: !root.enabled ? ArchTheme.textDisabled
             : (root.highlighted ? ArchTheme.textOnAccent : ArchTheme.textPrimary)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
