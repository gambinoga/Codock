import AppKit
if CommandLine.arguments.contains("--self-test") {
    runModelTests()
    runDockTests()
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
