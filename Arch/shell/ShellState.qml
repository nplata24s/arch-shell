import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import "theme"

Item {
    id: root
    visible: false
    width: 0
    height: 0

    property var openModule: null
    property string searchQuery: ""
    property var allApps: []

    // Prefer the player that is currently playing; otherwise the first available one.
    readonly property var mprisPlayer: {
        const list = Mpris.players.values
        if (!list || list.length === 0)
            return null
        let fallback = null
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (!fallback)
                fallback = p
            if (p.isPlaying)
                return p
        }
        return fallback
    }

    property var settings: defaultSettings()
    property int settingsRev: 0
    property string configDir: Quickshell.env("HOME") + "/.config/arch-shell"
    property string scriptsPath: configDir + "/scripts"

    // ── Notifications ────────────────────────────────────────────────
    property bool dnd: false
    property int notifCount: 0
    property var notifServer: notifLoader.item
    property var liveNotifs: ({})
    property int toastSeq: 0

    signal toastPushed(int uid, string appName, string summary, string body, int urgency, string actionsJson, real expireMs)
    signal toastPopped(int uid)
    signal toastsCleared()

    // Volume / brightness / caps OSD (replaces swayosd / Serpantinum)
    property string osdKind: ""
    property int osdValue: 0
    property bool osdMuted: false
    property int osdTick: 0

    // Every module that can be placed on the taskbar.
    readonly property var allModules: [
        { id: "Start", label: "Start", icon: Icons.start, fixed: true },
        { id: "AgentCentre", label: "Agent Centre", icon: Icons.agent },
        { id: "DesktopManager", label: "Desktops", icon: Icons.desktops },
        { id: "DynamicMusic", label: "Music", icon: Icons.music },
        { id: "Audio", label: "Audio", icon: Icons.volume },
        { id: "NetworkBluetooth", label: "Network", icon: Icons.wifi },
        { id: "BatteryNotifications", label: "Battery & alerts", icon: Icons.battery },
        { id: "SystemTray", label: "System tray", icon: Icons.tray },
        { id: "Keyboard", label: "Keyboard layout", icon: Icons.keyboard },
        { id: "ClockWeather", label: "Clock & weather", icon: Icons.clock },
        { id: "QuickSettings", label: "Quick settings", icon: Icons.quickSettings },
        { id: "Clipboard", label: "Clipboard", icon: Icons.clipboard },
        { id: "Notes", label: "Notes", icon: Icons.notes },
        { id: "Calculator", label: "Calculator", icon: Icons.calculator },
        { id: "TaskView", label: "Task view", icon: Icons.taskView },
        { id: "Wallpaper", label: "Wallpaper", icon: Icons.wallpaper },
        { id: "SystemUpdates", label: "Updates", icon: Icons.updates },
        { id: "GamingMode", label: "Gaming mode", icon: Icons.gaming },
        { id: "Settings", label: "Settings", icon: Icons.settings }
    ]

    function moduleMeta(id) {
        for (let i = 0; i < allModules.length; i++) {
            if (allModules[i].id === id)
                return allModules[i]
        }
        return { id: id, label: id, icon: Icons.settings }
    }

    function defaultSettings() {
        return {
            taskbar: {
                position: "bottom",
                height: 48,
                color: "#1a1f28",
                opacity: 0.6,
                margins: { top: 6, left: 10, right: 10, bottom: 0 },
                modules: {
                    left: ["Start", "AgentCentre", "DesktopManager", "DynamicMusic"],
                    center: ["ClockWeather"],
                    right: ["SystemTray", "NetworkBluetooth", "BatteryNotifications",
                            "Audio", "Settings", "Wallpaper"]
                }
            },
            workspaces: { count: 9, showOnBar: 5 },
            theme: { accent: "#60cdff", fontFamily: "JetBrainsMono Nerd Font" },
            weather: { unit: "celsius" }
        }
    }

    // ── Derived appearance ───────────────────────────────────────────
    // Fluent acrylic is a blurred backdrop plus a tint plus a luminosity layer.
    // The luminosity layer is what stops the surface picking up the brightness
    // of whatever happens to sit behind it; without it a low tint setting lets
    // window edges behind show through as a hard change in background colour.
    readonly property real luminosityFloor: 0.55

    readonly property color barColor: {
        const _ = settingsRev
        const t = settings.taskbar || {}
        const base = Qt.color(t.color || "#1c1c1c")
        const op = t.opacity === undefined ? 0.72 : t.opacity
        const combined = 1 - (1 - luminosityFloor) * (1 - op)
        return Qt.rgba(base.r, base.g, base.b, combined)
    }

    onBarColorChanged: ArchTheme.mica = barColor

    function applyTheme() {
        ArchTheme.mica = barColor
        const accent = (settings.theme && settings.theme.accent) || "#60cdff"
        ArchTheme.accent = Qt.color(accent)
    }

    Component.onCompleted: applyTheme()

    // ── Persistence ──────────────────────────────────────────────────
    function replaceSettings(next) {
        settings = next
        settingsRev += 1
        applyTheme()
        persistJson(configDir + "/settings.json", next)
    }

    function patchSettings(fn) {
        const next = JSON.parse(JSON.stringify(settings))
        fn(next)
        replaceSettings(next)
    }

    function setTaskbarPosition(pos) {
        patchSettings(n => { n.taskbar.position = pos })
    }

    function setTaskbarHeight(h) {
        patchSettings(n => { n.taskbar.height = h })
    }

    function setTaskbarOpacity(o) {
        patchSettings(n => { n.taskbar.opacity = o })
    }

    function setTaskbarColor(hex) {
        patchSettings(n => { n.taskbar.color = hex })
    }

    function setAccent(hex) {
        patchSettings(n => {
            if (!n.theme) n.theme = {}
            n.theme.accent = hex
        })
    }

    function setWorkspacesOnBar(count) {
        patchSettings(n => {
            if (!n.workspaces) n.workspaces = {}
            n.workspaces.showOnBar = count
        })
    }

    function setWeatherUnit(unit) {
        patchSettings(n => {
            if (!n.weather) n.weather = {}
            n.weather.unit = unit
        })
    }

    // ── Taskbar module layout editing ────────────────────────────────
    function zoneModules(zone) {
        const _ = settingsRev
        if (!settings.taskbar || !settings.taskbar.modules)
            return []
        return settings.taskbar.modules[zone] || []
    }

    function moduleZone(id) {
        const zones = ["left", "center", "right"]
        for (let i = 0; i < zones.length; i++) {
            if (zoneModules(zones[i]).indexOf(id) >= 0)
                return zones[i]
        }
        return ""
    }

    function addModuleToZone(id, zone) {
        patchSettings(n => {
            const m = n.taskbar.modules
            for (const z of ["left", "center", "right"])
                m[z] = (m[z] || []).filter(x => x !== id)
            m[zone] = (m[zone] || []).concat([id])
        })
    }

    function removeModuleFromBar(id) {
        patchSettings(n => {
            const m = n.taskbar.modules
            for (const z of ["left", "center", "right"])
                m[z] = (m[z] || []).filter(x => x !== id)
        })
    }

    function moveModule(id, delta) {
        patchSettings(n => {
            const m = n.taskbar.modules
            for (const z of ["left", "center", "right"]) {
                const list = m[z] || []
                const i = list.indexOf(id)
                if (i < 0)
                    continue
                const j = i + delta
                if (j < 0 || j >= list.length)
                    return
                list.splice(i, 1)
                list.splice(j, 0, id)
                m[z] = list
                return
            }
        })
    }

    function resetSettings() {
        replaceSettings(defaultSettings())
    }

    function persistJson(path, obj) {
        Quickshell.execDetached([
            "python3", scriptsPath + "/write_json.py", path, JSON.stringify(obj)
        ])
    }

    function persistKeybinds(obj) {
        Quickshell.execDetached([
            "python3", scriptsPath + "/apply_keybinds.py",
            configDir + "/keybinds.json",
            configDir + "/hyprland/keybinds.conf",
            configDir,
            JSON.stringify(obj)
        ])
    }

    // ── Popup control ────────────────────────────────────────────────
    function open(name) {
        if (name === "ColorPicker") {
            Quickshell.execDetached(["hyprpicker", "-a"])
            return
        }
        // Old ids that were merged into ClockWeather.
        if (name === "Clock" || name === "Location")
            name = "ClockWeather"
        if (openModule === name) {
            close()
            return
        }
        if (name === "Start")
            refreshApps()
        openModule = name
    }

    function refreshApps() {
        appFetcher.running = false
        appFetcher.running = true
    }

    function close() {
        openModule = null
        searchQuery = ""
    }

    function showOsd(kind, value, extra) {
        osdKind = kind || "volume"
        const n = parseInt(value)
        osdValue = isNaN(n) ? 0 : Math.max(0, Math.min(100, n))
        const x = String(extra || "").toLowerCase()
        osdMuted = (x === "true" || x === "1" || x === "mute")
        osdTick++
    }

    function isOpen(name) {
        if (name === "Clock" || name === "Location")
            name = "ClockWeather"
        return openModule === name
    }

    // ── Settings file ────────────────────────────────────────────────
    function migrate(s) {
        if (!s.taskbar)
            s.taskbar = defaultSettings().taskbar

        const t = s.taskbar

        // Old builds folded alpha into the colour string, and QML read those
        // 8-digit values as #AARRGGBB — which is where the yellow came from.
        if (typeof t.color === "string" && t.color.length > 7) {
            t.color = "#" + t.color.replace("#", "").slice(0, 6)
            if (t.opacity === undefined)
                t.opacity = 0.72
        }
        if (t.opacity === undefined)
            t.opacity = 0.72

        // Anything that was a shipped default becomes the new default tint.
        const legacyTints = ["#141422", "#1a1a2e", "#202020", "#0f0f17"]
        if (legacyTints.indexOf(String(t.color).toLowerCase()) >= 0)
            t.color = "#1c1c1c"
        if (t.height === 42)
            t.height = 48

        // Clock and Weather became one module.
        if (t.modules) {
            for (const z of ["left", "center", "right"]) {
                let list = t.modules[z] || []
                let seenClock = false
                const out = []
                for (const id of list) {
                    const mapped = (id === "Clock" || id === "Location") ? "ClockWeather" : id
                    if (mapped === "ClockWeather") {
                        if (seenClock)
                            continue
                        seenClock = true
                    }
                    if (out.indexOf(mapped) < 0)
                        out.push(mapped)
                }
                t.modules[z] = out
            }
        }

        if (s.theme && s.theme.accent === "#0078d4")
            s.theme.accent = "#60cdff"
        if (!s.weather)
            s.weather = { unit: "celsius" }

        return s
    }

    function mergeSettings(base, patch) {
        if (!patch || typeof patch !== "object")
            return base
        const out = JSON.parse(JSON.stringify(base))
        for (const k in patch) {
            if (patch[k] && typeof patch[k] === "object" && !Array.isArray(patch[k]))
                out[k] = mergeSettings(out[k] || {}, patch[k])
            else
                out[k] = patch[k]
        }
        return out
    }

    FileView {
        id: settingsFile
        path: root.configDir + "/settings.json"
        onLoaded: {
            try {
                root.settings = root.migrate(
                    root.mergeSettings(root.defaultSettings(), JSON.parse(text())))
                root.settingsRev += 1
                root.applyTheme()
            } catch (e) {
                console.log("Arch Shell: could not parse settings.json", e)
            }
        }
        onLoadFailed: console.log("Arch Shell: using default settings")
    }

    Process {
        id: blurApply
        running: true
        command: ["bash", root.scriptsPath + "/apply_blur.sh"]
    }

    Process {
        id: appFetcher
        running: true
        command: ["python3", root.scriptsPath + "/app_fetcher.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (text.trim().length > 0)
                        root.allApps = JSON.parse(text)
                } catch (e) {
                    console.log("Arch Shell: app list parse error", e)
                }
            }
        }
    }

    // ── Notification daemon ──────────────────────────────────────────
    // Only one process can own org.freedesktop.Notifications. Stop mako
    // first so this shell can be the daemon and draw its own toasts.
    Process {
        id: stopMako
        running: true
        command: ["bash", "-c", "pkill -x mako; pkill -x dunst; pkill -x swaync; pkill -f 'quickshell -p .*/hypr/scripts/quickshell/Shell.qml'; true"]
        onExited: notifLoader.active = true
    }

    Timer {
        interval: 400
        running: true
        repeat: false
        onTriggered: {
            if (!notifLoader.active)
                notifLoader.active = true
        }
    }

    ListModel {
        id: toastList
    }

    Loader {
        id: notifLoader
        active: false
        sourceComponent: NotificationServer {
            keepOnReload: true
            persistenceSupported: true
            bodySupported: true
            bodyMarkupSupported: true
            bodyHyperlinksSupported: true
            actionsSupported: true
            imageSupported: true

            onNotification: (n) => root.onIncomingNotification(n)
        }
    }

    Process {
        id: dndProc
        command: ["bash", root.scriptsPath + "/dnd.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.dnd = JSON.parse(text).enabled } catch (e) { }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            dndProc.running = true
            root.refreshNotifCount()
        }
    }

    function toggleDnd() {
        Quickshell.execDetached(["bash", scriptsPath + "/dnd.sh", "toggle"])
        Qt.callLater(() => { dndProc.running = true })
    }

    function notifImage(n) {
        if (!n)
            return ""
        if (n.image && n.image.length)
            return n.image
        const ic = n.appIcon || ""
        if (!ic.length)
            return ""
        if (ic.indexOf("file:") === 0 || ic.indexOf("image:") === 0)
            return ic
        if (ic.indexOf("/") === 0)
            return "file://" + ic
        return Quickshell.iconPath(ic)
    }

    function toastMs(n) {
        if (!n)
            return 5000
        if (n.urgency === NotificationUrgency.Critical)
            return 0
        const t = n.expireTimeout
        if (t === 0)
            return 0
        if (t > 0)
            return t
        return 5000
    }

    function onIncomingNotification(n) {
        if (!n)
            return
        n.tracked = true
        Qt.callLater(refreshNotifCount)
        refreshNotifCount()

        if (root.dnd && n.urgency !== NotificationUrgency.Critical)
            return

        toastSeq += 1
        const uid = toastSeq
        const map = liveNotifs
        map[uid] = n
        liveNotifs = map

        const actions = []
        if (n.actions) {
            for (let i = 0; i < n.actions.length; i++) {
                actions.push({
                    id: n.actions[i].identifier || "",
                    text: n.actions[i].text || "Action"
                })
            }
        }

        const appName = n.appName && n.appName.length ? n.appName : "System"
        const summary = n.summary || ""
        const body = n.body || ""
        const actionsJson = JSON.stringify(actions)
        const expireMs = toastMs(n)
        const urgency = Number(n.urgency)

        toastList.insert(0, {
            uid: uid,
            appName: appName,
            summary: summary,
            body: body,
            urgency: urgency,
            actionsJson: actionsJson,
            expireMs: expireMs
        })

        while (toastList.count > 4)
            hideToast(toastList.get(toastList.count - 1).uid)

        toastPushed(uid, appName, summary, body, urgency, actionsJson, expireMs)
    }

    function notifByUid(uid) {
        return liveNotifs[uid] || null
    }

    function hideToast(uid) {
        for (let i = 0; i < toastList.count; i++) {
            if (toastList.get(i).uid === uid) {
                toastList.remove(i)
                break
            }
        }
        toastPopped(uid)
    }

    function dismissToast(uid) {
        const n = notifByUid(uid)
        hideToast(uid)
        if (n)
            n.dismiss()
        refreshNotifCount()
    }

    function invokeToastAction(uid, actionId) {
        const n = notifByUid(uid)
        if (n && n.actions) {
            for (let i = 0; i < n.actions.length; i++) {
                if (n.actions[i].identifier === actionId) {
                    n.actions[i].invoke()
                    break
                }
            }
        }
        hideToast(uid)
        refreshNotifCount()
    }

    function dismissNotif(n) {
        if (!n)
            return
        n.dismiss()
        refreshNotifCount()
    }

    function dismissAllNotifs() {
        toastList.clear()
        toastsCleared()
        const s = notifLoader.item
        if (!s || !s.trackedNotifications)
            return
        const list = s.trackedNotifications.values
        if (!list)
            return
        const copy = []
        for (let i = 0; i < list.length; i++)
            copy.push(list[i])
        for (let i = 0; i < copy.length; i++) {
            try { copy[i].dismiss() } catch (e) { }
        }
        refreshNotifCount()
    }

    function refreshNotifCount() {
        try {
            const s = notifLoader.item
            if (!s || !s.trackedNotifications) {
                notifCount = 0
                return
            }
            const m = s.trackedNotifications
            if (m.values !== undefined)
                notifCount = m.values.length
            else if (m.count !== undefined)
                notifCount = m.count
            else
                notifCount = 0
        } catch (e) {
            notifCount = 0
        }
    }
}
