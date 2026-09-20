import Foundation

/// Fail-closed, atomic install transaction for a minimal `.app` bundle.
///
/// BIN-101 / HAB-621. Companion to `BinaryInstaller` (bare Mach-O, HAB-618).
/// `scripts/install-and-sign.sh` still copies the unsigned binary into
/// `~/Applications/*.app` *before* `codesign --force --deep`, which is the
/// same copy-before-sign window that got the CLI SIGKILLed (HAB-606). This
/// type inverts the order:
///
/// 1. validate the source executable,
/// 2. assemble a complete `.app` at a **staging** path next to the destination
///    (same volume → publish is a same-volume replace/rename, never a
///    cross-volume copy),
/// 3. strip leftover signatures on the inner binary and the staging bundle,
/// 4. ad-hoc re-sign the staging bundle (`codesign --force --deep --sign -`),
/// 5. strictly verify (`codesign --verify --deep --strict`),
/// 6. atomically publish staging → destination (`replaceItemAt` if the dest
///    exists, `moveItem` if it does not).
///
/// The live destination is never mutated until the staging bundle has a
/// strict-valid signature. Any failure before publish leaves the destination
/// untouched and removes the staging tree.
///
/// Out of scope: LaunchAgent plist rewrite/bootstrap, `open -a`, writing
/// `~/Applications` (callers choose the destination), adjacent rpath dylibs
/// beyond `codesign --deep`.
public actor AppBundleInstaller {

    /// Identity written into `Contents/Info.plist`.
    public struct Spec: Sendable {
        public var productName: String
        public var bundleIdentifier: String
        public var displayName: String
        public var shortVersion: String
        public var buildVersion: String
        public var lsuiElement: Bool
        public var minimumSystemVersion: String

        public init(
            productName: String,
            bundleIdentifier: String,
            displayName: String,
            shortVersion: String = "0.3",
            buildVersion: String,
            lsuiElement: Bool = false,
            minimumSystemVersion: String = "14.0"
        ) {
            self.productName = productName
            self.bundleIdentifier = bundleIdentifier
            self.displayName = displayName
            self.shortVersion = shortVersion
            self.buildVersion = buildVersion
            self.lsuiElement = lsuiElement
            self.minimumSystemVersion = minimumSystemVersion
        }
    }

    /// Outcome of a successful bundle install.
    public struct Report: Sendable, CustomStringConvertible {
        public let source: String
        public let destination: String
        public let bundleIdentifier: String
        public let productName: String
        public let bytes: Int
        public let replacedExisting: Bool

        public var description: String {
            """
            install-app report
              source:       \(source)
              destination:  \(destination)
              bundle id:    \(bundleIdentifier)
              product:      \(productName)
              replaced:     \(replacedExisting)
              size:         \(bytes) bytes
            """
        }
    }

    public enum InstallError: Error, CustomStringConvertible, Sendable {
        case sourceMissing(String)
        case sourceNotExecutable(String)
        case destinationNotBundle(String)
        case destinationIsFile(String)
        case stagingFailed(String)
        case plistFailed(String)
        case chmodFailed(String)
        case signingFailed(String)
        case verificationFailed(String)
        case publishFailed(String)
        case postPublishVerificationFailed(String)

        public var description: String {
            switch self {
            case .sourceMissing(let path):
                "Source executable not found: \(path)"
            case .sourceNotExecutable(let path):
                "Source is not an executable file: \(path)"
            case .destinationNotBundle(let path):
                "Destination must be an .app bundle path: \(path)"
            case .destinationIsFile(let path):
                "Destination exists and is a file, not a bundle: \(path)"
            case .stagingFailed(let detail):
                "Failed to stage .app bundle: \(detail)"
            case .plistFailed(let detail):
                "Failed to write Info.plist: \(detail)"
            case .chmodFailed(let detail):
                "Failed to make inner executable executable: \(detail)"
            case .signingFailed(let detail):
                "Ad-hoc deep-sign of staged bundle failed (destination untouched): \(detail)"
            case .verificationFailed(let detail):
                "Strict deep verification of staged bundle failed (destination untouched): \(detail)"
            case .publishFailed(let detail):
                "Atomic publish into destination failed (destination untouched): \(detail)"
            case .postPublishVerificationFailed(let detail):
                "Published bundle failed post-publish verification: \(detail)"
            }
        }
    }

    private let shell: any ShellExecuting
    private let fileManager: FileManager

    public init(
        shell: (any ShellExecuting)? = LiveShell(),
        fileManager: FileManager = .default
    ) {
        self.shell = shell ?? LiveShell()
        self.fileManager = fileManager
    }

    /// Assemble, sign, verify, and atomically publish a `.app` bundle.
    public func install(source: URL, destination: URL, spec: Spec) async throws -> Report {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw InstallError.sourceMissing(source.path)
        }
        guard fileManager.isExecutableFile(atPath: source.path) else {
            throw InstallError.sourceNotExecutable(source.path)
        }
        guard destination.pathExtension == "app" else {
            throw InstallError.destinationNotBundle(destination.path)
        }
        if fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw InstallError.destinationIsFile(destination.path)
            }
        }

        let destinationDirectory = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw InstallError.stagingFailed("could not create \(destinationDirectory.path): \(error.localizedDescription)")
        }

        // `.app` suffix so codesign treats the staging tree as a bundle.
        let stagingURL = destinationDirectory
            .appendingPathComponent(".\(spec.productName).install-\(UUID().uuidString).tmp.app")

        func cleanupAndThrow(_ error: InstallError) -> InstallError {
            try? fileManager.removeItem(at: stagingURL)
            return error
        }

        do {
            try assembleBundle(at: stagingURL, source: source, spec: spec)
        } catch let error as InstallError {
            throw cleanupAndThrow(error)
        } catch {
            throw cleanupAndThrow(.stagingFailed(error.localizedDescription))
        }

        let innerBinary = stagingURL
            .appendingPathComponent("Contents/MacOS/\(spec.productName)")

        // Best-effort strip of any signature that came along with the source
        // copy (Apple-signed system binaries, linker-signed SwiftPM artifacts).
        // Failures are ignored — the subsequent --force --deep re-sign is the
        // source of truth, matching install-and-sign.sh.
        _ = try? await shell.execute(["codesign", "--remove-signature", innerBinary.path])
        _ = try? await shell.execute(["codesign", "--remove-signature", stagingURL.path])

        let signResult = try await shell.execute([
            "codesign", "--force", "--deep", "--sign", "-", stagingURL.path,
        ])
        guard signResult.success else {
            throw cleanupAndThrow(.signingFailed(signResult.output))
        }

        let verifyResult = try await shell.execute([
            "codesign", "--verify", "--deep", "--strict", stagingURL.path,
        ])
        guard verifyResult.success else {
            throw cleanupAndThrow(.verificationFailed(verifyResult.output))
        }

        let replacedExisting = fileManager.fileExists(atPath: destination.path)
        do {
            if replacedExisting {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: stagingURL, to: destination)
            }
        } catch {
            throw cleanupAndThrow(.publishFailed(error.localizedDescription))
        }

        let bytes = directoryByteSize(at: destination)

        let postVerify = try await shell.execute([
            "codesign", "--verify", "--deep", "--strict", destination.path,
        ])
        guard postVerify.success else {
            throw InstallError.postPublishVerificationFailed(postVerify.output)
        }

        return Report(
            source: source.path,
            destination: destination.path,
            bundleIdentifier: spec.bundleIdentifier,
            productName: spec.productName,
            bytes: bytes,
            replacedExisting: replacedExisting
        )
    }

    private func assembleBundle(at stagingURL: URL, source: URL, spec: Spec) throws {
        let macos = stagingURL.appendingPathComponent("Contents/MacOS")
        let resources = stagingURL.appendingPathComponent("Contents/Resources")
        try fileManager.createDirectory(at: macos, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        let inner = macos.appendingPathComponent(spec.productName)
        try fileManager.copyItem(at: source, to: inner)
        do {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inner.path)
        } catch {
            throw InstallError.chmodFailed(error.localizedDescription)
        }

        let info: [String: Any] = [
            "CFBundleDisplayName": spec.displayName,
            "CFBundleExecutable": spec.productName,
            "CFBundleIdentifier": spec.bundleIdentifier,
            "CFBundleName": spec.displayName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": spec.shortVersion,
            "CFBundleVersion": spec.buildVersion,
            "LSMinimumSystemVersion": spec.minimumSystemVersion,
            "LSUIElement": spec.lsuiElement,
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
        ]
        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try data.write(
                to: stagingURL.appendingPathComponent("Contents/Info.plist"),
                options: .atomic
            )
        } catch {
            throw InstallError.plistFailed(error.localizedDescription)
        }
    }

    private func directoryByteSize(at url: URL) -> Int {
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var total = 0
        while let item = enumerator?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += values?.fileSize ?? 0
            }
        }
        return total
    }
}
