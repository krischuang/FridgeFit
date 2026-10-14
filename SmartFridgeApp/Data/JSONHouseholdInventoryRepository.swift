import Foundation

/// JSON-backed household inventory repository used by the current MVP.
///
/// The concrete persistence technology is file-based JSON through
/// `JSONInventoryPersistence`. `InventoryService` remains as a compatibility
/// facade for existing SwiftUI injection points while the domain-facing name is
/// explicit about the actual storage approach.
public typealias JSONHouseholdInventoryRepository = InventoryService
