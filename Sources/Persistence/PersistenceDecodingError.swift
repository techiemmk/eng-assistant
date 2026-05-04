import Foundation

public enum PersistenceDecodingError: Error, Equatable {
    case malformedField(table: String, column: String, value: String)
}
