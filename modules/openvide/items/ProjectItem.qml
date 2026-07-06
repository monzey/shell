import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.openvide.services

Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    implicitHeight: Tokens.sizes.launcher.itemHeight
    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: Projects.accept(root.modelData, root.screenState)
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        MaterialIcon {
            id: icon

            text: root.modelData?.icon ?? "folder_code"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.large
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: icon.verticalCenter
            implicitHeight: name.implicitHeight + desc.implicitHeight

            StyledText {
                id: name

                text: root.modelData?.label ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideMiddle
                width: parent.width
            }

            StyledText {
                id: desc

                text: root.modelData?.kind ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
                width: parent.width
                anchors.top: name.bottom
            }
        }
    }
}
