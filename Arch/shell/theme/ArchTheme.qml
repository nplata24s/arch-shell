//@ pragma Singleton
pragma Singleton

import QtQuick

QtObject {
    id: theme

    // QML parses 8-digit hex as #AARRGGBB — alpha FIRST. Writing #ffffff18
    // gives opaque yellow, not translucent white. Every literal below is ARGB.

    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property string fontFamilyFallback: "JetBrainsMono Nerd Font"

    // Accent follows settings.json; ShellState writes to it on load.
    property color accent: "#ff60cdff"

    // ── Glass materials ──────────────────────────────────────────────
    // These are deliberately translucent; Hyprland blur behind the layer
    // is what turns them into acrylic.
    property color mica: "#b81c1c1c"        // taskbar + flyouts (same material)
    readonly property color acrylic: "#c4222222"
    readonly property color solid: "#ff1c1c1c"

    // Cards / rows layered on top of the glass
    readonly property color layer: "#0dffffff"
    readonly property color layerHover: "#17ffffff"
    readonly property color layerActive: "#24ffffff"

    readonly property color hover: "#14ffffff"
    readonly property color hoverStrong: "#24ffffff"
    readonly property color pressed: "#0affffff"

    readonly property color border: "#1fffffff"
    readonly property color borderStrong: "#33ffffff"
    readonly property color glassHighlight: "#26ffffff"
    readonly property color shadow: "#59000000"
    readonly property color scrim: "#99000000"

    // ── Accent derivatives ───────────────────────────────────────────
    readonly property color accentHover: Qt.lighter(accent, 1.12)
    readonly property color accentPressed: Qt.darker(accent, 1.12)
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.22)
    readonly property color accentMuted: Qt.rgba(accent.r, accent.g, accent.b, 0.14)
    readonly property color accentLine: Qt.rgba(accent.r, accent.g, accent.b, 0.55)

    // Dark text on light accents, white text on dark ones.
    readonly property color textOnAccent:
        (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6
            ? "#ff10222e" : "#ffffffff"

    // ── Text ─────────────────────────────────────────────────────────
    readonly property color textPrimary: "#ffffffff"
    readonly property color textSecondary: "#c7ffffff"
    readonly property color textTertiary: "#8affffff"
    readonly property color textDisabled: "#5cffffff"

    readonly property color danger: "#ffff6b6b"
    readonly property color success: "#ff6ccb5f"
    readonly property color warning: "#ffffc95c"

    readonly property color dangerMuted: Qt.rgba(danger.r, danger.g, danger.b, 0.14)
    readonly property color dangerLine: Qt.rgba(danger.r, danger.g, danger.b, 0.55)

    // ── Workspace pills ──────────────────────────────────────────────
    readonly property color workspaceActive: accent
    readonly property color workspaceOccupied: "#8affffff"
    readonly property color workspaceEmpty: "#3dffffff"

    // ── Geometry ─────────────────────────────────────────────────────
    readonly property int radiusSmall: 4
    readonly property int radius: 6
    readonly property int radiusCard: 8
    readonly property int radiusLarge: 12
    readonly property int radiusPill: 999

    readonly property int sizeCaption: 10
    readonly property int sizeSmall: 11
    readonly property int sizeBody: 13
    readonly property int sizeTitle: 15
    readonly property int sizeHeading: 18
    readonly property int sizeDisplay: 34

    readonly property int animFast: 110
    readonly property int animNormal: 160

    // Legacy aliases kept so older module files keep resolving.
    readonly property color background: mica
    readonly property color backgroundTranslucent: mica
    readonly property color surface: layer
    readonly property color surfaceTranslucent: layer
    readonly property color popup: mica
    readonly property color popupBorder: border
    readonly property color flyout: mica
    readonly property color micaTranslucent: mica

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
}
