import AppKit
if CommandLine.arguments.contains("--window-self-test") {
    runDockWindowTests()
    exit(0)
}
if CommandLine.arguments.contains("--self-test") {
    runModelTests()
    runDockTests()
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
