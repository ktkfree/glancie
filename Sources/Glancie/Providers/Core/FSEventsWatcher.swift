import Foundation
import CoreServices
import Combine
import os

/// One "something is working" observation.
///
/// Carries the account when the directory that changed belongs to a known login,
/// so a write under `~/.claude-work` reports that account rather than a generic
/// "Claude is busy".
public struct ActivitySignal: Hashable {
    public let provider: AIProviderType
    public let accountID: String?

    public init(provider: AIProviderType, accountID: String?) {
        self.provider = provider
        self.accountID = accountID
    }
}

/// Native macOS FSEvents Stream wrapper for zero-CPU real-time AI quota updates
public final class FSEventsWatcher {
    public typealias ChangeHandler = (Set<ActivitySignal>) -> Void
    
    private let logger = GlancieLog.watcher
    private var eventStream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.glancie.fsevents", qos: .utility)
    private var watchedPathsMap: [(path: String, provider: AIProviderType)] = []
    private var changeHandler: ChangeHandler?
    
    private var debounceSubject = PassthroughSubject<ActivitySignal, Never>()
    /// Longest-prefix table mapping a changed path back to the account working
    /// out of it. Supplied by `ProviderManager` after each account scan.
    private var accountPaths: [(path: String, provider: AIProviderType, accountID: String)] = []
    private let accountPathsLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    
    private let ruleRegistry: AIActivityRuleRegistry
    private let filterEngine: AIActivityFilterEngine
    
    public init(ruleRegistry: AIActivityRuleRegistry = .shared) {
        self.ruleRegistry = ruleRegistry
        self.filterEngine = AIActivityFilterEngine(registry: ruleRegistry)
        setupDebouncePipeline()
    }
    
    deinit {
        stop()
    }
    
    private func setupDebouncePipeline() {
        // Collect and debounce high-frequency file write events (streaming logs)
        debounceSubject
            .collect(.byTime(queue, .milliseconds(600)))
            .filter { !$0.isEmpty }
            .sink { [weak self] signals in
                let unique = Set(signals)
                let described = unique.map { signal in
                    signal.accountID.map { "\(signal.provider.rawValue)/\($0.prefix(8))" }
                        ?? signal.provider.rawValue
                }
                self?.logger.debug("Streaming activity dispatched for: \(described.joined(separator: ", "), privacy: .public)")
                self?.changeHandler?(unique)
            }
            .store(in: &cancellables)
    }
    
    /// Starts watching paths relevant to registered AI Provider rules
    public func startWatching(handler: @escaping ChangeHandler) {
        stop()
        self.changeHandler = handler
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fileManager = FileManager.default
        
        // Dynamically build candidate mappings from the Rule Registry
        var candidateMappings: [(path: String, provider: AIProviderType)] = []
        for rule in ruleRegistry.allRules {
            for relPath in rule.relativeRootPaths {
                let fullPath = relPath.hasPrefix("/")
                    ? relPath
                    : home.appendingPathComponent(relPath).path
                candidateMappings.append((fullPath, rule.provider))
            }
        }
        
        // Only watch paths that currently exist on the filesystem
        watchedPathsMap = candidateMappings.filter { mapping in
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: mapping.path, isDirectory: &isDir) && isDir.boolValue
            return exists
        }
        
        logger.info("Monitoring \(self.watchedPathsMap.count) active paths")
        for mapping in watchedPathsMap {
            logger.info("Watching \(mapping.path, privacy: .public) for \(mapping.provider.rawValue, privacy: .public)")
        }
        
        guard !watchedPathsMap.isEmpty else {
            logger.info("No candidate directory paths exist to watch")
            return
        }
        
        let pathsToWatch = watchedPathsMap.map { $0.path as CFString } as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            watcher.handleEvents(paths: paths, numEvents: numEvents)
        }
        
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // 0.3s responsive latency
            flags
        )
        
        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            logger.info("FSEventStream started")
        }
    }
    
    private func handleEvents(paths: [String], numEvents: Int) {
        for eventPath in paths {
            for mapping in watchedPathsMap {
                guard Self.path(eventPath, isWithin: mapping.path) else { continue }
                
                let provider = mapping.provider
                let (shouldDispatch, reason) = filterEngine.shouldDispatchBurst(provider: provider, eventPath: eventPath)
                
                if shouldDispatch {
                    let accountID = resolveAccount(provider: provider, eventPath: eventPath)
                    logger.debug("[\(provider.rawValue, privacy: .public)] \(reason, privacy: .public)")
                    debounceSubject.send(ActivitySignal(provider: provider, accountID: accountID))
                    break
                } else {
                    logger.debug("[\(provider.rawValue)] Filtered: \(reason) -> \(eventPath)")
                }
            }
        }
    }
    
    /// Rebuilds the path-to-account table. Safe to call while watching.
    public func updateAccountPaths(
        _ paths: [(path: String, provider: AIProviderType, accountID: String)]
    ) {
        accountPathsLock.lock()
        defer { accountPathsLock.unlock() }
        // Longest first, so `~/.claude-work` wins over a shorter prefix that
        // happens to also match.
        accountPaths = paths.sorted { $0.path.count > $1.path.count }
    }

    /// The account whose directory contains `eventPath`, if any is known.
    private func resolveAccount(provider: AIProviderType, eventPath: String) -> String? {
        accountPathsLock.lock()
        defer { accountPathsLock.unlock() }
        return accountPaths.first {
            $0.provider == provider && Self.path(eventPath, isWithin: $0.path)
        }?.accountID
    }

    /// Whether `path` is the directory `root` or something inside it.
    ///
    /// A bare `hasPrefix` is not that test: `~/.claude` is a prefix of
    /// `~/.claude-work` and of `~/.claude.json`, so a second profile's writes
    /// would be attributed to the first watched root that happened to spell its
    /// name. Harmless while both roots belong to the same provider, and a silent
    /// misattribution the moment they do not.
    static func path(_ path: String, isWithin root: String) -> Bool {
        if path == root { return true }
        let boundary = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(boundary)
    }

    public func stop() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
            logger.info("FSEventStream stopped")
        }
    }
}
