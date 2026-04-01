#!/usr/bin/env python3
"""KickMyMac UI — menu bar app that listens for hit events and plays swears."""

import os
import random
import socket
import subprocess
import sys
import threading
import time

import rumps

AUDIO_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio")
SOCKET_PATH = "/tmp/kickmymac.sock.ui"


class KickMyMacApp(rumps.App):
    def __init__(self):
        super().__init__("KickMyMac", title="👊", quit_button=None)

        # Load audio
        self.audio_files = sorted([
            os.path.join(AUDIO_DIR, f)
            for f in os.listdir(AUDIO_DIR)
            if f.endswith(".mp3")
        ]) if os.path.isdir(AUDIO_DIR) else []

        self.audio_process = None
        self.hit_count = 0

        # Menu
        self.hits_item = rumps.MenuItem(f"Hits: 0")
        self.status_item = rumps.MenuItem("Waiting for sensor...")
        self.status_item.set_callback(None)

        self.menu = [
            self.status_item,
            self.hits_item,
            None,
            rumps.MenuItem("Test Swear", callback=self.test_swear),
            None,
            rumps.MenuItem("Quit", callback=self.quit_app),
        ]

        print(f"Loaded {len(self.audio_files)} audio files")

        # Start listener
        self._listener = threading.Thread(target=self._listen, daemon=True)
        self._listener.start()

    def _listen(self):
        """Listen for hit events from the sensor daemon."""
        # Clean up old socket
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sock.bind(SOCKET_PATH)
        os.chmod(SOCKET_PATH, 0o777)

        # Update status
        rumps.Timer(lambda _: self._update_status("Sensor connected"), 0.1).start()

        while True:
            try:
                data, _ = sock.recvfrom(256)
                msg = data.decode().strip()
                if msg.startswith("HIT"):
                    parts = msg.split()
                    count = int(parts[1]) if len(parts) > 1 else 0
                    mag = parts[2] if len(parts) > 2 else "?"
                    self.hit_count = count
                    self._on_hit(mag)
            except Exception as e:
                print(f"Listener error: {e}")
                time.sleep(0.5)

    def _update_status(self, text):
        self.status_item.title = text

    def _on_hit(self, mag):
        self.play_random()
        self.title = "💥"
        self.hits_item.title = f"Hits: {self.hit_count}"
        self.status_item.title = f"Last hit: {mag}g"

        # Reset icon after delay
        def reset():
            time.sleep(0.8)
            self.title = "👊"
        threading.Thread(target=reset, daemon=True).start()

    def play_random(self):
        if not self.audio_files:
            return
        if self.audio_process and self.audio_process.poll() is None:
            self.audio_process.terminate()
        f = random.choice(self.audio_files)
        self.audio_process = subprocess.Popen(
            ["/usr/bin/afplay", f],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    def test_swear(self, _):
        self.hit_count += 1
        self.hits_item.title = f"Hits: {self.hit_count}"
        self.play_random()

    def quit_app(self, _):
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        rumps.quit_application()


if __name__ == "__main__":
    app = KickMyMacApp()
    app.run()
