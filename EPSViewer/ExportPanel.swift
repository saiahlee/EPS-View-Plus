import AppKit

enum ExportPanel {
    /// Modal DPI picker; returns the selected DPI or `0` if cancelled.
    @MainActor
    static func runForPNG() -> Int {
        let alert = NSAlert()
        alert.messageText = "Export as PNG"
        alert.informativeText = "Choose the export resolution."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        popup.addItems(withTitles: [
            "72 DPI — screen",
            "150 DPI — web",
            "300 DPI — print",
            "600 DPI — high quality",
            "1200 DPI — archival",
        ])
        popup.selectItem(at: 2)
        alert.accessoryView = popup

        alert.addButton(withTitle: "Export…")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return 0 }

        switch popup.indexOfSelectedItem {
        case 0: return 72
        case 1: return 150
        case 2: return 300
        case 3: return 600
        case 4: return 1200
        default: return 300
        }
    }
}
