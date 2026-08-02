/**
 * ✅ AndromedaMemoryCommand parse — capability verbs only (HAB-74)
 */

import AndromedaHomeCore
import Testing

@Suite("AndromedaMemoryCommand")
struct AndromedaMemoryCommandTests {
    @Test("Parses recall / store / journal / session dump")
    func parsesVerbs() {
        #expect(AndromedaMemoryCommand.parse("recall andromeda") == .recall(query: "andromeda"))
        #expect(AndromedaMemoryCommand.parse("store hello hive") == .store(narrative: "hello hive"))
        #expect(AndromedaMemoryCommand.parse("journal end of day") == .journal(body: "end of day"))
        #expect(AndromedaMemoryCommand.parse("session dump wrap-up") == .journal(body: "wrap-up"))
    }

    @Test("Capability IDs stay memory.*")
    func capabilityIDs() {
        #expect(AndromedaMemoryCapability.recall.rawValue == "memory.recall")
        #expect(AndromedaMemoryCapability.store.rawValue == "memory.store")
        #expect(AndromedaMemoryCapability.journal.rawValue == "memory.journal")
        #expect(AndromedaMemoryCapability.sessionDump.rawValue == "memory.session_dump")
    }

    @Test("Rejects non-memory queries")
    func rejectsNoise() {
        #expect(AndromedaMemoryCommand.parse("com.multibrain.nightly") == nil)
        #expect(AndromedaMemoryCommand.parse("") == nil)
    }

    @Test("Console verb detect maps prefixes to memory.* chips")
    func consoleVerbDetect() {
        #expect(MemoryConsoleVerb.detect(in: "") == nil)
        #expect(MemoryConsoleVerb.detect(in: "recall andromeda") == .recall)
        #expect(MemoryConsoleVerb.detect(in: "store hello") == .store)
        #expect(MemoryConsoleVerb.detect(in: "journal wrap") == .journal)
        #expect(MemoryConsoleVerb.detect(in: "session dump") == .journal)
        #expect(MemoryConsoleVerb.detect(in: "agents") == nil)
        #expect(MemoryConsoleVerb.recall.capability.rawValue == "memory.recall")
        #expect(MemoryConsoleVerb.store.capability.rawValue == "memory.store")
        #expect(MemoryConsoleVerb.journal.capability.rawValue == "memory.journal")
    }
}
