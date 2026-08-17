import XCTest
import SwiftUI
@testable import AndromedaUI

#if canImport(UIKit)
import UIKit
/// Host a SwiftUI view at a fixed size in a given scheme (iOS/tvOS).
@MainActor
func andromedaHost(_ view: some View, _ size: CGSize, dark: Bool) -> UIViewController {
    let vc = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
    vc.view.frame = CGRect(origin: .zero, size: size)
    vc.overrideUserInterfaceStyle = dark ? .dark : .light
    return vc
}
#elseif canImport(AppKit)
import AppKit
/// Host a SwiftUI view at a fixed size in a given scheme (macOS).
@MainActor
func andromedaHost(_ view: some View, _ size: CGSize, dark: Bool) -> NSViewController {
    let themed = view
        .environment(\.colorScheme, dark ? .dark : .light)
        .frame(width: size.width, height: size.height)
    let vc = NSHostingController(rootView: AnyView(themed))
    vc.view.frame = CGRect(origin: .zero, size: size)
    vc.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    return vc
}
#endif

/// The standard specimen canvas: one component on the Andromeda surface,
/// with looping motion pinned to its end frame so captures are stable.
@MainActor
func specimenCanvas(_ view: some View, size: CGSize = CGSize(width: 220, height: 170)) -> some View {
    ZStack { AndromedaSurface(); view }
        .frame(width: size.width, height: size.height)
        .andromedaFrozen()
}
