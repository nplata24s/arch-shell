import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import "theme"
import "live"

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: ArchTheme.solid

    property int currentUserIndex: 0
    property bool inputActive: false
    property bool loginFailed: false
    property bool loggingIn: false
    property bool barOnTop: live.barOnTop
    property int barHeight: live.barHeight
    property int barMargin: 6
    property int barSide: 10
    property int barRadius: 8
    property string wallpaperPath: "file:///var/lib/arch-shell/wallpaper"
    property string bundledWallpaper: Qt.resolvedUrl("wallpaper.jpg")

    LiveTheme { id: live }

    readonly property int nameRole: 257
    readonly property int realNameRole: 258
    readonly property int homeRole: 259
    readonly property int iconRole: 260

    readonly property int userCount: userModel.count
    readonly property string currentUserName: userNameAt(currentUserIndex)
    readonly property string currentRealName: {
        const real = userData(currentUserIndex, root.realNameRole)
        if (real && String(real).trim() !== "")
            return String(real)
        return currentUserName
    }
    readonly property string currentIcon: {
        const fromModel = userData(currentUserIndex, root.iconRole)
        if (fromModel && String(fromModel) !== "")
            return String(fromModel)
        if (currentUserName !== "")
            return "file:///usr/share/sddm/faces/" + currentUserName + ".face.icon"
        return ""
    }

    function userData(i, role) {
        if (i < 0 || i >= userModel.count)
            return ""
        return userModel.data(userModel.index(i, 0), role)
    }

    function userNameAt(i) {
        const n = userData(i, root.nameRole)
        return n && String(n) !== "" ? String(n) : "User"
    }

    function nextUser() {
        if (userModel.count <= 1)
            return
        currentUserIndex = (currentUserIndex + 1) % userModel.count
        resetLogin()
    }

    function prevUser() {
        if (userModel.count <= 1)
            return
        currentUserIndex = (currentUserIndex - 1 + userModel.count) % userModel.count
        resetLogin()
    }

    function resetLogin() {
        passwordField.text = ""
        loginFailed = false
        loggingIn = false
        if (inputActive)
            passwordField.forceActiveFocus()
    }

    function submit() {
        if (passwordField.text === "" || loggingIn)
            return
        loggingIn = true
        loginFailed = false
        sddm.login(currentUserName, passwordField.text, sessionMenu.currentIndex)
    }

    Binding { target: ArchTheme; property: "accent"; value: live.accent }
    Binding { target: ArchTheme; property: "mica"; value: live.mica }

    Component.onCompleted: {
        let idx = 0
        if (userModel.lastUser !== "") {
            for (let i = 0; i < userModel.count; ++i) {
                if (userNameAt(i) === userModel.lastUser) {
                    idx = i
                    break
                }
            }
        }
        currentUserIndex = idx
        if (config.accent && String(config.accent) !== "")
            ArchTheme.accent = config.accent
        keySink.forceActiveFocus()
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.loggingIn = false
            root.loginFailed = true
            passwordField.text = ""
            shakeAnim.restart()
            passwordField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            root.loggingIn = false
        }
    }

    // ── Wallpaper ────────────────────────────────────────────────────
    Image {
        id: wall
        anchors.fill: parent
        source: root.wallpaperPath
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
        onStatusChanged: {
            if (status === Image.Error && source !== root.bundledWallpaper)
                source = root.bundledWallpaper
        }
    }

    MultiEffect {
        id: wallFx
        anchors.fill: parent
        source: wall
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 48
        blur: root.inputActive ? 0.22 : 0.0
        brightness: root.inputActive ? -0.02 : 0.0
        Behavior on blur { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        Behavior on brightness { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        anchors.fill: parent
        color: ArchTheme.scrim
        opacity: root.inputActive ? 0.35 : 0.18
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        z: 2
        onClicked: {
            root.inputActive = true
            passwordField.forceActiveFocus()
        }
    }

    // ── Lock clock ───────────────────────────────────────────────────
    Column {
        id: lockClock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.barOnTop ? root.barHeight / 2 : -root.barHeight / 2
        z: 1
        spacing: 4
        opacity: root.inputActive ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(new Date(), "HH:mm")
            font.family: ArchTheme.fontFamily
            font.pixelSize: 92
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeTitle
            color: ArchTheme.textSecondary
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            timeText.text = Qt.formatTime(now, "HH:mm")
            dateText.text = Qt.formatDate(now, "dddd, d MMMM")
            barTime.text = Qt.formatTime(now, "HH:mm")
            barDate.text = Qt.formatDate(now, "ddd d MMM")
        }
    }

    // ── Login card ───────────────────────────────────────────────────
    Item {
        id: loginWrap
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.barOnTop ? (root.barHeight + 8) / 2 : -(root.barHeight + 8) / 2
        z: 3
        width: 380
        height: cardCol.implicitHeight + 48
        opacity: root.inputActive ? 1 : 0
        scale: root.inputActive ? 1 : 0.96
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

        Rectangle {
            id: loginCard
            anchors.fill: parent
            radius: ArchTheme.radiusLarge
            color: ArchTheme.mica
            border.width: 1
            border.color: ArchTheme.border

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                anchors.topMargin: 1
                height: 1
                color: ArchTheme.glassHighlight
                opacity: 0.5
            }
        }

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 14

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 88
                implicitHeight: 88

                Rectangle {
                    id: avatarRing
                    anchors.fill: parent
                    radius: width / 2
                    color: ArchTheme.layer
                    border.width: 2
                    border.color: root.loginFailed ? ArchTheme.danger : ArchTheme.accentLine
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    Text {
                        visible: avatar.status !== Image.Ready
                        anchors.centerIn: parent
                        text: Icons.user
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: 36
                        color: ArchTheme.textSecondary
                    }
                }

                Image {
                    id: avatar
                    anchors.fill: parent
                    anchors.margins: 4
                    source: root.currentIcon
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    asynchronous: true
                    onStatusChanged: {
                        if (status === Image.Error)
                            source = ""
                    }
                }

                Rectangle {
                    id: avatarMask
                    anchors.fill: avatar
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: avatar
                    source: avatar
                    maskEnabled: true
                    maskSource: avatarMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    visible: avatar.status === Image.Ready
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.currentRealName
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeHeading
                font.weight: Font.DemiBold
                color: ArchTheme.textPrimary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: root.userCount > 1

                Item {
                    implicitWidth: 32
                    implicitHeight: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: ArchTheme.radiusCard
                        color: prevMa.containsMouse ? ArchTheme.layerHover : ArchTheme.layer
                        border.width: 1
                        border.color: ArchTheme.border
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.chevronLeft
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: 14
                        color: ArchTheme.textPrimary
                    }
                    MouseArea {
                        id: prevMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.prevUser()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: (root.currentUserIndex + 1) + " / " + root.userCount
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }

                Item { Layout.fillWidth: true }

                Item {
                    implicitWidth: 32
                    implicitHeight: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: ArchTheme.radiusCard
                        color: nextMa.containsMouse ? ArchTheme.layerHover : ArchTheme.layer
                        border.width: 1
                        border.color: ArchTheme.border
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.chevronRight
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: 14
                        color: ArchTheme.textPrimary
                    }
                    MouseArea {
                        id: nextMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextUser()
                    }
                }
            }

            Rectangle {
                id: passBox
                Layout.fillWidth: true
                implicitHeight: 36
                radius: ArchTheme.radiusCard
                color: passwordField.activeFocus ? ArchTheme.layerActive : ArchTheme.layer
                border.width: 1
                border.color: root.loginFailed ? ArchTheme.danger
                             : (passwordField.activeFocus ? ArchTheme.accent : ArchTheme.border)
                transform: Translate { id: shakeTranslate; x: 0 }

                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: shakeTranslate; property: "x"; to: -7; duration: 50 }
                    NumberAnimation { target: shakeTranslate; property: "x"; to: 7; duration: 50 }
                    NumberAnimation { target: shakeTranslate; property: "x"; to: -5; duration: 50 }
                    NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 50 }
                }

                TextInput {
                    id: passwordField
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeBody
                    color: ArchTheme.textPrimary
                    selectionColor: ArchTheme.accentSoft
                    selectedTextColor: ArchTheme.textPrimary
                    clip: true
                    enabled: !root.loggingIn

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        font: passwordField.font
                        color: ArchTheme.textTertiary
                        visible: passwordField.text.length === 0 && !passwordField.inputMethodComposing
                    }

                    Keys.onEscapePressed: root.inputActive = false
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Tab) {
                            root.nextUser()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Backtab) {
                            root.prevUser()
                            event.accepted = true
                        }
                    }
                    onAccepted: root.submit()
                    onTextChanged: {
                        if (root.loginFailed)
                            root.loginFailed = false
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 4
                    height: 2
                    radius: 1
                    visible: passwordField.activeFocus && !root.loginFailed
                    color: ArchTheme.accent
                }
            }

            Text {
                Layout.fillWidth: true
                visible: keyboard.capsLock
                text: "Caps Lock is on"
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: ArchTheme.warning
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                text: root.loginFailed ? "Incorrect password" : (root.loggingIn ? "Signing in…" : " ")
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: root.loginFailed ? ArchTheme.danger : ArchTheme.textTertiary
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 32
                radius: ArchTheme.radiusCard
                color: {
                    if (root.loggingIn) return ArchTheme.accentPressed
                    if (goMa.containsMouse) return ArchTheme.accentHover
                    return ArchTheme.accent
                }
                Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

                Text {
                    anchors.centerIn: parent
                    text: root.loggingIn ? "Signing in" : "Sign in"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textOnAccent
                }

                MouseArea {
                    id: goMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.loggingIn
                    onClicked: root.submit()
                }
            }
        }
    }

    // ── Taskbar ──────────────────────────────────────────────────────
    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.barOnTop ? parent.top : undefined
        anchors.bottom: root.barOnTop ? undefined : parent.bottom
        anchors.leftMargin: root.barSide
        anchors.rightMargin: root.barSide
        anchors.topMargin: root.barOnTop ? root.barMargin : 0
        anchors.bottomMargin: root.barOnTop ? 0 : root.barMargin
        z: 4
        height: root.barHeight
        radius: root.barRadius
        color: ArchTheme.mica
        border.width: 1
        border.color: ArchTheme.border

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: root.barOnTop ? parent.top : undefined
            anchors.bottom: root.barOnTop ? undefined : parent.bottom
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            height: 1
            color: ArchTheme.glassHighlight
            opacity: 0.5
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            ComboBox {
                id: sessionMenu
                Layout.preferredWidth: 168
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignVCenter
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall

                background: Rectangle {
                    radius: ArchTheme.radiusCard
                    color: sessionMenu.pressed ? ArchTheme.pressed
                         : (sessionMenu.hovered ? ArchTheme.layerHover : ArchTheme.layer)
                    border.width: 1
                    border.color: sessionMenu.activeFocus ? ArchTheme.accent : ArchTheme.border
                }

                contentItem: Text {
                    leftPadding: 10
                    rightPadding: 28
                    text: Icons.desktops + "  " + sessionMenu.displayText
                    font: sessionMenu.font
                    color: ArchTheme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: sessionMenu.width - width - 10
                    y: (sessionMenu.height - height) / 2
                    text: Icons.chevronDown
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: 12
                    color: ArchTheme.textSecondary
                }

                delegate: ItemDelegate {
                    id: sessionEntry
                    width: sessionMenu.width
                    height: 32
                    highlighted: sessionMenu.highlightedIndex === index

                    background: Rectangle {
                        radius: ArchTheme.radius
                        color: sessionEntry.highlighted ? ArchTheme.accentMuted
                             : (sessionEntry.hovered ? ArchTheme.layerHover : "transparent")
                    }

                    contentItem: Text {
                        leftPadding: 8
                        text: model.name
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                        color: ArchTheme.textPrimary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                popup: Popup {
                    y: root.barOnTop ? sessionMenu.height + 4 : -(implicitHeight + 4)
                    width: sessionMenu.width
                    implicitHeight: Math.min(listView.contentHeight + 8, 220)
                    padding: 4

                    contentItem: ListView {
                        id: listView
                        clip: true
                        model: sessionMenu.delegateModel
                        currentIndex: sessionMenu.highlightedIndex
                        boundsBehavior: Flickable.StopAtBounds
                    }

                    background: Rectangle {
                        radius: ArchTheme.radiusCard
                        color: ArchTheme.acrylic
                        border.width: 1
                        border.color: ArchTheme.border
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Column {
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                Text {
                    id: barTime
                    anchors.right: parent.right
                    text: Qt.formatTime(new Date(), "HH:mm")
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textPrimary
                    horizontalAlignment: Text.AlignRight
                }

                Text {
                    id: barDate
                    anchors.right: parent.right
                    text: Qt.formatDate(new Date(), "ddd d MMM")
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                    horizontalAlignment: Text.AlignRight
                }
            }

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                PowerBtn {
                    glyph: Icons.sleep
                    enabled: sddm.canSuspend
                    onClicked: if (sddm.canSuspend) sddm.suspend()
                }
                PowerBtn {
                    glyph: Icons.restart
                    enabled: sddm.canReboot
                    onClicked: if (sddm.canReboot) sddm.reboot()
                }
                PowerBtn {
                    glyph: Icons.power
                    danger: true
                    enabled: sddm.canPowerOff
                    onClicked: if (sddm.canPowerOff) sddm.powerOff()
                }
            }
        }
    }

    component PowerBtn: Item {
        id: pbtn
        property string glyph: ""
        property bool danger: false
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        opacity: enabled ? 1 : 0.45

        Rectangle {
            anchors.fill: parent
            radius: ArchTheme.radiusCard
            color: pma.containsMouse ? (pbtn.danger ? ArchTheme.dangerMuted : ArchTheme.layerHover)
                                     : ArchTheme.layer
            border.width: 1
            border.color: pma.containsMouse && pbtn.danger ? ArchTheme.dangerLine : ArchTheme.border
        }

        Text {
            anchors.centerIn: parent
            text: pbtn.glyph
            font.family: ArchTheme.fontFamily
            font.pixelSize: 15
            color: pma.containsMouse && pbtn.danger ? ArchTheme.danger : ArchTheme.textPrimary
        }

        MouseArea {
            id: pma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pbtn.clicked()
        }
    }

    Item {
        id: keySink
        focus: !root.inputActive
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.inputActive = false
                event.accepted = true
                return
            }
            root.inputActive = true
            passwordField.forceActiveFocus()
            event.accepted = false
        }
    }

    onInputActiveChanged: {
        if (inputActive)
            passwordField.forceActiveFocus()
        else {
            resetLogin()
            keySink.forceActiveFocus()
        }
    }
}
