pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property ShellScreen screen
    readonly property var monitor: Hypr.monitorFor(screen)
    readonly property string project: (monitor?.activeWorkspace?.name ?? "").replace(/-(code|opencode|lazygit)$/, "")
    readonly property var gitWorkspace: Hypr.workspaces.values.find(w => w.name === `special:${project}-lazygit` || w.name === `${project}-lazygit`)
    readonly property bool active: !!gitWorkspace && (monitor?.lastIpcObject.specialWorkspace?.name === gitWorkspace.name || monitor?.activeWorkspace?.name === gitWorkspace.name)

    visible: !!gitWorkspace
    implicitWidth: content.implicitWidth + Tokens.padding.medium * 2
    implicitHeight: Tokens.sizes.bar.innerWidth
    radius: Tokens.rounding.full
    color: active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: "account_tree"
            color: root.active ? Colours.palette.m3onPrimary : Colours.palette.m3primary
        }

        StyledText {
            text: "Git"
            color: root.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
        }
    }

    StateLayer {
        id: button

        radius: root.radius
        onClicked: {
            const name = root.gitWorkspace.name;
            if (name.startsWith("special:"))
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.workspace.toggle_special(${JSON.stringify(name.slice(8))})` : `togglespecialworkspace ${name.slice(8)}`);
            else
                Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${JSON.stringify(`name:${name}`)} })` : `workspace name:${name}`);
        }
    }

    ToolTip.visible: button.containsMouse
    ToolTip.text: qsTr("Lazygit — %1\nGraphe Git et push").arg(project)
    ToolTip.delay: 400
}
