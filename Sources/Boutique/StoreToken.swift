import Foundation
import Bodega

/// An opaque token that represents an instance of ``Store``.
public final class StoreToken: NSObject, NSSecureCoding {
    let storeID: String
    let itemType: String

    init<T>(with store: Store<T>) where T: Codable & Equatable {
        self.storeID = store.id
        self.itemType = String(describing: T.self)

        super.init()
    }

    public static func ==(lhs: StoreToken, rhs: StoreToken) -> Bool {
        lhs.storeID == rhs.storeID
        && lhs.itemType == rhs.itemType
    }

    public func isSameType(as other: StoreToken) -> Bool {
        itemType == other.itemType
    }

    // MARK: NSSecureCoding Conformance

    private struct Keys {
        static let storeID = "storeID"
        static let itemType = "itemType"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(storeID as NSString, forKey: Keys.storeID)
        coder.encode(itemType as NSString, forKey: Keys.itemType)
    }

    public init?(coder: NSCoder) {
        guard let storeID = coder.decodeObject(of: NSString.self, forKey: Keys.storeID) as? String else {
            return nil
        }
        guard let itemType = coder.decodeObject(of: NSString.self, forKey: Keys.itemType) as? String else {
            return nil
        }

        self.storeID = storeID
        self.itemType = itemType

        super.init()
    }

    public static var supportsSecureCoding: Bool { true }
}

public final class StoreEventWrapper: NSObject, NSSecureCoding {
    let token: StoreToken
    let event: StoreEvent

    public init(token: StoreToken, event: StoreEvent) {
        self.token = token
        self.event = event

        super.init()
    }

    // MARK: NSSecureCoding Conformance

    private struct Keys {
        static let token = "token"
        static let eventType = "eventType"
        static let eventData = "eventData"
    }

    private enum EventType: Int {
        case update
        case remove
        case removeAll
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(token, forKey: Keys.token)

            switch event {
            case .update(let keys):
                let eventData = try JSONEncoder().encode(keys)

                coder.encode(EventType.update.rawValue, forKey: Keys.eventType)
                coder.encode(eventData as NSData, forKey: Keys.eventData)
            case .remove(let keys):
                let eventData = try JSONEncoder().encode(keys)

                coder.encode(EventType.remove.rawValue, forKey: Keys.eventType)
                coder.encode(eventData as NSData, forKey: Keys.eventData)
            case .removeAll:
                coder.encode(EventType.removeAll.rawValue, forKey: Keys.eventType)
            }
        } catch {
            assertionFailure("Error encoding store event data: \(error)")
        }
    }

    public init?(coder: NSCoder) {
        guard let token = coder.decodeObject(of: StoreToken.self, forKey: Keys.token) else {
            assertionFailure("Couldn't decode store token")
            return nil
        }

        self.token = token

        let rawEventType = coder.decodeInteger(forKey: Keys.eventType)

        guard let eventType = EventType(rawValue: rawEventType) else {
            assertionFailure("Invalid event type: \(rawEventType)")
            return nil
        }

        do {
            switch eventType {
            case .update:
                guard let eventData = coder.decodeObject(of: NSData.self, forKey: Keys.eventData) as? Data else {
                    assertionFailure("Event type \(eventType) requires event data, but none was provided")
                    return nil
                }

                let keys = try JSONDecoder().decode([CacheKey].self, from: eventData)

                self.event = .update(keys)
            case .remove:
                guard let eventData = coder.decodeObject(of: NSData.self, forKey: Keys.eventData) as? Data else {
                    assertionFailure("Event type \(eventType) requires event data, but none was provided")
                    return nil
                }

                let keys = try JSONDecoder().decode([CacheKey].self, from: eventData)

                self.event = .remove(keys)
            case .removeAll:
                self.event = .removeAll
            }

            super.init()
        } catch {
            return nil
        }
    }
}
