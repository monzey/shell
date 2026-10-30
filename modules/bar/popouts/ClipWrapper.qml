pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.modules.bar.popouts // Need to import this module so the Wrapper type is the same as others

Item {
    id: root

    required property ShellScreen screen
    required property real borderThickness

    readonly property alias content: content
    property real offsetScale: content.isDetached || content.hasCurrent ? 0 : 1

    visible: width > 0 && height > 0
    clip: true

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight * (1 - offsetScale)

    x: content.isDetached ? (parent.width - content.nonAnimWidth) / 2 : Math.max(0, Math.min(parent.width - content.nonAnimWidth, content.currentCenter - borderThickness - content.nonAnimWidth / 2))
    y: content.isDetached ? (parent.height - content.nonAnimHeight) / 2 : 0

    Behavior on offsetScale {
        Anim {}
    }

    Behavior on x {
        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Behavior on y {
        enabled: root.offsetScale < 1

        Anim {
            duration: content.animLength
            easing: content.animCurve
        }
    }

    Wrapper {
        id: content

        screen: root.screen
        offsetScale: root.offsetScale

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: (-implicitHeight - 5) * root.offsetScale
    }
}
