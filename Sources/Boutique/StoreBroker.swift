import Foundation
import OSLog
import Bodega

/// Represents an event that causes items in a store to be invalidated.
///
/// This type is used by ``StoreBroker`` and its implementations.
public enum StoreEvent: Hashable {
    /// The store sends this event when items are added or updated.
    case update([Bodega.CacheKey])
    /// The store sends this event when specific items are removed.
    case remove([Bodega.CacheKey])
    /// The store sends this event when all items are removed.
    case removeAll
}

/// A ``StoreBroker`` is responsible for exchanging events between multiple ``Store`` instances that share the same underlying storage.
///
/// You configure a store with a specific broker type by passing an instance of the broker type in the store's initializer.
/// The store then attaches itself to the broker and begins sending it events whenever items are added, updated, or removed from the store.
/// At the same time, the store also uses the broker to receive events from other store instances, updating its in-memory cache accordingly.
///
/// The broker is only used for exchanging events between stores, so it's the client's responsibility to ensure that the storage engine used by
/// the stores is backed by the same underlying data, such as a SQLite database in a shared app group container.
public protocol StoreBroker: AnyObject {
    /// A ``StoreToken`` identifying the store this broker is currently attached to.
    var storeToken: StoreToken? { get set }

    /// Attaches a given instance of ``Store`` to this broker.
    ///
    /// There's a default implementation provider that creates a token and stores it in ``storeToken``.
    func attach<Item>(_ store: Store<Item>) where Item: Codable & Equatable

    /// Called by the store right after it performs an operation that changes its underlying storage.
    ///
    /// A broker's implementation of this method will perform the necessary steps to propagate the event to other brokers.
    func send(_ event: StoreEvent) async

    /// Used by the attached store to stream events sent by other store instances.
    ///
    /// The broker should only publish events for changes made by other store instances
    /// that manage the same item type.
    ///
    /// When implementing a custom broker, you may use ``StoreToken/isSameType(as:)``
    /// to check if an incoming message should be relayed to the attached store.
    var events: AsyncStream<StoreEvent> { get }
}

public extension StoreBroker {
    func attach<Item>(_ store: Store<Item>) where Item: Codable & Equatable {
        storeToken = StoreToken(with: store)
    }
}
