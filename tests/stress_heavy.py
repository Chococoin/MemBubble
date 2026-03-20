#!/usr/bin/env python3
"""
Heavy memory stress — allocates fast in 512MB chunks, writes every page.
Designed to overwhelm macOS memory management.
Press Ctrl+C to release.
"""

import sys
import time
import os
import random

chunks = []
allocated = 0
pid = os.getpid()

print(f"[stress_heavy] PID {pid} — aggressive allocation starting")
print(f"[stress_heavy] Press Ctrl+C to release\n")

try:
    while True:
        # 512MB chunk
        size = 512 * 1024 * 1024
        chunk = bytearray(size)
        # Write random data to every page so macOS can't compress easily
        for i in range(0, len(chunk), 4096):
            chunk[i] = random.randint(0, 255)
            chunk[i+1] = random.randint(0, 255)
            chunk[i+2] = random.randint(0, 255)
            chunk[i+3] = random.randint(0, 255)
        chunks.append(chunk)
        allocated += 512
        print(f"  Allocated: {allocated} MB")
        # Also re-touch old chunks to prevent them from being swapped
        for old in chunks[:-1]:
            idx = random.randint(0, len(old) - 1)
            old[idx] = random.randint(0, 255)
        time.sleep(0.5)

except (KeyboardInterrupt, MemoryError) as e:
    print(f"\n[stress_heavy] Stopped at {allocated} MB — {type(e).__name__}")
    chunks.clear()
    print("[stress_heavy] Released.")
