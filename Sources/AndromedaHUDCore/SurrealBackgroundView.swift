import SwiftUI

/// A magical background view that uses MeshGradient on macOS 15, 
/// and falls back to an animated blurred angular gradient on macOS 14.
public struct SurrealBackgroundView: View {
    @State private var time: Float = 0.0
    @State private var animateGradient = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    public var body: some View {
        Group {
            if #available(macOS 15.0, iOS 18.0, *) {
                // macOS 15+ Mesh Gradient
                TimelineView(.animation) { timeline in
                    let phase = Float(timeline.date.timeIntervalSince1970.remainder(dividingBy: 10)) / 10.0
                    
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            .init(0, 0), .init(0.5, 0), .init(1, 0),
                            .init(0, 0.5),
                            .init(
                                0.5 + 0.1 * sin(phase * .pi * 2),
                                0.5 + 0.1 * cos(phase * .pi * 2)
                            ),
                            .init(1, 0.5),
                            .init(0, 1), .init(0.5, 1), .init(1, 1)
                        ],
                        colors: [
                            colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.2) : Color(red: 0.9, green: 0.9, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.2, green: 0.1, blue: 0.3) : Color(red: 0.8, green: 0.7, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.1, green: 0.2, blue: 0.3) : Color(red: 0.7, green: 0.9, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.3, green: 0.1, blue: 0.2) : Color(red: 1.0, green: 0.7, blue: 0.9),
                            colorScheme == .dark ? Color(red: 0.2, green: 0.3, blue: 0.4) : Color(red: 0.8, green: 0.9, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.2) : Color(red: 0.9, green: 0.9, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.2) : Color(red: 0.9, green: 0.9, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.3) : Color(red: 0.8, green: 0.8, blue: 1.0),
                            colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.2) : Color(red: 0.9, green: 0.9, blue: 1.0)
                        ]
                    )
                    .blur(radius: 20)
                }
            } else {
                // macOS 14 Fallback
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.2, green: 0.1, blue: 0.3),
                        Color(red: 0.1, green: 0.2, blue: 0.3),
                        Color(red: 0.3, green: 0.1, blue: 0.2),
                        Color(red: 0.2, green: 0.1, blue: 0.3)
                    ]),
                    center: .center,
                    angle: .degrees(animateGradient ? 360 : 0)
                )
                .blur(radius: 40)
                .onAppear {
                    withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                        animateGradient = true
                    }
                }
            }
        }
        .opacity(0.8)
    }
}

#Preview {
    SurrealBackgroundView()
        .frame(width: 400, height: 200)
}
