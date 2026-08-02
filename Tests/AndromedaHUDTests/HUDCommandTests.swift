import Testing
@testable import AndromedaHUDCore

@Suite("HUDCommand")
struct HUDCommandTests {
    @Test("Parses store / journal / session dump / infer.write / infer / recall verbs")
    func parsesVerbs() {
        #expect(HUDCommand.parse("store hello hive") == .store(narrative: "hello hive"))
        #expect(HUDCommand.parse("journal end of day") == .journal(body: "end of day"))
        #expect(HUDCommand.parse("memory.journal end of day") == .journal(body: "end of day"))
        #expect(HUDCommand.parse("session dump wrap-up") == .sessionDump(body: "wrap-up"))
        #expect(HUDCommand.parse("sessiondump notes") == .sessionDump(body: "notes"))
        #expect(HUDCommand.parse("memory.session_dump notes") == .sessionDump(body: "notes"))
        #expect(HUDCommand.parse("infer.write some thought") == .inferWrite(thought: "some thought"))
        #expect(HUDCommand.parse("infer some thought") == .inferWrite(thought: "some thought"))
        #expect(HUDCommand.parse("recall cats") == .recall(query: "cats"))
        #expect(HUDCommand.parse("bare needle") == .recall(query: "bare needle"))
    }

    @Test("Bare verbs yield empty payloads")
    func bareVerbs() {
        #expect(HUDCommand.parse("store") == .store(narrative: ""))
        #expect(HUDCommand.parse("journal") == .journal(body: ""))
        #expect(HUDCommand.parse("memory.journal") == .journal(body: ""))
        #expect(HUDCommand.parse("session dump") == .sessionDump(body: ""))
        #expect(HUDCommand.parse("sessiondump") == .sessionDump(body: ""))
        #expect(HUDCommand.parse("memory.session_dump") == .sessionDump(body: ""))
        #expect(HUDCommand.parse("infer.write") == .inferWrite(thought: ""))
        #expect(HUDCommand.parse("infer") == .inferWrite(thought: ""))
        #expect(HUDCommand.parse("recall") == .recall(query: ""))
        #expect(HUDCommand.parse("   ") == nil)
    }

    @Test("Capability IDs stay client-safe")
    func capabilityIDs() {
        #expect(HUDCommand.parse("store x")?.capabilityID == .store)
        #expect(HUDCommand.parse("journal x")?.capabilityID == .journal)
        #expect(HUDCommand.parse("session dump x")?.capabilityID == .sessionDump)
        #expect(HUDCommand.parse("infer.write x")?.capabilityID == .inferWrite)
        #expect(HUDCommand.parse("infer x")?.capabilityID == .inferWrite)
        #expect(HUDCapabilityID.journal.rawValue == "memory.journal")
        #expect(HUDCapabilityID.sessionDump.rawValue == "memory.session_dump")
        #expect(HUDCapabilityID.inferWrite.rawValue == "infer.write")
        #expect(HUDCapabilityID.store.rawValue == "memory.store")
    }
}
