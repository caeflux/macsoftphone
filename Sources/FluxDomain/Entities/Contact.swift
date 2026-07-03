import Foundation

/// Contato local ou futuro contato de diretório Flux (docs/06_INTEGRATIONS_FLUX.md).
public struct Contact: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let numbers: [ContactNumber]
    public let company: String?
    public let email: String?

    public init(
        id: UUID = UUID(),
        name: String,
        numbers: [ContactNumber],
        company: String? = nil,
        email: String? = nil
    ) {
        self.id = id
        self.name = name
        self.numbers = numbers
        self.company = company
        self.email = email
    }
}

public struct ContactNumber: Codable, Equatable, Sendable {
    public let label: String
    public let number: String

    public init(label: String, number: String) {
        self.label = label
        self.number = number
    }
}
