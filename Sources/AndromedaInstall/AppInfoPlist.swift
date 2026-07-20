import Foundation

/// Generates the minimal Info.plist embedded in `~/Applications/*.app`.
public enum AppInfoPlist {
    /// Builds Info.plist XML for an installed product bundle.
    public static func xml(
        product: InstallProduct,
        shortVersion: String,
        buildVersion: String
    ) -> String {
        let lsUI = product.isLSUIElement ? "<true/>" : "<false/>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleDisplayName</key>
        \t<string>\(product.displayName)</string>
        \t<key>CFBundleExecutable</key>
        \t<string>\(product.rawValue)</string>
        \t<key>CFBundleIdentifier</key>
        \t<string>\(product.bundleIdentifier)</string>
        \t<key>CFBundleName</key>
        \t<string>\(product.displayName)</string>
        \t<key>CFBundlePackageType</key>
        \t<string>APPL</string>
        \t<key>CFBundleShortVersionString</key>
        \t<string>\(shortVersion)</string>
        \t<key>CFBundleVersion</key>
        \t<string>\(buildVersion)</string>
        \t<key>LSMinimumSystemVersion</key>
        \t<string>14.0</string>
        \t<key>LSUIElement</key>
        \t\(lsUI)
        \t<key>NSHighResolutionCapable</key>
        \t<true/>
        \t<key>NSPrincipalClass</key>
        \t<string>NSApplication</string>
        </dict>
        </plist>

        """
    }
}
