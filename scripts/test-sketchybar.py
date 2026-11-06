#!/usr/bin/env python3
"""Exercise rendering/control decisions in dry-run mode: never launch a recorder."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

SCRIPT = Path(__file__).with_name("sketchybar-recorder.sh")
WIDGET = SCRIPT.parent.parent / "integrations/sketchybar/mantis.sh"


class SketchyBarTests(unittest.TestCase):
    def run_script(self, state=None, click=False, button="left", age=0, pid=None, sender="routine", language="en"):
        with tempfile.TemporaryDirectory(prefix="recorder-bar-test-") as directory:
            if state:
                Path(directory, "status.json").write_text(json.dumps({
                    "state": state, "pid": os.getpid() if pid is None else pid,
                    "elapsedSeconds": 125, "updatedAt": time.time() - age, "language": language,
                }))
            env = dict(os.environ, MEETING_RECORDER_CONTROL=directory,
                       MEETING_RECORDER_DRY_RUN="1", BUTTON=button, SENDER=sender)
            env.pop("MEETING_RECORDER_APP", None)
            return subprocess.check_output(["/bin/bash", str(SCRIPT)] + (["click"] if click else []),
                                           env=env, text=True)

    def test_offline(self):
        self.assertIn("state=offline label=Record label_color=0xffccd7e4", self.run_script())

    def test_recording(self):
        self.assertIn("state=recording label=REC 02:05 label_color=0xffd94a6d", self.run_script("recording"))
        self.assertIn("--toggle-recording", self.run_script("recording", click=True))

    def test_processing_does_not_start_another_recording(self):
        for state in ["preparing", "transcribing", "error"]:
            self.assertIn("--show", self.run_script(state, click=True))

    def test_idle_click(self):
        self.assertIn("--toggle-recording", self.run_script("idle", click=True))

    def test_right_click(self):
        self.assertIn("--show", self.run_script("idle", click=True, button="right"))

    def test_stale_status(self):
        self.assertIn("state=offline", self.run_script("recording", age=30))

    def test_dead_process(self):
        self.assertIn("state=offline", self.run_script("recording", pid=999999999))

    def test_native_click_event(self):
        self.assertIn("--toggle-recording", self.run_script("idle", sender="mouse.clicked"))
        self.assertIn("--show", self.run_script("idle", sender="mouse.clicked", button="right"))

    def test_wake_event_only_refreshes(self):
        output = self.run_script("idle", sender="system_woke")
        self.assertIn("state=idle", output)
        self.assertNotIn("Would send", output)

    def test_default_app_is_installed_bundle(self):
        self.assertIn("/Applications/Mantis.app/Contents/MacOS/MeetingRecorder", self.run_script("idle", click=True))

    def test_spanish_labels_follow_application_language(self):
        self.assertIn("label=Grabar", self.run_script("idle", language="es"))
        self.assertIn("label=Transcribiendo", self.run_script("transcribing", language="es"))
        self.assertIn("label=Transcribing", self.run_script("transcribing", language="en"))

    def test_widget_registers_and_quotes_custom_paths_without_recording(self):
        with tempfile.TemporaryDirectory(prefix="mantis widget ") as directory:
            root = Path(directory)
            binary = root / "fake sketchybar"
            log = root / "commands.json"
            plugin = root / "mantis plugin.sh"
            plugin.write_text(SCRIPT.read_text())
            binary.write_text("#!/usr/bin/env python3\nimport json, os, sys\nfrom pathlib import Path\nPath(os.environ['TEST_LOG']).write_text(json.dumps(sys.argv[1:]))\n")
            binary.chmod(0o755)
            app = str(root / "Mantis 'Demo; app.app")
            env = dict(os.environ, SKETCHYBAR_BIN=str(binary), MANTIS_WIDGET_SCRIPT=str(plugin),
                       MANTIS_APP_PATH=app, TEST_LOG=str(log), MEETING_RECORDER_DRY_RUN="1",
                       MEETING_RECORDER_CONTROL=directory, NAME="mantis", SENDER="mouse.clicked", BUTTON="left")
            subprocess.check_call(["/bin/bash", str(WIDGET)], env=env)
            args = json.loads(log.read_text())
            self.assertEqual(args[:4], ["--add", "item", "mantis", "right"])
            self.assertEqual(args[-4:], ["--subscribe", "mantis", "mouse.clicked", "system_woke"])
            self.assertIn("update_freq=1", args)
            self.assertFalse(any(arg.startswith("click_script=") for arg in args))
            command = next(arg.removeprefix("script=") for arg in args if arg.startswith("script="))
            output = subprocess.check_output(["/bin/bash", "-c", command], env=env, text=True)
            self.assertIn("Would send --toggle-recording", output)
            self.assertIn(app + "/Contents/MacOS/MeetingRecorder", output)


if __name__ == "__main__":
    unittest.main()
