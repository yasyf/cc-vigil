/// The oracle's answer to "should this Mac stay awake right now?".
/// Placeholder — the transcript oracle that computes it lands with the daemon.
public enum Verdict: String, CaseIterable, Sendable {
    case holdAwake = "hold-awake"
    case allowSleep = "allow-sleep"
}
