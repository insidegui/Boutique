import Foundation
import OSLog

public enum StoreEvent {
    case update([Bodega.CacheKey])
    case remove([Bodega.CacheKey])
    case removeAll
}

/// An opaque token that represents an instance of ``Store``.
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

    public func isSameType(as other: StoreToken) -> Bool {
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
