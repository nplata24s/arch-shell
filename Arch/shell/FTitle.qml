import QtQuick
import "theme"

Text {
    property string glyph: ""

    text: glyph ? glyph + "  " + title : title
    property string title: ""

    font.family: ArchTheme.fontFamily
    font.pixelSize: ArchTheme.sizeTitle
    font.weight: Font.DemiBold
    color: ArchTheme.textPrimary
    elide: Text.ElideRight
}
