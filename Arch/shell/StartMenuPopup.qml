import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

FocusScope {
    id: root
    focus: true

    required property var shellState
    property var stats: ({})

    implicitWidth: parent ? parent.width - 24 : 900
    implicitHeight: 500

    property int selectedIndex: 0

    readonly property var commonAppNames: [
        "Firefox", "Kitty", "Nemo", "Cursor", "Telegram Desktop", "Spotify",
        "Visual Studio Code", "Steam", "Discord", "Thunderbird", "LibreOffice Writer"
    ]

    property var filteredApps: sortApps(shellState.allApps || [], shellState.searchQuery)

    property var selectedApp: filteredApps.length > 0
        ? filteredApps[Math.max(0, Math.min(selectedIndex, filteredApps.length - 1))]
        : null

    function sortApps(apps, query) {
        const q = (query || "").trim().toLowerCase()
        if (!q) return commonAppsFirst(apps)
        const matched = apps.filter(a => a.name.toLowerCase().includes(q))
        matched.sort((a, b) => {
            const an = a.name.toLowerCase()
            const bn = b.name.toLowerCase()
            const aExact = an === q
            const bExact = bn === q
            if (aExact && !bExact) return -1
            if (!aExact && bExact) return 1
            const aStart = an.startsWith(q)
            const bStart = bn.startsWith(q)
            if (aStart && !bStart) return -1
            if (!aStart && bStart) return 1
            const ai = an.indexOf(q)
            const bi = bn.indexOf(q)
            if (ai !== bi) return ai - bi
            return an.localeCompare(bn)
        })
        return matched
    }

    function commonAppsFirst(apps) {
        const picked = []
        const used = {}
        for (let i = 0; i < commonAppNames.length; i++) {
            const name = commonAppNames[i]
            for (let j = 0; j < apps.length; j++) {
                if (apps[j].name === name && !used[name]) {
                    picked.push(apps[j])
                    used[name] = true
                    break
                }
            }
        }
        for (let k = 0; k < apps.length && picked.length < 20; k++) {
            if (!used[apps[k].name]) {
                picked.push(apps[k])
                used[apps[k].name] = true
            }
        }
        return picked
    }

    function focusSearch() {
        searchField.forceActiveFocus()
        if (searchField.text.length > 0)
            searchField.selectAll()
    }

    Timer {
        id: focusRetry
        interval: 80
        repeat: true
        running: true
        property int attempts: 0
        onTriggered: {
            attempts += 1
            if (searchField.activeFocus || attempts > 15)
                stop()
            else
                focusSearch()
        }
    }

    function formatRate(kbs) {
        const n = Number(kbs) || 0
        if (n >= 1024)
            return (n / 1024).toFixed(1) + " MB/s"
        return n + " KB/s"
    }

    function desktopDir(app) {
        if (!app || !app.desktop) return ""
        const parts = app.desktop.split("/")
        parts.pop()
        return parts.join("/")
    }

    function launchApp(app) {
        if (!app || !app.exec) return
        Quickshell.execDetached(["bash", "-c", app.exec + " &"])
        shellState.close()
    }

    function openInFiles(app) {
        const dir = desktopDir(app)
        if (!dir) return
        Quickshell.execDetached([
            "bash", "-lc",
            "dir=" + JSON.stringify(dir)
            + '; if command -v nemo >/dev/null; then nemo "$dir"'
            + '; elif command -v nautilus >/dev/null; then nautilus "$dir"'
            + '; else xdg-open "$dir"; fi'
        ])
    }

    function openInTerminal(app) {
        const dir = desktopDir(app)
        if (!dir) return
        Quickshell.execDetached(["kitty", "--directory", dir])
    }

    onFilteredAppsChanged: selectedIndex = Math.min(selectedIndex, Math.max(0, filteredApps.length - 1))

    Connections {
        target: shellState
        function onSearchQueryChanged() {
            root.selectedIndex = 0
        }
        function onAllAppsChanged() {
            root.selectedIndex = 0
        }
    }

    Process {
        id: statsProc
        running: true
        command: ["bash", shellState.scriptsPath + "/sys_stats.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.stats = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: statsProc.running = true
    }

    Component.onCompleted: focusSearch()

    Keys.onEscapePressed: {
        shellState.close()
        event.accepted = true
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down) {
            selectedIndex = Math.min(selectedIndex + 1, filteredApps.length - 1)
            appList.positionViewAtIndex(selectedIndex, ListView.Contain)
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            selectedIndex = Math.max(selectedIndex - 1, 0)
            appList.positionViewAtIndex(selectedIndex, ListView.Contain)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (selectedApp) launchApp(selectedApp)
            event.accepted = true
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // Left — search + scrollable app list
        FCard {
            Layout.fillHeight: true
            Layout.preferredWidth: 320
            radius: ArchTheme.radiusLarge

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                FField {
                    id: searchField
                    Layout.fillWidth: true
                    pill: true
                    placeholderText: "Type here to search"
                    focus: true
                    activeFocusOnPress: true
                    leftPadding: 36
                    Keys.onEscapePressed: {
                        shellState.close()
                        event.accepted = true
                    }
                    onTextChanged: shellState.searchQuery = text

                    Text {
                        x: 13
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.search
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: 14
                        color: searchField.activeFocus ? ArchTheme.accent : ArchTheme.textTertiary
                    }
                }

                Text {
                    visible: !shellState.searchQuery
                    text: "Suggested"
                    color: ArchTheme.textSecondary
                    font.pixelSize: ArchTheme.sizeSmall
                    font.family: ArchTheme.fontFamily
                }

                ListView {
                    id: appList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    model: root.filteredApps
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: FScroll { }

                    onCurrentIndexChanged: root.selectedIndex = currentIndex

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: appList.width
                        height: 38
                        radius: ArchTheme.radius
                        color: root.selectedIndex === index ? ArchTheme.accentMuted
                             : (appMa.containsMouse ? ArchTheme.layerHover : "transparent")
                        border.color: "transparent"
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            Rectangle {
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: ArchTheme.radiusSmall
                                color: ArchTheme.accentMuted
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name.charAt(0).toUpperCase()
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    font.weight: Font.DemiBold
                                    color: ArchTheme.accent
                                }
                            }
                            Text {
                                text: modelData.name
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: ArchTheme.textPrimary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                            }
                        }

                        MouseArea {
                            id: appMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.selectedIndex = index
                                appList.currentIndex = index
                            }
                        }
                    }
                }
            }
        }

        // Middle — app info, actions, system stats, power
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 300
            spacing: 8

            Text {
                text: root.selectedApp ? root.selectedApp.name : "Select an app"
                font.pixelSize: ArchTheme.sizeTitle
                font.weight: Font.DemiBold
                color: ArchTheme.textPrimary
                font.family: ArchTheme.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                maximumLineCount: 4
                elide: Text.ElideRight
                text: root.selectedApp
                    ? (root.selectedApp.comment || root.selectedApp.exec || "No description")
                    : "Click an app in the list to see details and actions."
                color: ArchTheme.textSecondary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: root.selectedApp !== null

                FBtn {
                    text: "Open"
                    Layout.fillWidth: true
                    font.family: ArchTheme.fontFamily
                    highlighted: true
                    onClicked: launchApp(root.selectedApp)
                }
                FBtn {
                    text: "Open location in file browser"
                    Layout.fillWidth: true
                    font.family: ArchTheme.fontFamily
                    enabled: root.selectedApp && root.selectedApp.desktop
                    onClicked: openInFiles(root.selectedApp)
                }
                FBtn {
                    text: "Open location in terminal"
                    Layout.fillWidth: true
                    font.family: ArchTheme.fontFamily
                    enabled: root.selectedApp && root.selectedApp.desktop
                    onClicked: openInTerminal(root.selectedApp)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: ArchTheme.border }

            Text {
                text: "System"
                font.weight: Font.DemiBold
                color: ArchTheme.textPrimary
                font.family: ArchTheme.fontFamily
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "CPU"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
                Item { Layout.fillWidth: true }
                Text { text: (root.stats.cpu || 0) + "%"; color: ArchTheme.textPrimary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Memory"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
                Item { Layout.fillWidth: true }
                Text { text: (root.stats.mem || 0) + "%"; color: ArchTheme.textPrimary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Disk"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
                Item { Layout.fillWidth: true }
                Text { text: (root.stats.disk || 0) + "%"; color: ArchTheme.textPrimary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Download"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
                Item { Layout.fillWidth: true }
                Text { text: formatRate(root.stats.downKbs); color: ArchTheme.textPrimary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Upload"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
                Item { Layout.fillWidth: true }
                Text { text: formatRate(root.stats.upKbs); color: ArchTheme.textPrimary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeSmall }
            }

            Item { Layout.fillHeight: true }

            GridLayout {
                columns: 2
                columnSpacing: 6
                rowSpacing: 6
                Layout.fillWidth: true
                FBtn { text: Icons.sleep + "  Sleep"; Layout.fillWidth: true; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
                FBtn { text: Icons.restart + "  Restart"; Layout.fillWidth: true; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                FBtn { text: Icons.power + "  Shutdown"; Layout.fillWidth: true; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
                FBtn { text: Icons.logout + "  Logout"; Layout.fillWidth: true; onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "exit"]) }
            }
        }

        // Right — modules
        FCard {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            radius: ArchTheme.radiusLarge

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                Text {
                    text: "Modules"
                    font.weight: Font.DemiBold
                    color: ArchTheme.textPrimary
                    font.family: ArchTheme.fontFamily
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    model: shellState.allModules
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: FScroll { }

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view ? ListView.view.width : 0
                        height: 34
                        radius: ArchTheme.radius
                        color: modMa.containsMouse ? ArchTheme.layerHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            Text { text: modelData.icon; color: ArchTheme.accent; font.family: ArchTheme.fontFamily; font.pixelSize: 14 }
                            Text {
                                text: modelData.label
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: ArchTheme.textPrimary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                            }
                        }

                        MouseArea {
                            id: modMa
                            anchors.fill: parent
                            onClicked: {
                                shellState.openModule = null
                                shellState.open(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
