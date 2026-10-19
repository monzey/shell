import QtQuick

Item {
    id: root

    required property var lock

    implicitWidth: center.centerWidth
    implicitHeight: center.reservedHeight

    Center {
        id: center

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: centerWidth

        lock: root.lock
    }
}
