import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root
    property var pluginApi: null

    // Create one panel per screen. Variants binds to Quickshell.screens.
    property var panelComponent: Qt.createComponent("RKTPanel.qml")

    Connections {
        target: Quickshell
        function onScreensChanged() {
            rebuildPanels()
        }
    }

    Component.onCompleted: rebuildPanels()

    function rebuildPanels() {
        if (panelComponent.status !== Component.Ready) {
            Logger.e("rkt-dashboard", "RKTPanel component not ready: " + panelComponent.errorString())
            return
        }
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            panelComponent.createObject(root, {
                "screen": Quickshell.screens[i],
                "pluginApi": root.pluginApi
            })
        }
    }
}
