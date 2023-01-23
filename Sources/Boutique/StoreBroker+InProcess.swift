import Foundation
import OSLog

private extension Notification.Name {
    static let storeBrokerDidSendEvent = Notification.Name("storeBrokerDidSendEvent")
}

/// A store broker that can synchronize multiple stores within the same process.
/// Mostly useful for testing the store broker mechanism.
public final class InProcessStoreBroker: StoreBroker {
    private lazy var logger = Logger(subsystem: kBoutiqueStoreSubsystem, category: String(describing: Self.self))

    public var storeToken: StoreToken?

    private static let notificationCenter = NotificationCenter()
    private static let notificationQueue = NotificationQueue(notificationCenter: InProcessStoreBroker.notificationCenter)

    public init() { }

    public func send(_ event: StoreEvent) async {
        if storeToken == nil {
            logger.fault("Attempting to send an event without attaching the store first")
            assertionFailure("Attempting to send an event without attaching the store first")
        }

        switch event {
        case .update(let keys):
            logger.debug("🪄 SEND Update \(keys)")
        case .remove(let keys):
            logger.debug("🪄 SEND Remove \(keys)")
        case .removeAll:
            logger.debug("🪄 SEND Remove All")
        }

        await MainActor.run {
            let note = Notification(name: .storeBrokerDidSendEvent, object: storeToken, userInfo: ["event": event])
            Self.notificationQueue.enqueue(note, postingStyle: .asap, coalesceMask: .onSender, forModes: nil)
        }
    }

    public var events: AsyncStream<StoreEvent> {
        AsyncStream { continuation in
            if storeToken == nil {
                logger.fault("Attempting to stream events without attaching the store first")
                assertionFailure("Attempting to stream events without attaching the store first")
            }

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
