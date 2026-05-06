import AppKit
import SwiftUI

@main
struct EPSViewerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single SwiftUI scene that exists only so the app launches in
        // GUI mode. We immediately close any window SwiftUI creates here
        // and route ALL document windows through the AppDelegate's
        // AppKit-backed window factory. SwiftUI's WindowGroup multi-
        // window dedup behavior in macOS 26 is unreliable for our use
        // case ("always open a new window per file"), so we sidestep it.
        Window("", id: "stub") {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.windows
                            .filter { $0.identifier?.rawValue == "stub" }
                            .forEach { $0.close() }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { appDelegate.openFromMenu() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("EPS View Plus on GitHub",
                     destination: URL(string: "https://github.com/saiahlee/EPS-View-Plus")!)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - App delegate that manages NSWindows directly

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Strong refs to all open viewer windows so they don't deallocate.
    private var openControllers: [NSWindowController] = []

    private var pendingURLs: [URL] = []
    private var didFinishLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunch = true
        // If we received open events before launch finished, drain now.
        let queued = pendingURLs
        pendingURLs.removeAll()
        if queued.isEmpty {
            // Launched with no document — show one empty viewer window.
            spawnWindow(for: nil)
        } else {
            for url in queued { spawnWindow(for: url) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if !didFinishLaunch {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls { spawnWindow(for: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Re-open behavior: clicking the dock icon when no windows are
    /// visible should bring up an empty viewer rather than nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { spawnWindow(for: nil) }
        return true
    }

    func openFromMenu() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epsImage, .postscript]
        panel.allowsMultipleSelection = true
        panel.message = "Choose one or more EPS or PostScript files."
        if panel.runModal() == .OK {
            for url in panel.urls { spawnWindow(for: url) }
        }
    }

    /// Public entry point used by ViewerWindow's drag&drop handler when
    /// it wants additional dropped files to open as new windows.
    func spawnWindow(for url: URL?) {
        let controller = ViewerWindowController(url: url) { [weak self] closing in
            // Drop the strong ref when the window closes.
            self?.openControllers.removeAll { $0 === closing }
        }
        openControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - NSWindowController hosting our SwiftUI ViewerWindow

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {

    private let onClose: (NSWindowController) -> Void

    init(url: URL?, onClose: @escaping (NSWindowController) -> Void) {
        self.onClose = onClose

        let initialSize = NSSize(width: 600, height: 450)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url?.lastPathComponent ?? "EPS View+"
        window.contentMinSize = NSSize(width: 320, height: 240)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false

        // Host the SwiftUI viewer inside the AppKit window.
        let host = NSHostingController(
            rootView: ViewerWindow(initialURL: url)
        )
        // NSHostingController exposes the SwiftUI view's intrinsic size
        // through `preferredContentSize` and `view.fittingSize`, which
        // AppKit then uses to size the window — overriding our
        // contentRect. Force the host's preferred size to our target so
        // the window doesn't shrink to the SwiftUI minWidth/minHeight.
        host.preferredContentSize = initialSize
        window.contentViewController = host

        // After installing the contentViewController, SwiftUI may have
        // resized the window to its content's intrinsic size. Snap it
        // back to our intended initial size and recenter.
        window.setContentSize(initialSize)
        window.center()

        super.init(window: window)
        window.delegate = self

        // Cascade so multiple windows don't stack exactly on top of each other.
        Self.cascadePoint = window.cascadeTopLeft(from: Self.cascadePoint)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static var cascadePoint = NSPoint.zero

    func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @AppStorage("EPSViewer.export.defaultDPI") private var defaultDPI: Int = 300

    var body: some View {
        Form {
            Section("Export defaults") {
                Picker("Default PNG resolution", selection: $defaultDPI) {
                    Text("72 DPI — screen").tag(72)
                    Text("150 DPI — web").tag(150)
                    Text("300 DPI — print").tag(300)
                    Text("600 DPI — high quality").tag(600)
                    Text("1200 DPI — archival").tag(1200)
                }
            }
            Section("Cache") {
                Button("Reveal Cache in Finder") {
                    if let url = CacheStore.directory {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Button("Empty Cache") {
                    CacheStore.evict(olderThan: 0)
                }
                .help("Removes every file in the cache directory.")
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
