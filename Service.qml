import QtQuick
import Quickshell
import Quickshell.Io

// One instance for the whole shell (a bar widget exists per monitor, and each
// would otherwise send its own copy of every wicket alert). Runs stumpbar.py,
// keeps the latest state it printed, and forwards commands to it on stdin.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool ready: false
  property string label: ""
  property string error: ""
  property string updated: ""
  property string pinnedId: ""
  property bool internationalOnly: false
  property bool wicketAlerts: true
  property var sections: []

  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("stumpbar.py")).replace(/^file:\/\//, ""))

  function apply(line) {
    var state
    try { state = JSON.parse(line) } catch (e) { return }
    label = String(state.label || "")
    error = String(state.error || "")
    updated = String(state.updated || "")
    pinnedId = String(state.pinnedId || "")
    internationalOnly = state.internationalOnly === true
    wicketAlerts = state.wicketAlerts !== false
    sections = Array.isArray(state.sections) ? state.sections : []
    ready = true
  }

  function send(command) {
    if (helper.running) helper.write(command + "\n")
  }

  function refresh() { send("refresh") }
  function pin(id) { send("pin " + id) }
  function unpin() { send("unpin") }
  function togglePin(id) { id === pinnedId ? unpin() : pin(id) }
  function setInternationalOnly(on) { internationalOnly = on; send("international " + (on ? "on" : "off")) }
  function setWicketAlerts(on) { wicketAlerts = on; send("alerts " + (on ? "on" : "off")) }
  function openLink(url) { if (url) Qt.openUrlExternally(url) }

  Process {
    id: helper
    command: ["python3", "-u", root.helperPath]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.apply(line) } }
    stderr: SplitParser { onRead: function(line) { console.warn("stumpbar:", line) } }
    onExited: function(exitCode) {
      root.error = "Stumpbar helper stopped (exit " + exitCode + "); restarting…"
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 5000
    onTriggered: helper.running = true
  }
}
