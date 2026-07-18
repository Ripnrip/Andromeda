import Testing
@testable import AndromedaHUDCore

@Suite("HUDCommand")
struct HUDCommandTests {
    @Test("Parses store / infer.write / infer / recall verbs")
    func parsesVerbs() {
        #expect(HUDCommand.parse("store hello hive") == .store(narrative: "hello hive"))
        #expect(HUDCommand.parse("infer.write some thought") == .inferWrite(thought: "some thought"))
        #expect(HUDCommand.parse("infer some thought") == .inferWrite(thought: "some thought"))
        #expect(HUDCommand.parse("recall cats") == .recall(query: "cats"))
        #expect(HUDCommand.parse("bare needle") == .recall(query: "bare needle"))
    }

    @Test("Bare verbs yield empty payloads")
    func bareVerbs() {
        #expect(HUDCommand.parse("store") == .store(narrative: ""))
        #expect(HUDCommand.parse("infer.write") == .inferWrite(thought: ""))
        #expect(HUDCommand.parse("infer") == .inferWrite(thought: ""))
        #expect(HUDCommand.parse("recall") == .recall(query: ""))
        #expect(HUDCommand.parse("   ") == nil)
    }

    @Test("Capability IDs stay client-safe")
    func capabilityIDs() {
        #expect(HUDCommand.parse("store x")?.capabilityID == .store)
        #expect(HUDCommand.parse("infer.write x")?.capabilityID == .inferWrite)
        #expect(HUDCommand.parse("infer x")?.capabilityID == .inferWrite)
        #expect(HUDCapabilityID.inferWrite.rawValue == "infer.write")
        #expect(HUDCapabilityID.store.rawValue == "memory.store")
    }
}
