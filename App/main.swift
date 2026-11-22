import ToolchordCore
import ToolchordMac

if CommandLine.arguments.dropFirst().elementsEqual([ScriptWorker.argument]) {
    ScriptWorker.serve()
} else {
    ToolchordApplication.run()
}
