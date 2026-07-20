import Foundation

/// Human-readable mutate step for dry-run and logging.
public struct InstallStep: Sendable, Equatable, CustomStringConvertible {
    public var summary: String

    public init(_ summary: String) {
        self.summary = summary
    }

    public var description: String { summary }
}

/// Declarative plan of build / sign / LaunchAgent steps (no side effects).
public struct InstallPlan: Sendable, Equatable {
    public var target: InstallTarget
    public var steps: [InstallStep]

    public init(target: InstallTarget, steps: [InstallStep]) {
        self.target = target
        self.steps = steps
    }

    /// Builds the ordered plan for `target` against resolved paths.
    public static func make(
        target: InstallTarget,
        paths: InstallPaths,
        shortVersion: String,
        buildVersion: String
    ) -> InstallPlan {
        var steps: [InstallStep] = []
        for product in target.products {
            let app = paths.appBundle(for: product)
            steps.append(InstallStep("swift build -c release --product \(product.rawValue)"))
            steps.append(InstallStep("stage \(app.path) (v\(shortVersion)/\(buildVersion))"))
            steps.append(InstallStep("adhoc codesign --force --deep --sign - \(app.path)"))
            if product.opensAfterInstall {
                steps.append(InstallStep("open -a \(app.path)"))
            } else {
                steps.append(InstallStep("skip open for \(product.rawValue) (LaunchAgent only)"))
            }
        }
        if target.installsHUDLaunchAgent {
            steps.append(
                InstallStep(
                    "render \(paths.hudPlistTemplate.path) → \(paths.hudPlistDestination.path) (HOME=\(paths.homeDirectory.path))"
                )
            )
            steps.append(InstallStep("launchctl bootstrap gui/<uid> \(paths.hudPlistDestination.path)"))
            steps.append(InstallStep("launchctl kickstart -k gui/<uid>/\(HUDLaunchAgent.label) (fail-closed)"))
        }
        return InstallPlan(target: target, steps: steps)
    }
}
