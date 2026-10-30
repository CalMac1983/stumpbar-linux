import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar label (🏏 plus the pinned score or live-match count) with a popup that
// lists Live, Results and Upcoming matches. Click a match to pin it; the
// state itself lives in the shared Service.qml.
Panel {
  id: root
  moduleName: "calmac.stumpbar"

  // Shared service; looked up until the shell has created it (and again if a
  // plugin reload replaces it).
  property var stumpbar: null
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var sections: stumpbar ? stumpbar.sections : []
  readonly property var matches: {
    var all = []
    for (var i = 0; i < sections.length; i++)
      for (var j = 0; j < sections[i].matches.length; j++) all.push(sections[i].matches[j])
    return all
  }
  // Cursor stops: every match, then the two toggles.
  readonly property int internationalIndex: matches.length
  readonly property int alertsIndex: matches.length + 1
  readonly property string barText: {
    var label = stumpbar ? stumpbar.label : ""
    return label ? "🏏 " + label : "🏏"
  }

  function findService() {
    if (stumpbar) return
    var shell = bar ? bar.shell : null
    if (shell && typeof shell.serviceFor === "function") stumpbar = shell.serviceFor(moduleName)  }

  function matchIndex(id) {
    for (var i = 0; i < matches.length; i++) if (matches[i].id === id) return i
    return -1
  }

  function moveCursor(dy) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(alertsIndex, cursorIndex + dy))
    scrollCursorIntoView()
  }

  function activateCursor() {
    if (!stumpbar) return
    if (cursorIndex < matches.length) stumpbar.togglePin(matches[cursorIndex].id)
    else if (cursorIndex === internationalIndex) stumpbar.setInternationalOnly(!stumpbar.internationalOnly)
    else if (cursorIndex === alertsIndex) stumpbar.setWicketAlerts(!stumpbar.wicketAlerts)
  }

  function openCursorLink() {
    if (stumpbar && cursorIndex < matches.length) stumpbar.openLink(matches[cursorIndex].link)
  }

  function scrollCursorIntoView() {
    var item = cursorIndex < matches.length ? matchRepeaterItem(cursorIndex) : toggles
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function matchRepeaterItem(index) {
    for (var i = 0; i < sectionColumn.children.length; i++) {
      var section = sectionColumn.children[i]
      if (section.rowFor) {
        var row = section.rowFor(index)
        if (row) return row
      }
    }
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: findService()
  onOpenedChanged: if (opened) {
    cursorActive = false
    var pinned = stumpbar ? matchIndex(stumpbar.pinnedId) : -1
    cursorIndex = pinned >= 0 ? pinned : 0
    if (panelFlick) panelFlick.contentY = 0
    if (stumpbar) stumpbar.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: 500
    repeat: true
    running: !root.stumpbar
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "🏏" : root.barText
    horizontalMargin: 8.75

    onPressed: function(b) {
      if (!root.stumpbar) return
      if (b === Qt.RightButton) root.stumpbar.refresh()
      else if (b === Qt.MiddleButton) root.stumpbar.unpin()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.stumpbar) return
        if (t === "r" || t === "R") root.stumpbar.refresh()
        else if (t === "o" || t === "O") root.openCursorLink()
        else if (t === "u" || t === "U") root.stumpbar.unpin()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Stumpbar"
            meta: root.stumpbar && root.stumpbar.label ? root.stumpbar.label : "No live matches"
            detail: root.stumpbar && root.stumpbar.updated ? "Updated " + root.stumpbar.updated : "Loading scores…"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text { text: "🏏"; font.pixelSize: Style.font.display }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !!root.stumpbar && root.stumpbar.error !== ""
            width: parent.width
            text: root.stumpbar ? "Couldn't fetch scores: " + root.stumpbar.error : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !!root.stumpbar && root.stumpbar.ready && root.matches.length === 0
            width: parent.width
            text: "No matches right now"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: sectionColumn
            width: parent.width
            spacing: Style.space(12)

            Repeater {
              model: root.sections
              Column {
                id: section
                required property var modelData
                width: sectionColumn.width
                spacing: Style.space(6)

                function rowFor(index) {
                  for (var i = 0; i < rows.count; i++) {
                    var row = rows.itemAt(i)
                    if (row && row.rowIndex === index) return row
                  }
                  return null
                }

                PanelSectionHeader {
                  text: String(section.modelData.heading).toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  id: rows
                  model: section.modelData.matches
                  MatchRow {
                    required property var modelData
                    width: section.width
                    match: modelData
                    rowIndex: root.matchIndex(modelData.id)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: toggles
            width: parent.width
            spacing: Style.space(6)

            Toggle {
              width: parent.width
              label: "International only"
              description: "Hide domestic and A-team games"
              checked: !!root.stumpbar && root.stumpbar.internationalOnly
              hasCursor: root.cursorActive && root.cursorIndex === root.internationalIndex
              foreground: root.foreground
              fontFamily: root.fontFamily
              onHovered: function(on) { if (on) { root.cursorActive = true; root.cursorIndex = root.internationalIndex } }
              onClicked: if (root.stumpbar) root.stumpbar.setInternationalOnly(!root.stumpbar.internationalOnly)
            }

            Toggle {
              width: parent.width
              label: "Wicket alerts"
              description: "Notify when a wicket falls in the pinned match"
              checked: !root.stumpbar || root.stumpbar.wicketAlerts
              hasCursor: root.cursorActive && root.cursorIndex === root.alertsIndex
              foreground: root.foreground
              fontFamily: root.fontFamily
              onHovered: function(on) { if (on) { root.cursorActive = true; root.cursorIndex = root.alertsIndex } }
              onClicked: if (root.stumpbar) root.stumpbar.setWicketAlerts(!root.stumpbar.wicketAlerts)
            }
          }
        }
      }
    }
  }

  component MatchRow: CursorSurface {
    id: matchRow
    property var match: ({})
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: match.pinned === true
    foreground: root.foreground
    implicitHeight: matchContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = matchRow.rowIndex }
      onClicked: if (root.stumpbar) root.stumpbar.togglePin(matchRow.match.id)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      ColumnLayout {
        id: matchContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: (matchRow.match.pinned ? "📌 " : "") + matchRow.match.score
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: matchRow.match.summary
          color: root.foreground
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: matchRow.match.description
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: !!matchRow.match.link
        iconText: "󰏌"
        tooltipText: "Open on ESPNcricinfo"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (root.stumpbar) root.stumpbar.openLink(matchRow.match.link)
      }
    }
  }
}
