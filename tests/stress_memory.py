#!/usr/bin/env python3
"""
MemBubble stress test — allocates memory in 256MB chunks.
Each chunk is written to prevent macOS from compressing empty pages.

Usage:
    python3 stress_memory.py          # allocates until killed
    python3 stress_memory.py 2048     # allocates up to 2048 MB then holds

Press Ctrl+C to release all memory and exit.
"""

import sys
import time
import os

CHUNK_SIZE = 256 * 1024 * 1024  # 256 MB per chunk
MAX_MB = int(sys.argv[1]) if len(sys.argv) > 1 else 99999

chunks = []
allocated = 0
pid = os.getpid()

print(f"[stress_memory] PID {pid} — allocating up to {MAX_MB} MB in 256MB chunks")
print(f"[stress_memory] Press Ctrl+C to release and exit\n")

try:
    while allocated < MAX_MB:
        # Allocate and dirty the memory so macOS can't just compress zeros
        chunk = bytearray(CHUNK_SIZE)
        for i in range(0, len(chunk), 4096):
            chunk[i] = i % 256  # write to each page
        chunks.append(chunk)
        allocated += 256
        print(f"  Allocated: {allocated} MB  (chunks: {len(chunks)})")
        time.sleep(1)  # give the system time to react

    print(f"\n[stress_memory] Reached {allocated} MB — holding. Ctrl+C to release.")
    while True:
        time.sleep(1)

except KeyboardInterrupt:
    print(f"\n[stress_memory] Releasing {allocated} MB...")
    chunks.clear()
    print("[stress_memory] Done.")
