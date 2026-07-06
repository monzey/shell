pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.openvide.items
import qs.modules.openvide.services

Item {
    id: root

    required property ScreenState screenState
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property alias currentItem: list.currentItem
    readonly property alias count: list.count

    function incrementCurrentIndex(): void {
        list.incrementCurrentIndex();
    }

    function decrementCurrentIndex(): void {
        list.decrementCurrentIndex();
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    clip: true
    implicitWidth: Tokens.sizes.launcher.itemWidth
    implicitHeight: Math.min(maxHeight, list.count > 0 ? list.implicitHeight : empty.implicitHeight)

    StyledListView {
        id: list

        anchors.fill: parent
        model: Projects.showList ? Projects.filteredItems : []
        spacing: Tokens.spacing.small
        orientation: Qt.Vertical
        implicitHeight: (Tokens.sizes.launcher.itemHeight + spacing) * Math.min(Config.launcher.maxShown, count) - spacing

        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        highlightRangeMode: ListView.ApplyRange
        highlightFollowsCurrentItem: false
        highlight: StyledRect {
            radius: Tokens.rounding.large
            color: Colours.palette.m3onSurface
            opacity: 0.08
            y: list.currentItem?.y ?? 0
            implicitWidth: list.width
            implicitHeight: list.currentItem?.implicitHeight ?? 0

            Behavior on y {
                Anim {}
            }
        }

        delegate: ProjectItem {
            screenState: root.screenState
        }

        onModelChanged: currentIndex = 0

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }
    }

    Row {
        id: empty

        opacity: Projects.showList && root.count === 0 ? 1 : 0
        scale: Projects.showList && root.count === 0 ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large
        anchors.centerIn: parent

        MaterialIcon {
            text: "workspaces"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: qsTr("No projects found")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: qsTr("Try another search")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }
}
