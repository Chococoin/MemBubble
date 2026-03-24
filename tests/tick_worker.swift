import Foundation

setbuf(stdout, nil)

let args = CommandLine.arguments
let workerID = args.count > 1 ? args[1] : "0"
let targetMB = args.count > 2 ? Int(args[2]) ?? 8 : 8
let tickMs = args.count > 3 ? Int(args[3]) ?? 500 : 500

let tickInterval = Double(tickMs) / 1000.0
let chunkSize = 1_048_576  // 1MB

print("W\(workerID) | target=\(targetMB)MB | tick=\(tickMs)ms | pid=\(ProcessInfo.processInfo.processIdentifier)")

var chunks: [UnsafeMutableRawPointer] = []
var tickCount = 0
var maxDrift: Double = 0
var totalDrift: Double = 0
let startTime = Date()

while true {
    tickCount += 1
    let expected = startTime.addingTimeInterval(Double(tickCount) * tickInterval)

    // Allocate 1MB per tick until target
    if chunks.count < targetMB {
        let p = mmap(nil, chunkSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
        if let p = p, p != MAP_FAILED {
            // Touch first and last byte of each page
            let b = p.assumingMemoryBound(to: UInt8.self)
            var i = 0
            while i < chunkSize {
                b[i] = UInt8(truncatingIfNeeded: i)
                i += 16384
            }
            chunks.append(p)
        }
    }

    // Touch random chunks
    if chunks.count > 0 {
        for _ in 0..<max(1, chunks.count / 4) {
            let ci = Int.random(in: 0..<chunks.count)
            let b = chunks[ci].assumingMemoryBound(to: UInt8.self)
            let off = Int.random(in: 0..<(chunkSize / 16384)) * 16384
            b[off] = b[off] &+ 1
        }
    }

    // Wait for tick
    let now = Date()
    let wait = expected.timeIntervalSince(now)
    if wait > 0 { Thread.sleep(forTimeInterval: wait) }

    // Measure
    let actual = Date()
    let drift = actual.timeIntervalSince(expected) * 1000
    totalDrift += Swift.abs(drift)
    maxDrift = Swift.max(maxDrift, Swift.abs(drift))
    let avg = totalDrift / Double(tickCount)

    print("W\(workerID) | t=\(String(format: "%04d", tickCount)) | \(chunks.count)MB | drift=\(String(format: "%+.1f", drift))ms | avg=\(String(format: "%.1f", avg))ms | max=\(String(format: "%.1f", maxDrift))ms")
}
