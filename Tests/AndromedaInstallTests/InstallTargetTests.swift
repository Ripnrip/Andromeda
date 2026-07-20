import AndromedaInstall
import Testing

/// Verifies required `hud|home|both` parsing and product expansion.
struct InstallTargetTests {
    @Test("parses home aliases")
    func parsesHome() throws {
        #expect(try InstallTarget.parse("home") == .home)
        #expect(try InstallTarget.parse("AndromedaHome") == .home)
        #expect(InstallTarget.home.products == [.home])
        #expect(InstallTarget.home.installsHUDLaunchAgent == false)
    }

    @Test("parses hud aliases")
    func parsesHUD() throws {
        #expect(try InstallTarget.parse("hud") == .hud)
        #expect(try InstallTarget.parse("HUD") == .hud)
        #expect(try InstallTarget.parse("AndromedaHUD") == .hud)
        #expect(InstallTarget.hud.products == [.hud])
        #expect(InstallTarget.hud.installsHUDLaunchAgent == true)
    }

    @Test("parses both aliases")
    func parsesBoth() throws {
        #expect(try InstallTarget.parse("both") == .both)
        #expect(try InstallTarget.parse("all") == .both)
        #expect(InstallTarget.both.products == [.home, .hud])
        #expect(InstallTarget.both.installsHUDLaunchAgent == true)
    }

    @Test("rejects unknown targets")
    func rejectsUnknown() {
        #expect(throws: InstallError.self) {
            _ = try InstallTarget.parse("desktop")
        }
    }

    @Test("product metadata matches former bash installer")
    func productMetadata() {
        #expect(InstallProduct.home.bundleIdentifier == "com.andromeda.home")
        #expect(InstallProduct.hud.bundleIdentifier == "com.andromeda.hud")
        #expect(InstallProduct.home.isLSUIElement == false)
        #expect(InstallProduct.hud.isLSUIElement == true)
        #expect(InstallProduct.home.opensAfterInstall == true)
        #expect(InstallProduct.hud.opensAfterInstall == false)
    }
}
