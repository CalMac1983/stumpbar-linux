"""Stumpbar helper for the Omarchy bar widget.

Runs as a long-lived child of the widget's Service.qml. Every refresh it prints
one JSON line describing what the bar and panel should show, and it sends
wicket alerts with notify-send. The widget drives it with one command per line
on stdin:

    refresh | pin <match id> | unpin | international on|off | alerts on|off
    demo-wicket | demo-dismissals

Exits when stdin closes, so it never outlives the shell.
Run it by hand to see the output: `python3 stumpbar.py` (type commands, Ctrl-D quits).
"""

import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path

from scores import fetch_matches
from wickets import Wicket, WicketWatcher, parse_dismissal

REFRESH_SECONDS = 15
SECTIONS = [("in", "Live"), ("post", "Results"), ("pre", "Upcoming")]
ICON = str(Path(__file__).resolve().parent / "assets" / "icon.png")
STATE_FILE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "stumpbar" / "settings.json"

# Scorecard lines in ESPN's format, one per dismissal type, for demo-dismissals.
DEMO_DISMISSALS = [
    ("AUS-A", "7/277 (84.5)", "T Murphy  b Kamboj 33 (91b 2x4 1x6) SR: 36.26"),
    ("AUS-A", "1/12 (7.1)", "JR Philippe c Padikkal b Bhute 5 (21b 0x4 0x6) SR: 23.8"),
    ("AUS-A", "3/31 (11.6)", "PSP Handscomb c &dagger;Kushagra b Bhute 0 (15b 0x4 0x6) SR: 0"),
    ("IND", "3/142 (31.2)", "V Kohli c & b Lyon 44 (60b 5x4 0x6) SR: 73.33"),
    ("SA", "1/20 (2.4)", "Q de Kock lbw b Starc 12 (9b 2x4 0x6) SR: 133.33"),
    ("IND", "5/188 (24.3)", "RR Pant st &dagger;Carey b Zampa 27 (18b 3x4 1x6) SR: 150"),
    ("AUS", "4/201 (44.1)", "M Labuschagne hit wicket b Bumrah 3 (7b 0x4 0x6) SR: 42.85"),
    ("AUS", "3/150 (30.4)", "SPD Smith run out (Jadeja/&dagger;Pant) 61 (80b 6x4 0x6) SR: 76.25"),
    ("IND", "1/40 (5.2)", "RG Sharma retired hurt 20 (22b 3x4 0x6) SR: 90.9"),
]


def notify(wicket: Wicket):
    body = "\n".join(part for part in (wicket.subtitle, wicket.commentary) if part)
    try:
        subprocess.run(["notify-send", "--app-name=Stumpbar", f"--icon={ICON}",
                        wicket.title, body], check=False, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"[stumpbar] notify-send failed: {exc}", file=sys.stderr, flush=True)


class Stumpbar:
    def __init__(self):
        self.pinned_id = None
        self.international_only = False
        self.wicket_alerts = True
        self.load_settings()
        self.watcher = WicketWatcher()
        self.matches = []
        self.error = None

    def load_settings(self):
        try:
            saved = json.loads(STATE_FILE.read_text())
        except (OSError, ValueError):
            return
        self.pinned_id = saved.get("pinnedId")
        self.international_only = bool(saved.get("internationalOnly", False))
        self.wicket_alerts = bool(saved.get("wicketAlerts", True))

    def save_settings(self):
        try:
            STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            STATE_FILE.write_text(json.dumps({
                "pinnedId": self.pinned_id,
                "internationalOnly": self.international_only,
                "wicketAlerts": self.wicket_alerts,
            }))
        except OSError as exc:
            print(f"[stumpbar] couldn't save settings: {exc}", file=sys.stderr, flush=True)

    def refresh(self):
        try:
            self.matches = fetch_matches()
            self.error = None
        except Exception as exc:  # network errors etc. — keep the last good data
            self.error = str(exc)
        else:
            self.check_wickets()
        self.emit()

    def check_wickets(self):
        pinned = self.pinned()
        for wicket in self.watcher.check(pinned if self.wicket_alerts else None):
            notify(wicket)

    def pinned(self):
        return next((m for m in self.matches if m.id == self.pinned_id), None)

    def label(self) -> str:
        """Bar text after the 🏏, like the macOS menu bar title."""
        pinned = self.pinned()
        if pinned:
            return pinned.batting_score
        live = sum(1 for m in self.matches if m.state == "in"
                   and (m.international or not self.international_only))
        return f"{live} live" if live else ""

    def emit(self):
        shown = [m for m in self.matches if m.international or not self.international_only]
        sections = []
        for state, heading in SECTIONS:
            group = [m for m in shown if m.state == state]
            if group:
                sections.append({"heading": heading, "matches": [{
                    "id": m.id,
                    "score": m.short_score,
                    "summary": m.summary,
                    "description": m.description,
                    "link": m.link,
                    "pinned": m.id == self.pinned_id,
                } for m in group]})
        print(json.dumps({
            "label": self.label(),
            "error": self.error,
            "pinnedId": self.pinned_id,
            "internationalOnly": self.international_only,
            "wicketAlerts": self.wicket_alerts,
            "sections": sections,
            "updated": time.strftime("%H:%M:%S"),
        }), flush=True)

    def handle(self, line: str):
        command, _, arg = line.strip().partition(" ")
        if command == "refresh":
            self.refresh()
            return
        if command == "pin":
            self.pinned_id = arg or None
        elif command == "unpin":
            self.pinned_id = None
        elif command == "international":
            self.international_only = arg == "on"
        elif command == "alerts":
            self.wicket_alerts = arg == "on"
        elif command == "demo-wicket":
            notify(Wicket("AUS-A", "Murphy b Kamboj", "33", "91", "7/277 (84.5)",
                          "Kamboj does the job straightaway. A perfect length on middle, "
                          "nips in enough to beat the bat and to rattle stumps."))
            return
        elif command == "demo-dismissals":
            for team, score, text in DEMO_DISMISSALS:
                line, runs, balls = parse_dismissal(text)
                notify(Wicket(team, line, runs, balls, score, "Demo alert: " + text.split(" (")[0]))
            return
        else:
            print(f"[stumpbar] unknown command: {line.strip()!r}", file=sys.stderr, flush=True)
            return
        self.save_settings()
        self.check_wickets()  # starts (or stops) watching the newly pinned match
        self.emit()

    def run(self):
        self.refresh()
        next_refresh = time.monotonic() + REFRESH_SECONDS
        while True:
            wait = max(0, next_refresh - time.monotonic())
            ready, _, _ = select.select([sys.stdin], [], [], wait)
            if ready:
                line = sys.stdin.readline()
                if not line:  # stdin closed: the widget has gone
                    return
                self.handle(line)
            if time.monotonic() >= next_refresh:
                self.refresh()
                next_refresh = time.monotonic() + REFRESH_SECONDS


if __name__ == "__main__":
    try:
        Stumpbar().run()
    except KeyboardInterrupt:
        pass
