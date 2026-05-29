import CoreGraphics
import Darwin
import Foundation

private enum ExitCode: Int32 {
    case success = 0
    case usage = 2
    case unavailable = 69
    case unsafe = 78
    case failure = 1
}

private enum Command: String {
    case status
    case disable
    case enable
    case help
}

private struct Display {
    let id: CGDirectDisplayID
    let isBuiltin: Bool
    let isActive: Bool

    var state: String {
        isActive ? "enabled" : "disabled"
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case noBuiltinDisplay
    case noExternalDisplay
    case noSavedBuiltinDisplay(URL)
    case privateAPIUnavailable(String)
    case coreGraphicsFailed(Int32)
    case cannotSaveBuiltinDisplayID(URL, Error)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .noBuiltinDisplay:
            return "Could not detect a built-in MacBook display."
        case .noExternalDisplay:
            return "Refusing to disable the built-in display: no connected external display was detected."
        case .noSavedBuiltinDisplay(let url):
            return "Could not find a saved built-in display id at \(url.path). Log out/reboot, then run disable once with this version so future enables can recover."
        case .privateAPIUnavailable(let symbol):
            return "Private CoreGraphics symbol '\(symbol)' is unavailable on this system."
        case .coreGraphicsFailed(let code):
            return "CoreGraphics display configuration failed with CGError raw value \(code)."
        case .cannotSaveBuiltinDisplayID(let url, let error):
            return "Could not save built-in display id to \(url.path): \(error.localizedDescription)"
        }
    }
}

private typealias CGSConfigureDisplayEnabledFunction =
    @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> Int32

private struct DisplayToggler {
    private let configureDisplayEnabled: CGSConfigureDisplayEnabledFunction

    init() throws {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ) else {
            throw CLIError.privateAPIUnavailable("CoreGraphics")
        }

        guard let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") else {
            throw CLIError.privateAPIUnavailable("CGSConfigureDisplayEnabled")
        }
        configureDisplayEnabled = unsafeBitCast(symbol, to: CGSConfigureDisplayEnabledFunction.self)
    }

    func setDisplay(_ displayID: CGDirectDisplayID, enabled: Bool) throws {
        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success, let config else {
            throw CLIError.coreGraphicsFailed(error.rawValue)
        }

        let result = configureDisplayEnabled(config, displayID, enabled)
        guard result == CGError.success.rawValue else {
            CGCancelDisplayConfiguration(config)
            throw CLIError.coreGraphicsFailed(result)
        }

        error = CGCompleteDisplayConfiguration(config, .forSession)
        guard error == .success else {
            throw CLIError.coreGraphicsFailed(error.rawValue)
        }
    }
}

private func parseCommand(_ arguments: [String]) throws -> Command {
    guard let first = arguments.first else {
        return .status
    }
    guard arguments.count == 1 else {
        throw CLIError.usage("Only one command may be provided.")
    }

    switch first {
    case "--help", "-h":
        return .help
    default:
        guard let command = Command(rawValue: first) else {
            throw CLIError.usage("Unknown command: \(first)")
        }
        return command
    }
}

private func usage() -> String {
    """
    Usage:
      macbook-display
      macbook-display status
      macbook-display disable
      macbook-display enable

    Commands:
      status    Show built-in and external display state.
      disable   Disable the MacBook built-in display for the current login session.
      enable    Re-enable the last disabled MacBook built-in display.
    """
}

private func onlineDisplays() throws -> [Display] {
    var count: UInt32 = 0
    var error = CGGetOnlineDisplayList(0, nil, &count)
    guard error == .success else {
        throw CLIError.coreGraphicsFailed(error.rawValue)
    }
    guard count > 0 else {
        return []
    }

    var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
    error = CGGetOnlineDisplayList(count, &ids, &count)
    guard error == .success else {
        throw CLIError.coreGraphicsFailed(error.rawValue)
    }

    return ids.prefix(Int(count)).map { id in
        Display(
            id: id,
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isActive: CGDisplayIsActive(id) != 0
        )
    }
}

private func stateFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("macbook-display-\(getuid())", isDirectory: true)
        .appendingPathComponent("builtin-display-id")
}

private func saveBuiltinDisplayID(_ displayID: CGDirectDisplayID, to url: URL = stateFileURL()) throws {
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "\(displayID)\n".write(to: url, atomically: true, encoding: .utf8)
    } catch {
        throw CLIError.cannotSaveBuiltinDisplayID(url, error)
    }
}

private func loadBuiltinDisplayID(from url: URL = stateFileURL()) throws -> CGDirectDisplayID {
    guard
        let contents = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        let id = UInt32(contents, radix: 10)
    else {
        throw CLIError.noSavedBuiltinDisplay(url)
    }
    return CGDirectDisplayID(id)
}

private func printStatus(_ displays: [Display]) {
    let builtin = displays.first(where: { $0.isBuiltin })
    let externalCount = displays.filter { !$0.isBuiltin }.count

    if let builtin {
        print("built-in: \(builtin.state) (\(builtin.id))")
    } else {
        print("built-in: not detected")
    }
    print("external: \(externalCount) connected")
}

private func disable(displays: [Display]) throws {
    guard displays.contains(where: { !$0.isBuiltin }) else {
        throw CLIError.noExternalDisplay
    }
    guard let builtin = displays.first(where: { $0.isBuiltin }) else {
        throw CLIError.noBuiltinDisplay
    }
    guard builtin.isActive else {
        print("built-in display is already disabled")
        return
    }

    try saveBuiltinDisplayID(builtin.id)
    try DisplayToggler().setDisplay(builtin.id, enabled: false)
    print("disabled built-in display \(builtin.id)")
}

private func enable(displays: [Display]) throws {
    if let builtin = displays.first(where: { $0.isBuiltin }) {
        guard !builtin.isActive else {
            print("built-in display is already enabled")
            return
        }

        try DisplayToggler().setDisplay(builtin.id, enabled: true)
        print("enabled built-in display \(builtin.id)")
        return
    }

    let displayID = try loadBuiltinDisplayID()
    try DisplayToggler().setDisplay(displayID, enabled: true)
    print("enabled built-in display \(displayID)")
}

private func run() throws {
    let command = try parseCommand(Array(CommandLine.arguments.dropFirst()))

    if command == .help {
        print(usage())
        return
    }

    let displays = try onlineDisplays()

    switch command {
    case .status:
        printStatus(displays)
    case .disable:
        try disable(displays: displays)
    case .enable:
        try enable(displays: displays)
    case .help:
        print(usage())
    }
}

do {
    try run()
} catch let error as CLIError {
    fputs("macbook-display: \(error.description)\n", stderr)
    if case .usage = error {
        fputs("\n\(usage())\n", stderr)
        exit(ExitCode.usage.rawValue)
    }

    switch error {
    case .privateAPIUnavailable:
        exit(ExitCode.unavailable.rawValue)
    case .noBuiltinDisplay, .noExternalDisplay, .noSavedBuiltinDisplay:
        exit(ExitCode.unsafe.rawValue)
    case .coreGraphicsFailed, .cannotSaveBuiltinDisplayID:
        exit(ExitCode.failure.rawValue)
    case .usage:
        exit(ExitCode.usage.rawValue)
    }
} catch {
    fputs("macbook-display: \(error)\n", stderr)
    exit(ExitCode.failure.rawValue)
}
