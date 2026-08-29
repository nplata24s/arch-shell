import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "theme"

PanelWindow {
    id: root

    required property var shellState
    required property var barScreen
    required property bool barOnTop
    required property int barTotalHeight
    required property int marginSide
    property color barColor: ArchTheme.mica

    screen: root.barScreen
    visible: (shellState ? shellState.openModule !== null : false) && !resizing
    focusable: visible
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "arch-shell-popup"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    property bool dropUp: !barOnTop
    property string moduleId: shellState ? (shellState.openModule || "") : ""
    property bool isStart: moduleId === "Start"

    readonly property var rightModules: [
        "Settings", "ClockWeather", "Audio", "NetworkBluetooth",
        "BatteryNotifications", "QuickSettings", "Keyboard", "Clipboard", "Notes",
        "Calculator", "SystemUpdates", "Wallpaper"
    ]
    readonly property var centerModules: ["DynamicMusic", "TaskView", "GamingMode", "KeybindHelp"]

    property bool anchorRight: rightModules.indexOf(moduleId) >= 0
    property bool isCenter: centerModules.indexOf(moduleId) >= 0
    property int popupWidth: widthForModule(moduleId)
    property int popupHeight: {
        const cap = (barScreen && barScreen.height)
            ? (barScreen.height - barTotalHeight - 16) : 640
        return Math.min(heightForModule(moduleId), cap)
    }
    property int overlap: 2
    property int farRadius: ArchTheme.radiusLarge
    property real screenW: barScreen ? barScreen.width : 1920

    // Square where the flyout meets the bar, rounded on the free edge.
    property int joinTL: dropUp ? farRadius : 0
    property int joinTR: dropUp ? farRadius : 0
    property int joinBL: dropUp ? 0 : farRadius
    property int joinBR: dropUp ? 0 : farRadius

    // Hyprland works out a layer's blur region when the surface is mapped and
    // does not redo it when the surface is resized in place. A flyout that
    // changes size while it is open therefore keeps a stale rectangle of blur:
    // that is the hard horizontal seam across the background and the square
    // corners sitting outside the rounded ones. Sizes come from a table rather
    // than from the loaded content so the surface is right from the first
    // frame, and any remaining size change unmaps the surface for a tick so it
    // is recreated rather than resized.
    property bool resizing: false
    property string surfaceSize: popupWidth + "x" + popupHeight

    onSurfaceSizeChanged: {
        if (shellState && shellState.openModule)
            resizing = true
    }

    Timer {
        id: remapTimer
        interval: 1
        running: root.resizing
        onTriggered: root.resizing = false
    }

    anchors {
        top: !dropUp
        bottom: dropUp
        left: !anchorRight
        right: anchorRight || isCenter
    }

    margins {
        top: dropUp ? 0 : Math.max(0, barTotalHeight - overlap)
        bottom: dropUp ? Math.max(0, barTotalHeight - overlap) : 0
        left: leftMargin()
        right: rightMargin()
    }

    implicitWidth: popupWidth
    implicitHeight: popupHeight

    Rectangle {
        id: popupPanel
        anchors.fill: parent

        topLeftRadius: joinTL
        topRightRadius: joinTR
        bottomLeftRadius: joinBL
        bottomRightRadius: joinBR

        color: root.barColor
        border.color: ArchTheme.border
        border.width: 1

        // Hyprland layer fade is off (no_anim). Slide the pane in QML so
        // drop-ups still move without Hyprland stretching the blur sample.
        opacity: 0
        transform: Translate { id: slide; y: root.dropUp ? 28 : -28 }

        ParallelAnimation {
            id: inAnim
            NumberAnimation {
                target: popupPanel
                property: "opacity"
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: slide
                property: "y"
                to: 0
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        function playIn() {
            if (root.resizing)
                return
            inAnim.stop()
            popupPanel.opacity = 0
            slide.y = root.dropUp ? 28 : -28
            inAnim.start()
        }

        Connections {
            target: root
            function onVisibleChanged() {
                if (root.visible)
                    popupPanel.playIn()
            }
        }

        Component.onCompleted: {
            if (root.visible)
                playIn()
        }

        // Hide the border line where the flyout meets the taskbar.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            y: dropUp ? parent.height - height : 0
            height: 3
            color: popupPanel.color
        }

        Shortcut {
            sequence: "Escape"
            enabled: root.visible
            onActivated: if (shellState) shellState.close()
        }

        Loader {
            id: popupLoader
            anchors.fill: parent
            anchors.margins: 14
            // Tied to the open module, not to `visible`: the surface blips
            // invisible on resize and unloading here would feed that back into
            // the height and loop.
            active: shellState ? shellState.openModule !== null : false
            sourceComponent: popupComponentFor(moduleId)

            onLoaded: {
                if (item && item.focusSearch)
                    Qt.callLater(item.focusSearch)
            }

            Component { id: startComp; StartMenuPopup { shellState: root.shellState } }
            Component { id: settingsComp; SettingsPopup { shellState: root.shellState } }
            Component { id: keybindComp; KeybindHelpPopup { shellState: root.shellState } }
            Component { id: audioComp; AudioPopup { shellState: root.shellState } }
            Component { id: networkComp; NetworkPopup { shellState: root.shellState } }
            Component { id: musicComp; MusicPopup { shellState: root.shellState } }
            Component { id: batteryComp; BatteryPopup { shellState: root.shellState } }
            Component { id: clockWeatherComp; ClockWeatherPopup { shellState: root.shellState } }
            Component { id: quickComp; QuickSettingsPopup { shellState: root.shellState } }
            Component { id: clipComp; ClipboardPopup { shellState: root.shellState } }
            Component { id: notesComp; NotesPopup { shellState: root.shellState } }
            Component { id: calcComp; CalculatorPopup { shellState: root.shellState } }
            Component { id: gameComp; GamingPopup { shellState: root.shellState } }
            Component { id: wallComp; WallpaperPopup { shellState: root.shellState } }
            Component { id: updComp; UpdatesPopup { shellState: root.shellState } }
            Component { id: taskComp; TaskViewPopup { shellState: root.shellState } }
            Component { id: agentComp; AgentCentrePopup { shellState: root.shellState } }

            Component {
                id: genericComp
                Column {
                    spacing: 8
                    width: root.popupWidth - 28

                    Text {
                        text: root.titleFor(root.moduleId)
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeTitle
                        font.weight: Font.DemiBold
                        color: ArchTheme.textPrimary
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: root.bodyFor(root.moduleId)
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                        color: ArchTheme.textSecondary
                    }

                    FBtn {
                        text: "Close (Esc)"
                        onClicked: shellState.close()
                    }
                }
            }
        }
    }

    Connections {
        target: shellState
        function onOpenModuleChanged() {
            if (shellState && shellState.openModule)
                focusGrabTimer.restart()
        }
    }

    Timer {
        id: focusGrabTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (popupLoader.item && popupLoader.item.focusSearch)
                popupLoader.item.focusSearch()
        }
    }

    function leftMargin() {
        if (anchorRight)
            return 0
        if (isCenter)
            return Math.max(marginSide, Math.round((screenW - popupWidth) / 2))
        return marginSide
    }

    function rightMargin() {
        if (isCenter)
            return Math.max(marginSide, Math.round((screenW - popupWidth) / 2))
        if (anchorRight)
            return marginSide
        return 0
    }

    function popupComponentFor(id) {
        if (!id) return null
        switch (id) {
        case "Start": return startComp
        case "Settings": return settingsComp
        case "KeybindHelp": return keybindComp
        case "Audio": return audioComp
        case "NetworkBluetooth": return networkComp
        case "DynamicMusic": return musicComp
        case "BatteryNotifications": return batteryComp
        case "ClockWeather": return clockWeatherComp
        case "QuickSettings": return quickComp
        case "Clipboard": return clipComp
        case "Notes": return notesComp
        case "Calculator": return calcComp
        case "GamingMode": return gameComp
        case "Wallpaper": return wallComp
        case "SystemUpdates": return updComp
        case "TaskView": return taskComp
        case "AgentCentre": return agentComp
        default: return genericComp
        }
    }

    function widthForModule(id) {
        switch (id) {
        case "Start": return 920
        case "AgentCentre": return 920
        case "ClockWeather": return 590
        case "Settings": return 620
        case "DynamicMusic": return 470
        case "NetworkBluetooth": return 410
        case "Audio": return 410
        case "BatteryNotifications": return 350
        case "QuickSettings": return 400
        case "Clipboard": return 450
        case "Notes": return 450
        case "Calculator": return 370
        case "GamingMode": return 390
        case "Wallpaper": return 430
        case "SystemUpdates": return 430
        case "TaskView": return 450
        default: return 370
        }
    }

    // Mirrors the implicitHeight of each popup component, plus the 28px of
    // panel padding. Keep the two in step when a popup's height changes.
    function heightForModule(id) {
        switch (id) {
        case "Start": return 528
        case "AgentCentre": return 668
        case "Settings": return 548
        case "QuickSettings": return 508
        case "ClockWeather": return 448
        case "Audio": return 448
        case "NetworkBluetooth": return 468
        case "Clipboard": return 448
        case "TaskView": return 428
        case "Wallpaper": return 428
        case "DynamicMusic": return 488
        case "KeybindHelp": return 408
        case "Notes": return 388
        case "SystemUpdates": return 388
        case "Calculator": return 308
        case "BatteryNotifications": return 448
        case "GamingMode": return 228
        default: return 248
        }
    }

    // MusicPopup grows when its equaliser is expanded.
    readonly property bool musicTall:
        popupLoader.item && popupLoader.item.showEq !== undefined
            ? popupLoader.item.showEq : false

    function titleFor(id) {
        if (id === "Keyboard") return "Keyboard layouts"
        return id
    }

    function bodyFor(id) {
        if (id === "Keyboard") return "Click the layout code on the taskbar to cycle layouts."
        return "Coming in a future sprint."
    }
}
