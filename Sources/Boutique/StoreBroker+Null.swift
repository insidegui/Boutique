import Foundation

/// A default store broker that doesn't perform any synchronization.
public final class NullStoreBroker: StoreBroker {
    public var storeToken: StoreToken?

    public init() { }

    public func send(_ event: StoreEvent) async { }

    public var events: AsyncStream<StoreEvent> { AsyncStream { _ in } }
}
