import Foundation

enum ProcessError: LocalizedError {
    case nonzeroExit(status: Int32, stderr: String)
    case spawnFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .nonzeroExit(let status, let stderr):
            let preview = stderr.prefix(500)
            return "Converter exited with status \(status). \(preview)"
        case .spawnFailed(let error):
            return "Could not launch converter: \(error.localizedDescription)"
        }
    }
}

enum ProcessRunner {
    /// Runs `executable` with `arguments`, blocking until exit. Throws on
    /// non-zero exit status.
    ///
    /// Stdout is discarded; stderr is captured and returned in the error.
    static func run(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // discard

        do {
            try process.run()
        } catch {
            throw ProcessError.spawnFailed(underlying: error)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data: Data = ((try? stderrPipe.fileHandleForReading.readToEnd()) ?? nil) ?? Data()
            let message = String(data: data, encoding: .utf8) ?? "(unreadable stderr)"
            throw ProcessError.nonzeroExit(status: process.terminationStatus, stderr: message)
        }
    }
}
