import CCVigilShared
import Testing

@Test func daemonWorstCaseIsAttemptsTimesTheHelperCall() {
    #expect(ClearBudget.attempts == 4)
    #expect(ClearBudget.helperCallSeconds == 15)
    #expect(ClearBudget.daemonWorstCaseSeconds == Double(ClearBudget.attempts) * ClearBudget.helperCallSeconds)
    #expect(ClearBudget.daemonWorstCaseSeconds == 60)
}

@Test func socketHandlerBudgetExceedsTheDaemonWorstCase() {
    #expect(ClearBudget.socketHandlerSeconds > ClearBudget.daemonWorstCaseSeconds)
    #expect(ClearBudget.socketHandlerSeconds == 70)
}

@Test func clientBudgetExceedsTheSocketHandlerBudget() {
    #expect(Double(ClearBudget.clientSeconds) > ClearBudget.socketHandlerSeconds)
    #expect(ClearBudget.clientSeconds == 80)
}
