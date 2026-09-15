import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--render-check"), CommandLine.arguments.count > index + 1 {
    do {
        try IntegrationCheck.run(output: CommandLine.arguments[index + 1])
        exit(0)
    } catch {
        fputs("Render check failed: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
