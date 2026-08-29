import QtQuick
import QtQuick.Layouts
import "theme"

Item {
    id: root

    required property var shellState
    required property string zone

    implicitHeight: 34
    implicitWidth: zoneRow.implicitWidth

    readonly property var popupModules: [
        "Start", "AgentCentre", "DynamicMusic", "Audio", "NetworkBluetooth",
        "BatteryNotifications", "ClockWeather", "QuickSettings", "Settings",
        "Clipboard", "Notes", "Calculator", "TaskView", "Wallpaper",
        "SystemUpdates", "GamingMode"
    ]

    // Left-to-right in every zone so the order in Settings matches what you see.
    RowLayout {
        id: zoneRow
        spacing: zone === "left" ? 8 : 3

        Repeater {
            model: shellState ? shellState.zoneModules(zone) : []

            delegate: Loader {
                required property string modelData
                Layout.alignment: Qt.AlignVCenter

                sourceComponent: {
                    switch (modelData) {
                    case "DesktopManager": return desktopComp
                    case "ClockWeather": return clockWeatherComp
                    case "Keyboard": return keyboardComp
                    case "SystemTray": return trayComp
                    case "DynamicMusic": return musicComp
                    case "Audio": return audioComp
                    case "NetworkBluetooth": return networkComp
                    case "BatteryNotifications": return batteryComp
                    default: return defaultComp
                    }
                }

                Component {
                    id: defaultComp
                    BaseModule {
                        moduleId: modelData
                        label: root.shellState ? root.shellState.moduleMeta(modelData).label : modelData
                        icon: ""
                        shellState: root.shellState
                        hasPopup: root.popupModules.indexOf(modelData) >= 0
                    }
                }

                Component { id: desktopComp; DesktopManagerBar { shellState: root.shellState } }
                Component { id: clockWeatherComp; ClockWeatherBar { shellState: root.shellState } }
                Component { id: keyboardComp; KeyboardBar { shellState: root.shellState } }
                Component { id: trayComp; SystemTrayBar { } }
                Component { id: musicComp; MusicBar { shellState: root.shellState } }
                Component { id: audioComp; AudioBar { shellState: root.shellState } }
                Component { id: networkComp; NetworkBar { shellState: root.shellState } }
                Component { id: batteryComp; BatteryBar { shellState: root.shellState } }
            }
        }
    }
}
