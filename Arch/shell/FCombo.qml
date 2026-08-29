import QtQuick
import QtQuick.Controls
import "theme"

ComboBox {
    id: root

    font.family: ArchTheme.fontFamily
    font.pixelSize: ArchTheme.sizeSmall
    implicitHeight: 32
    implicitWidth: 130

    background: Rectangle {
        radius: ArchTheme.radiusCard
        color: root.pressed ? ArchTheme.pressed
             : (root.hovered ? ArchTheme.layerHover : ArchTheme.layer)
        border.width: 1
        border.color: root.activeFocus ? ArchTheme.accent : ArchTheme.border
    }

    contentItem: Text {
        leftPadding: 12
        rightPadding: 28
        text: root.displayText
        font: root.font
        color: ArchTheme.textPrimary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - 10
        y: (root.height - height) / 2
        text: Icons.chevronDown
        font.family: ArchTheme.fontFamily
        font.pixelSize: 12
        color: ArchTheme.textSecondary
    }

    delegate: ItemDelegate {
        id: entry
        width: root.width
        height: 32
        highlighted: root.highlightedIndex === entry.rowIndex

        readonly property int rowIndex: typeof index !== "undefined" ? index : -1
        readonly property string rowText: {
            if (typeof modelData === "string") return modelData
            if (modelData && root.textRole) return String(modelData[root.textRole])
            return modelData !== undefined ? String(modelData) : ""
        }

        background: Rectangle {
            radius: ArchTheme.radius
            color: entry.highlighted ? ArchTheme.accentMuted
                 : (entry.hovered ? ArchTheme.layerHover : "transparent")
        }

        contentItem: Text {
            leftPadding: 8
            text: entry.rowText
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
            color: ArchTheme.textPrimary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        implicitHeight: Math.min(listView.contentHeight + 8, 220)
        padding: 4

        contentItem: ListView {
            id: listView
            clip: true
            model: root.delegateModel
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }
        }

        background: Rectangle {
            radius: ArchTheme.radiusCard
            color: ArchTheme.acrylic
            border.width: 1
            border.color: ArchTheme.border
        }
    }
}
