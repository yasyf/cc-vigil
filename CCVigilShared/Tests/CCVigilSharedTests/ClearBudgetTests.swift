import CCVigilShared
import Testing

@Test func daemonWorstCaseIsAttemptsTimesTheHelperCall() {
    #expect(ClearBudget.attempts == 4)
    #expect(ClearBudget.helperCallSeconds == 15)
    #expect(ClearBudget.daemonWorstCaseSeconds == Double(ClearBudget.attempts) * ClearBudget.helperCallSeconds)
    #expect(ClearBudget.daemonWorstCaseSeconds == 60)
}

@Test func clientBudgetExceedsTheDaemonWorstCase() {
    #expect(Double(ClearBudget.clientSeconds) > ClearBudget.daemonWorstCaseSeconds)
    #expect(ClearBudget.clientSeconds == 80)
}
