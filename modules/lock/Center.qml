import "center"
import QtQuick
import Caelestia.Config

Item {
    id: root

    required property var lock
    readonly property real centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440)
    readonly property int centerWidth: Tokens.sizes.lock.centerWidth * centerScale
    readonly property int reservedHeight: password.implicitHeight

    implicitWidth: centerWidth
    implicitHeight: reservedHeight

    PasswordInput {
        id: password

        anchors.centerIn: parent
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    StateMessage {
        anchors.top: password.bottom
        anchors.topMargin: Tokens.spacing.largeIncreased
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.centerWidth

        pam: root.lock.pam
    }
}
