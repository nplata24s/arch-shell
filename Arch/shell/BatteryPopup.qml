import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState

    implicitWidth: 320
    implicitHeight: 420

    property var battery: ({ present: false, percent: 100, status: "Unknown", charging: false })

    Process {
        id: fetchProc
        command: ["bash", shellState.scriptsPath + "/battery_state.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.battery = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    Component.onCompleted: fetchProc.running = true

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Power & Notifications"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Text {
            visible: root.battery.present
            text: (root.battery.charging ? "Charging — " : "") + root.battery.percent + "% (" + root.battery.status + ")"
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        Text {
            visible: !root.battery.present
            text: "No battery detected (desktop PC)"
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ArchTheme.border }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Notifications"
                font.weight: Font.DemiBold
                color: ArchTheme.textPrimary
                font.family: ArchTheme.fontFamily
            }

            FBtn {
                visible: shellState && shellState.notifCount > 0
                text: "Clear all"
                implicitHeight: 26
                onClicked: if (shellState) shellState.dismissAllNotifs()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            FSwitch {
                id: dndSwitch
                anchors.fill: parent
                text: "Do not disturb"
                checked: shellState ? shellState.dnd : false
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (shellState) shellState.toggleDnd()
            }
        }

        ListView {
            id: historyList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }

            model: shellState && shellState.notifServer
                ? shellState.notifServer.trackedNotifications : null

            Text {
                anchors.centerIn: parent
                width: parent.width - 16
                visible: historyList.count === 0
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                text: shellState && shellState.dnd
                    ? "Do not disturb is on. Toasts are hidden; new alerts still land here."
                    : "No notifications yet."
                color: ArchTheme.textSecondary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
            }

            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                implicitHeight: histInner.implicitHeight + 16
                height: implicitHeight
                radius: ArchTheme.radiusCard
                color: histMa.containsMouse ? ArchTheme.layerHover : ArchTheme.layer
                border.width: 1
                border.color: ArchTheme.border

                MouseArea {
                    id: histMa
                    anchors.fill: parent
                    hoverEnabled: true
                }

                RowLayout {
                    id: histInner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignTop
                        radius: 6
                        color: ArchTheme.pressed
                        clip: true

                        Image {
                            id: histIcon
                            anchors.fill: parent
                            anchors.margins: 2
                            source: shellState ? shellState.notifImage(modelData) : ""
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !histIcon.visible
                            text: Icons.bell
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: 13
                            color: ArchTheme.textSecondary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: (modelData.appName && modelData.appName.length)
                                ? modelData.appName : "System"
                            elide: Text.ElideRight
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: ArchTheme.textTertiary
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.summary || ""
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            font.weight: Font.DemiBold
                            color: ArchTheme.textPrimary
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: (modelData.body || "").length > 0
                            text: modelData.body || ""
                            elide: Text.ElideRight
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            textFormat: Text.StyledText
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: ArchTheme.textSecondary
                        }
                    }

                    FIconBtn {
                        Layout.alignment: Qt.AlignTop
                        glyph: Icons.close
                        glyphSize: 12
                        diameter: 24
                        onClicked: if (shellState) shellState.dismissNotif(modelData)
                    }
                }
            }
        }
    }
}
