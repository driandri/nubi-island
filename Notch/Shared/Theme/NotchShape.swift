import SwiftUI

struct NotchShape: InsettableShape {
    var radius: CGFloat
    var attachesToScreenEdge: Bool
    private var insetAmount: CGFloat = 0

    init(radius: CGFloat, attachesToScreenEdge: Bool = false) {
        self.radius = radius
        self.attachesToScreenEdge = attachesToScreenEdge
    }

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func shoulderWidth(in size: CGSize) -> CGFloat {
        guard attachesToScreenEdge, size.width > 0, size.height > 0 else { return 0 }
        return min(12, cornerRadius(in: size) * 0.65, size.height / 4, size.width / 4)
    }

    private func cornerRadius(in size: CGSize) -> CGFloat {
        max(0, min(radius - insetAmount, min(size.width, size.height) / 2))
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let corner = cornerRadius(in: bounds.size)
        guard attachesToScreenEdge else {
            return RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: bounds)
        }

        let shoulder = shoulderWidth(in: bounds.size)
        let left = bounds.minX + shoulder
        let right = bounds.maxX - shoulder
        let top = bounds.minY
        let bottom = bounds.maxY
        let lower = min(corner, (right - left) / 2, (bounds.height - shoulder) / 2)
        let shoulderControl = shoulder * 0.55
        let lowerControl = lower * 0.55

        return Path { path in
            path.move(to: CGPoint(x: bounds.minX, y: top))
            path.addLine(to: CGPoint(x: bounds.maxX, y: top))
            path.addCurve(to: CGPoint(x: right, y: top + shoulder),
                          control1: CGPoint(x: bounds.maxX - shoulderControl, y: top),
                          control2: CGPoint(x: right, y: top + shoulder - shoulderControl))
            path.addLine(to: CGPoint(x: right, y: bottom - lower))
            path.addCurve(to: CGPoint(x: right - lower, y: bottom),
                          control1: CGPoint(x: right, y: bottom - lower + lowerControl),
                          control2: CGPoint(x: right - lower + lowerControl, y: bottom))
            path.addLine(to: CGPoint(x: left + lower, y: bottom))
            path.addCurve(to: CGPoint(x: left, y: bottom - lower),
                          control1: CGPoint(x: left + lower - lowerControl, y: bottom),
                          control2: CGPoint(x: left, y: bottom - lower + lowerControl))
            path.addLine(to: CGPoint(x: left, y: top + shoulder))
            path.addCurve(to: CGPoint(x: bounds.minX, y: top),
                          control1: CGPoint(x: left, y: top + shoulder - shoulderControl),
                          control2: CGPoint(x: bounds.minX + shoulderControl, y: top))
            path.closeSubpath()
        }
    }

    func contains(_ point: CGPoint, in rect: CGRect, yIncreasesDownward: Bool) -> Bool {
        let shapePoint = yIncreasesDownward ? point : CGPoint(x: point.x, y: rect.minY + rect.maxY - point.y)
        return path(in: rect).contains(shapePoint)
    }
    func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
