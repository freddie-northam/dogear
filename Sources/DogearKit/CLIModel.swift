import Foundation

/// Runs a prompt through a command line tool and returns what it printed.
///
/// Dogear asks the model the user already pays for, rather than shipping an
/// API client and asking for a key. That keeps the dependency list empty, but
/// it does send text off the machine, so every caller is behind an opt-in.
public protocol CLIModelRunner: Sendable {
    func run(prompt: String) async throws -> String
}

public enum CLIModelError: Error, Equatable {
    /// The configured command is missing, or is not something we can run.
    case commandNotFound(String)
    /// The command ran and failed. Carries whatever it put on stderr.
    case failed(exitCode: Int32, message: String)
    /// The command ran past its deadline and was stopped.
    case timedOut
    /// The command succeeded and printed nothing useful.
    case emptyResponse
}

/// How to reach the model. The command is a full path on purpose.
///
/// An app launched from the Finder gets `/usr/bin:/bin:/usr/sbin:/sbin` and
/// nothing else, while these tools install into Homebrew, `~/.local/bin`, or
/// inside another app's bundle. Searching PATH would find nothing and fall
/// back silently, so the user names the command and can test it.
public struct CLIModelSettings: Codable, Equatable, Sendable {
    public var commandPath: String
    public var arguments: [String]
    public var timeout: Duration

    /// `claude -p <prompt>` and `codex exec <prompt>` both take the prompt as
    /// the last argument, which is why the prompt is appended rather than piped.
    public init(commandPath: String, arguments: [String] = ["-p"], timeout: Duration = .seconds(90)) {
        self.commandPath = commandPath
        self.arguments = arguments
        self.timeout = timeout
    }

    // Duration is not Codable, so the stored form is a plain seconds count.
    private enum CodingKeys: String, CodingKey { case commandPath, arguments, timeoutSeconds }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandPath = try container.decode(String.self, forKey: .commandPath)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? ["-p"]
        let seconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 90
        timeout = .seconds(seconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandPath, forKey: .commandPath)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(Int(timeout.components.seconds), forKey: .timeoutSeconds)
    }

    /// Places these tools are commonly installed, for a "find it for me"
    /// button. Only ever a suggestion: the user confirms what gets used.
    public static let likelyPaths = [
        "/opt/homebrew/bin", "/usr/local/bin",
        NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin",
    ]

    public static func findLikelyCommands(named names: [String] = ["claude", "codex"]) -> [String] {
        var found: [String] = []
        for directory in likelyPaths {
            for name in names {
                let path = directory + "/" + name
                if FileManager.default.isExecutableFile(atPath: path) { found.append(path) }
            }
        }
        return found
    }
}

/// Runs the command as a child process.
public struct ProcessCLIModelRunner: CLIModelRunner {
    let settings: CLIModelSettings

    public init(settings: CLIModelSettings) {
        self.settings = settings
    }

    public func run(prompt: String) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: settings.commandPath) else {
            throw CLIModelError.commandNotFound(settings.commandPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.commandPath)
        process.arguments = settings.arguments + [prompt]
        // These tools wait on stdin when it is a terminal, so hand them nothing.
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()

        // Read both pipes while the process runs. A tool that fills the 64 KB
        // pipe buffer while we wait for it to exit would deadlock otherwise.
        async let outData = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }.value

        let deadline = Task {
            try await Task.sleep(for: settings.timeout)
            if process.isRunning { process.terminate() }
        }
        defer { deadline.cancel() }

        let stdout = String(decoding: await outData, as: UTF8.self)
        let stderr = String(decoding: await errData, as: UTF8.self)
        process.waitUntilExit()

        if process.terminationReason == .uncaughtSignal, process.terminationStatus != 0 {
            throw CLIModelError.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw CLIModelError.failed(
                exitCode: process.terminationStatus,
                message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CLIModelError.emptyResponse }
        return trimmed
    }
}
