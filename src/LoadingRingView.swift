import AppKit
import QuartzCore

// The compositor rotates the arc continuously, without a main-thread frame timer.
final class LoadingRingView: NSView {
    private let arc = CAShapeLayer()
    private let cutout = CAShapeLayer()
    private var strokeWidth: CGFloat = 2
    private var fraction: CGFloat = 0.6
    var excludedRect: NSRect? { didSet { updateGeometry() } }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(arc)
        arc.fillColor = nil
        arc.lineCap = .round
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func configure(color: NSColor, lineWidth: CGFloat, fraction: CGFloat, duration: Double, reduced: Bool) {
        strokeWidth = lineWidth; self.fraction = fraction
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arc.strokeColor = color.cgColor
        arc.lineWidth = lineWidth
        updateGeometry()
        CATransaction.commit()
        if reduced { arc.removeAnimation(forKey: "rotation") }
        else if arc.animation(forKey: "rotation") == nil {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0; animation.toValue = -Double.pi * 2
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            arc.add(animation, forKey: "rotation")
        }
    }
    override func layout() { super.layout(); updateGeometry() }
    private func updateGeometry() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arc.frame = bounds
        arc.contentsScale = window?.backingScaleFactor ?? 2
        let radius = max(0, min(bounds.width, bounds.height) / 2 - strokeWidth / 2)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: 0, endAngle: .pi * 2 * fraction, clockwise: false)
        arc.path = path
        if let excludedRect {
            let mask = CGMutablePath(); mask.addRect(bounds); mask.addRect(excludedRect)
            cutout.frame = bounds; cutout.path = mask; cutout.fillRule = .evenOdd
            layer?.mask = cutout
        } else { layer?.mask = nil }
        CATransaction.commit()
    }
}
