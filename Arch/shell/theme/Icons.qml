//@ pragma Singleton
pragma Singleton

import QtQuick

// JetBrainsMono Nerd Font, Material Design range. Every codepoint here was
// rendered and eyeballed — the MDI numbering has traps next to each other
// (f0759 is music-off, f075a is music).
//
// Note the \u{...} form: a plain \uXXXXX escape only consumes four digits.
QtObject {
    readonly property string start: "\u{f05b3}"          // microsoft-windows
    readonly property string agent: "\u{f06a9}"          // robot
    readonly property string desktops: "\u{f0379}"       // monitor
    readonly property string music: "\u{f075a}"          // music
    readonly property string volume: "\u{f057e}"         // volume-high
    readonly property string volumeOff: "\u{f075f}"      // volume-off
    readonly property string mic: "\u{f036c}"            // microphone
    readonly property string micOff: "\u{f036d}"         // microphone-off
    readonly property string wifi: "\u{f0928}"           // wifi-strength-4
    readonly property string wifiOff: "\u{f092d}"        // wifi-off
    readonly property string ethernet: "\u{f0200}"       // ethernet
    readonly property string bluetooth: "\u{f00af}"      // bluetooth
    readonly property string bluetoothOff: "\u{f00b2}"   // bluetooth-off
    readonly property string bell: "\u{f009a}"           // bell
    readonly property string bellOff: "\u{f009b}"        // bell-off
    readonly property string warning: "\u{f0026}"        // alert
    readonly property string weather: "\u{f05a8}"        // white-balance-sunny
    readonly property string nightLight: "\u{f0594}"     // weather-night
    readonly property string quickSettings: "\u{f062e}"  // tune
    readonly property string settings: "\u{f0493}"       // cog
    readonly property string clipboard: "\u{f014c}"      // clipboard-text
    readonly property string notes: "\u{f039a}"          // note-text
    readonly property string calculator: "\u{f00ec}"     // calculator
    readonly property string taskView: "\u{f02c1}"       // table / grid
    readonly property string tray: "\u{f003b}"           // apps (dots grid)
    readonly property string keyboard: "\u{f030c}"       // keyboard
    readonly property string wallpaper: "\u{f0e09}"      // image
    readonly property string updates: "\u{f06b0}"        // update
    readonly property string gaming: "\u{f02b4}"         // controller
    readonly property string clock: "\u{f0954}"          // clock
    readonly property string battery: "\u{f0079}"        // battery
    readonly property string batteryCharging: "\u{f0084}"
    readonly property string brightness: "\u{f00e0}"     // brightness-7
    readonly property string equalizer: "\u{f0f3b}"      // chart-bar
    readonly property string search: "\u{f0349}"         // magnify
    readonly property string folder: "\u{f024b}"         // folder
    readonly property string terminal: "\u{f018d}"       // console
    readonly property string power: "\u{f0425}"          // power
    readonly property string restart: "\u{f0709}"        // restart
    readonly property string sleep: "\u{f04b2}"          // sleep
    readonly property string logout: "\u{f0343}"         // logout
    readonly property string play: "\u{f040a}"           // play
    readonly property string pause: "\u{f03e4}"          // pause
    readonly property string next: "\u{f04ad}"           // skip-next
    readonly property string previous: "\u{f04ae}"       // skip-previous
    readonly property string album: "\u{f0025}"          // album
    readonly property string record: "\u{f044a}"         // record
    readonly property string check: "\u{f012c}"          // check
    readonly property string close: "\u{f0156}"          // close
    readonly property string plus: "\u{f0415}"           // plus
    readonly property string trash: "\u{f01b4}"          // delete
    readonly property string refresh: "\u{f0450}"        // refresh
    readonly property string chevronLeft: "\u{f0141}"
    readonly property string chevronRight: "\u{f0142}"
    readonly property string chevronUp: "\u{f0143}"
    readonly property string chevronDown: "\u{f0140}"
    readonly property string user: "\u{f0013}"           // account-circle
}
