import "center"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var lock
    readonly property real centerScale: Math.min(1, (lock.screen?.height ?? 1440) / 1440)
    readonly property int centerWidth: Tokens.sizes.lock.centerWidth * centerScale
    // Fixed space kept for the auth state message so the card doesn't need to resize
    readonly property int messageReserve: 64 * centerScale
    readonly property int reservedHeight: clock.implicitHeight + clock.Layout.topMargin + password.implicitHeight + spacing * 2 + messageReserve

    spacing: Tokens.spacing.largeIncreased

    Clock {
        id: clock

        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.large
        centerScale: root.centerScale
    }

    PasswordInput {
        id: password

        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        lock: root.lock
    }

    StateMessage {
        Layout.fillWidth: true
        pam: root.lock.pam
    }
}
