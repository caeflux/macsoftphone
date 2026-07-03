import Foundation

/// Dispositivo de áudio disponível no sistema.
public struct AudioDevice: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case input
        case output
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let isDefault: Bool

    public init(id: String, name: String, kind: Kind, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isDefault = isDefault
    }
}
