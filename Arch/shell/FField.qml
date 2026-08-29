import QtQuick
import QtQuick.Controls
import "theme"

TextField {
    id: root

    property bool pill: false
    // When true, `liveText` is applied only while the field is not focused,
    // so a parent refresh cannot wipe what the user is typing.
    property bool bindLive: false
    property string liveText: ""

    font.family: ArchTheme.fontFamily
    font.pixelSize: ArchTheme.sizeBody
    color: ArchTheme.textPrimary
    placeholderTextColor: ArchTheme.textTertiary
    selectByMouse: true
    selectionColor: ArchTheme.accentSoft
    selectedTextColor: ArchTheme.textPrimary
    leftPadding: 14
    rightPadding: 14
    topPadding: 8
    bottomPadding: 8

    background: Rectangle {
        implicitHeight: 36
        radius: root.pill ? height / 2 : ArchTheme.radiusCard
        color: root.activeFocus ? ArchTheme.layerActive : ArchTheme.layer
        border.width: 1
        border.color: root.activeFocus ? ArchTheme.accent : ArchTheme.border
        Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

        // Fluent underline accent on focus
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - (root.pill ? 24 : 4)
            height: 2
            radius: 1
            visible: root.activeFocus && !root.pill
            color: ArchTheme.accent
        }
    }

    Binding {
        target: root
        property: "text"
        value: root.liveText
        when: root.bindLive && !root.activeFocus
        restoreMode: Binding.RestoreNone
    }
}
