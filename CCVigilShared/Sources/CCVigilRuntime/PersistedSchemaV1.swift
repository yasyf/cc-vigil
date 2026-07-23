import CCVigilShared
import Foundation

public enum PersistedSchemaV1 {
    public static let configIdentity = "dev.yasyf.cc-vigil.config"
    public static let stateIdentity = "dev.yasyf.cc-vigil.state"
    public static let eventIdentity = "dev.yasyf.cc-vigil.event"
    public static let version = ExactPersistedJSONV1.version

    public static let configFingerprint = ExactPersistedJSONV1.fingerprint(
        identity: configIdentity,
        descriptor: [
            "payload{activityWindowSeconds:int,batteryFloorPercent:int,hideMenuBarExtra:bool,",
            "lowPowerCutout:bool,notifyOnCutout:bool,notifyOnRelease:bool,pendingAsyncMaxAgeSeconds:int,",
            "pollBlockingSeconds:int,pollIdleSeconds:int,thermalCutoutCelsius:double,transcriptsRoots:[string]}",
        ].joined()
    )

    public static let stateFingerprint = ExactPersistedJSONV1.fingerprint(
        identity: stateIdentity,
        descriptor: [
            "payload{alertedCutouts:set<battery|thermal|low-power>,holds:[{createdAt:epoch-seconds,",
            "key:string,pid?:int32,reason:string,ttlSeconds:int}],nextAlertId:int64,",
            "pausedUntil?:epoch-seconds,recentAlerts:[released{atEpoch:int64,holds:int,id:int64,",
            "kind:released,sessions:int}|cutout{atEpoch:int64,id:int64,kind:cutoutLatched,",
            "kinds:[battery|thermal|low-power]}],registeredRoots:[string]}",
        ].joined()
    )

    public static let eventFingerprint = ExactPersistedJSONV1.fingerprint(
        identity: eventIdentity,
        descriptor: [
            "payload:event{at:epoch-seconds,",
            "kind:daemon-started{dryRun:bool,version:string}|daemon-stopped{}|",
            "block-edge{applied:bool,blocked:bool,decision:{activeSessions:[{path:string,",
            "reasons:[recent-activity|mid-tool|waiting|background-work]}],discounts:[{path:string,",
            "reason:human-wait-hint|pending-async-max-age|stale-activity-max-age|session-process-dead}],",
            "shouldBlock:bool},holds:[{createdAt:epoch-seconds,key:string,pid?:int32,reason:string,",
            "ttlSeconds:int}]}|cutout-latched{kind:battery|thermal|low-power}|",
            "cutout-cleared{kind:battery|thermal|low-power}|lid{closed:bool}|",
            "hold-added{hold:{createdAt:epoch-seconds,key:string,pid?:int32,reason:string,ttlSeconds:int}}|",
            "hold-released{key:string}|holds-expired{keys:[string]}|",
            "probe-failed{message:string,path:string}|paused{until:epoch-seconds}|resumed{}|wake{}}",
        ].joined()
    )
}

enum PersistedSchemaCodec {
    static func decodeConfig(_ data: Data) throws -> VigilConfig {
        try ExactPersistedJSONV1.decode(
            VigilConfig.self,
            from: data,
            identity: PersistedSchemaV1.configIdentity,
            fingerprint: PersistedSchemaV1.configFingerprint
        )
    }

    static func encodeConfig(_ config: VigilConfig) throws -> Data {
        try ExactPersistedJSONV1.encode(
            config,
            identity: PersistedSchemaV1.configIdentity,
            fingerprint: PersistedSchemaV1.configFingerprint,
            prettyPrinted: true
        )
    }

    static func decodeState(_ data: Data) throws -> PersistedState {
        try ExactPersistedJSONV1.decode(
            PersistedState.self,
            from: data,
            identity: PersistedSchemaV1.stateIdentity,
            fingerprint: PersistedSchemaV1.stateFingerprint
        )
    }

    static func encodeState(_ state: PersistedState) throws -> Data {
        try ExactPersistedJSONV1.encode(
            state,
            identity: PersistedSchemaV1.stateIdentity,
            fingerprint: PersistedSchemaV1.stateFingerprint,
            prettyPrinted: false
        )
    }

    static func decodeEvent(_ data: Data) throws -> EventRecord {
        try ExactPersistedJSONV1.decode(
            EventRecord.self,
            from: data,
            identity: PersistedSchemaV1.eventIdentity,
            fingerprint: PersistedSchemaV1.eventFingerprint
        )
    }

    static func encodeEvent(_ event: EventRecord) throws -> Data {
        try ExactPersistedJSONV1.encode(
            event,
            identity: PersistedSchemaV1.eventIdentity,
            fingerprint: PersistedSchemaV1.eventFingerprint
        )
    }
}
