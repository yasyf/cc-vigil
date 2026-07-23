import Foundation

struct ExactCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public func requireExactKeys(
    from decoder: Decoder,
    required: Set<String>,
    optional: Set<String> = []
) throws {
    let container = try decoder.container(keyedBy: ExactCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    let allowed = required.union(optional)
    guard required.isSubset(of: actual), actual.isSubset(of: allowed) else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "expected keys \(allowed.sorted()), found \(actual.sorted())"
            )
        )
    }
}
