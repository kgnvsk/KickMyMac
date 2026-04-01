#!/usr/bin/env python3
"""KickMyMac Sensor — detects punches via accelerometer vibration (jerk)."""

import math
import os
import socket
import sys
import time
from collections import deque

SOCKET_PATH = "/tmp/kickmymac.sock.ui"
SAMPLE_RATE = 100
COOLDOWN = 2.0

# Jerk-based detection: measures how fast acceleration CHANGES (vibration)
# A punch causes rapid oscillations; lifting the laptop causes slow smooth changes
JERK_WINDOW = 5          # samples to compute jerk over
JERK_THRESHOLD = 0.08    # threshold for jerk magnitude (lower = more sensitive)
BASELINE_WINDOW = 50     # samples for baseline jerk level


def main():
    if os.geteuid() != 0:
        print("ERROR: needs root. Run: sudo python3 sensor.py")
        sys.exit(1)

    from macimu import IMU

    if not IMU.available():
        print("ERROR: accelerometer not available")
        sys.exit(1)

    # Setup Unix socket
    client_sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)

    print("Starting accelerometer...")
    imu = IMU(accel=True, gyro=False, sample_rate=SAMPLE_RATE)
    imu.start()
    time.sleep(0.3)

    # Recent samples for jerk calculation
    recent = deque(maxlen=JERK_WINDOW)
    jerk_history = deque(maxlen=BASELINE_WINDOW)
    last_trigger = 0.0
    hit_count = 0

    print(f"Sensor ready. Detecting punches via vibration.")
    print(f"Jerk threshold: {JERK_THRESHOLD}")
    print("Waiting for hits... (Ctrl+C to stop)\n")

    try:
        for sample in imu.stream_accel(interval=1.0 / SAMPLE_RATE):
            recent.append((sample.x, sample.y, sample.z))

            if len(recent) < JERK_WINDOW:
                continue

            # Calculate jerk: difference between consecutive samples
            # Sum of absolute changes over the window = vibration intensity
            jerk = 0.0
            for i in range(1, len(recent)):
                dx = recent[i][0] - recent[i-1][0]
                dy = recent[i][1] - recent[i-1][1]
                dz = recent[i][2] - recent[i-1][2]
                jerk += math.sqrt(dx*dx + dy*dy + dz*dz)
            jerk /= (len(recent) - 1)  # average jerk per sample

            jerk_history.append(jerk)

            now = time.time()
            if (jerk > JERK_THRESHOLD
                    and (now - last_trigger) > COOLDOWN):
                last_trigger = now
                hit_count += 1
                print(f"💥 HIT #{hit_count}! jerk={jerk:.4f}")

                # Send to UI
                try:
                    client_sock.sendto(
                        f"HIT {hit_count} {jerk:.4f}".encode(),
                        SOCKET_PATH
                    )
                except Exception:
                    pass

    except KeyboardInterrupt:
        print("\nSensor stopped.")
    finally:
        imu.stop()
        client_sock.close()


if __name__ == "__main__":
    main()
