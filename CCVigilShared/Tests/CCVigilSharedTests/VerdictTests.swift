import CCVigilShared
import Testing

@Test(arguments: [
    (Verdict.holdAwake, "hold-awake"),
    (Verdict.allowSleep, "allow-sleep"),
])
func verdictRawValue(verdict: Verdict, expected: String) {
    #expect(verdict.rawValue == expected)
}

@Test func verdictCasesAreExhaustive() {
    #expect(Verdict.allCases == [.holdAwake, .allowSleep])
}
