import AppKit

/// Standard macOS folder picker. Only the folder the user picks is inspected.
enum FolderPicker {
    @MainActor
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder to Inspect"
        panel.message = "Choose a folder to inspect. Nothing in it will be changed."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // The picker itself must not offer a "New Folder" button.
        panel.canCreateDirectories = false
        // Do not resolve aliases: what the user picks is what is inspected.
        panel.resolvesAliases = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
