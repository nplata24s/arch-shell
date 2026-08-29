import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "theme"

// Toast stack lives in this window with its own ListModel. A ListModel on
// ShellState does not reliably update a Repeater in another PanelWindow,
// which is why history (same process, trackedNotifications) worked and
// these popups did not. No remap-on-resize: that unmapped the layer every
// time height changed, so the toast never stayed on screen.
PanelWindow {
    id: root

    required property var shellState

    screen: Quickshell.screens.length ? Quickshell.screens[0] : null
    visible: localToasts.count > 0
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    focusable: false
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "arch-shell-notif"

    readonly property bool barOnTop: {
        const _ = shellState ? shellState.settingsRev : 0
        const t = shellState && shellState.settings.taskbar
            ? shellState.settings.taskbar : {}
        return (t.position || "top") !== "bottom"
    }

    readonly property int barReserve: {
        const _ = shellState ? shellState.settingsRev : 0
        const t = shellState && shellState.settings.taskbar
            ? shellState.settings.taskbar : {}
        const h = t.height || 48
        const m = (t.margins && t.margins.top !== undefined) ? t.margins.top : 6
        return h + m
    }

    anchors {
        top: true
        right: true
    }

    margins {
        top: (barOnTop ? barReserve : 0) + 12
        right: 12
    }

    implicitWidth: 372
    implicitHeight: Math.max(toastColumn.implicitHeight, 1)

    ListModel {
        id: localToasts
    }

    Connections {
        target: shellState
        function onToastPushed(uid, appName, summary, body, urgency, actionsJson, expireMs) {
            localToasts.insert(0, {
                uid: uid,
                appName: appName,
                summary: summary,
                body: body,
                urgency: urgency,
                actionsJson: actionsJson,
                expireMs: expireMs
            })
            while (localToasts.count > 4)
                localToasts.remove(localToasts.count - 1)
        }
        function onToastPopped(uid) {
            for (let i = 0; i < localToasts.count; i++) {
                if (localToasts.get(i).uid === uid) {
                    localToasts.remove(i)
                    break
                }
            }
        }
        function onToastsCleared() {
            localToasts.clear()
        }
    }

    Column {
        id: toastColumn
        width: 372
        spacing: 8

        Repeater {
            model: localToasts

            delegate: Rectangle {
                id: card
                required property var uid
                required property string appName
                required property string summary
                required property string body
                required property var urgency
                required property string actionsJson
                required property var expireMs

                width: toastColumn.width
                implicitHeight: inner.implicitHeight + 24
                height: implicitHeight
                radius: ArchTheme.radiusLarge
                color: ArchTheme.mica
                border.width: 1
                border.color: isCritical ? ArchTheme.dangerLine : ArchTheme.border
                clip: true

                readonly property bool isCritical: Number(urgency) === NotificationUrgency.Critical
                readonly property var actionList: {
                    try { return actionsJson ? JSON.parse(actionsJson) : [] }
                    catch (e) { return [] }
                }
                property var sourceNotif: shellState ? shellState.notifByUid(uid) : null

                opacity: 0
                transform: Translate { id: slide; x: 24 }

                Component.onCompleted: {
                    appear.start()
                }

                ParallelAnimation {
                    id: appear
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slide; property: "x"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                }

                Connections {
                    target: card.sourceNotif
                    function onClosed(reason) {
                        if (shellState)
                            shellState.hideToast(uid)
                    }
                }

                Timer {
                    interval: Math.max(1, Number(expireMs) || 5000)
                    running: Number(expireMs) > 0
                    repeat: false
                    onTriggered: {
                        if (shellState)
                            shellState.hideToast(uid)
                    }
                }

                Rectangle {
                    visible: card.isCritical
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    color: ArchTheme.danger
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: parent.radius
                    anchors.rightMargin: parent.radius
                    anchors.topMargin: 1
                    height: 1
                    color: ArchTheme.glassHighlight
                    opacity: 0.5
                }

                ColumnLayout {
                    id: inner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    anchors.leftMargin: card.isCritical ? 16 : 12
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignTop
                            radius: 6
                            color: ArchTheme.layer
                            clip: true

                            Image {
                                id: iconImg
                                anchors.fill: parent
                                anchors.margins: 2
                                source: shellState ? shellState.notifImage(card.sourceNotif) : ""
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !iconImg.visible
                                text: Icons.bell
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: 15
                                color: ArchTheme.textSecondary
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: appName || "System"
                                elide: Text.ElideRight
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textTertiary
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (summary || "").length > 0
                                text: summary || ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeBody
                                font.weight: Font.DemiBold
                                color: ArchTheme.textPrimary
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (body || "").length > 0
                                text: body || ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                                color: ArchTheme.textSecondary
                            }
                        }

                        FIconBtn {
                            Layout.alignment: Qt.AlignTop
                            glyph: Icons.close
                            glyphSize: 13
                            diameter: 26
                            onClicked: {
                                if (shellState)
                                    shellState.dismissToast(uid)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: card.actionList.length > 0 ? 4 : 0
                        spacing: 6
                        visible: card.actionList.length > 0

                        Repeater {
                            model: card.actionList

                            FBtn {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                text: modelData.text || "Action"
                                highlighted: index === 0
                                onClicked: {
                                    if (shellState)
                                        shellState.invokeToastAction(uid, modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
