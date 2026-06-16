import SwiftUI

/// Top-down animated trajectory simulation for a trick. Loads wheel params (/wheel), derives the
/// motor's rated RPM from MotorPresets, runs TrickSim, and draws the path + swept body + dimensioned
/// bounding box + the moving car, with distance/revolutions/area stats. iOS-only.
struct TrickSimView: View {
    let trick: Trick
    let durs: [Int]
    let palette: Palette
    @State private var wheel: WheelClient.Params?
    private var p: Palette { palette }

    // Car geometry — v1 constants (metres). TODO: move to settings next to the motor params.
    private static let carLenM = 0.25, carWidM = 0.15, trackM = 0.13

    private var steps: [TrickStep] {
        let d = durs.isEmpty ? Tricks.baseDurations(trick) : durs
        return Tricks.withDurations(trick, d).steps
    }
    private var totalSec: Double { Double(steps.reduce(0) { $0 + $1.ms }) / 1000 }

    private var rpm: Int? {
        guard let w = wheel else { return nil }
        return MotorPresets.match(ppr: w.ppr, gearX100: w.gearX100, quad: w.quad)?.rpm
    }
    private var sim: TrickSim.Result? {
        guard let w = wheel, let rpm else { return nil }
        let vmax = Double.pi * (Double(w.diameterMm) / 1000) * Double(rpm) / 60
        return TrickSim.simulate(steps: steps, vmaxMS: vmax, trackM: Self.trackM,
                                 carLenM: Self.carLenM, carWidM: Self.carWidM)
    }

    var body: some View {
        VStack(spacing: 10) {
            if let r = sim {
                TimelineView(.animation) { tl in
                    Canvas { ctx, size in
                        draw(&ctx, size, r, time: tl.date.timeIntervalSinceReferenceDate)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                stats(r)
            } else {
                Spacer()
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 28)).foregroundStyle(p.muted)
                Text(L.simPickMotor).font(.system(size: 13)).foregroundStyle(p.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                Spacer()
            }
        }
        .padding(12)
        .task { wheel = await WheelClient().get() }
    }

    // MARK: stats
    private func stats(_ r: TrickSim.Result) -> some View {
        let turns = r.turnRad / (2 * .pi)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                chip(L.simPath, String(format: "%.1f %@", r.pathLenM, L.mUnit))
                chip(L.simTurns, String(format: "%.1f", turns))
                chip(L.simArea, String(format: "%d×%d %@", Int((r.areaWM * 100).rounded()),
                                       Int((r.areaHM * 100).rounded()), L.cmUnit))
            }
            Text(L.simVerdict(totalSec, turns)).font(.system(size: 12)).foregroundStyle(p.muted)
        }
    }
    private func chip(_ key: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(p.accent).monospacedDigit()
            Text(key).font(.system(size: 9, weight: .semibold)).foregroundStyle(p.muted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(p.panel).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.metal.opacity(0.4), lineWidth: 1))
    }

    // MARK: drawing
    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ r: TrickSim.Result, time: Double) {
        let pad: CGFloat = 30   // room for dimension labels
        let bw = max(r.areaWM, 1e-3), bh = max(r.areaHM, 1e-3)
        let cx = (r.minX + r.maxX) / 2, cy = (r.minY + r.maxY) / 2
        let scale = min((size.width - 2 * pad) / bw, (size.height - 2 * pad) / bh)
        func toS(_ wx: Double, _ wy: Double) -> CGPoint {
            CGPoint(x: size.width / 2 + (wx - cx) * scale, y: size.height / 2 - (wy - cy) * scale)
        }
        let carL = Self.carLenM * scale, carW = Self.carWidM * scale

        // car body path at a pose (rounded rect, forward = +x in body frame)
        func carPath(_ pose: TrickSim.Pose) -> Path {
            let c = toS(pose.x, pose.y)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: -pose.theta)
            return Path(roundedRect: CGRect(x: -carL / 2, y: -carW / 2, width: carL, height: carW),
                        cornerRadius: 3).applying(t)
        }

        // 1) swept area: faint body ghosts along the path
        for pose in r.poses {
            ctx.fill(carPath(pose), with: .color(p.accent.opacity(0.06)))
        }
        // 2) centre trajectory (dashed green)
        var path = Path()
        for (i, pose) in r.poses.enumerated() {
            let s = toS(pose.x, pose.y)
            if i == 0 { path.move(to: s) } else { path.addLine(to: s) }
        }
        ctx.stroke(path, with: .color(p.accent.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
        // 3) bounding box + cm dimension labels
        let tl = toS(r.minX, r.maxY), br = toS(r.maxX, r.minY)
        let box = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
        ctx.stroke(Path(box), with: .color(p.muted.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        let wCm = Int((r.areaWM * 100).rounded()), hCm = Int((r.areaHM * 100).rounded())
        ctx.draw(Text("\(wCm) \(L.cmUnit)").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.muted), at: CGPoint(x: box.midX, y: box.minY - 12))
        ctx.draw(Text("\(hCm) \(L.cmUnit)").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(p.muted), at: CGPoint(x: box.minX - 16, y: box.midY))
        // 4) the moving car at the current phase
        if r.poses.count > 1, totalSec > 0 {
            let phase = (time.truncatingRemainder(dividingBy: totalSec)) / totalSec
            let idx = min(r.poses.count - 1, max(0, Int(phase * Double(r.poses.count - 1))))
            let pose = r.poses[idx]
            let cp = carPath(pose)
            ctx.fill(cp, with: .color(p.panel))
            ctx.stroke(cp, with: .color(p.accent), lineWidth: 2)
            // windshield mark at the front
            let fc = toS(pose.x, pose.y)
            let ft = CGAffineTransform(translationX: fc.x, y: fc.y).rotated(by: -pose.theta)
            ctx.fill(Path(roundedRect: CGRect(x: carL / 2 - carW * 0.35, y: -carW * 0.3,
                                              width: carW * 0.3, height: carW * 0.6),
                          cornerRadius: 2).applying(ft), with: .color(p.accent.opacity(0.5)))
        }
    }
}
