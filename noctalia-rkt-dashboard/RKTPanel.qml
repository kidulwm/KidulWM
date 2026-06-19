import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: panel
    required property var screen
    property var pluginApi: null

    // This is the mission-control layer: behind normal windows, visible through gaps.
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "rkt-dashboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    screen: panel.screen
    color: "transparent"

    implicitWidth: 260
    implicitHeight: screen?.height ?? 1080

    anchors {
        top: true
        bottom: true
        left: true
        right: false
    }

    // Click-through the empty shell area; the mask is built around real widgets below.
    mask: Region {
        id: clickMask
        regions: []
    }

    // Live data model
    property real cpuVal: 0.0
    property real memUsed: 0.0
    property real memTotal: 0.0
    property real load1: 0.0
    property real netUp: 0.0
    property real netDown: 0.0
    property var connectionsList: []

    Process {
        id: statsProc
        command: ["rkt-stats"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text)
                    panel.cpuVal = data.cpu || 0
                    panel.memUsed = data.mem_used || 0
                    panel.memTotal = data.mem_total || 0
                    panel.load1 = (data.load && data.load[0]) || 0
                    panel.netUp = data.net_up || 0
                    panel.netDown = data.net_down || 0
                    panel.connectionsList = data.connections || []
                } catch (e) {
                    Logger.w("rkt-dashboard", "Failed to parse rkt-stats output: " + e)
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: statsProc.running = true
    }

    // Launcher toggle process
    Process {
        id: launcherProc
        command: ["qs", "-c", "noctalia-shell", "ipc", "call", "launcher", "toggle"]
        running: false
    }

    property int lastLauncherToggle: 0
    function maybeToggleLauncher() {
        var now = Date.now()
        if (now - lastLauncherToggle > 1500) {
            lastLauncherToggle = now
            launcherProc.running = true
        }
    }

    // Main layout
    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        // Logo / control-center trigger
        MouseArea {
            width: parent.width
            height: 80
            hoverEnabled: true
            onEntered: maybeToggleLauncher()
            onClicked: maybeToggleLauncher()

            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "RKT"
                font.pixelSize: 42
                font.bold: true
                color: "#c69aff"
                style: Text.Outline
                styleColor: Qt.rgba(0.4, 0.15, 0.7, 0.4)
            }
        }

        // System vitals
        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "CPU " + panel.cpuVal.toFixed(1) + "%"
                font.pixelSize: 18
                font.bold: true
                color: "#c69aff"
                width: parent.width
                wrapMode: Text.Wrap
            }
            Text {
                text: "MEM " + panel.memUsed.toFixed(1) + " / " + panel.memTotal.toFixed(1) + " GB"
                font.pixelSize: 18
                font.bold: true
                color: "#75c5ff"
                width: parent.width
                wrapMode: Text.Wrap
            }
            Text {
                text: "LD " + panel.load1.toFixed(2)
                font.pixelSize: 18
                font.bold: true
                color: "#9dffee"
                width: parent.width
                wrapMode: Text.Wrap
            }
        }

        // Network
        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "Network"
                font.pixelSize: 16
                font.bold: true
                color: "#9dffee"
            }
            Text {
                text: "↑ " + panel.netUp.toFixed(1) + " KB/s"
                font.pixelSize: 14
                color: "#75c5ff"
                width: parent.width
                wrapMode: Text.Wrap
            }
            Text {
                text: "↓ " + panel.netDown.toFixed(1) + " KB/s"
                font.pixelSize: 14
                color: "#75c5ff"
                width: parent.width
                wrapMode: Text.Wrap
            }

            // Connection river
            Column {
                width: parent.width
                spacing: 2
                visible: panel.connectionsList.length > 0

                Repeater {
                    model: panel.connectionsList

                    Text {
                        required property var modelData
                        text: modelData.local + " → " + modelData.remote
                        font.pixelSize: 11
                        color: "#d6e6ff"
                        width: parent.width
                        wrapMode: Text.Wrap
                        opacity: 0.85
                    }
                }
            }
        }

        // News river placeholder
        Column {
            width: parent.width
            spacing: 6
            visible: false // wired up later

            Text {
                text: "News River"
                font.pixelSize: 16
                font.bold: true
                color: "#c69aff"
            }
            Text {
                text: "No updates yet."
                font.pixelSize: 13
                color: "#d6e6ff"
                width: parent.width
                wrapMode: Text.Wrap
            }
        }

        Item { Layout.fillHeight: true }
    }

    Component.onCompleted: {
        // Build mask regions for interactive children so the empty panel is click-through.
        rebuildMask()
    }

    function rebuildMask() {
        var regs = []
        // Logo region
        regs.push({x: 14, y: 14, width: width - 28, height: 80})
        // Top of vitals/network region
        regs.push({x: 14, y: 108, width: width - 28, height: 260})
        // News region lower down
        regs.push({x: 14, y: height - 120, width: width - 28, height: 100})
        clickMask.regions = regs
    }
}
