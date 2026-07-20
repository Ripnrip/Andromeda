import AndromedaInstall
import Foundation
import Testing

/// Verifies dry-run plan ordering and absolute-tool expectations.
struct InstallPlanTests {
    @Test("hud plan includes fail-closed kickstart and skips open")
    func hudPlan() {
        let paths = InstallPaths(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            homeDirectory: URL(fileURLWithPath: "/Users/demo")
        )
        let plan = InstallPlan.make(
            target: .hud,
            paths: paths,
            shortVersion: "0.3",
            buildVersion: "1"
        )
        let summaries = plan.steps.map(\.summary)
        #expect(summaries.contains { $0.contains("AndromedaHUD") && $0.contains("swift build") })
        #expect(summaries.contains { $0.contains("skip open for AndromedaHUD") })
        #expect(summaries.contains { $0.contains("kickstart") && $0.contains("fail-closed") })
        #expect(summaries.contains { $0.contains("/Users/demo/Library/LaunchAgents/com.andromeda.hud.plist") })
        #expect(!summaries.contains { $0.hasPrefix("open -a") })
    }

    @Test("home plan opens app and omits LaunchAgent")
    func homePlan() {
        let paths = InstallPaths(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            homeDirectory: URL(fileURLWithPath: "/Users/demo")
        )
        let plan = InstallPlan.make(
            target: .home,
            paths: paths,
            shortVersion: "0.3",
            buildVersion: "1"
        )
        let summaries = plan.steps.map(\.summary)
        #expect(summaries.contains { $0.hasPrefix("open -a") })
        #expect(!summaries.contains { $0.contains("LaunchAgents") })
        #expect(!summaries.contains { $0.contains("kickstart") })
    }

    @Test("both plan installs home then hud plus LaunchAgent")
    func bothPlan() {
        let paths = InstallPaths(
            repositoryRoot: URL(fileURLWithPath: "/repo"),
            homeDirectory: URL(fileURLWithPath: "/Users/demo")
        )
        let plan = InstallPlan.make(
            target: .both,
            paths: paths,
            shortVersion: "0.3",
            buildVersion: "1"
        )
        let summaries = plan.steps.map(\.summary)
        let homeBuild = summaries.firstIndex { $0.contains("--product AndromedaHome") }
        let hudBuild = summaries.firstIndex { $0.contains("--product AndromedaHUD") }
        let kick = summaries.firstIndex { $0.contains("kickstart") }
        #expect(homeBuild != nil)
        #expect(hudBuild != nil)
        #expect(kick != nil)
        if let homeBuild, let hudBuild, let kick {
            #expect(homeBuild < hudBuild)
            #expect(hudBuild < kick)
        }
    }

    @Test("absolute tool paths prefer /usr/bin and /bin")
    func absoluteTools() {
        let tools = AbsoluteToolPaths(swift: "/usr/bin/swift")
        #expect(tools.codesign == "/usr/bin/codesign")
        #expect(tools.launchctl == "/bin/launchctl")
        #expect(tools.open == "/usr/bin/open")
        #expect(tools.id == "/usr/bin/id")
    }
}
