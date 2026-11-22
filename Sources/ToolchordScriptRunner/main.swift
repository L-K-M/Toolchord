import ToolchordCore

// SwiftPM tools and tests use a standalone entry point. The shipped app
// dispatches the same worker mode before initializing AppKit.
ScriptWorker.serve()
