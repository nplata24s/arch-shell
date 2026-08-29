import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "theme"

// Clock, calendar and weather in a single flyout.
Item {
    id: root
    required property var shellState

    implicitWidth: 560
    implicitHeight: 420

    property var weather: ({ city: "", temp: null, description: "", code: 0, daily: [] })
    property string timeText: ""
    property string dateText: ""
    property date shownMonth: new Date()

    readonly property string unit: {
        const _ = shellState ? shellState.settingsRev : 0
        return shellState && shellState.settings.weather
            ? (shellState.settings.weather.unit || "celsius") : "celsius"
    }
    readonly property string unitSuffix: unit === "fahrenheit" ? "°F" : "°C"

    // ── Calendar maths (Monday-first grid) ───────────────────────────
    readonly property var monthCells: buildMonth(shownMonth)

    function buildMonth(ref) {
        const year = ref.getFullYear()
        const month = ref.getMonth()
        const first = new Date(year, month, 1)
        // JS: 0=Sunday. Shift so Monday is column 0.
        const lead = (first.getDay() + 6) % 7
        const daysInMonth = new Date(year, month + 1, 0).getDate()
        const today = new Date()
        const cells = []
        for (let i = 0; i < 42; i++) {
            const dayNum = i - lead + 1
            const inMonth = dayNum >= 1 && dayNum <= daysInMonth
            const isToday = inMonth
                && dayNum === today.getDate()
                && month === today.getMonth()
                && year === today.getFullYear()
            cells.push({
                label: inMonth ? String(dayNum) : "",
                inMonth: inMonth,
                today: isToday
            })
        }
        return cells
    }

    function shiftMonth(delta) {
        const d = new Date(shownMonth)
        d.setDate(1)
        d.setMonth(d.getMonth() + delta)
        shownMonth = d
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            root.timeText = Qt.formatTime(now, "HH:mm:ss")
            root.dateText = Qt.formatDate(now, "dddd, d MMMM yyyy")
        }
    }

    Process {
        id: fetchProc
        command: ["bash", shellState.scriptsPath + "/weather_state.sh", root.unit]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.weather = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Component.onCompleted: fetchProc.running = true
    onUnitChanged: fetchProc.running = true

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // ── Left: time + calendar ────────────────────────────────────
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 300
            spacing: 10

            Text {
                text: root.timeText
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeDisplay
                font.weight: Font.Light
                color: ArchTheme.textPrimary
            }

            Text {
                text: root.dateText
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
                color: ArchTheme.textSecondary
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            FCard {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: Qt.formatDate(root.shownMonth, "MMMM yyyy")
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            font.weight: Font.DemiBold
                            color: ArchTheme.textPrimary
                        }
                        FIconBtn {
                            glyph: Icons.chevronLeft
                            diameter: 24
                            glyphSize: 12
                            onClicked: root.shiftMonth(-1)
                        }
                        FIconBtn {
                            glyph: Icons.chevronRight
                            diameter: 24
                            glyphSize: 12
                            onClicked: root.shiftMonth(1)
                        }
                    }

                    // Weekday headers
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 7
                        columnSpacing: 0
                        rowSpacing: 2

                        Repeater {
                            model: ["M", "T", "W", "T", "F", "S", "S"]
                            delegate: Text {
                                required property string modelData
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textTertiary
                            }
                        }

                        Repeater {
                            model: root.monthCells
                            delegate: Item {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: modelData.today ? ArchTheme.accent : "transparent"
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    font.weight: modelData.today ? Font.DemiBold : Font.Normal
                                    color: modelData.today ? ArchTheme.textOnAccent
                                         : modelData.inMonth ? ArchTheme.textPrimary
                                         : ArchTheme.textDisabled
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Right: weather ──────────────────────────────────────────
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 236
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.weather.city || "Locating…"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    font.weight: Font.DemiBold
                    color: ArchTheme.textPrimary
                    elide: Text.ElideRight
                }
                FIconBtn {
                    glyph: Icons.refresh
                    diameter: 26
                    glyphSize: 12
                    onClicked: fetchProc.running = true
                }
            }

            FCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 104

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    WeatherGlyph {
                        code: root.weather.code || 0
                        font.pixelSize: 42
                        color: ArchTheme.accent
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: root.weather.temp === null || root.weather.temp === undefined
                                ? "—" : Math.round(root.weather.temp) + root.unitSuffix
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.Light
                            color: ArchTheme.textPrimary
                        }
                        Text {
                            text: root.weather.description || ""
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            color: ArchTheme.textSecondary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: root.weather.humidity !== undefined
                            text: "Humidity " + (root.weather.humidity || 0) + "%   Wind "
                                  + Math.round(root.weather.wind || 0)
                                  + (root.unit === "fahrenheit" ? " mph" : " km/h")
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: ArchTheme.textTertiary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Text {
                text: "Next few days"
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: ArchTheme.textTertiary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.weather.daily || []

                    delegate: FCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: modelData.day || ""
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                                color: ArchTheme.textPrimary
                                Layout.preferredWidth: 44
                            }
                            WeatherGlyph {
                                code: modelData.code || 0
                                font.pixelSize: 15
                                color: ArchTheme.textSecondary
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(modelData.max) + "°"
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                                color: ArchTheme.textPrimary
                            }
                            Text {
                                text: Math.round(modelData.min) + "°"
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                                color: ArchTheme.textTertiary
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        { label: "°C", value: "celsius" },
                        { label: "°F", value: "fahrenheit" }
                    ]
                    delegate: FBtn {
                        required property var modelData
                        text: modelData.label
                        Layout.fillWidth: true
                        highlighted: root.unit === modelData.value
                        onClicked: shellState.setWeatherUnit(modelData.value)
                    }
                }
            }
        }
    }
}
