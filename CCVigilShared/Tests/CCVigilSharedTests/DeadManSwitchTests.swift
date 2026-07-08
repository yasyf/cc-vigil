import CCVigilShared
import Testing

@Test func deadManStartsDisarmed() {
    let deadMan = DeadManSwitch()
    #expect(deadMan.liveConnections == 0)
    #expect(deadMan.generation == 0)
}

@Test func deadManLastCloseWhileBlockedArms() {
    var deadMan = DeadManSwitch()
    deadMan.connectionOpened()
    let generation = deadMan.connectionClosed(whileBlocked: true)
    #expect(generation == 2)
    #expect(deadMan.shouldClear(firedGeneration: 2) == true)
}

@Test func deadManCloseWhileNotBlockedNeverArms() {
    var deadMan = DeadManSwitch()
    deadMan.connectionOpened()
    #expect(deadMan.connectionClosed(whileBlocked: false) == nil)
}

@Test func deadManCloseWithSurvivingConnectionNeverArms() {
    var deadMan = DeadManSwitch()
    deadMan.connectionOpened()
    deadMan.connectionOpened()
    #expect(deadMan.connectionClosed(whileBlocked: true) == nil)
    let generation = deadMan.connectionClosed(whileBlocked: true)
    #expect(generation == 4)
    #expect(deadMan.shouldClear(firedGeneration: 4) == true)
}

@Test func deadManReconnectInvalidatesArmedGeneration() {
    var deadMan = DeadManSwitch()
    deadMan.connectionOpened()
    let armed = deadMan.connectionClosed(whileBlocked: true)
    #expect(armed == 2)
    deadMan.connectionOpened()
    #expect(deadMan.shouldClear(firedGeneration: 2) == false)
}

@Test func deadManRearmedGenerationWinsRace() {
    var deadMan = DeadManSwitch()
    deadMan.connectionOpened()
    let stale = deadMan.connectionClosed(whileBlocked: true)
    #expect(stale == 2)
    deadMan.connectionOpened()
    let fresh = deadMan.connectionClosed(whileBlocked: true)
    #expect(fresh == 4)
    #expect(deadMan.shouldClear(firedGeneration: 2) == false)
    #expect(deadMan.shouldClear(firedGeneration: 4) == true)
}

@Test func deadManStaleFireAfterNotBlockedCloseStaysQuiet() {
    var deadMan = DeadManSwitch()
    deadMan.connectionOpened()
    let armed = deadMan.connectionClosed(whileBlocked: true)
    #expect(armed == 2)
    deadMan.connectionOpened()
    #expect(deadMan.connectionClosed(whileBlocked: false) == nil)
    #expect(deadMan.shouldClear(firedGeneration: 2) == false)
}
