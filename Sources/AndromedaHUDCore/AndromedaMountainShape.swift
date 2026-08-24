import SwiftUI

/// An organic, "triangleish" mountain shape resembling an alien peak from space.
public struct AndromedaMountainShape: InsettableShape {
    var insetAmount: CGFloat = 0
    
    public init() {}
    
    public func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Apply inset to the bounding box
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let iWidth = insetRect.width
        let iHeight = insetRect.height
        let minX = insetRect.minX
        let minY = insetRect.minY
        
        // Start at top middle (the peak)
        path.move(to: CGPoint(x: minX + iWidth * 0.5, y: minY + iHeight * 0.05))
        
        // Curve down to the right base
        path.addCurve(
            to: CGPoint(x: minX + iWidth * 0.95, y: minY + iHeight * 0.95),
            control1: CGPoint(x: minX + iWidth * 0.75, y: minY + iHeight * 0.1),
            control2: CGPoint(x: minX + iWidth * 0.9, y: minY + iHeight * 0.6)
        )
        
        // Soft corner at the bottom right
        path.addQuadCurve(
            to: CGPoint(x: minX + iWidth * 0.9, y: minY + iHeight),
            control: CGPoint(x: minX + iWidth * 0.98, y: minY + iHeight)
        )
        
        // Line across the bottom base
        path.addLine(to: CGPoint(x: minX + iWidth * 0.1, y: minY + iHeight))
        
        // Soft corner at the bottom left
        path.addQuadCurve(
            to: CGPoint(x: minX + iWidth * 0.05, y: minY + iHeight * 0.95),
            control: CGPoint(x: minX + iWidth * 0.02, y: minY + iHeight)
        )
        
        // Curve back up to the peak on the left
        path.addCurve(
            to: CGPoint(x: minX + iWidth * 0.5, y: minY + iHeight * 0.05),
            control1: CGPoint(x: minX + iWidth * 0.1, y: minY + iHeight * 0.6),
            control2: CGPoint(x: minX + iWidth * 0.25, y: minY + iHeight * 0.1)
        )
        
        return path
    }
}

#Preview {
    AndromedaMountainShape()
        .fill(Color.blue)
        .frame(width: 400, height: 300)
}
