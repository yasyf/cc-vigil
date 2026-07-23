import CryptoKit
import Foundation

public enum ExactPersistedJSONV1 {
    public static let version = 1

    public static func fingerprint(identity: String, descriptor: String) -> String {
        let digest = SHA256.hash(data: Data("\(identity)\u{0}v1\u{0}\(descriptor)".utf8))
        return "\(identity)." + digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func encode(
        _ payload: some Encodable,
        identity: String,
        fingerprint: String,
        prettyPrinted: Bool = false
    ) throws -> Data {
        let envelope = EncodingEnvelope(
            schema: identity,
            schemaVersion: version,
            schemaFingerprint: fingerprint,
            payload: payload
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(envelope)
    }

    public static func decode<Payload: Decodable>(
        _: Payload.Type,
        from data: Data,
        identity: String,
        fingerprint: String
    ) throws -> Payload {
        var document = ExactJSONDocument(data: data)
        try document.validate()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let envelope = try decoder.decode(DecodingEnvelope<Payload>.self, from: data)
        guard envelope.schema == identity else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "schema must equal \(identity)")
            )
        }
        guard envelope.schemaVersion == version else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "schemaVersion must equal \(version)")
            )
        }
        guard envelope.schemaFingerprint == fingerprint else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "schemaFingerprint must equal \(fingerprint)")
            )
        }
        return envelope.payload
    }
}

private struct EncodingEnvelope<Payload: Encodable>: Encodable {
    let schema: String
    let schemaVersion: Int
    let schemaFingerprint: String
    let payload: Payload
}

private struct DecodingEnvelope<Payload: Decodable>: Decodable {
    private enum CodingKeys: String, CodingKey {
        case schema, schemaVersion, schemaFingerprint, payload
    }

    let schema: String
    let schemaVersion: Int
    let schemaFingerprint: String
    let payload: Payload

    init(from decoder: Decoder) throws {
        try requireExactKeys(
            from: decoder,
            required: ["payload", "schema", "schemaFingerprint", "schemaVersion"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        schemaFingerprint = try container.decode(String.self, forKey: .schemaFingerprint)
        payload = try container.decode(Payload.self, forKey: .payload)
    }
}

private struct ExactJSONDocument {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func validate() throws {
        skipWhitespace()
        try scanValue()
        skipWhitespace()
        guard index == bytes.count else {
            throw error("trailing JSON data")
        }
    }

    private mutating func scanValue() throws {
        guard let byte = current else { throw error("expected JSON value") }
        switch byte {
        case ascii("{"):
            try scanObject()
        case ascii("["):
            try scanArray()
        case ascii("\""):
            _ = try scanString()
        case ascii("t"):
            try scanLiteral("true")
        case ascii("f"):
            try scanLiteral("false")
        case ascii("n"):
            try scanLiteral("null")
        case ascii("-"), ascii("0") ... ascii("9"):
            try scanNumber()
        default:
            throw error("invalid JSON value")
        }
    }

    private mutating func scanObject() throws {
        index += 1
        skipWhitespace()
        var keys: Set<String> = []
        if consume(ascii("}")) {
            return
        }
        while true {
            guard current == ascii("\"") else { throw error("expected object key") }
            let key = try scanString()
            guard keys.insert(key).inserted else { throw error("duplicate object key \(key)") }
            skipWhitespace()
            guard consume(ascii(":")) else { throw error("expected colon after object key") }
            skipWhitespace()
            try scanValue()
            skipWhitespace()
            if consume(ascii("}")) {
                return
            }
            guard consume(ascii(",")) else { throw error("expected comma or closing brace") }
            skipWhitespace()
        }
    }

    private mutating func scanArray() throws {
        index += 1
        skipWhitespace()
        if consume(ascii("]")) {
            return
        }
        while true {
            try scanValue()
            skipWhitespace()
            if consume(ascii("]")) {
                return
            }
            guard consume(ascii(",")) else { throw error("expected comma or closing bracket") }
            skipWhitespace()
        }
    }

    private mutating func scanString() throws -> String {
        let start = index
        index += 1
        while let byte = current {
            switch byte {
            case ascii("\""):
                index += 1
                let token = Data(bytes[start ..< index])
                return try JSONDecoder().decode(String.self, from: token)
            case ascii("\\"):
                index += 1
                guard current != nil else { throw error("unterminated string escape") }
                index += 1
            case 0 ... 0x1F:
                throw error("unescaped control character in string")
            default:
                index += 1
            }
        }
        throw error("unterminated string")
    }

    private mutating func scanLiteral(_ literal: StaticString) throws {
        for byte in literal.description.utf8 {
            guard consume(byte) else { throw error("invalid JSON literal") }
        }
    }

    private mutating func scanNumber() throws {
        if consume(ascii("-")), current == nil {
            throw error("incomplete JSON number")
        }
        if consume(ascii("0")) {
            if let current, ascii("0") ... ascii("9") ~= current {
                throw error("leading zero in JSON number")
            }
        } else {
            try consumeDigits(required: true)
        }
        if consume(ascii(".")) {
            try consumeDigits(required: true)
        }
        if consume(ascii("e")) || consume(ascii("E")) {
            _ = consume(ascii("+")) || consume(ascii("-"))
            try consumeDigits(required: true)
        }
    }

    private mutating func consumeDigits(required: Bool) throws {
        let start = index
        while let current, ascii("0") ... ascii("9") ~= current {
            index += 1
        }
        if required, index == start {
            throw error("expected digit")
        }
    }

    private mutating func skipWhitespace() {
        while let current, [ascii(" "), ascii("\n"), ascii("\r"), ascii("\t")].contains(current) {
            index += 1
        }
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        index += 1
        return true
    }

    private func error(_ message: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: "\(message) at byte \(index)"))
    }
}

private func ascii(_ character: StaticString) -> UInt8 {
    precondition(character.utf8CodeUnitCount == 1)
    return character.utf8Start.pointee
}
