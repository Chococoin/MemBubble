#!/bin/bash
set -uo pipefail

# MARK: - Pressure Benchmark
# Launches tick workers progressively to find the real performance limit.
# Each worker allocates RAM and measures tick drift.
# When drift spikes, that's the REAL pressure point.

cd "$(dirname "$0")/.."

ALLOC_MB="${1:-512}"
TICK_MS="${2:-500}"
MAX_WORKERS="${3:-20}"
RAMP_DELAY="${4:-8}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  MemBubble Pressure Benchmark                              ║"
echo "║  ${ALLOC_MB}MB/worker | ${TICK_MS}ms ticks | max ${MAX_WORKERS} workers        ║"
echo "║  New worker every ${RAMP_DELAY}s | Ctrl+C to stop                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Build the tick worker
echo "==> Compiling tick_worker..."
swiftc tests/tick_worker.swift -o tests/tick_worker_bin
echo "==> Ready."
echo ""

# Track state
PIDS_FILE=$(mktemp)
LOG_DIR="tests/bench_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
MONITOR_PID=""
NUM_WORKERS=0

cleanup() {
    echo ""
    echo "==> Stopping all workers..."
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null || true
    while read -r pid; do
        kill "$pid" 2>/dev/null || true
    done < "$PIDS_FILE"
    wait 2>/dev/null || true

    echo ""
    echo "==> Results in $LOG_DIR/"
    echo "   Workers launched: $NUM_WORKERS"
    echo "   Total RAM allocated: $(( NUM_WORKERS * ALLOC_MB )) MB"
    echo ""
    echo "   Worker | Max Drift (ms)"
    echo "   -------|---------------"
    for f in "$LOG_DIR"/worker_*.log; do
        if [ -f "$f" ]; then
            wid=$(basename "$f" .log | sed 's/worker_//')
            max_d=$(grep "max=" "$f" 2>/dev/null | tail -1 | sed 's/.*max=\([0-9.]*\)ms/\1/' || echo "?")
            printf "   W%-5s | %s ms\n" "$wid" "$max_d"
        fi
    done

    echo ""
    echo "==> System state at end:"
    sysctl kern.memorystatus_vm_pressure_level 2>/dev/null || true
    memory_pressure 2>&1 | grep -E "free|Swap|Compressor" | head -5
    rm -f "$PIDS_FILE"
    echo ""
}

trap cleanup EXIT INT TERM

# Background monitor
(
    while true; do
        sleep "$RAMP_DELAY"
        kern=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo "?")
        swap=$(sysctl vm.swapusage 2>/dev/null | sed 's/.*used = \([0-9,.]*\)M.*/\1/' || echo "?")
        free_pct=$(memory_pressure 2>&1 | grep "free percentage" | sed 's/.*: //' || echo "?")
        echo ""
        echo "──── STATE | workers=$NUM_WORKERS | alloc=$(( NUM_WORKERS * ALLOC_MB ))MB | kernel=$kern | swap=${swap}MB | free=$free_pct ────"
        echo ""
    done
) &
MONITOR_PID=$!

# Launch workers
for i in $(seq 1 "$MAX_WORKERS"); do
    echo "==> Launching worker $i (${ALLOC_MB}MB)..."
    ./tests/tick_worker_bin "$i" "$ALLOC_MB" "$TICK_MS" > "$LOG_DIR/worker_${i}.log" 2>&1 &
    WPID=$!
    echo "$WPID" >> "$PIDS_FILE"
    NUM_WORKERS=$i
    echo "    PID=$WPID | total=$(( i * ALLOC_MB ))MB"

    sleep "$RAMP_DELAY"

    # Show latest tick from each running worker
    echo "    Latest ticks:"
    for f in "$LOG_DIR"/worker_*.log; do
        [ -f "$f" ] && tail -1 "$f" 2>/dev/null | sed 's/^/      /'
    done
    echo ""
done

echo "==> All $MAX_WORKERS workers running. Ctrl+C to stop and see summary."

while true; do
    sleep 5
    echo "    Latest ticks:"
    for f in "$LOG_DIR"/worker_*.log; do
        [ -f "$f" ] && tail -1 "$f" 2>/dev/null | sed 's/^/      /'
    done
done
