import QtQuick
import "theme"

// Maps an Open-Meteo weather code to a Nerd Font weather glyph.
Text {
    property int code: 0

    font.family: ArchTheme.fontFamily
    color: ArchTheme.textPrimary

    text: {
        const c = code
        if (c === 0) return "\u{f05a8}"                        // sunny
        if (c === 1 || c === 2) return "\u{f0595}"             // partly cloudy
        if (c === 3) return "\u{f0590}"                        // cloudy
        if (c === 45 || c === 48) return "\u{f0591}"           // fog
        if (c >= 51 && c <= 57) return "\u{f0597}"             // drizzle
        if (c >= 61 && c <= 67) return "\u{f0596}"             // rain
        if (c >= 80 && c <= 82) return "\u{f0596}"             // showers
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return "\u{f0598}"
        if (c >= 95) return "\u{f0593}"                        // storm
        return "\u{f05a8}"
    }
}
