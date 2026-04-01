#!/bin/zsh
cd "$(dirname "$0")"

echo "👊 KickMyMac"
echo ""

# Kill old instances
killall KickUI 2>/dev/null
sudo killall -9 sensor.py 2>/dev/null

# Start native Swift UI (menu bar) as normal user
./KickUI &
UI_PID=$!
echo "UI started (PID: $UI_PID) — look for 👊 in menu bar"
sleep 1

# Start sensor as root
echo "Starting sensor (needs sudo)..."
sudo python3 sensor.py

# When sensor stops, kill UI
kill $UI_PID 2>/dev/null
echo "Done."
