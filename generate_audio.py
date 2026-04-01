#!/usr/bin/env python3
"""Pre-generate swear audio files using edge-tts MarekNeural voice."""

import asyncio
import edge_tts
import os

VOICE = "pl-PL-MarekNeural"
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio")

PHRASES = [
    "Kurwa!",
    "Ja pierdolę!",
    "Co jest, kurwa?!",
    "Chuj cię!",
    "O kurwa mać!",
    "Spierdalaj!",
    "Kurwa, pojebało cię?!",
    "Ja ci zaraz oddam, kurwa!",
    "Kurwa, boli!",
    "Zajebię ci!",
]


async def generate_all():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Clean old files
    for f in os.listdir(OUTPUT_DIR):
        if f.endswith(".mp3"):
            os.remove(os.path.join(OUTPUT_DIR, f))

    for i, phrase in enumerate(PHRASES):
        filename = os.path.join(OUTPUT_DIR, f"swear_{i:02d}.mp3")
        print(f"[{i+1}/{len(PHRASES)}] {phrase}")
        communicate = edge_tts.Communicate(phrase, VOICE, rate="+10%")
        await communicate.save(filename)

    print(f"\nDone! {len(PHRASES)} files in {OUTPUT_DIR}")


if __name__ == "__main__":
    asyncio.run(generate_all())
