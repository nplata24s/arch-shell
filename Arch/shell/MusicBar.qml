import QtQuick
import "theme"

BarChip {
    id: root
    required property var shellState

    readonly property var player: shellState ? shellState.mprisPlayer : null
    readonly property bool playing: player ? player.isPlaying : false
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string artUrl: player ? (player.trackArtUrl || "") : ""

    active: shellState ? shellState.isOpen("DynamicMusic") : false
    implicitWidth: Math.min(250, holder2.implicitWidth + hPadding * 2)

    onActivated: if (shellState) shellState.open("DynamicMusic")

    Row {
        id: holder2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        // Tiny album thumbnail, falls back to a glyph.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: 4
            color: ArchTheme.layer
            visible: root.player !== null
            clip: true

            Image {
                id: thumb
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                text: Icons.music
                font.family: ArchTheme.fontFamily
                font.pixelSize: 12
                color: ArchTheme.textSecondary
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.playing ? Icons.play : Icons.pause
            font.family: ArchTheme.fontFamily
            font.pixelSize: 13
            color: root.playing ? ArchTheme.accent : ArchTheme.textTertiary
            visible: root.player !== null
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 170)
            elide: Text.ElideRight
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
            color: root.playing ? ArchTheme.textPrimary : ArchTheme.textSecondary
            text: {
                if (!root.player)
                    return Icons.music + "  No music"
                if (root.artist && root.title)
                    return root.artist + " — " + root.title
                return root.title || root.player.identity || "Playing"
            }
        }
    }
}
