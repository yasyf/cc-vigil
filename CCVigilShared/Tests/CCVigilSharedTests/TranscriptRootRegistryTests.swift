import CCVigilShared
import Testing

@Test func registersANewRootOnce() {
    var registry = TranscriptRootRegistry(knownRealPaths: ["/base/projects"], registeredRoots: [])
    let first = registry.register(rawPath: "/relocated/projects", realPath: "/relocated/projects")
    let second = registry.register(rawPath: "/relocated/projects", realPath: "/relocated/projects")
    #expect(first)
    #expect(!second)
    #expect(registry.registeredRoots == ["/relocated/projects"])
}

@Test func ignoresARootAlreadyCoveredByRealPath() {
    var registry = TranscriptRootRegistry(knownRealPaths: ["/base/projects"], registeredRoots: [])
    // A different raw path that resolves onto an already-scanned real path.
    let admitted = registry.register(rawPath: "/symlink/to/base/projects", realPath: "/base/projects")
    #expect(!admitted)
    #expect(registry.registeredRoots == [])
}

@Test func accumulatesDistinctRootsForPersistence() {
    var registry = TranscriptRootRegistry(
        knownRealPaths: ["/base/projects", "/first/projects"],
        registeredRoots: ["/first/projects"]
    )
    let second = registry.register(rawPath: "/second/projects", realPath: "/second/projects")
    let duplicate = registry.register(rawPath: "/first/again", realPath: "/first/projects")
    #expect(second)
    #expect(!duplicate)
    #expect(registry.registeredRoots == ["/first/projects", "/second/projects"])
}
