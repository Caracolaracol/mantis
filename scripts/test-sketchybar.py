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


class SketchyBarTests(unittest.TestCase):
    def run_script(self, state=None, click=False, button="left", age=0, pid=None):
        with tempfile.TemporaryDirectory(prefix="recorder-bar-test-") as directory:
            if state:
                Path(directory, "status.json").write_text(json.dumps({
                    "state": state, "pid": os.getpid() if pid is None else pid,
                    "elapsedSeconds": 125, "updatedAt": time.time() - age,
                }))
            env = dict(os.environ, MEETING_RECORDER_CONTROL=directory,
                       MEETING_RECORDER_DRY_RUN="1", BUTTON=button)
            return subprocess.check_output(["/bin/bash", str(SCRIPT)] + (["click"] if click else []),
                                           env=env, text=True)

    def test_offline(self):
        self.assertIn("state=offline label=Grabar label_color=0xffccd7e4", self.run_script())

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


if __name__ == "__main__":
    unittest.main()
