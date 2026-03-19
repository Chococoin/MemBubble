import Cocoa

// MARK: - Prevent Multiple Instances

let lockPath = NSTemporaryDirectory() + "MemBubble.lock"
let lockFD = open(lockPath, O_CREAT | O_WRONLY, 0o644)
if lockFD == -1 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    fputs("MemBubble is already running.\n", stderr)
    exit(1)
}

// MARK: - Launch

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
