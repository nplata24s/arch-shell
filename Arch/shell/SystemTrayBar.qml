import QtQuick
import Quickshell.Services.SystemTray
import "theme"

Item {
    id: root
    implicitWidth: trayRow.implicitWidth
    implicitHeight: 34

    Row {
        id: trayRow
        spacing: 1
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            model: SystemTray.items
            delegate: Rectangle {
                required property var modelData
                width: 28
                height: 28
                radius: ArchTheme.radius
                color: trayMa.containsMouse ? ArchTheme.layerHover : "transparent"
                Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

                Image {
                    anchors.centerIn: parent
                    source: modelData.icon || ""
                    width: 16
                    height: 16
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    opacity: trayMa.containsMouse ? 1 : 0.88
                }

                MouseArea {
                    id: trayMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: {
                        if (typeof modelData.activate === "function")
                            modelData.activate()
                    }
                }
            }
        }
    }
}
