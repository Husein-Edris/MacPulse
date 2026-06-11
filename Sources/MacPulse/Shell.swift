import Foundation

/// Minimal helper for running trusted system binaries with absolute paths.
/// Never interpolates user input into a shell — arguments are passed as an array.
enum Shell {
    static func run(_ path: String, _ args: [String] = []) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waitUntilExit to avoid pipe-buffer deadlock on large output.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
