import CoreGraphics

enum NotchGeometry {
    static let topFlareRadius: CGFloat = 6
    static let fallbackSize = CGSize(width: 150, height: 28)

    static func expandedShapeSize(browserSize: CGSize, notchHeight: CGFloat) -> CGSize {
        NotchBrowserGeometry.shapeSize(browser: browserSize, notchHeight: notchHeight)
    }

    static func collapsedSize(
        screenWidth: CGFloat,
        leftAreaWidth: CGFloat?,
        rightAreaWidth: CGFloat?,
        safeAreaTop: CGFloat
    ) -> CGSize {
        guard safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth else {
            return fallbackSize
        }
        let width = screenWidth - left - right
        guard width > 1 else { return fallbackSize }
        return CGSize(width: width, height: safeAreaTop)
    }

    static func origin(screenFrame: CGRect, panelSize: CGSize) -> CGPoint {
        CGPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height)
    }

    static let openInset: CGFloat = 6
    static let keepInset: CGFloat = 24
    static let interactInset: CGFloat = 24
    static let openMargin = openInset
    static let panelPadding = CGSize(width: 24, height: 10)
    static let hoverGrow: CGFloat = 12

    static func panelSize(forShape shape: CGSize) -> CGSize {
        CGSize(width: shape.width + panelPadding.width, height: shape.height + panelPadding.height)
    }

    static func union(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(width: max(lhs.width, rhs.width), height: max(lhs.height, rhs.height))
    }

    static func expandedAcceptsPointer(
        _ point: CGPoint, shapeFrame: CGRect, buttonPressed: Bool, heldOpen: Bool
    ) -> Bool {
        buttonPressed || heldOpen || openFrame(around: shapeFrame).contains(point)
    }

    static let expandedTopRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 22
    static let collapsedBottomRadius: CGFloat = 12

    static func proximity(
        point: CGPoint,
        collapsedFrame: CGRect,
        expandedFrame: CGRect,
        openInset: CGFloat = openInset,
        keepInset: CGFloat = keepInset
    ) -> NotchProximity {
        if insetFrame(collapsedFrame, by: openInset).contains(point) {
            return .open
        }
        if insetFrame(expandedFrame, by: keepInset).contains(point) {
            return .keepOpen
        }
        return .outside
    }

    static func openFrame(around frame: CGRect) -> CGRect {
        insetFrame(frame, by: openInset)
    }

    static func interactionFrame(around frame: CGRect) -> CGRect {
        insetFrame(frame, by: interactInset)
    }

    private static func insetFrame(_ frame: CGRect, by inset: CGFloat) -> CGRect {
        frame.insetBy(dx: -inset, dy: -inset)
    }
}
