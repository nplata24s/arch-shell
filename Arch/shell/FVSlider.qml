import QtQuick
import QtQuick.Controls
import "theme"

// Vertical slider used by the equaliser bands.
Slider {
    id: root

    orientation: Qt.Vertical
    implicitWidth: 26
    implicitHeight: 110
    live: true

    // Zero line sits mid-track for symmetric gain ranges.
    readonly property real zeroPos: (0 - from) / (to - from)

    background: Rectangle {
        x: root.leftPadding + (root.availableWidth - width) / 2
        y: root.topPadding
        implicitHeight: 100
        width: 4
        height: root.availableHeight
        radius: 2
        color: ArchTheme.hoverStrong

        Rectangle {
            width: parent.width
            height: 1
            y: (1 - root.zeroPos) * parent.height
            color: ArchTheme.borderStrong
        }

        // Fill runs from the zero line to the handle.
        Rectangle {
            width: parent.width
            radius: 2
            color: ArchTheme.accent
            y: Math.min(1 - root.visualPosition, 1 - root.zeroPos) * parent.height
            height: Math.abs(root.visualPosition - root.zeroPos) * parent.height
        }
    }

    handle: Rectangle {
        x: root.leftPadding + (root.availableWidth - width) / 2
        y: root.topPadding + root.visualPosition * (root.availableHeight - height)
        implicitWidth: 14
        implicitHeight: 14
        radius: 7
        color: ArchTheme.textPrimary
        border.width: 4
        border.color: ArchTheme.accent
        scale: root.pressed ? 0.88 : 1.0
        Behavior on scale { NumberAnimation { duration: ArchTheme.animFast } }
    }
}
