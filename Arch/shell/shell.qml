//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Component.onCompleted: {
        Qt.application.font.family = "JetBrainsMono Nerd Font"
        Qt.application.font.pixelSize = 13
    }

    ShellState {
        id: appState
    }

    IpcHandler {
        target: "arch"

        function toggle(name: string): void {
            appState.open(name)
        }

        function open(name: string): void {
            if (appState.openModule !== name)
                appState.open(name)
        }

        function close(): void {
            appState.close()
        }

        function osd(kind: string, value: string, extra: string): void {
            appState.showOsd(kind, value, extra)
        }
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    Variants {
        model: Quickshell.screens
        delegate: Taskbar {
            shellState: appState
        }
    }

    NotificationOverlay {
        shellState: appState
    }

    OsdOverlay {
        shellState: appState
    }
}
