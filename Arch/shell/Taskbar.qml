import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "theme"

Item {
    id: root

    required property var modelData
    required property var shellState

    property var taskbarSettings: {
        const _ = shellState ? shellState.settingsRev : 0
        return shellState && shellState.settings.taskbar
            ? shellState.settings.taskbar
            : ({ position: "top", height: 48 })
    }

    property bool barOnTop: (taskbarSettings.position || "top") !== "bottom"
    property int barHeight: taskbarSettings.height || 48
    property int marginTop: taskbarSettings.margins && taskbarSettings.margins.top !== undefined
        ? taskbarSettings.margins.top : 6
    property int marginSide: taskbarSettings.margins && taskbarSettings.margins.left !== undefined
        ? taskbarSettings.margins.left : 10
    property int barTotalHeight: barHeight + marginTop
    property int barRadius: 8
    property color glass: shellState ? shellState.barColor : ArchTheme.mica
    property bool popupOpen: shellState && shellState.openModule !== null

    PanelWindow {
        id: barWindow
        screen: root.modelData

        anchors {
            top: root.barOnTop
            bottom: !root.barOnTop
            left: true
            right: true
        }

        margins {
            top: root.barOnTop ? root.marginTop : 0
            bottom: root.barOnTop ? 0 : root.marginTop
            left: root.marginSide
            right: root.marginSide
        }

        implicitHeight: root.barHeight
        exclusiveZone: root.barTotalHeight
        color: "transparent"
        WlrLayershell.namespace: "arch-shell-bar"

        Rectangle {
            id: barBackground
            anchors.fill: parent

            // Corners stay square where a flyout is attached so the two
            // surfaces read as one piece of glass.
            topLeftRadius: root.barOnTop ? root.barRadius : (root.popupOpen ? 0 : root.barRadius)
            topRightRadius: root.barOnTop ? root.barRadius : (root.popupOpen ? 0 : root.barRadius)
            bottomLeftRadius: root.barOnTop ? (root.popupOpen ? 0 : root.barRadius) : root.barRadius
            bottomRightRadius: root.barOnTop ? (root.popupOpen ? 0 : root.barRadius) : root.barRadius

            color: root.glass
            border.color: ArchTheme.border
            border.width: 1

            // Covers the border line along the flyout seam.
            Rectangle {
                visible: root.popupOpen
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: root.barOnTop ? undefined : parent.top
                anchors.bottom: root.barOnTop ? parent.bottom : undefined
                height: 3
                color: parent.color
            }

            // Glass sheen along the outer edge, inset by the corner radius
            // so it cannot paint a sharp rectangle through the rounded corners.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: root.barOnTop ? parent.top : undefined
                anchors.bottom: root.barOnTop ? undefined : parent.bottom
                anchors.leftMargin: root.barRadius
                anchors.rightMargin: root.barRadius
                height: 1
                color: ArchTheme.glassHighlight
                opacity: 0.5
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 0

                ModuleSlot {
                    zone: "left"
                    shellState: root.shellState
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true; Layout.minimumWidth: 8 }

                ModuleSlot {
                    zone: "center"
                    shellState: root.shellState
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true; Layout.minimumWidth: 8 }

                ModuleSlot {
                    zone: "right"
                    shellState: root.shellState
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    ModulePopup {
        id: modulePopup
        shellState: root.shellState
        barScreen: root.modelData
        barOnTop: root.barOnTop
        barTotalHeight: root.barTotalHeight
        marginSide: root.marginSide
        barColor: root.glass
    }

    Timer {
        id: grabDelay
        interval: 80
        repeat: false
        onTriggered: grabReady = true
    }

    property bool grabReady: false

    Connections {
        target: shellState
        function onOpenModuleChanged() {
            if (shellState && shellState.openModule) {
                grabReady = false
                grabDelay.restart()
            } else {
                grabReady = false
                grabDelay.stop()
            }
        }
    }

    HyprlandFocusGrab {
        active: grabReady && shellState && shellState.openModule !== null
        windows: [barWindow, modulePopup]
        onCleared: if (shellState) shellState.close()
    }
}
