import AndromedaInstall
import Foundation
import Testing

/// Verifies Studio-home → `$HOME` rewrite for LaunchAgent templates.
struct LaunchAgentPlistRendererTests {
    @Test("rewrites Studio home template to installing user home")
    func rewritesStudioHome() throws {
        let template = """
        <string>/Users/<user>/Applications/AndromedaHUD.app/Contents/MacOS/AndromedaHUD</string>
        <string>/Users/<user></string>
        <string>/Users/<user>/.multibrain/logs/andromeda-hud.launchd.log</string>
        """
        let rendered = try LaunchAgentPlistRenderer.render(
            template: template,
            homeDirectory: "/Users/demo"
        )
        #expect(rendered.contains("/Users/demo/Applications/AndromedaHUD.app"))
        #expect(!rendered.contains("/Users/<user>"))
        #expect(rendered.contains("/Users/demo/.multibrain/logs/andromeda-hud.launchd.log"))
    }

    @Test("fails closed when Studio template marker is missing")
    func failsWhenTemplateMissing() {
        let template = "<string>/Users/other/Applications/AndromedaHUD.app</string>"
        #expect(throws: InstallError.self) {
            _ = try LaunchAgentPlistRenderer.render(
                template: template,
                homeDirectory: "/Users/demo"
            )
        }
    }

    @Test("allows identity rewrite when installing on Studio itself")
    func allowsStudioIdentity() throws {
        let template = "<string>/Users/<user>/Applications/AndromedaHUD.app</string>"
        let rendered = try LaunchAgentPlistRenderer.render(
            template: template,
            homeDirectory: "/Users/<user>"
        )
        #expect(rendered.contains("/Users/<user>/Applications/AndromedaHUD.app"))
    }

    @Test("renders repo ops plist template to a temp destination")
    func rendersRepoTemplateFile() throws {
        let root = try InstallPaths.discoverRepositoryRoot()
        let source = root.appendingPathComponent(HUDLaunchAgent.relativeTemplatePath)
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("andromeda-install-plist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let destination = tempRoot.appendingPathComponent("com.andromeda.hud.plist")

        try LaunchAgentPlistRenderer.renderFile(
            source: source,
            destination: destination,
            homeDirectory: "/Users/book"
        )

        let text = try String(contentsOf: destination, encoding: .utf8)
        #expect(text.contains("/Users/book/Applications/AndromedaHUD.app"))
        #expect(!text.contains("/Users/<user>"))
        #expect(text.contains(HUDLaunchAgent.label))
    }
}
