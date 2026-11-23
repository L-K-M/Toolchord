import AppKit

@MainActor
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        func group(_ title: String) -> NSMenu {
            let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu
            return submenu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
                 _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
        }

        let app = group("Toolchord")
        add(app, "About Toolchord", #selector(AppDelegate.showAbout), target: target)
        app.addItem(.separator())
        add(app, "Settings…", #selector(AppDelegate.showSettingsAction), ",", target: target)
        let services = app.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        app.addItem(.separator())
        add(app, "Hide Toolchord", #selector(NSApplication.hide(_:)), "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Toolchord", #selector(NSApplication.terminate(_:)), "q")

        let file = group("File")
        add(file, "New Tool", #selector(AppDelegate.newTool), "n", target: target)
        add(file, "Open Tool…", #selector(AppDelegate.openTool), "o", target: target)
        let recents = file.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = target
        recents.submenu = recentMenu
        file.addItem(.separator())
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        add(file, "Save to Tool Library", #selector(ToolEditorWindow.saveTool), "s")
        add(file, "Export Tool…", #selector(ToolEditorWindow.exportTool), "s", [.command, .shift])
        add(file, "Revert Changes", #selector(ToolEditorWindow.revertTool))

        let edit = group("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find…", action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue

        let view = group("View")
        add(view, "Hide Tool Library", #selector(ToolEditorWindow.toggleLibrary), "s", [.command, .control])
        add(view, "Hide Sample Inspector", #selector(ToolEditorWindow.toggleInspector), "i", [.command, .option])
        view.addItem(.separator())
        add(view, "Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        add(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        let tool = group("Tool")
        add(tool, "Open Palette", #selector(AppDelegate.openPalette), target: target)
        add(tool, "Make Custom Tool", #selector(AppDelegate.showCustomToolEditorAction), target: target)
        tool.addItem(.separator())
        add(tool, "Run Sample", #selector(ToolEditorWindow.runSample), "\r")
        add(tool, "Generate from Description", #selector(ToolEditorWindow.generateTool))
        add(tool, "Cancel Operation", #selector(ToolEditorWindow.cancelOperationInEditor), ".")

        let window = group("Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window
        return main
    }
}
