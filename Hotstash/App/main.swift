import AppKit

// Create the application singleton, assign the delegate, then enter the run loop.
// Using NSApplication.shared.run() instead of NSApplicationMain() gives us full
// control over delegate lifetime without relying on @NSApplicationMain.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
