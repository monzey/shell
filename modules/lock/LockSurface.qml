pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import Caelestia.Config
import qs.components

WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running

    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name

    color: "transparent"

    Connections {
        function onUnlock(): void {
            unlockAnim.start();
        }

        target: root.lock
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            Anim {
                target: lockContent
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
            Anim {
                target: lockContent
                property: "scale"
                to: 0.96
            }
            Anim {
                target: background
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
        }
        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    ParallelAnimation {
        id: initAnim

        running: true

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        Anim {
            target: lockContent
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        Anim {
            target: lockContent
            property: "scale"
            to: 1
            type: Anim.FastSpatial
        }
    }

    ScreencopyView {
        id: background

        anchors.fill: parent
        captureSource: root.screen
        opacity: 0

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
        }
    }

    Item {
        id: lockContent

        anchors.centerIn: parent
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        visible: Config.lock.enabled
        opacity: 0
        scale: 0.96

        Content {
            id: content

            anchors.centerIn: parent
            lock: root
        }
    }
}
