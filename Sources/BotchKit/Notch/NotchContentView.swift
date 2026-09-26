import AppKit
import SwiftUI

struct NotchContentView: View {
    var controller: NotchController
    var displayID: CGDirectDisplayID = 0
    var collapsedBase: CGSize = NotchGeometry.fallbackSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { controller.isExpanded(on: displayID) }
    private var isHovering: Bool { controller.isHovering(on: displayID) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                CenteredNotchShape(
                    width: shapeSize.width, height: shapeSize.height,
                    topRadius: topRadius, bottomRadius: bottomRadius
                )
                .fill(.black)
                .scaleEffect(x: hoverScale.width, y: hoverScale.height, anchor: .top)
                layers
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(glide, value: isExpanded)
            .animation(glide, value: isHovering)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    controller.hoverChanged(
                        hoverRect(in: geo.size).contains(point), on: displayID)
                case .ended:
                    controller.hoverChanged(false, on: displayID)
                }
            }
        }
    }

    @ViewBuilder private var layers: some View {
        if isExpanded {
            let size = expandedShape
            NotchBrowserPane(store: controller.browser)
                .padding(.top, collapsedBase.height)
                .frame(width: size.width, height: size.height, alignment: .top)
                .transition(contentTransition)
        } else {
            Color.clear
                .frame(width: collapsedBase.width, height: collapsedBase.height)
                .transition(collapsedTransition)
        }
    }

    private var expandedShape: CGSize {
        NotchGeometry.expandedShapeSize(
            browserSize: controller.browserSize(on: displayID), notchHeight: collapsedBase.height)
    }

    private var shapeSize: CGSize { isExpanded ? expandedShape : collapsedBase }

    private var collapsedTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.35)),
            removal: .opacity.animation(.easeOut(duration: 0.08)))
    }

    private func hoverRect(in panel: CGSize) -> CGRect {
        let shape = shapeSize
        return CGRect(
            x: (panel.width - shape.width) / 2, y: 0, width: shape.width, height: shape.height
        )
        .insetBy(dx: -NotchGeometry.openMargin, dy: -NotchGeometry.openMargin)
    }

    private var hoverScale: CGSize {
        guard !reduceMotion, isHovering, !isExpanded else { return CGSize(width: 1, height: 1) }
        let shape = shapeSize
        return CGSize(
            width: 1 + NotchGeometry.hoverGrow / shape.width,
            height: 1 + NotchGeometry.hoverGrow / shape.height)
    }

    private var topRadius: CGFloat { isExpanded ? NotchGeometry.expandedTopRadius : 0 }

    private var bottomRadius: CGFloat {
        isExpanded ? NotchGeometry.expandedBottomRadius : NotchGeometry.collapsedBottomRadius
    }

    private var glide: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.16)
    }

    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.1).delay(0.12)),
            removal: .identity)
    }
}
