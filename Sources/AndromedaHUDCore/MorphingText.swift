import SwiftUI

/// A view that creates a mesmerizing, gooey morphing effect between text strings.
/// Inspired by MagicUI's Morphing Text.
public struct MorphingText: View {
    public let texts: [String]
    public let font: Font
    public let color: Color
    public let duration: TimeInterval
    public let pause: TimeInterval
    public let alignment: Alignment

    @State private var currentIndex = 0
    @State private var nextIndex = 1
    @State private var morphProgress: CGFloat = 0.0
    @State private var timer: Timer?

    public init(
        texts: [String], 
        font: Font = .system(size: 40, weight: .bold, design: .rounded), 
        color: Color = .primary, 
        duration: TimeInterval = 1.0, 
        pause: TimeInterval = 2.0, 
        alignment: Alignment = .center
    ) {
        self.texts = texts
        self.font = font
        self.color = color
        self.duration = duration
        self.pause = pause
        self.alignment = alignment
    }

    public var body: some View {
        ZStack(alignment: alignment) {
            if texts.isEmpty {
                EmptyView()
            } else {
                // The threshold effect to create the gooey morph
                Canvas { context, size in
                    // Apply a threshold filter to the drawing
                    context.addFilter(.alphaThreshold(min: 0.5, color: color))
                    context.addFilter(.blur(radius: 12))
                    
                    context.drawLayer { ctx in
                        let drawPoint: CGPoint
                        switch alignment {
                        case .leading:
                            drawPoint = CGPoint(x: 0, y: size.height / 2)
                        case .trailing:
                            drawPoint = CGPoint(x: size.width, y: size.height / 2)
                        default:
                            drawPoint = CGPoint(x: size.width / 2, y: size.height / 2)
                        }
                        
                        // Current text
                        if let currentSymbol = context.resolveSymbol(id: 0) {
                            ctx.draw(currentSymbol, at: drawPoint, anchor: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center)
                        }
                        
                        // Next text
                        if let nextSymbol = context.resolveSymbol(id: 1) {
                            ctx.draw(nextSymbol, at: drawPoint, anchor: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center)
                        }
                    }
                } symbols: {
                    Text(texts[currentIndex])
                        .font(font)
                        .foregroundStyle(color)
                        .opacity(1.0 - morphProgress)
                        .scaleEffect(1.0 + (morphProgress * 0.2))
                        .blur(radius: morphProgress * 10)
                        .tag(0)
                        
                    Text(texts[nextIndex])
                        .font(font)
                        .foregroundStyle(color)
                        .opacity(morphProgress)
                        .scaleEffect(1.2 - (morphProgress * 0.2))
                        .blur(radius: (1.0 - morphProgress) * 10)
                        .tag(1)
                }
            }
        }
        .onAppear {
            guard texts.count > 1 else { return }
            startAnimation()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: duration + pause, repeats: true) { _ in
            withAnimation(.easeInOut(duration: duration)) {
                morphProgress = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                morphProgress = 0.0
                currentIndex = nextIndex
                nextIndex = (nextIndex + 1) % texts.count
            }
        }
    }
}

#Preview {
    MorphingText(texts: ["Hello", "Morphing", "Text", "Animation", "SwiftUI", "Mesmerizing"])
        .frame(width: 400, height: 200)
        .background(Color.black)
}
