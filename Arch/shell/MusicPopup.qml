import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState

    implicitWidth: 460
    implicitHeight: 460

    readonly property var player: shellState ? shellState.mprisPlayer : null
    property bool userSeeking: false
    property real livePosition: 0

    property string eqPreset: "Flat"
    property var eqGains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    readonly property var eqBands: ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property var eqPresets: ["Flat", "Bass", "Treble", "Vocal", "Rock", "Classic"]

    property bool showEq: true

    readonly property real lengthSec: player ? asSeconds(player.length) : 0
    readonly property real percent: lengthSec > 0
        ? Math.min(100, (livePosition / lengthSec) * 100) : 0

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0)
            return "0:00"
        const s = Math.floor(sec)
        const m = Math.floor(s / 60)
        const r = s % 60
        return m + ":" + String(r).padStart(2, "0")
    }

    function asSeconds(val) {
        if (!isFinite(val) || val <= 0)
            return 0
        // MPRIS reports microseconds; Quickshell sometimes hands back seconds.
        if (val > 10000)
            return val / 1000000
        return val
    }

    function applyPreset(name) {
        eqPreset = name
        eqProcSet.command = ["bash", shellState.scriptsPath + "/eq.sh", "set", name]
        eqProcSet.running = true
    }

    function pushGains() {
        const args = ["bash", shellState.scriptsPath + "/eq.sh", "set-gains"]
        for (let i = 0; i < 10; i++)
            args.push(String(Math.round(eqGains[i])))
        eqPreset = "Custom"
        eqProcSet.command = args
        eqProcSet.running = true
    }

    function setBand(index, value) {
        const next = eqGains.slice()
        next[index] = value
        eqGains = next
    }

    Timer {
        interval: 500
        running: root.player !== null
        repeat: true
        onTriggered: {
            if (!root.userSeeking && root.player)
                root.livePosition = root.asSeconds(root.player.position)
        }
    }

    Connections {
        target: root.player
        function onPositionChanged() {
            if (!root.userSeeking)
                root.livePosition = root.asSeconds(root.player.position)
        }
        function onTrackChanged() { root.livePosition = 0 }
    }

    Process {
        id: eqProcGet
        command: ["bash", shellState.scriptsPath + "/eq.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.eqPreset = d.preset || "Flat"
                    if (d.gains && d.gains.length === 10)
                        root.eqGains = d.gains
                } catch (e) { }
            }
        }
    }

    Process {
        id: eqProcSet
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.eqPreset = d.preset || root.eqPreset
                    if (d.gains && d.gains.length === 10)
                        root.eqGains = d.gains
                } catch (e) { }
            }
        }
    }

    Component.onCompleted: eqProcGet.running = true

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // ── Now playing ─────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 108
            Layout.maximumHeight: 108
            spacing: 14

            // Album cover
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 104
                Layout.preferredHeight: 104
                radius: ArchTheme.radiusCard
                color: ArchTheme.layer
                border.width: 1
                border.color: ArchTheme.border
                clip: true

                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.player ? (root.player.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: status === Image.Ready
                }

                // Placeholder while there is no art
                Text {
                    anchors.centerIn: parent
                    visible: cover.status !== Image.Ready
                    text: Icons.album
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: 40
                    color: ArchTheme.textTertiary
                }

                // Subtle sheen so the cover sits in the glass
                Rectangle {
                    anchors.fill: parent
                    radius: ArchTheme.radiusCard
                    color: "transparent"
                    border.width: 1
                    border.color: ArchTheme.glassHighlight
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: root.player && root.player.trackTitle
                        ? root.player.trackTitle : "Nothing playing"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeTitle
                    font.weight: Font.DemiBold
                    color: ArchTheme.textPrimary
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackArtist || "Unknown artist") : ""
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textSecondary
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.player
                        ? (root.player.trackAlbum || root.player.identity || "")
                        : "Start a track in Spotify, a browser or any media player."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }

                Item { Layout.fillHeight: true }

                // Transport
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    FIconBtn {
                        glyph: Icons.previous
                        circular: true
                        diameter: 32
                        enabled: root.player && root.player.canGoPrevious
                        onClicked: if (root.player) root.player.previous()
                    }
                    FIconBtn {
                        glyph: root.player && root.player.isPlaying ? Icons.pause : Icons.play
                        circular: true
                        diameter: 38
                        glyphSize: 17
                        highlighted: true
                        enabled: root.player && root.player.canTogglePlaying
                        onClicked: if (root.player) root.player.togglePlaying()
                    }
                    FIconBtn {
                        glyph: Icons.next
                        circular: true
                        diameter: 32
                        enabled: root.player && root.player.canGoNext
                        onClicked: if (root.player) root.player.next()
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ── Seek bar ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            FSlider {
                Layout.fillWidth: true
                from: 0
                to: 100
                value: root.percent
                enabled: root.player && root.player.canSeek && root.lengthSec > 0
                onPressedChanged: {
                    root.userSeeking = pressed
                    if (!pressed && root.player && root.lengthSec > 0)
                        root.player.position = root.lengthSec * (value / 100)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.fmt(root.livePosition)
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.fmt(root.lengthSec)
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }
            }
        }

        // ── Equaliser ───────────────────────────────────────────────
        FCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 208
            Layout.minimumHeight: 200

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Equaliser"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                        font.weight: Font.DemiBold
                        color: ArchTheme.textPrimary
                    }
                    Text {
                        text: root.eqPreset
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.accent
                    }
                    Item { Layout.fillWidth: true }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 5

                    Repeater {
                        model: root.eqPresets
                        delegate: FBtn {
                            required property string modelData
                            text: modelData
                            implicitHeight: 26
                            highlighted: root.eqPreset === modelData
                            onClicked: root.applyPreset(modelData)
                        }
                    }
                }

                // Frequency bands
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2

                    Repeater {
                        model: 10

                        // Item, not ColumnLayout: a Layout nested straight into
                        // another Layout ignores fillWidth and collapses to its
                        // implicit width, which bunches all ten bands together.
                        delegate: Item {
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 2

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: {
                                        const g = Math.round(root.eqGains[index] || 0)
                                        return (g > 0 ? "+" : "") + g
                                    }
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: Math.round(root.eqGains[index] || 0) === 0
                                        ? ArchTheme.textTertiary : ArchTheme.accent
                                }

                                FVSlider {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillHeight: true
                                    from: -12
                                    to: 12
                                    stepSize: 1
                                    value: root.eqGains[index] || 0
                                    onMoved: root.setBand(index, value)
                                    onPressedChanged: if (!pressed) root.pushGains()
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.eqBands[index]
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: ArchTheme.textTertiary
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: "dB per band · needs EasyEffects running"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                        elide: Text.ElideRight
                    }
                    FBtn {
                        text: "Reset"
                        implicitHeight: 26
                        onClicked: root.applyPreset("Flat")
                    }
                }
            }
        }
    }
}
