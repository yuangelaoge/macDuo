//
//  FoldEffect.swift
//  DuoLikeAnimation
//

import SwiftUI

/// Physical parameters of the frosted-glass fold.
struct FoldParameters: Equatable {
    /// Distance from the viewer's eyes to the untilted screen, looking at it head-on.
    /// The eye stays there while the device tilts. A typical hand-held distance is about 30 cm.
    var eyeDistanceMillimeters: CGFloat = 320
    /// Approximate density of SwiftUI points on current iPhone panels
    /// (about 460 ppi at 3x, 326 ppi at 2x, both close to 6 pt/mm).
    var pointsPerMillimeter: CGFloat = 6
    /// Blur radius gained per point of separation between the glass and the UI plane
    /// (tangent of the frosted glass scattering half-angle).
    var blurSpread: CGFloat = 0.12
    /// Fraction of light lost per point of blur radius, so the frostier the glass, the darker it gets.
    var darkening: CGFloat = 0.015

    var eyeDistancePoints: CGFloat { eyeDistanceMillimeters * pointsPerMillimeter }
}

extension View {
    /// Renders the view as if seen through a frosted-glass pane tilted by `angle` (radians)
    /// around the screen-space Y axis, hinged on the edge farther from the viewer.
    func foldEffect(angle: Double, parameters: FoldParameters = FoldParameters()) -> some View {
        modifier(FoldEffectModifier(angle: angle, parameters: parameters))
    }
}

private struct FoldEffectModifier: ViewModifier {
    let angle: Double
    let parameters: FoldParameters

    func body(content: Content) -> some View {
        // Flatten the subtree first; otherwise SwiftUI shades every leaf view on its own
        // transparent layer and the shader never sees the composited interface.
        content
            .compositingGroup()
            .visualEffect { [angle, parameters] content, _ in
                content.layerEffect(
                    ShaderLibrary.duoFold(
                        .boundingRect,
                        .float(angle),
                        .float(parameters.eyeDistancePoints),
                        .float(parameters.blurSpread),
                        .float(parameters.darkening)
                    ),
                    maxSampleOffset: .zero,
                    isEnabled: abs(angle) > 1e-4
                )
            }
    }
}
