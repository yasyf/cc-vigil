import CCVigilShared
import CryptoKit
import Foundation

private struct PersistedCodingKey: CodingKey {
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

private func requireEnvelopeKeys(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: PersistedCodingKey.self)
    let actual = Set(container.allKeys.map(\.stringValue))
    let expected: Set = ["payload", "schema", "schemaFingerprint", "schemaVersion"]
    guard actual == expected else {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "expected keys \(expected.sorted()), found \(actual.sorted())"
            )
        )
    }
}

public enum PersistedSchemaV1 {
    public static let configIdentity = "dev.yasyf.cc-vigil.config"
    public static let stateIdentity = "dev.yasyf.cc-vigil.state"
    public static let version = 1

    public static let configFingerprint = fingerprint(
        identity: configIdentity,
        descriptor: [
            "payload{activityWindowSeconds:int,batteryFloorPercent:int,hideMenuBarExtra:bool,",
            "lowPowerCutout:bool,notifyOnCutout:bool,notifyOnRelease:bool,pendingAsyncMaxAgeSeconds:int,",
            "pollBlockingSeconds:int,pollIdleSeconds:int,thermalCutoutCelsius:double,transcriptsRoots:[string]}",
        ].joined()
    )

    public static let stateFingerprint = fingerprint(
        identity: stateIdentity,
        descriptor: [
            "payload{alertedCutouts:set<battery|thermal|low-power>,holds:[{createdAt:epoch-seconds,",
            "key:string,pid?:int32,reason:string,ttlSeconds:int}],nextAlertId:int64,",
            "pausedUntil?:epoch-seconds,recentAlerts:[released{atEpoch:int64,holds:int,id:int64,",
            "kind:released,sessions:int}|cutout{atEpoch:int64,id:int64,kind:cutoutLatched,",
            "kinds:[battery|thermal|low-power]}],registeredRoots:[string]}",
        ].joined()
    )

    private static func fingerprint(identity: String, descriptor: String) -> String {
        let digest = SHA256.hash(data: Data("\(identity)\u{0}v1\u{0}\(descriptor)".utf8))
        return "\(identity)." + digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct PersistedEnvelope<Payload: Codable>: Codable {
    let schema: String
    let schemaVersion: Int
    let schemaFingerprint: String
    let payload: Payload

    init(schema: String, schemaVersion: Int, schemaFingerprint: String, payload: Payload) {
        self.schema = schema
        self.schemaVersion = schemaVersion
        self.schemaFingerprint = schemaFingerprint
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        try requireEnvelopeKeys(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        schemaFingerprint = try container.decode(String.self, forKey: .schemaFingerprint)
        payload = try container.decode(Payload.self, forKey: .payload)
    }
}

enum PersistedSchemaCodec {
    static func decodeConfig(_ data: Data) throws -> VigilConfig {
        try decode(
            VigilConfig.self,
            from: data,
            identity: PersistedSchemaV1.configIdentity,
            fingerprint: PersistedSchemaV1.configFingerprint
        )
    }

    static func encodeConfig(_ config: VigilConfig) throws -> Data {
        try encode(
            config,
            identity: PersistedSchemaV1.configIdentity,
            fingerprint: PersistedSchemaV1.configFingerprint,
            prettyPrinted: true
        )
    }

    static func decodeState(_ data: Data) throws -> PersistedState {
        try decode(
            PersistedState.self,
            from: data,
            identity: PersistedSchemaV1.stateIdentity,
            fingerprint: PersistedSchemaV1.stateFingerprint
        )
    }

    static func encodeState(_ state: PersistedState) throws -> Data {
        try encode(
            state,
            identity: PersistedSchemaV1.stateIdentity,
            fingerprint: PersistedSchemaV1.stateFingerprint,
            prettyPrinted: false
        )
    }

    private static func decode<Payload: Codable>(
        _: Payload.Type,
        from data: Data,
        identity: String,
        fingerprint: String
    ) throws -> Payload {
        let envelope = try decoder().decode(PersistedEnvelope<Payload>.self, from: data)
        guard envelope.schema == identity else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "schema must equal \(identity)")
            )
        }
        guard envelope.schemaVersion == PersistedSchemaV1.version else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "schemaVersion must equal \(PersistedSchemaV1.version)")
            )
        }
        guard envelope.schemaFingerprint == fingerprint else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "schemaFingerprint must equal \(fingerprint)")
            )
        }
        return envelope.payload
    }

    private static func encode(
        _ payload: some Codable,
        identity: String,
        fingerprint: String,
        prettyPrinted: Bool
    ) throws -> Data {
        let envelope = PersistedEnvelope(
            schema: identity,
            schemaVersion: PersistedSchemaV1.version,
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

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
