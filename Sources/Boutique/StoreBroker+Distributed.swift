#if os(macOS)
import Foundation
import OSLog

/// A store broker that can synchronize multiple stores across processes on macOS using `DistributedNotificationCenter`.
///
/// - warning: Using this broker for sensitive data is not recommended, since any process running on the same machine can
/// technically receive the messages sent over the Darwin notification center.
public final class DistributedNotificationStoreBroker: StoreBroker {
    private lazy var logger = Logger(subsystem: kBoutiqueStoreSubsystem, category: String(describing: Self.self))

    public var storeToken: StoreToken?

    private static let notificationCenter = DistributedNotificationCenter.default()

    /// A name that identifies the broker across processes.
    public let name: String

    private lazy var notificationName: Notification.Name = {
        Notification.Name("\(name)-distributedStoreBrokerDidSendEvent")
    }()

    /// Creates a broker that can be used to synchronize multiple stores across processes on macOS.
    /// - Parameter name: A name that identifies the broker across processes.
    /// You should use a unique string to avoid potential collisions with other processes on the same machine
    /// that are also using ``DistributedNotificationStoreBroker``. The string must be the same
    /// for every process you wish to synchronize using the broker.
    public init(name: String) {
        self.name = name
    }

    public func send(_ event: StoreEvent) async {
        guard let storeToken else {
            logger.fault("Attempting to send an event without attaching the store first")
            assertionFailure("Attempting to send an event without attaching the store first")
            return
        }

        switch event {
        case .update(let keys):
            logger.debug("🪄 SEND Update \(keys)")
        case .remove(let keys):
            logger.debug("🪄 SEND Remove \(keys)")
        case .removeAll:
            logger.debug("🪄 SEND Remove All")
        }

        let payload = event.base64Encoded(with: storeToken)

        await MainActor.run {
            Self.notificationCenter.postNotificationName(notificationName, object: payload, deliverImmediately: true)
        }
    }

    public var events: AsyncStream<StoreEvent> {
        AsyncStream { continuation in
            if storeToken == nil {
                logger.fault("Attempting to stream events without attaching the store first")
                assertionFailure("Attempting to stream events without attaching the store first")
            }

            let cancellable = Self.notificationCenter
                .publisher(for: notificationName, object: nil)
                .sink { [weak self] note in
                    guard let self = self else { return }

                    /// We only want to send an event if the sender's token is not the exact same instance
                    /// as our token, and if the sender's token is for a store which has the same item type as ours.
                    guard let ourToken = self.storeToken,
                          let info = note.decoded(),
                          info.token !== self.storeToken
                    else { return }

                    guard info.token.isSameType(as: ourToken) else { return }

                    continuation.yield(info.event)
                }

            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}

private extension Notification {
    func decoded() -> (token: StoreToken, event: StoreEvent)? {
        guard let input = object as? String else { return nil }
        return StoreEvent.fromBase64(input)
    }
}

private extension StoreEvent {
    func base64Encoded(with token: StoreToken) -> String {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(StoreEventWrapper(token: token, event: self), forKey: NSKeyedArchiveRootObjectKey)

        archiver.finishEncoding()

        return archiver.encodedData.base64EncodedString()
    }

    static func fromBase64(_ input: String) -> (token: StoreToken, event: StoreEvent)? {
        guard let data = Data(base64Encoded: Data(input.utf8)) else { return nil }
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true

        guard let wrapper = unarchiver.decodeObject(of: StoreEventWrapper.self, forKey: NSKeyedArchiveRootObjectKey) else { return nil }

        return (wrapper.token, wrapper.event)
    }
}


#endif
