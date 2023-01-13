import Foundation

public enum StoreEvent {
    case update([Bodega.CacheKey])
    case remove([Bodega.CacheKey])
    case removeAll
}

public final class StoreToken: Hashable {
    var storeID: String
    var itemType: String

    init<T>(with store: Store<T>) where T: Codable & Equatable {
        self.storeID = store.id
        self.itemType = String(describing: T.self)
    }

    public static func ==(lhs: StoreToken, rhs: StoreToken) -> Bool {
        lhs.storeID == rhs.storeID
        && lhs.itemType == rhs.itemType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storeID)
        hasher.combine(itemType)
    }

    func isSameType(as other: StoreToken) -> Bool {
        itemType == other.itemType
    }
}

public protocol StoreBroker: AnyObject {
    var storeToken: StoreToken? { get set }
    func attach<Item>(_ store: Store<Item>) where Item: Codable & Equatable
    func send(_ event: StoreEvent) async
    var events: AsyncStream<StoreEvent> { get }
}

public extension StoreBroker {
    func attach<Item>(_ store: Store<Item>) where Item: Codable & Equatable {
        storeToken = StoreToken(with: store)
    }
}

/// A default store broker that doesn't perform any synchronization.
public final class NullStoreBroker: StoreBroker {
    public var storeToken: StoreToken?

    public init() { }

    public func send(_ event: StoreEvent) async {
        switch event {
        case .update(let keys):
            print("🪄 SEND Update \(keys)")
        case .remove(let keys):
            print("🪄 SEND Remove \(keys)")
        case .removeAll:
            print("🪄 SEND Remove All")
        }
    }

    public var events: AsyncStream<StoreEvent> { AsyncStream { _ in } }
}

private extension Notification.Name {
    static let storeBrokerDidSendEvent = Notification.Name("storeBrokerDidSendEvent")
}

/// A store broker that can synchronize multiple stores within the same process.
/// Mostly useful for testing the store broker mechanism.
public final class InProcessStoreBroker: StoreBroker {
    public var storeToken: StoreToken?

    private static let notificationCenter = NotificationCenter()
    private static let notificationQueue = NotificationQueue(notificationCenter: InProcessStoreBroker.notificationCenter)

    public init() { }

    public func send(_ event: StoreEvent) async {
        assert(storeToken != nil, "Attempting to send an event without attaching the store first")

        await MainActor.run {
            let note = Notification(name: .storeBrokerDidSendEvent, object: storeToken, userInfo: ["event": event])
            Self.notificationQueue.enqueue(note, postingStyle: .asap, coalesceMask: .onSender, forModes: nil)
        }

        switch event {
        case .update(let keys):
            print("🪄 SEND Update \(keys)")
        case .remove(let keys):
            print("🪄 SEND Remove \(keys)")
        case .removeAll:
            print("🪄 SEND Remove All")
        }
    }

    public var events: AsyncStream<StoreEvent> {
        AsyncStream { continuation in
            assert(storeToken != nil, "Attempting to stream events without attaching the store first")

            let cancellable = Self.notificationCenter
                .publisher(for: .storeBrokerDidSendEvent, object: nil)
                .sink { [weak self] note in
                    guard let self = self else { return }

                    /// We only want to send an event if the sender's token is not the exact same instance
                    /// as our token, and if the sender's token is for a store which has the same item type as ours.
                    guard let ourToken = self.storeToken,
                          let senderToken = note.storeToken,
                          senderToken !== self.storeToken
                    else { return }

                    guard senderToken.isSameType(as: ourToken) else { return }

                    guard let event = note.storeEvent else { return }

                    continuation.yield(event)
                }

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}

private extension Notification {
    var storeEvent: StoreEvent? { userInfo?["event"] as? StoreEvent }

    var storeToken: StoreToken? { object as? StoreToken }
}
