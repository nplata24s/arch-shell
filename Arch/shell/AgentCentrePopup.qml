import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "theme"

// Sprint 5 — Agent Centre. Teams, agents, providers, live activity and
// a direct Chat tab with computer access, talking to the local arch-agentd.
Item {
    id: root
    required property var shellState

    implicitWidth: 890
    implicitHeight: 700

    property bool daemonRunning: false
    property bool daemonEnabled: false
    property var teams: []
    property var agents: []
    property var activity: []
    property var pending: []
    property var providers: ({})
    property var knownProviders: ({})
    property var providerOrder: ["openai", "anthropic", "google", "copilot"]
    property var rulePresets: [
        "ask-before-commit", "ask-before-shell", "ask-before-network",
        "no-destructive", "stay-in-repo", "report-to-lead"
    ]
    property var dutyPresets: ["implement", "review", "coordinate"]

    property string selectedTeam: ""
    property string mode: "centre"
    property string tab: "agents"
    property string busy: ""
    property string error: ""
    property string actionPendingBody: ""
    property string orgKind: ""
    property string orgId: ""
    // The daemon is a local user service, so bring it up on first open rather
    // than leaving every action to fail quietly. Tried once, so a service that
    // cannot start does not turn into a restart loop.
    property bool autoStartTried: false

    property var chatMessages: []
    property string chatProvider: "google"
    property string chatSavedModel: ""
    property var chatModels: []
    property string chatBusy: ""
    property bool chatLoaded: false

    readonly property var teamAgents: agents.filter(
        a => !selectedTeam || a.teamId === selectedTeam)

    readonly property var selectedTeamObj: {
        const id = selectedTeam
        return teams.find(t => t.id === id) || null
    }

    readonly property var orgTeam: orgKind === "team"
        ? (teams.find(t => t.id === orgId) || null) : null
    readonly property var orgAgent: orgKind === "agent"
        ? (agents.find(a => a.id === orgId) || null) : null

    function scriptPath() {
        return shellState.scriptsPath + "/agentd.sh"
    }

    // The team a new agent lands in: the selected one, else the first.
    function currentTeamName() {
        const id = selectedTeam || (teams.length ? teams[0].id : "")
        const t = teams.find(x => x.id === id)
        return t ? t.name : "no team"
    }

    // Returns a real bool. Indexing `providers` inline inside a bool binding
    // hands QML an undefined it refuses to coerce.
    function providerConfigured(name) {
        const p = providers ? providers[name] : undefined
        return p !== undefined && p !== null && p.configured === true
    }

    function providerActiveModel(name) {
        const p = providers ? providers[name] : undefined
        return (p && p.model) ? String(p.model) : ""
    }

    function providerLabel(name) {
        const p = knownProviders ? knownProviders[name] : undefined
        return (p && p.label) ? p.label : name
    }

    function providerIds() {
        const order = root.providerOrder || []
        if (order.length)
            return order
        const keys = Object.keys(root.knownProviders || {})
        return keys.length ? keys : ["openai", "anthropic", "google", "copilot"]
    }

    function providerInfo(name) {
        return (root.providers && root.providers[name]) ? root.providers[name] : ({})
    }

    function providerStatusText(name) {
        const p = root.providerInfo(name)
        if (p.loginJob && p.loginJob.status === "running")
            return p.loginJob.message || "Waiting for sign-in…"
        if (p.loginJob && p.loginJob.status === "error")
            return p.loginJob.message
        if (p.mode === "login")
            return "Signed in" + (p.account ? (" · " + p.account) : "") +
                   (root.providerActiveModel(name) ? (" · " + root.providerActiveModel(name)) : "")
        if (p.mode === "local")
            return "Local · " + (root.providerActiveModel(name) || "auto")
        if (root.providerConfigured(name))
            return "API key saved · " + (root.providerActiveModel(name) || "auto")
        if (p.cli && p.cli.available && p.cli.account)
            return "Session found · " + p.cli.account + " — click Use existing login"
        return "Not configured"
    }

    function providerModels(name) {
        const live = root.providerInfo(name).models
        if (live && live.length)
            return live
        const p = knownProviders ? knownProviders[name] : undefined
        return (p && p.fallbacks) ? p.fallbacks : []
    }

    function rankName(rank) {
        if (rank === 2) return "director"
        if (rank === 1) return "lead"
        return "worker"
    }

    function teamName(id) {
        const t = teams.find(x => x.id === id)
        return t ? t.name : ""
    }

    function agentName(id) {
        const a = agents.find(x => x.id === id)
        return a ? a.name : ""
    }

    function indexIn(list, value) {
        const i = (list || []).indexOf(value)
        return i < 0 ? 0 : i
    }

    readonly property var chatProviderIds: {
        const keys = Object.keys(root.knownProviders || {})
        const all = keys.length ? keys : root.providerIds()
        const configured = all.filter(k => root.providerConfigured(k))
        return configured.length ? configured : all
    }

    // Polling GET /state used to replace every bound TextField every 2.5s.
    function editingNow() {
        const win = root.Window.window
        const item = win ? win.activeFocusItem : null
        if (!item)
            return false
        return item instanceof TextInput || item instanceof TextEdit
    }

    function refresh() {
        if (root.editingNow())
            return
        statusProc.running = true
    }

    function applyChat(d) {
        if (!d || d.ok === false)
            return
        root.chatMessages = d.messages || []
        if (d.provider)
            root.chatProvider = d.provider
        if (d.model !== undefined)
            root.chatSavedModel = d.model || ""
        const ids = root.chatProviderIds
        chatProviderCombo.currentIndex = root.indexIn(ids, root.chatProvider)
        if ((root.chatModels || []).length)
            chatModelCombo.currentIndex = root.indexIn(root.chatModels, root.chatSavedModel)
    }

    function loadChat() {
        if (Object.keys(root.knownProviders || {}).length === 0)
            stateProc.running = true
        chatStateProc.running = true
        root.loadChatModels(chatProviderCombo.currentText || root.chatProvider)
    }

    function loadChatModels(provider) {
        const name = provider || root.chatProvider || "google"
        chatModelsProc.command = ["bash", root.scriptPath(), "get",
                                  "/models?provider=" + name]
        chatModelsProc.running = true
    }

    function sendChat() {
        const text = chatInput.text.trim()
        if (!text || root.chatBusy !== "")
            return
        chatInput.text = ""
        root.chatBusy = "send"
        root.error = ""
        const provider = chatProviderCombo.currentText || root.chatProvider
        const model = chatModelCombo.currentText || root.chatSavedModel
        root.chatMessages = root.chatMessages.concat([{
            role: "user", content: text, at: ""
        }])
        chatSendProc.command = ["bash", root.scriptPath(), "post", "/chat/send",
                                JSON.stringify({ provider: provider, model: model, text: text })]
        chatSendProc.running = true
    }

    function post(path, payload) {
        busy = path
        error = ""
        actionPendingBody = JSON.stringify(payload)
        actionProc.stdinEnabled = true
        actionProc.command = ["bash", scriptPath(), "post", path, "-"]
        actionProc.running = true
    }

    function service(action) {
        busy = action
        error = ""
        actionPendingBody = ""
        actionProc.stdinEnabled = false
        actionProc.command = ["bash", scriptPath(), action]
        actionProc.running = true
    }

    // ── Backend plumbing ─────────────────────────────────────────────
    Process {
        id: statusProc
        command: ["bash", root.scriptPath(), "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.daemonRunning = !!d.running
                    root.daemonEnabled = !!d.enabled
                } catch (e) { root.daemonRunning = false }
                if (root.daemonRunning) {
                    if (root.mode !== "chat")
                        stateProc.running = true
                } else if (!root.autoStartTried) {
                    root.autoStartTried = true
                    root.service("start")
                }
            }
        }
    }

    Process {
        id: stateProc
        command: ["bash", root.scriptPath(), "get", "/state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (!d.ok)
                        return
                    if (root.editingNow())
                        return
                    root.teams = d.teams || []
                    root.agents = d.agents || []
                    root.activity = d.activity || []
                    root.pending = d.pending || []
                    root.providers = d.providers || ({})
                    root.knownProviders = d.knownProviders || ({})
                    if (d.providerOrder && d.providerOrder.length)
                        root.providerOrder = d.providerOrder
                    if (d.rulePresets && d.rulePresets.length)
                        root.rulePresets = d.rulePresets
                    if (d.dutyPresets && d.dutyPresets.length)
                        root.dutyPresets = d.dutyPresets
                    if (root.selectedTeam
                        && !root.teams.some(t => t.id === root.selectedTeam))
                        root.selectedTeam = ""
                    if (root.orgKind === "team"
                        && !root.teams.some(t => t.id === root.orgId)) {
                        root.orgKind = ""; root.orgId = ""
                    }
                    if (root.orgKind === "agent"
                        && !root.agents.some(a => a.id === root.orgId)) {
                        root.orgKind = ""; root.orgId = ""
                    }
                } catch (e) { }
            }
        }
    }

    Process {
        id: actionProc
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = ""
                // agentd.sh always exits 0 and prints {"ok":false} when the
                // daemon is unreachable, so failures have to be read out of the
                // body or they vanish and the click looks like it did nothing.
                try {
                    const d = JSON.parse(text)
                    if (d.error)
                        root.error = String(d.error)
                    else if (d.ok === false)
                        root.error = "Could not reach the agent service."
                } catch (e) { }
                root.refresh()
            }
        }
        onStarted: {
            if (root.actionPendingBody !== "") {
                write(root.actionPendingBody)
                root.actionPendingBody = ""
                stdinEnabled = false
            }
        }
    }

    Process {
        id: chatStateProc
        command: ["bash", root.scriptPath(), "get", "/chat"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyChat(JSON.parse(text))
                    root.chatLoaded = true
                } catch (e) { }
            }
        }
    }

    Process {
        id: chatModelsProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    let models = d.models || []
                    if (!models.length)
                        models = root.providerModels(d.provider || root.chatProvider)
                    root.chatModels = models
                    const want = root.chatSavedModel
                    const idx = models.indexOf(want)
                    chatModelCombo.currentIndex = idx >= 0 ? idx : 0
                    if (!want && models.length)
                        root.chatSavedModel = models[0]
                } catch (e) {
                    root.chatModels = root.providerModels(root.chatProvider)
                }
            }
        }
    }

    Process {
        id: chatSendProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.chatBusy = ""
                try {
                    const d = JSON.parse(text)
                    if (d.error)
                        root.error = String(d.error)
                    else if (d.ok === false)
                        root.error = "Could not reach the agent service."
                    if (d.messages)
                        root.applyChat(d)
                    else
                        chatStateProc.running = true
                } catch (e) {
                    root.error = "Chat request failed."
                }
            }
        }
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ── Layout ───────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: Icons.agent
                font.family: ArchTheme.fontFamily
                font.pixelSize: 20
                color: ArchTheme.accent
            }

            ColumnLayout {
                spacing: 0
                Text {
                    text: root.mode === "chat" ? "Chat" : "Agent Centre"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeTitle
                    font.weight: Font.DemiBold
                    color: ArchTheme.textPrimary
                }
                Text {
                    text: root.mode === "chat"
                        ? (root.daemonRunning
                            ? "Conversation with computer access"
                            : "Service stopped")
                        : (root.daemonRunning
                            ? "Service running · " + root.agents.length + " agents"
                            : "Service stopped")
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: root.daemonRunning ? ArchTheme.success : ArchTheme.textTertiary
                }
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: ["centre", "chat"]
                delegate: FBtn {
                    required property string modelData
                    text: modelData === "centre" ? "Teams" : "Chat"
                    implicitHeight: 28
                    highlighted: root.mode === modelData
                    onClicked: {
                        root.mode = modelData
                        if (modelData === "chat")
                            root.loadChat()
                    }
                }
            }

            Repeater {
                model: ["agents", "org", "activity", "providers"]
                delegate: FBtn {
                    required property string modelData
                    visible: root.mode === "centre"
                    text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                    implicitHeight: 28
                    highlighted: root.tab === modelData
                    onClicked: root.tab = modelData
                }
            }

            FBtn {
                text: root.daemonRunning ? "Stop" : "Start"
                implicitHeight: 28
                highlighted: !root.daemonRunning
                enabled: root.busy === ""
                onClicked: root.service(root.daemonRunning ? "stop" : "start")
            }
        }

        FCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            visible: !root.daemonRunning || root.error !== ""
            color: ArchTheme.dangerMuted
            border.color: ArchTheme.dangerLine

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 10

                Text {
                    text: Icons.warning
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: 14
                    color: ArchTheme.danger
                }
                Text {
                    Layout.fillWidth: true
                    text: root.error !== "" ? root.error
                        : "Agent service is not running — nothing can be created until it starts."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textSecondary
                    elide: Text.ElideRight
                }
                FBtn {
                    text: "Start service"
                    visible: !root.daemonRunning
                    implicitHeight: 26
                    enabled: root.busy === ""
                    onClicked: root.service("start")
                }
            }
        }

        // Permission prompts sit above everything — they block agents.
        Repeater {
            model: root.pending

            delegate: FCard {
                required property var modelData
                readonly property bool needsSudo: !!(modelData.needsSudo)
                readonly property bool sudoNeedsPassword: needsSudo
                    && modelData.elevation !== "pkexec"
                    && modelData.sudoNeedsPassword !== false
                Layout.fillWidth: true
                implicitHeight: permCol.implicitHeight + 20
                color: ArchTheme.accentMuted
                border.color: ArchTheme.accentLine

                ColumnLayout {
                    id: permCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    anchors.topMargin: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: Icons.bell
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: 15
                            color: ArchTheme.accent
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: modelData.agent + " " + modelData.what
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                                color: ArchTheme.textPrimary
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: needsSudo
                                    ? (sudoNeedsPassword
                                        ? "Needs root — type your sudo password. Used once, not saved."
                                        : (modelData.elevation === "pkexec"
                                            ? "Needs root — approve, then complete the desktop prompt."
                                            : "Needs root — approve to run with your current sudo session."))
                                    : (modelData.status === "awaiting-agent"
                                        ? "Awaiting " + (modelData.approverName || "lead")
                                          + " — you can still override"
                                        : "Awaiting you")
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textTertiary
                                wrapMode: Text.WordWrap
                            }
                        }
                        FBtn {
                            text: "Approve"
                            implicitHeight: 26
                            highlighted: true
                            onClicked: {
                                const body = { id: modelData.id, approve: true }
                                if (sudoField.visible && sudoField.text !== "")
                                    body.sudoPassword = sudoField.text
                                sudoField.text = ""
                                root.post("/permissions/resolve", body)
                            }
                        }
                        FBtn {
                            text: "Deny"
                            implicitHeight: 26
                            danger: true
                            onClicked: {
                                sudoField.text = ""
                                root.post("/permissions/resolve",
                                          { id: modelData.id, approve: false })
                            }
                        }
                    }

                    FField {
                        id: sudoField
                        visible: sudoNeedsPassword
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: "sudo password"
                        font.pixelSize: ArchTheme.sizeCaption
                    }
                }
            }
        }

        // Service not running → explain instead of showing empty panes.
        FCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.daemonRunning

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 80
                spacing: 10

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Icons.agent
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: 40
                    color: ArchTheme.textTertiary
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "The Agent Centre service is not running"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    font.weight: Font.DemiBold
                    color: ArchTheme.textPrimary
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Start it to create agent teams. Enable it to start "
                          + "automatically every time you log in."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textSecondary
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    FBtn {
                        text: "Start now"
                        highlighted: true
                        onClicked: root.service("start")
                    }
                    FBtn {
                        text: root.daemonEnabled ? "Autostart on" : "Start on login"
                        enabled: !root.daemonEnabled
                        onClicked: root.service("enable")
                    }
                }
            }
        }

        // ── Agents tab ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.daemonRunning && root.mode === "centre" && root.tab === "agents"
            spacing: 12

            // Teams sidebar
            FCard {
                Layout.preferredWidth: 190
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "Teams"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: ArchTheme.radius
                        color: root.selectedTeam === "" ? ArchTheme.accentMuted : "transparent"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            text: "All agents"
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            color: root.selectedTeam === "" ? ArchTheme.accent : ArchTheme.textPrimary
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedTeam = ""
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.teams
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: FScroll { }

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            height: 32
                            radius: ArchTheme.radius
                            color: root.selectedTeam === modelData.id
                                ? ArchTheme.accentMuted
                                : (teamMa.containsMouse ? ArchTheme.layerHover : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 4
                                spacing: 4

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    color: ArchTheme.textPrimary
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: root.agents.filter(a => a.teamId === modelData.id).length
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: ArchTheme.textTertiary
                                }
                                FIconBtn {
                                    glyph: Icons.trash
                                    diameter: 22
                                    glyphSize: 11
                                    visible: teamMa.containsMouse
                                    onClicked: root.post("/teams/delete", { id: modelData.id })
                                }
                            }

                            MouseArea {
                                id: teamMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedTeam = modelData.id
                                z: -1
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        FField {
                            id: teamName
                            Layout.fillWidth: true
                            placeholderText: "New team"
                            font.pixelSize: ArchTheme.sizeSmall
                            onAccepted: {
                                if (text.trim()) {
                                    root.post("/teams", { name: text.trim() })
                                    text = ""
                                }
                            }
                        }
                        FIconBtn {
                            glyph: Icons.plus
                            diameter: 32
                            enabled: teamName.text.trim() !== ""
                            onClicked: {
                                root.post("/teams", { name: teamName.text.trim() })
                                teamName.text = ""
                            }
                        }
                    }
                }
            }

            // Agent cards
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Text {
                    visible: root.teamAgents.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.teams.length === 0
                        ? "Create a team on the left, then add your first agent below."
                        : "No agents in this team yet. Add one below."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textSecondary
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: root.teamAgents
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: FScroll { }

                    delegate: FCard {
                        required property var modelData
                        width: ListView.view ? ListView.view.width - 12 : 0
                        height: agentCol.implicitHeight + 20

                        ColumnLayout {
                            id: agentCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: modelData.status === "working" ? ArchTheme.accent
                                         : modelData.status === "error" ? ArchTheme.danger
                                         : ArchTheme.success
                                }
                                Text {
                                    text: modelData.name
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    font.weight: Font.DemiBold
                                    color: ArchTheme.textPrimary
                                }
                                Text {
                                    text: root.rankName(modelData.rank)
                                          + " · " + modelData.role
                                          + " · " + root.providerLabel(modelData.provider)
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: ArchTheme.textTertiary
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    visible: modelData.team !== ""
                                    text: modelData.team
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: ArchTheme.accent
                                }
                                FIconBtn {
                                    glyph: Icons.trash
                                    diameter: 24
                                    glyphSize: 11
                                    onClicked: root.post("/agents/delete", { id: modelData.id })
                                }
                            }

                            Text {
                                visible: (modelData.reportsTo || "") !== ""
                                Layout.fillWidth: true
                                text: "Reports to " + root.agentName(modelData.reportsTo)
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textTertiary
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: modelData.repo !== ""
                                Layout.fillWidth: true
                                text: Icons.folder + "  " + modelData.repo
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textTertiary
                                elide: Text.ElideMiddle
                            }

                            Text {
                                visible: modelData.lastReply !== ""
                                Layout.fillWidth: true
                                text: modelData.lastReply
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: modelData.status === "error"
                                    ? ArchTheme.danger : ArchTheme.textSecondary
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                FField {
                                    id: taskField
                                    Layout.fillWidth: true
                                    placeholderText: modelData.status === "working"
                                        ? "Working: " + modelData.task
                                        : "Give this agent a task…"
                                    enabled: modelData.status !== "working"
                                    font.pixelSize: ArchTheme.sizeSmall
                                    onAccepted: {
                                        if (text.trim()) {
                                            root.post("/agents/task",
                                                      { id: modelData.id, task: text.trim() })
                                            text = ""
                                        }
                                    }
                                }
                                FIconBtn {
                                    glyph: Icons.play
                                    diameter: 32
                                    highlighted: true
                                    enabled: taskField.text.trim() !== ""
                                             && modelData.status !== "working"
                                    onClicked: {
                                        root.post("/agents/task",
                                                  { id: modelData.id, task: taskField.text.trim() })
                                        taskField.text = ""
                                    }
                                }
                            }
                        }
                    }
                }

                // New agent form
                FCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 138

                    GridLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        columns: 4
                        columnSpacing: 6
                        rowSpacing: 6

                        Text {
                            Layout.columnSpan: 4
                            Layout.fillWidth: true
                            text: root.teams.length === 0
                                ? "Create a team on the left before adding an agent."
                                : "New agent in " + root.currentTeamName()
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: root.teams.length === 0
                                ? ArchTheme.warning : ArchTheme.textTertiary
                            elide: Text.ElideRight
                        }

                        FField {
                            id: agentName
                            Layout.fillWidth: true
                            placeholderText: "Agent name"
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                        FField {
                            id: agentRole
                            Layout.fillWidth: true
                            placeholderText: "Role (e.g. Reviewer)"
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                        FCombo {
                            id: agentProvider
                            Layout.fillWidth: true
                            model: root.providerIds()
                        }
                        FCombo {
                            id: agentRank
                            Layout.fillWidth: true
                            model: ["worker", "lead", "director"]
                        }
                        FField {
                            id: agentModel
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            placeholderText: "Model (blank = auto / fallback)"
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                        FField {
                            id: agentRepo
                            Layout.fillWidth: true
                            placeholderText: "Repository path (optional)"
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                        FBtn {
                            text: "Add agent"
                            highlighted: true
                            enabled: agentName.text.trim() !== "" && root.teams.length > 0
                            onClicked: {
                                root.post("/agents", {
                                    team: root.selectedTeam
                                        || (root.teams.length ? root.teams[0].id : ""),
                                    name: agentName.text.trim(),
                                    role: agentRole.text.trim() || "Developer",
                                    repo: agentRepo.text.trim(),
                                    provider: agentProvider.currentText,
                                    model: agentModel.text.trim(),
                                    rank: agentRank.currentIndex,
                                    rules: root.selectedTeamObj
                                        ? (root.selectedTeamObj.rules || [])
                                        : ["ask-before-commit"]
                                })
                                agentName.text = ""
                                agentRole.text = ""
                                agentRepo.text = ""
                                agentModel.text = ""
                            }
                        }
                    }
                }
            }
        }

        // ── Org tab ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.daemonRunning && root.mode === "centre" && root.tab === "org"
            spacing: 12

            FCard {
                Layout.preferredWidth: 220
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    Text {
                        text: "Hierarchy"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: FScroll { }
                        model: {
                            const rows = []
                            for (let i = 0; i < root.teams.length; i++) {
                                const t = root.teams[i]
                                rows.push({ kind: "team", id: t.id, name: t.name,
                                            parent: t.parentId ? root.teamName(t.parentId) : "" })
                                const members = root.agents.filter(a => a.teamId === t.id)
                                members.sort((a, b) => (b.rank || 0) - (a.rank || 0))
                                for (let j = 0; j < members.length; j++) {
                                    const a = members[j]
                                    rows.push({ kind: "agent", id: a.id, name: a.name,
                                                parent: root.rankName(a.rank) })
                                }
                            }
                            const unteamed = root.agents.filter(a => !a.teamId)
                            for (let k = 0; k < unteamed.length; k++) {
                                const a = unteamed[k]
                                rows.push({ kind: "agent", id: a.id, name: a.name, parent: "no team" })
                            }
                            return rows
                        }

                        delegate: Rectangle {
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            height: 28
                            radius: ArchTheme.radius
                            color: (root.orgKind === modelData.kind && root.orgId === modelData.id)
                                ? ArchTheme.accentMuted
                                : (orgMa.containsMouse ? ArchTheme.layerHover : "transparent")

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: modelData.kind === "agent" ? 18 : 8
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: (modelData.kind === "team" ? "▸ " : "") + modelData.name
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    font.weight: modelData.kind === "team" ? Font.DemiBold : Font.Normal
                                    color: ArchTheme.textPrimary
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: (modelData.parent || "") !== ""
                                    text: modelData.parent
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: ArchTheme.textTertiary
                                }
                            }
                            MouseArea {
                                id: orgMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.orgKind = modelData.kind
                                    root.orgId = modelData.id
                                }
                            }
                        }
                    }
                }
            }

            FCard {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Team inspector
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    visible: root.orgTeam !== null

                    Text {
                        text: root.orgTeam ? root.orgTeam.name : ""
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeTitle
                        font.weight: Font.DemiBold
                        color: ArchTheme.textPrimary
                    }
                    Text {
                        text: "Team rules apply to every agent here. Approval and comms set how they escalate and talk."
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 6

                        Text { text: "Parent team"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["none"].concat(root.teams.filter(t => !root.orgTeam || t.id !== root.orgTeam.id).map(t => t.name))
                            currentIndex: {
                                if (!root.orgTeam || !root.orgTeam.parentId) return 0
                                const names = ["none"].concat(root.teams.filter(t => t.id !== root.orgTeam.id).map(t => t.name))
                                return root.indexIn(names, root.teamName(root.orgTeam.parentId))
                            }
                            onActivated: {
                                const name = currentText
                                const t = root.teams.find(x => x.name === name)
                                root.post("/teams/update", {
                                    id: root.orgId,
                                    parentId: currentIndex === 0 ? "" : (t ? t.id : "")
                                })
                            }
                        }

                        Text { text: "Team lead"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["none"].concat(root.agents.filter(a => a.teamId === root.orgId).map(a => a.name))
                            currentIndex: {
                                if (!root.orgTeam || !root.orgTeam.leadAgentId) return 0
                                const names = ["none"].concat(root.agents.filter(a => a.teamId === root.orgId).map(a => a.name))
                                return root.indexIn(names, root.agentName(root.orgTeam.leadAgentId))
                            }
                            onActivated: {
                                const name = currentText
                                const a = root.agents.find(x => x.name === name)
                                root.post("/teams/update", {
                                    id: root.orgId,
                                    leadAgentId: currentIndex === 0 ? "" : (a ? a.id : "")
                                })
                            }
                        }

                        Text { text: "Approvals"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["user", "higher", "auto"]
                            currentIndex: root.indexIn(["user", "higher", "auto"],
                                                       (root.orgTeam && root.orgTeam.approval) || "user")
                            onActivated: root.post("/teams/update", { id: root.orgId, approval: currentText })
                        }

                        Text { text: "Communication"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["isolated", "team", "org", "open"]
                            currentIndex: root.indexIn(["isolated", "team", "org", "open"],
                                                       (root.orgTeam && root.orgTeam.comms) || "team")
                            onActivated: root.post("/teams/update", { id: root.orgId, comms: currentText })
                        }
                    }

                    Text {
                        text: "Team brief"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    FField {
                        Layout.fillWidth: true
                        bindLive: true
                        liveText: root.orgTeam ? (root.orgTeam.brief || "") : ""
                        placeholderText: "How this team works (optional)"
                        font.pixelSize: ArchTheme.sizeSmall
                        onEditingFinished: root.post("/teams/update", {
                            id: root.orgId, brief: text.trim()
                        })
                    }

                    Text {
                        text: "user = you approve every action · higher = up the reporting line, then you · auto = no prompt"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    Text {
                        text: "isolated = only supervisor · team = same team · org = parent/child teams · open = anyone"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    Text {
                        text: "Rules"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    AgentRulesEditor {
                        Layout.fillWidth: true
                        rules: root.orgTeam ? (root.orgTeam.rules || []) : []
                        presets: root.rulePresets
                        onEdited: next => root.post("/teams/update", { id: root.orgId, rules: next })
                    }

                    Item { Layout.fillHeight: true }
                }

                // Agent inspector
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    visible: root.orgAgent !== null

                    Text {
                        text: root.orgAgent ? root.orgAgent.name : ""
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeTitle
                        font.weight: Font.DemiBold
                        color: ArchTheme.textPrimary
                    }
                    Text {
                        text: root.orgAgent
                            ? (root.orgAgent.role + " · " + root.providerLabel(root.orgAgent.provider)
                               + (root.orgAgent.resolvedModel ? " · " + root.orgAgent.resolvedModel : ""))
                            : ""
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 6

                        Text { text: "Rank"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["worker", "lead", "director"]
                            currentIndex: root.orgAgent ? (root.orgAgent.rank || 0) : 0
                            onActivated: root.post("/agents/update", { id: root.orgId, rank: currentIndex })
                        }

                        Text { text: "Reports to"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["none"].concat(root.agents.filter(a => a.id !== root.orgId).map(a => a.name))
                            currentIndex: {
                                if (!root.orgAgent || !root.orgAgent.reportsTo) return 0
                                const names = ["none"].concat(root.agents.filter(a => a.id !== root.orgId).map(a => a.name))
                                return root.indexIn(names, root.agentName(root.orgAgent.reportsTo))
                            }
                            onActivated: {
                                const name = currentText
                                const a = root.agents.find(x => x.name === name)
                                root.post("/agents/update", {
                                    id: root.orgId,
                                    reportsTo: currentIndex === 0 ? "" : (a ? a.id : "")
                                })
                            }
                        }

                        Text { text: "Approvals"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FCombo {
                            Layout.fillWidth: true
                            model: ["inherit", "user", "higher", "auto"]
                            currentIndex: root.indexIn(["inherit", "user", "higher", "auto"],
                                                       (root.orgAgent && root.orgAgent.approval) || "inherit")
                            onActivated: root.post("/agents/update", { id: root.orgId, approval: currentText })
                        }

                        Text { text: "Model"; color: ArchTheme.textSecondary; font.family: ArchTheme.fontFamily; font.pixelSize: ArchTheme.sizeCaption }
                        FField {
                            Layout.fillWidth: true
                            bindLive: true
                            liveText: root.orgAgent ? (root.orgAgent.model || "") : ""
                            placeholderText: "blank = auto"
                            font.pixelSize: ArchTheme.sizeSmall
                            onEditingFinished: root.post("/agents/update", { id: root.orgId, model: text.trim() })
                        }
                    }

                    Text {
                        text: "inherit uses the team's approval policy. higher asks the next person on Reports to, then you."
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    Text {
                        text: "Duties (blank = inferred from role and who reports to whom)"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: root.dutyPresets
                            delegate: Rectangle {
                                required property string modelData
                                readonly property bool on: (root.orgAgent && (root.orgAgent.duties || []).indexOf(modelData) >= 0)
                                readonly property bool inferred: !on && root.orgAgent && (root.orgAgent.resolvedDuties || []).indexOf(modelData) >= 0
                                height: 24
                                width: lab.implicitWidth + 16
                                radius: ArchTheme.radius
                                color: on ? ArchTheme.accentMuted : ArchTheme.layer
                                border.width: 1
                                border.color: on ? ArchTheme.accentLine
                                    : (inferred ? ArchTheme.accent : ArchTheme.border)
                                Text {
                                    id: lab
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: on || inferred ? ArchTheme.accent : ArchTheme.textSecondary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const cur = ((root.orgAgent && root.orgAgent.duties) || []).slice()
                                        const i = cur.indexOf(modelData)
                                        if (i >= 0)
                                            cur.splice(i, 1)
                                        else
                                            cur.push(modelData)
                                        root.post("/agents/update", { id: root.orgId, duties: cur })
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "Standing instructions"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    FField {
                        Layout.fillWidth: true
                        bindLive: true
                        liveText: root.orgAgent ? (root.orgAgent.brief || "") : ""
                        placeholderText: "Anything this agent should always do"
                        font.pixelSize: ArchTheme.sizeSmall
                        onEditingFinished: root.post("/agents/update", {
                            id: root.orgId, brief: text.trim()
                        })
                    }

                    Text {
                        text: "Personal rules (added on top of team rules)"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    AgentRulesEditor {
                        Layout.fillWidth: true
                        rules: root.orgAgent ? (root.orgAgent.rules || []) : []
                        presets: root.rulePresets
                        onEdited: next => root.post("/agents/update", { id: root.orgId, rules: next })
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        FField {
                            id: relayText
                            Layout.fillWidth: true
                            placeholderText: "Send a message as this agent to…"
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                        FCombo {
                            id: relayTo
                            Layout.preferredWidth: 140
                            model: ["lead"].concat(root.agents.filter(a => a.id !== root.orgId).map(a => a.name))
                        }
                        FBtn {
                            text: "Send"
                            enabled: relayText.text.trim() !== "" && root.orgId !== ""
                            onClicked: {
                                root.post("/agents/message", {
                                    from: root.orgId,
                                    to: relayTo.currentText,
                                    text: relayText.text.trim()
                                })
                                relayText.text = ""
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                Text {
                    visible: root.orgTeam === null && root.orgAgent === null
                    anchors.centerIn: parent
                    width: parent.width - 40
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: "Select a team or agent on the left. Reports-to and duties are how the org actually runs — not a fixed script."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textSecondary
                }
            }
        }

        // ── Activity tab ────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.daemonRunning && root.mode === "centre" && root.tab === "activity"
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Live activity"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }
                FBtn {
                    text: "Clear"
                    implicitHeight: 26
                    onClicked: root.post("/activity/clear", ({}))
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                model: root.activity
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view ? ListView.view.width - 12 : 0
                    height: Math.max(30, line.implicitHeight + 14)
                    radius: ArchTheme.radius
                    color: ArchTheme.layer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 7
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: modelData.at
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: ArchTheme.textTertiary
                        }
                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: modelData.agent || modelData.kind
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: modelData.kind === "error" ? ArchTheme.danger : ArchTheme.accent
                            Layout.preferredWidth: 78
                            elide: Text.ElideRight
                        }
                        Text {
                            id: line
                            Layout.fillWidth: true
                            text: modelData.text
                            wrapMode: Text.WordWrap
                            maximumLineCount: 6
                            elide: Text.ElideRight
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeCaption
                            color: ArchTheme.textSecondary
                        }
                    }
                }
            }
        }

        // ── Providers tab ───────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.daemonRunning && root.mode === "centre" && root.tab === "providers"
            spacing: 8

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Keys and sign-in sessions stay in ~/.config/arch-shell/agent/providers.json "
                      + "(owner-only). Sign in uses that vendor's official app so Google AI Pro, "
                      + "ChatGPT, Claude, and Copilot plans apply."
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: ArchTheme.textTertiary
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: providerCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }

                ColumnLayout {
                    id: providerCol
                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.providerIds()

                        delegate: FCard {
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: providerCard.implicitHeight + 20

                            ColumnLayout {
                                id: providerCard
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: root.providerLabel(modelData)
                                            font.family: ArchTheme.fontFamily
                                            font.pixelSize: ArchTheme.sizeSmall
                                            font.weight: Font.DemiBold
                                            color: ArchTheme.textPrimary
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            text: root.providerStatusText(modelData)
                                            font.family: ArchTheme.fontFamily
                                            font.pixelSize: ArchTheme.sizeCaption
                                            color: {
                                                const p = root.providerInfo(modelData)
                                                if (p.loginJob && p.loginJob.status === "error")
                                                    return ArchTheme.danger
                                                if (p.loginJob && p.loginJob.status === "running")
                                                    return ArchTheme.accent
                                                return root.providerConfigured(modelData)
                                                    ? ArchTheme.success : ArchTheme.textTertiary
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    visible: {
                                        const p = root.providerInfo(modelData)
                                        const known = root.knownProviders[modelData] || {}
                                        return !!(p.loginHint || known.loginHint || p.keyHint || known.keyHint)
                                    }
                                    text: {
                                        const p = root.providerInfo(modelData)
                                        const known = root.knownProviders[modelData] || {}
                                        const login = p.loginHint || known.loginHint || ""
                                        const key = p.keyHint || known.keyHint || ""
                                        return [login, key].filter(t => t).join("  ·  ")
                                    }
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: ArchTheme.textTertiary
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    FField {
                                        id: keyField
                                        Layout.fillWidth: true
                                        placeholderText: {
                                            const p = root.providerInfo(modelData)
                                            const known = root.knownProviders[modelData] || {}
                                            return p.keyHint || known.keyHint || "Paste API key"
                                        }
                                        echoMode: TextInput.Password
                                        font.pixelSize: ArchTheme.sizeSmall
                                    }
                                    FBtn {
                                        text: "Save key"
                                        highlighted: true
                                        enabled: keyField.text.trim() !== ""
                                            || modelData === "ollama"
                                        onClicked: {
                                            root.post("/providers",
                                                      { name: modelData, key: keyField.text.trim() })
                                            keyField.text = ""
                                        }
                                    }
                                    FBtn {
                                        text: {
                                            const p = root.providerInfo(modelData)
                                            return (p.loginJob && p.loginJob.status === "running")
                                                ? "Waiting…" : "Sign in"
                                        }
                                        visible: {
                                            const p = root.providerInfo(modelData)
                                            const known = root.knownProviders[modelData] || {}
                                            return !!(p.supportsLogin || known.supportsLogin)
                                        }
                                        enabled: {
                                            const p = root.providerInfo(modelData)
                                            return !(p.loginJob && p.loginJob.status === "running")
                                        }
                                        onClicked: root.post("/providers/login",
                                                             { name: modelData, action: "start" })
                                    }
                                    FBtn {
                                        text: "Use existing login"
                                        visible: {
                                            const p = root.providerInfo(modelData)
                                            return !!(p.supportsLogin && p.cli && p.cli.available
                                                      && p.mode !== "login")
                                        }
                                        onClicked: root.post("/providers/login",
                                                             { name: modelData, action: "import" })
                                    }
                                    FBtn {
                                        text: "Remove"
                                        danger: true
                                        visible: root.providerConfigured(modelData)
                                            && modelData !== "ollama"
                                        onClicked: root.post("/providers/delete", { name: modelData })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Chat ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.daemonRunning && root.mode === "chat"
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "API"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }
                FCombo {
                    id: chatProviderCombo
                    Layout.preferredWidth: 160
                    model: root.chatProviderIds
                    onActivated: {
                        root.chatProvider = currentText
                        root.chatSavedModel = ""
                        root.loadChatModels(currentText)
                        root.post("/chat/setup", { provider: currentText })
                    }
                }
                Text {
                    text: "Model"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }
                FCombo {
                    id: chatModelCombo
                    Layout.fillWidth: true
                    model: root.chatModels.length ? root.chatModels
                         : root.providerModels(root.chatProvider)
                    onActivated: {
                        root.chatSavedModel = currentText
                        root.post("/chat/setup", {
                            provider: chatProviderCombo.currentText || root.chatProvider,
                            model: currentText
                        })
                    }
                }
                FBtn {
                    text: "Clear"
                    implicitHeight: 28
                    enabled: root.chatMessages.length > 0 && root.chatBusy === ""
                    onClicked: {
                        root.post("/chat/clear", ({}))
                        root.chatMessages = []
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: !root.providerConfigured(chatProviderCombo.currentText || root.chatProvider)
                text: "Save an API key or sign in on the Teams → Providers tab first."
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: ArchTheme.warning
            }

            ListView {
                id: chatList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: root.chatMessages
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }
                onCountChanged: Qt.callLater(function() {
                    if (chatList.count > 0)
                        chatList.positionViewAtEnd()
                })

                delegate: Item {
                    required property var modelData
                    width: ListView.view ? ListView.view.width - 8 : 0
                    height: chatBubble.implicitHeight

                    RowLayout {
                        id: chatBubble
                        width: parent.width
                        layoutDirection: modelData.role === "user" ? Qt.RightToLeft : Qt.LeftToRight
                        spacing: 0

                        Rectangle {
                            Layout.maximumWidth: chatBubble.width * 0.82
                            Layout.minimumWidth: 80
                            implicitWidth: chatMsgCol.implicitWidth + 24
                            implicitHeight: chatMsgCol.implicitHeight + 20
                            radius: ArchTheme.radiusCard
                            color: modelData.role === "user" ? ArchTheme.accentMuted : ArchTheme.layer
                            border.width: 1
                            border.color: modelData.role === "user" ? ArchTheme.accentLine : ArchTheme.border

                            ColumnLayout {
                                id: chatMsgCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 4
                                width: Math.min(chatBubble.width * 0.82 - 24, 640)

                                Text {
                                    text: (modelData.role === "user" ? "You" : "Assistant")
                                          + (modelData.at ? " · " + modelData.at : "")
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeCaption
                                    color: modelData.role === "user" ? ArchTheme.accent : ArchTheme.textTertiary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.content || ""
                                    wrapMode: Text.Wrap
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    color: ArchTheme.textPrimary
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                Text {
                    visible: root.chatMessages.length === 0 && root.chatBusy === ""
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Chat with a model that can read and write files and run commands on this computer. Pick an API and model above."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textTertiary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                FField {
                    id: chatInput
                    Layout.fillWidth: true
                    placeholderText: root.chatBusy !== ""
                        ? "Waiting for the model…"
                        : "Message…"
                    enabled: root.chatBusy === ""
                    font.pixelSize: ArchTheme.sizeSmall
                    onAccepted: root.sendChat()
                }
                FBtn {
                    text: root.chatBusy !== "" ? "…" : "Send"
                    highlighted: true
                    implicitHeight: 36
                    enabled: chatInput.text.trim() !== "" && root.chatBusy === ""
                    onClicked: root.sendChat()
                }
            }
        }
    }
}
