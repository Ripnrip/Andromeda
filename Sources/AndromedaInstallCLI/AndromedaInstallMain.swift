import AndromedaInstall
import ArgumentParser
import Foundation

@main
struct AndromedaInstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "andromeda-install",
        abstract: "Build, adhoc-sign, and LaunchAgent-deploy Andromeda Home/HUD (Swift-only mutate path).",
        discussion: """
        BIN-101 / HAB-104 — replaces scripts/install-and-sign.sh.

        Target is required (no silent Home default):
          andromeda-install home
          andromeda-install hud
          andromeda-install both

        HUD installs LaunchAgent com.andromeda.hud with Studio-home rewrite → $HOME,
        absolute /usr/bin/codesign + /bin/launchctl, and fail-closed kickstart.
        MemoryKit FleetObserve remains observe-only.
        """
    )

    @Argument(help: "Install target: home | hud | both")
    var target: String

    @Flag(name: .long, help: "Print the mutate plan without building, signing, or launchctl.")
    var dryRun = false

    @Flag(name: .long, help: "Do not `open -a` AndromedaHome after install.")
    var skipOpen = false

    @Option(name: .long, help: "Override CFBundleShortVersionString (default 0.3 or env).")
    var version: String?

    func run() throws {
        let installTarget = try InstallTarget.parse(target)
        let paths = try InstallPaths.resolve()
        var configuration = InstallConfiguration(
            target: installTarget,
            paths: paths,
            dryRun: dryRun,
            skipOpen: skipOpen
        )
        if let version {
            configuration.shortVersion = version
        }

        let engine = InstallEngine()
        let plan = try engine.run(configuration)

        print("andromeda-install target=\(installTarget.rawValue) dryRun=\(dryRun)")
        print("repository: \(paths.repositoryRoot.path)")
        print("home: \(paths.homeDirectory.path)")
        for (index, step) in plan.steps.enumerated() {
            print("\(index + 1). \(step.summary)")
        }
        if dryRun {
            print("dry-run complete — no mutate performed")
        } else {
            print("install complete")
        }
    }
}
