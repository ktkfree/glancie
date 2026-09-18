import Foundation

/// A mutable value that may be read and written from any thread.
///
/// The adapters are plain classes reached through an `async` protocol, so their
/// methods run on the cooperative pool rather than on whichever actor called
/// them. Two refreshes for the same provider can therefore overlap — the
/// periodic sweep and an activity trigger routinely do — and an unguarded
/// `Dictionary` or `Optional` mutated from both is not a stale read but heap
/// corruption.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    public init(_ value: Value) {
        self.storage = value
    }

    public var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    /// Read-modify-write as one step, for the cases where `get` then `set`
    /// would let another thread in between.
    @discardableResult
    public func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }
}
