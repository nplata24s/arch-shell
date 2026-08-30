import QtQuick
import QtQuick.Layouts
import "theme"

// Renders agent/chat prose as markdown + LaTeX (Qt RichText).
Item {
    id: root

    property string source: ""
    property color textColor: ArchTheme.textPrimary
    property color mutedColor: ArchTheme.textSecondary
    property color accentColor: ArchTheme.accent
    property int pixelSize: ArchTheme.sizeSmall
    property int maximumLineCount: 0
    property string fontFamily: ArchTheme.fontFamily

    implicitWidth: body.implicitWidth
    implicitHeight: body.implicitHeight

    Text {
        id: body
        width: parent.width
        textFormat: Text.RichText
        text: root._html
        wrapMode: Text.Wrap
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        linkColor: root.accentColor
        maximumLineCount: root.maximumLineCount
        elide: root.maximumLineCount > 0 ? Text.ElideRight : Text.ElideNone
        onLinkActivated: function(link) {
            Qt.openUrlExternally(link)
        }
    }

    readonly property string _html: root.render(root.source)

    function esc(s) {
        return String(s || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function render(raw) {
        if (!raw)
            return ""
        const parts = []
        let i = 0
        const s = String(raw)
        while (i < s.length) {
            const fence = s.indexOf("```", i)
            const dollar2 = s.indexOf("$$", i)
            const brack = s.indexOf("\\[", i)
            const nexts = [fence, dollar2, brack].filter(n => n >= 0)
            if (!nexts.length) {
                parts.push(mdAndInline(s.slice(i)))
                break
            }
            const n = Math.min.apply(null, nexts)
            if (n > i)
                parts.push(mdAndInline(s.slice(i, n)))
            if (n === fence) {
                const end = s.indexOf("```", n + 3)
                if (end < 0) {
                    parts.push(mdAndInline(s.slice(n)))
                    break
                }
                let body = s.slice(n + 3, end)
                const nl = body.indexOf("\n")
                if (nl >= 0 && /^[a-zA-Z0-9_+-]+$/.test(body.slice(0, nl).trim()))
                    body = body.slice(nl + 1)
                parts.push(codeBlock(body.replace(/\s+$/, "")))
                i = end + 3
            } else if (n === dollar2) {
                const end = s.indexOf("$$", n + 2)
                if (end < 0) {
                    parts.push(mdAndInline(s.slice(n)))
                    break
                }
                parts.push(mathHtml(s.slice(n + 2, end), true))
                i = end + 2
            } else {
                const end = s.indexOf("\\]", n + 2)
                if (end < 0) {
                    parts.push(mdAndInline(s.slice(n)))
                    break
                }
                parts.push(mathHtml(s.slice(n + 2, end), true))
                i = end + 2
            }
        }
        return "<style>a{color:" + root.accentColor + ";}</style>" + parts.join("")
    }

    function codeBlock(body) {
        return "<p><pre><font color=\"" + root.mutedColor + "\" face=\""
            + root.fontFamily + "\">" + esc(body) + "</font></pre></p>"
    }

    function mdAndInline(chunk) {
        const bits = []
        let i = 0
        const s = String(chunk)
        while (i < s.length) {
            const inline = nextInlineMath(s, i)
            const code = s.indexOf("`", i)
            const cand = []
            if (inline >= 0)
                cand.push(inline)
            if (code >= 0)
                cand.push(code)
            if (!cand.length) {
                bits.push(markdown(s.slice(i)))
                break
            }
            const n = Math.min.apply(null, cand)
            if (n > i)
                bits.push(markdown(s.slice(i, n)))
            if (n === code && (inline < 0 || code <= inline)) {
                const end = s.indexOf("`", n + 1)
                if (end < 0) {
                    bits.push(markdown(s.slice(n)))
                    break
                }
                bits.push("<font color=\"" + root.mutedColor + "\"><code>"
                    + esc(s.slice(n + 1, end)) + "</code></font>")
                i = end + 1
            } else {
                const taken = takeInlineMath(s, n)
                bits.push(mathHtml(taken.body, false))
                i = taken.next
            }
        }
        return bits.join("")
    }

    function nextInlineMath(s, from) {
        const a = s.indexOf("$", from)
        const b = s.indexOf("\\(", from)
        if (a < 0)
            return b
        if (b < 0)
            return a
        return Math.min(a, b)
    }

    function takeInlineMath(s, n) {
        if (s.substr(n, 2) === "\\(") {
            const end = s.indexOf("\\)", n + 2)
            if (end < 0)
                return { body: s.slice(n + 2), next: s.length }
            return { body: s.slice(n + 2, end), next: end + 2 }
        }
        if (/^\$\d/.test(s.slice(n)))
            return { body: "", next: n + 1 }
        const end = s.indexOf("$", n + 1)
        if (end < 0)
            return { body: "", next: n + 1 }
        return { body: s.slice(n + 1, end), next: end + 1 }
    }

    function markdown(text) {
        let t = esc(text)
        t = t.replace(/^######\s+(.+)$/gm, "<b>$1</b>")
        t = t.replace(/^#####\s+(.+)$/gm, "<b>$1</b>")
        t = t.replace(/^####\s+(.+)$/gm, "<b>$1</b>")
        t = t.replace(/^###\s+(.+)$/gm, "<font size=\"+1\"><b>$1</b></font>")
        t = t.replace(/^##\s+(.+)$/gm, "<font size=\"+1\"><b>$1</b></font>")
        t = t.replace(/^#\s+(.+)$/gm, "<font size=\"+2\"><b>$1</b></font>")
        t = t.replace(/^&gt;\s+(.+)$/gm, "<i>$1</i>")
        t = t.replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g,
                      "<a href=\"$2\">$1</a>")
        t = t.replace(/\*\*\*(.+?)\*\*\*/g, "<b><i>$1</i></b>")
        t = t.replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")
        t = t.replace(/__(.+?)__/g, "<b>$1</b>")
        t = t.replace(/\*(.+?)\*/g, "<i>$1</i>")
        // Don't treat snake_case as italic; require surrounding spaces or edges.
        t = t.replace(/(^|[\s(])_([^_\s][^_]*)_(?=[\s).,!?:]|$)/g, "$1<i>$2</i>")
        t = t.replace(/~~(.+?)~~/g, "<s>$1</s>")
        t = t.replace(/^[\-\*]\s+(.+)$/gm, "• $1")
        t = t.replace(/^\d+\.\s+(.+)$/gm, "$1")
        t = t.replace(/\n\n+/g, "<br/><br/>")
        t = t.replace(/\n/g, "<br/>")
        return t
    }

    function mathHtml(src, display) {
        if (src === "" && arguments.length)
            return display ? "" : "$"
        const inner = "<i>" + latexToHtml(src) + "</i>"
        if (display)
            return "<p align=\"center\"><font size=\"+1\">" + inner + "</font></p>"
        return inner
    }

    function latexToHtml(src) {
        let s = String(src || "").replace(/\s+/g, " ").trim()
        const cmds = {
            "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ",
            "\\epsilon": "ε", "\\varepsilon": "ε", "\\zeta": "ζ", "\\eta": "η",
            "\\theta": "θ", "\\iota": "ι", "\\kappa": "κ", "\\lambda": "λ",
            "\\mu": "μ", "\\nu": "ν", "\\xi": "ξ", "\\pi": "π", "\\rho": "ρ",
            "\\sigma": "σ", "\\tau": "τ", "\\upsilon": "υ", "\\phi": "φ",
            "\\varphi": "φ", "\\chi": "χ", "\\psi": "ψ", "\\omega": "ω",
            "\\Gamma": "Γ", "\\Delta": "Δ", "\\Theta": "Θ", "\\Lambda": "Λ",
            "\\Xi": "Ξ", "\\Pi": "Π", "\\Sigma": "Σ", "\\Phi": "Φ",
            "\\Psi": "Ψ", "\\Omega": "Ω",
            "\\infty": "∞", "\\pm": "±", "\\mp": "∓", "\\times": "×",
            "\\cdot": "·", "\\div": "÷", "\\leq": "≤", "\\geq": "≥",
            "\\neq": "≠", "\\approx": "≈", "\\equiv": "≡", "\\sim": "∼",
            "\\propto": "∝", "\\in": "∈", "\\notin": "∉", "\\subset": "⊂",
            "\\subseteq": "⊆", "\\cup": "∪", "\\cap": "∩", "\\emptyset": "∅",
            "\\forall": "∀", "\\exists": "∃", "\\nabla": "∇", "\\partial": "∂",
            "\\sum": "∑", "\\prod": "∏", "\\int": "∫", "\\oint": "∮",
            "\\rightarrow": "→", "\\leftarrow": "←", "\\leftrightarrow": "↔",
            "\\Rightarrow": "⇒", "\\Leftarrow": "⇐", "\\to": "→",
            "\\cdotp": "·", "\\dots": "…", "\\ldots": "…", "\\cdots": "⋯",
            "\\hbar": "ℏ", "\\ell": "ℓ", "\\Re": "ℜ", "\\Im": "ℑ",
            "\\mathbb{R}": "ℝ", "\\mathbb{N}": "ℕ", "\\mathbb{Z}": "ℤ",
            "\\mathbb{Q}": "ℚ", "\\mathbb{C}": "ℂ",
            "\\langle": "⟨", "\\rangle": "⟩",
            "\\left": "", "\\right": "", "\\,": " ", "\\;": " ", "\\!": "",
            "\\quad": "  ", "\\qquad": "    ",
            "\\cdot": "·"
        }
        Object.keys(cmds).forEach(function(k) {
            s = s.split(k).join(cmds[k])
        })
        s = s.replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, "($1)/($2)")
        s = s.replace(/\\dfrac\{([^{}]+)\}\{([^{}]+)\}/g, "($1)/($2)")
        s = s.replace(/\\sqrt\{([^{}]+)\}/g, "√($1)")
        s = s.replace(/\\sqrt\[([^\]]+)\]\{([^{}]+)\}/g, "√[$1]($2)")
        s = s.replace(/\\overline\{([^{}]+)\}/g, "$1̅")
        s = s.replace(/\\vec\{([^{}]+)\}/g, "$1⃗")
        s = s.replace(/\\hat\{([^{}]+)\}/g, "$1̂")
        s = s.replace(/\\bar\{([^{}]+)\}/g, "$1̄")
        s = s.replace(/\\mathbf\{([^{}]+)\}/g, "<b>$1</b>")
        s = s.replace(/\\textbf\{([^{}]+)\}/g, "<b>$1</b>")
        s = s.replace(/\\mathrm\{([^{}]+)\}/g, "$1")
        s = s.replace(/\\text\{([^{}]+)\}/g, "$1")
        s = s.replace(/\\mathit\{([^{}]+)\}/g, "<i>$1</i>")
        s = s.replace(/\\emph\{([^{}]+)\}/g, "<i>$1</i>")
        // Super/sub: x^{2} x_i x^2
        s = s.replace(/\^\{([^{}]+)\}/g, "<sup>$1</sup>")
        s = s.replace(/_\{([^{}]+)\}/g, "<sub>$1</sub>")
        s = s.replace(/\^([A-Za-z0-9+\-])/g, "<sup>$1</sup>")
        s = s.replace(/_([A-Za-z0-9+\-])/g, "<sub>$1</sub>")
        s = s.replace(/\\([a-zA-Z]+)/g, "$1")
        s = s.replace(/[{}]/g, "")
        return s
    }
}
