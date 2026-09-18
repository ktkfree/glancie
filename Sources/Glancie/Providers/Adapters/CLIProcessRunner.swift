import Foundation

/// Robust non-blocking CLI process execution with timeout and output capture
public enum CLIProcessRunner {
    /// Runs a CLI and returns everything it printed, or nil if it could not be
    /// found, failed to launch, or outlived `timeout`.
    ///
    /// A run that hits the timeout returns nil rather than the bytes it managed
    /// to print first: half of a usage report parses into a plausible-looking
    /// number that is simply wrong, and the callers all have a cache to fall
    /// back on that is at least honest about its age.
    ///
    /// - Parameter environment: values layered over the inherited environment,
    ///   for the variables that pick which profile a CLI reads
    ///   (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, ...).
    /// - Parameter workingDirectory: where to run. Matters for CLIs that file
    ///   their transcripts by the directory they were invoked from: left to
    ///   inherit, a probe writes into whatever project Glancie happens to be
    ///   running out of, and its own writes come back as activity.
    public static func run(
        command: String,
        arguments: [String],
        timeout: TimeInterval = 6.0,
        environment: [String: String] = [:],
        workingDirectory: URL? = nil
    ) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Search standard binary locations
                let possiblePaths = [
                    command,
                    "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/\(command)",
                    "/usr/local/bin/\(command)",
                    "/opt/homebrew/bin/\(command)"
                ]

                guard let executablePath = possiblePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                    continuation.resume(returning: nil)
                    return
                }

                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                if let workingDirectory {
                    process.currentDirectoryURL = workingDirectory
                }

                // Inherit shell PATH
                var processEnvironment = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                processEnvironment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\(processEnvironment["PATH"] ?? "")"
                for (key, value) in environment {
                    processEnvironment[key] = value
                }
                process.environment = processEnvironment

                let collector = OutputCollector()

                func finish(timedOut: Bool) {
                    // Cleanup — cancelling the timer and the read source — hangs
                    // off the collector's completion, so it happens exactly once
                    // and this stays a pure "resume the continuation".
                    guard collector.claimCompletion() else { return }
                    continuation.resume(returning: timedOut ? nil : collector.text())
                }

                process.terminationHandler = { _ in
                    // Give the reader a moment to pick up whatever was written
                    // just before exit; the handler fires as soon as the process
                    // dies, not once its output has been drained.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                        finish(timedOut: false)
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // Read through a dispatch source on a descriptor we own, rather
                // than through `FileHandle.readabilityHandler`.
                //
                // The handler version had no way to close the pipe safely: the
                // handler runs on a queue Foundation owns, so clearing it and
                // closing the file handle from here could land while a read was
                // in flight, and `availableData` on a closed descriptor raises
                // an Objective-C exception that Swift cannot catch. With a
                // source, `cancel()` guarantees the cancel handler — and so the
                // `close` — runs only after any in-flight event handler has
                // returned.
                let readFD = dup(pipe.fileHandleForReading.fileDescriptor)
                try? pipe.fileHandleForReading.close()

                guard readFD >= 0 else {
                    process.terminationHandler = nil
                    if process.isRunning { process.terminate() }
                    continuation.resume(returning: nil)
                    return
                }

                let source = DispatchSource.makeReadSource(
                    fileDescriptor: readFD,
                    queue: DispatchQueue.global(qos: .utility)
                )
                source.setEventHandler {
                    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                    let count = read(readFD, &buffer, buffer.count)
                    if count > 0 {
                        collector.append(Data(buffer[0..<count]))
                    } else if count == 0 {
                        source.cancel() // EOF: every write end is closed.
                    } else if errno != EINTR && errno != EAGAIN {
                        source.cancel()
                    }
                }
                source.setCancelHandler { close(readFD) }
                source.resume()

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                        // SIGTERM is a request; a CLI that ignores it must not
                        // keep a probe alive past its deadline.
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                            if process.isRunning {
                                kill(process.processIdentifier, SIGKILL)
                            }
                        }
                    }
                    finish(timedOut: true)
                }
                timer.resume()

                // Whichever side finishes first tears down both, and the setter
                // runs this immediately if the run is already over.
                collector.onCompletion = {
                    timer.cancel()
                    source.cancel()
                }
            }
        }
    }

    /// Accumulates a process's output and guarantees the continuation is resumed
    /// exactly once, whichever of exit or timeout gets there first.
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var completed = false
        private var completionHandler: (() -> Void)?

        var onCompletion: (() -> Void)? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return completionHandler
            }
            set {
                lock.lock()
                let alreadyCompleted = completed
                completionHandler = newValue
                lock.unlock()
                if alreadyCompleted { newValue?() }
            }
        }

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func text() -> String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }

        /// True for the first caller only.
        func claimCompletion() -> Bool {
            lock.lock()
            let isFirst = !completed
            completed = true
            let handler = completionHandler
            lock.unlock()
            if isFirst { handler?() }
            return isFirst
        }
    }
}
