import AndromedaInstall
import Testing

/// Verifies Info.plist generation for staged app bundles.
struct AppInfoPlistTests {
    @Test("home Info.plist is not an LSUIElement")
    func homePlist() {
        let xml = AppInfoPlist.xml(
            product: .home,
            shortVersion: "0.3",
            buildVersion: "202607201200"
        )
        #expect(xml.contains("<string>com.andromeda.home</string>"))
        #expect(xml.contains("<string>AndromedaHome</string>"))
        #expect(xml.contains("<key>LSUIElement</key>\n\t<false/>"))
        #expect(xml.contains("<string>0.3</string>"))
        #expect(xml.contains("<string>202607201200</string>"))
    }

    @Test("hud Info.plist is an LSUIElement accessory")
    func hudPlist() {
        let xml = AppInfoPlist.xml(
            product: .hud,
            shortVersion: "0.3",
            buildVersion: "202607201200"
        )
        #expect(xml.contains("<string>com.andromeda.hud</string>"))
        #expect(xml.contains("<key>LSUIElement</key>\n\t<true/>"))
    }
}
