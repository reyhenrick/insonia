import AppKit
import Foundation

final class InteractionDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    let field = NSTextField()
    let result = NSTextField(labelWithString: "Cliques confirmados: 0")
    var clicks = 0
    let logURL: URL

    init(logURL: URL) { self.logURL = logURL }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Insonia · Interaction test"
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Visual access verification")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "This window records only its test text, clicks and the current lid position.")
        explanation.textColor = .secondaryLabelColor
        field.placeholderString = "Enter verification text"
        field.setAccessibilityIdentifier("verificationText")
        field.setAccessibilityLabel("Verification text")
        field.delegate = self
        let button = NSButton(title: "Confirmar clique", target: self, action: #selector(confirm))
        button.bezelStyle = .rounded
        let stack = NSStackView(views: [title, explanation, field, button, result])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        record("opened")
    }

    @objc func confirm() {
        clicks += 1
        result.stringValue = "Cliques confirmados: \(clicks)"
        record("clicked")
    }

    func controlTextDidChange(_ notification: Notification) { record("typed") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func record(_ event: String) {
        let row: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()),
            "event": event, "clicks": clicks, "text": field.stringValue,
            "lidClosed": MacState.lidClosed as Any? ?? NSNull(),
            "sessionAvailable": MacState.sessionAvailable, "displayAvailable": DisplayBrightness.usableDisplay]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile(); handle.write(data); handle.write(Data("\n".utf8))
        }
    }
}

@main struct InteractionProbe {
    static func main() {
        let path = CommandLine.arguments.dropFirst().first ?? "build/interaction-probe.jsonl"
        let app = NSApplication.shared
        let delegate = InteractionDelegate(logURL: URL(fileURLWithPath: path))
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
