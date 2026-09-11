import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A face for the sidecar-display service. The service does the work on its own;
// this only reports what it is doing and offers a manual override.
BarWidget {
  id: root
  moduleName: "io.github.felipecpaiva.omasidecart"

  // Not called `state`: Item already has one, and shadowing it breaks the
  // property in ways that do not announce themselves.
  property string sidecarState: "away"

  // Resolved through a shell so ~/.local/bin is found without assuming the
  // compositor's PATH includes it.
  readonly property string cmd: "$HOME/.local/bin/sidecar-display"

  // Nothing plugged in means nothing to say, so take no room on the bar.
  visible: sidecarState !== "away"
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function toggle() {
    if (toggleProc.running) return
    toggleProc.command = ["sh", "-c", root.cmd + (root.sidecarState === "streaming" ? " down" : " up")]
    toggleProc.running = true
  }

  Process {
    id: stateProc
    command: ["sh", "-c", root.cmd + " state"]
    stdout: StdioCollector {
      onStreamFinished: {
        var value = String(text).trim()
        root.sidecarState = value === "" ? "away" : value
      }
    }
  }

  Process {
    id: toggleProc
    onExited: root.refresh()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf10a"
    opacity: root.sidecarState === "streaming" ? 1 : 0.5
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.sidecarState === "streaming"
      ? "Tablet second screen: streaming. Click to stop."
      : "Tablet connected, not streaming. Click to start."
    onPressed: root.toggle()
  }
}
