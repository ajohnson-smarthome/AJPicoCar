import SwiftUI

struct JoystickView: View {
    var vertical: Bool = false
    var size: CGFloat = 132
    /// Reports normalized (x, y) in [-1, 1]; screen Y positive downward. (0,0) on release.
    var onChange: (Double, Double) -> Void

    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.09))
                .overlay(Circle().strokeBorder(Color(white: 0.16)))
            Circle().fill(Color(red: 0.29, green: 0.87, blue: 0.5))
                .frame(width: 56, height: 56)
                .offset(knob)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let r = size / 2
                    var dx = g.location.x - r
                    var dy = g.location.y - r
                    if vertical { dx = 0 }
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d > r { dx = dx / d * r; dy = dy / d * r }
                    knob = CGSize(width: dx, height: dy)
                    onChange(Double(dx / r), Double(dy / r))
                }
                .onEnded { _ in
                    knob = .zero
                    onChange(0, 0)
                }
        )
    }
}
