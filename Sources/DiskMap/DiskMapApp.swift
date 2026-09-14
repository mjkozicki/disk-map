import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DiskMapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Disk Map", id: "main") {
            ContentView().environmentObject(model)
                .onOpenURL { model.startScan($0) }
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Location…") { model.chooseLocation() }.keyboardShortcut("o")
                Button("Rescan") { model.rescan() }.keyboardShortcut("r").disabled(model.isScanning || !model.hasScan)
                Button("Cancel Scan") { model.cancelScan() }.keyboardShortcut(".").disabled(!model.isScanning)
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") { NotificationCenter.default.post(name: .diskMapFocusSearch, object: nil) }.keyboardShortcut("f")
                Button("Next Match") { model.nextMatch(1) }.keyboardShortcut("g").disabled(model.query.isEmpty)
                Button("Previous Match") { model.nextMatch(-1) }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(model.query.isEmpty)
            }
            CommandMenu("Navigate") {
                Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(model.history.isEmpty)
                Button("Enclosing Folder") { model.goUp() }.keyboardShortcut(.upArrow, modifiers: .command).disabled(model.current?.parent == nil)
                Button("Scan Root") { model.navigate(0, inspectPackage: true) }.keyboardShortcut("0").disabled(!model.hasScan)
                Divider()
                Button("Inspect Selected Item") { if let id = model.selectedID { model.inspect(id) } }.keyboardShortcut(.return, modifiers: .command).disabled(model.selectedID == nil)
                Button("Reveal in Finder") { if let id = model.selectedID { model.reveal(id) } }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.selectedID == nil)
                Button("Copy Path") { if let id = model.selectedID { model.copyPath(id) } }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(model.selectedID == nil)
            }
            CommandGroup(after: .sidebar) {
                Toggle("Show Inspector", isOn: $model.showInspector).keyboardShortcut("i", modifiers: [.command, .option])
                Toggle("Show Hidden Items", isOn: $model.showHidden).keyboardShortcut(".", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Disk Map Help") {
                    model.message = "Choose a folder or volume, or drop a folder into the window. Select tiles or table rows for details. Double-click folders to explore them; packages require Inspect Package Contents. Size on disk uses reported allocation, and + marks incomplete totals. Use Bundles & Packages to find large applications and libraries. Use Development Cleanup to review generated folders and move selected items to Trash. Space is freed only after you empty Trash in Finder."
                }
            }
        }
    }
}
