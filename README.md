# KickMyMac 👊

Hit your MacBook — it swears back at you in Polish.

Uses the **real hardware accelerometer** (Apple Silicon SPU) to detect physical impacts via jerk/vibration analysis. Plays random swear audio clips through a native macOS menu bar app.

## How it works

- **sensor.py** — root daemon that reads the accelerometer via `macimu` and detects hits using jerk-based vibration analysis
- **KickUI.swift** — native Swift menu bar app (👊) that receives hit events and plays audio
- **start.sh** — launches both with one command

## Requirements

- Apple Silicon MacBook (M1/M2/M3/M4)
- macOS 14+
- Python 3 + `macimu` + `edge-tts`
- Xcode Command Line Tools (for `swiftc`)

## Setup

```bash
# Install dependencies
pip3 install macimu edge-tts

# Generate audio (or drop your own .mp3 files into audio/)
python3 generate_audio.py

# Build the menu bar app
bash build.sh

# Run (needs sudo for accelerometer)
./start.sh
```

## Custom audio

Drop your own `.mp3` files into the `audio/` folder. The app picks them up automatically and plays them in shuffled order with no repeats.

## Architecture

```
sensor.py (root) ──[unix socket]──> KickUI (user)
     │                                    │
  accelerometer                     menu bar 👊
  jerk detection                    audio playback
```
