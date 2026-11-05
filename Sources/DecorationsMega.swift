import SwiftUI

// MARK: - 1.0.0 · twelve new decoration styles
//
// Each style is a small, hand built piece of motion design: runes that carry
// inner marks, a constellation whose stars are joined by dashed lines, petals
// that breathe, clockwork with real teeth, shards at uneven radii, silk
// ribbons, an 8-bit ring, a logarithmic spiral, two tilted halos, a crown arc,
// a flickering lightning ring and snow crystals with six spokes.
//
// Everything is deterministic (sin/cos of the index), so two devices draw the
// same picture at the same second, and nothing allocates per frame.

struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.02, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.22, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.midY - rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.10, y: rect.midY - rect.height * 0.04))
        path.closeSubpath()
        return path
    }
}

struct MegaDecorationArt: View {
    let decoration: CortexDecoration
    let size: CGFloat
    let t: Double

    private var radius: CGFloat { size * 0.5 }
    private var c1: Color { decoration.primary }
    private var c2: Color { decoration.secondary }

    var body: some View {
        ZStack {
            switch decoration.style {
            case .runes: runes
            case .constellation: constellation
            case .bloom: bloom
            case .clockwork: clockwork
            case .shards: shards
            case .ribbons: ribbons
            case .pixel: pixel
            case .spiral: spiral
            case .doubleHalo: doubleHalos
            case .crownArc: crownArc
            case .boltRing: boltRing
            case .snowRing: snowRing
            default: EmptyView()
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: runes

    private var runes: some View {
        ZStack {
            Circle()
                .strokeBorder(LinearGradient(colors: [c1, c2.opacity(0.5), c1], startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: max(2, size * 0.028))
                .padding(-size * 0.02)
            Circle()
                .strokeBorder(c2.opacity(0.75),
                              style: StrokeStyle(lineWidth: max(0.8, size * 0.010), dash: [size * 0.022, size * 0.05]))
                .padding(-size * 0.105)
                .rotationEffect(.degrees(-t * 9))
            ForEach(0..<12, id: \.self) { index in
                RuneMark(color: c1, accent: c2, unit: size, seed: index)
                    .offset(y: -radius - size * 0.035)
                    .rotationEffect(.degrees(Double(index) / 12 * 360 + t * 6))
                    .opacity(0.7 + 0.3 * abs(sin(t * 1.1 + Double(index))))
            }
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(c2)
                    .frame(width: size * 0.026, height: size * 0.026)
                    .offset(y: -radius - size * 0.15)
                    .rotationEffect(.degrees(t * 26 + Double(index) * 120))
                    .shadow(color: c2, radius: size * 0.03)
            }
        }
        .shadow(color: c1.opacity(0.5), radius: size * 0.06)
    }

    // MARK: constellation

    private var constellation: some View {
        let points: [CGPoint] = (0..<9).map { index in
            let angle = Double(index) / 9 * 2 * Double.pi + t * 0.11
            let distance = radius * (0.90 + 0.10 * CGFloat(sin(Double(index) * 2.1)))
            return CGPoint(x: CGFloat(cos(angle)) * distance, y: CGFloat(sin(angle)) * distance)
        }
        return ZStack {
            Path { path in
                for (index, point) in points.enumerated() {
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
            }
            .stroke(c2.opacity(0.35), style: StrokeStyle(lineWidth: max(0.6, size * 0.005), dash: [size * 0.02, size * 0.022]))
            ForEach(0..<points.count, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: size * (index % 3 == 0 ? 0.026 : 0.016),
                           height: size * (index % 3 == 0 ? 0.026 : 0.016))
                    .position(x: size / 2 + points[index].x, y: size / 2 + points[index].y)
                    .shadow(color: c1, radius: size * 0.025)
                    .opacity(0.65 + 0.35 * abs(sin(t * 1.6 + Double(index))))
            }
        }
    }

    // MARK: bloom

    private var bloom: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Ellipse()
                    .fill(LinearGradient(colors: [c1.opacity(0.9), c2.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.085, height: size * 0.20)
                    .offset(y: -radius - size * 0.015)
                    .rotationEffect(.degrees(Double(index) / 10 * 360 + t * 7))
                    .scaleEffect(1 + 0.10 * CGFloat(sin(t * 1.5 + Double(index) * 0.7)))
                    .shadow(color: c1.opacity(0.35), radius: size * 0.02)
            }
            Circle()
                .stroke(c2.opacity(0.35), lineWidth: max(1, size * 0.009))
                .padding(-size * 0.015)
        }
    }

    // MARK: clockwork

    private var clockwork: some View {
        ZStack {
            Circle()
                .strokeBorder(c1.opacity(0.55), lineWidth: max(1.4, size * 0.018))
            ForEach(0..<24, id: \.self) { index in
                Capsule()
                    .fill(index % 6 == 0 ? c2 : c1.opacity(0.55))
                    .frame(width: max(0.8, size * 0.007),
                           height: size * (index % 6 == 0 ? 0.058 : 0.032))
                    .offset(y: -radius + size * 0.028)
                    .rotationEffect(.degrees(Double(index) / 24 * 360))
            }
            ForEach(0..<3, id: \.self) { index in
                GearMark(color: c1, accent: c2, unit: size)
                    .offset(y: -radius - size * 0.07)
                    .rotationEffect(.degrees(t * (index % 2 == 0 ? 44 : -34) + Double(index) * 120))
            }
            Capsule()
                .fill(c1)
                .frame(width: max(1, size * 0.011), height: size * 0.30)
                .offset(y: -size * 0.15)
                .rotationEffect(.degrees(t * 30))
                .shadow(color: c1.opacity(0.6), radius: size * 0.02)
        }
    }

    // MARK: shards

    private var shards: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { index in
                PolygonShape(sides: 3)
                    .fill(LinearGradient(colors: [c1.opacity(0.95), c2.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.05, height: size * 0.125)
                    .rotationEffect(.degrees(t * 22 + Double(index) * 47))
                    .offset(y: -radius * (0.90 + 0.14 * CGFloat(sin(Double(index) * 1.7))))
                    .rotationEffect(.degrees(Double(index) / 12 * 360 + t * 12))
                    .shadow(color: c1.opacity(0.55), radius: size * 0.02)
            }
            Circle()
                .stroke(c2.opacity(0.22), lineWidth: max(0.7, size * 0.006))
                .padding(size * 0.02)
        }
    }

    // MARK: ribbons

    private var ribbons: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .trim(from: 0.03, to: 0.34)
                    .stroke(LinearGradient(colors: [c1, c2.opacity(0.1)], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: max(3, size * 0.042), lineCap: .round))
                    .padding(-size * 0.02 - CGFloat(index) * size * 0.035)
                    .rotationEffect(.degrees(t * (26 - Double(index) * 9) + Double(index) * 120))
                    .blur(radius: index == 2 ? size * 0.008 : 0)
            }
            Circle()
                .stroke(c2.opacity(0.18), lineWidth: max(0.7, size * 0.006))
                .padding(size * 0.04)
        }
        .shadow(color: c1.opacity(0.3), radius: size * 0.05)
    }

    // MARK: pixel

    private var pixel: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { index in
                let stepped = ((Double(index) / 16 * 360 + t * 22) / 12).rounded() * 12
                RoundedRectangle(cornerRadius: size * 0.006)
                    .fill(index % 3 == 0 ? c2 : c1.opacity(0.85))
                    .frame(width: size * 0.042, height: size * 0.042)
                    .offset(y: -radius - size * 0.028)
                    .rotationEffect(.degrees(stepped))
                    .opacity(sin(t * 2.6 + Double(index) * 1.4) > 0 ? 1 : 0.35)
            }
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: max(1, size * 0.010), dash: [size * 0.035, size * 0.03]))
                .foregroundStyle(c2.opacity(0.25))
        }
    }

    // MARK: spiral

    private var spiral: some View {
        ZStack {
            ForEach(0..<26, id: \.self) { index in
                let progress = Double(index) / 26
                Circle()
                    .fill(c1.opacity(0.95 - 0.55 * progress))
                    .frame(width: size * (0.011 + 0.020 * (1 - progress)),
                           height: size * (0.011 + 0.020 * (1 - progress)))
                    .offset(y: -radius * (0.32 + 0.64 * progress))
                    .rotationEffect(.degrees(progress * 720 + t * 26))
                    .shadow(color: c2.opacity(0.55), radius: size * 0.012)
            }
            Circle()
                .stroke(c2.opacity(0.16), lineWidth: max(0.7, size * 0.006))
                .padding(size * 0.03)
        }
    }

    // MARK: double halo

    private var doubleHalos: some View {
        ZStack {
            Ellipse()
                .stroke(LinearGradient(colors: [c1, c2.opacity(0.15), c1], startPoint: .leading, endPoint: .trailing),
                        lineWidth: max(2.4, size * 0.028))
                .frame(width: size * 1.34, height: size * 0.42)
                .rotationEffect(.degrees(-18 + sin(t / 3) * 4))
                .shadow(color: c1.opacity(0.55), radius: size * 0.05)
            Ellipse()
                .stroke(LinearGradient(colors: [c2, c1.opacity(0.15), c2], startPoint: .leading, endPoint: .trailing),
                        lineWidth: max(1.8, size * 0.020))
                .frame(width: size * 1.22, height: size * 0.36)
                .rotationEffect(.degrees(18 - sin(t / 3.4) * 4))
                .shadow(color: c2.opacity(0.45), radius: size * 0.04)
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.028, height: size * 0.028)
                    .offset(x: (index == 0 ? -1 : 1) * size * 0.60, y: (index == 0 ? 1 : -1) * size * 0.10)
                    .opacity(0.55 + 0.45 * abs(sin(t * 2 + Double(index))))
                    .shadow(color: c1, radius: size * 0.02)
            }
        }
    }

    // MARK: crown arc

    private var crownArc: some View {
        ZStack {
            Circle()
                .trim(from: 0.28, to: 0.72)
                .stroke(c1.opacity(0.85), style: StrokeStyle(lineWidth: max(2, size * 0.018), lineCap: .round))
                .rotationEffect(.degrees(180))
                .padding(-size * 0.01)
                .shadow(color: c1.opacity(0.6), radius: size * 0.04)
            ForEach(0..<5, id: \.self) { index in
                CrownPoint(color: c1, accent: c2, unit: size, tall: index == 2)
                    .offset(y: -radius - size * 0.03)
                    .rotationEffect(.degrees(-90 + Double(index - 2) * 25))
                    .shadow(color: c1.opacity(0.65), radius: size * 0.025)
            }
            Circle()
                .stroke(c2.opacity(0.18), lineWidth: max(0.7, size * 0.006))
                .padding(size * 0.02)
        }
    }

    // MARK: bolt ring

    private var boltRing: some View {
        ZStack {
            Circle()
                .stroke(c2.opacity(0.28), lineWidth: max(1, size * 0.010))
            ForEach(0..<6, id: \.self) { index in
                BoltShape()
                    .stroke(c1, style: StrokeStyle(lineWidth: max(1.4, size * 0.014), lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.09, height: size * 0.19)
                    .offset(y: -radius - size * 0.025)
                    .rotationEffect(.degrees(Double(index) / 6 * 360 + t * 9))
                    .opacity(0.30 + 0.70 * abs(sin(t * 2.8 + Double(index) * 1.3)))
                    .shadow(color: c1, radius: size * 0.03)
            }
        }
    }

    // MARK: snow ring

    private var snowRing: some View {
        ZStack {
            Circle()
                .stroke(c2.opacity(0.22), lineWidth: max(0.7, size * 0.006))
                .padding(size * 0.02)
            ForEach(0..<8, id: \.self) { index in
                SnowFlake(color: c1, accent: c2, unit: size)
                    .offset(y: -radius - size * 0.045)
                    .rotationEffect(.degrees(Double(index) / 8 * 360 + t * 8))
                    .shadow(color: c1.opacity(0.55), radius: size * 0.025)
            }
            Circle()
                .strokeBorder(c2.opacity(0.30),
                              style: StrokeStyle(lineWidth: max(0.7, size * 0.006), dash: [size * 0.01, size * 0.04]))
                .padding(-size * 0.08)
                .rotationEffect(.degrees(-t * 12))
        }
    }
}

// MARK: - small reusable marks

private struct RuneMark: View {
    let color: Color
    let accent: Color
    let unit: CGFloat
    let seed: Int

    private var barRotation: Double { Double(seed % 3) * 30 - 30 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.012)
                .stroke(color.opacity(0.9), lineWidth: max(0.7, unit * 0.007))
                .frame(width: unit * 0.042, height: unit * 0.070)
            Capsule()
                .fill(color.opacity(0.75))
                .frame(width: unit * 0.026, height: max(0.6, unit * 0.006))
                .rotationEffect(.degrees(barRotation))
                .offset(y: -unit * 0.014)
            Circle()
                .fill(accent.opacity(0.95))
                .frame(width: unit * 0.010, height: unit * 0.010)
                .offset(y: unit * 0.016)
        }
    }
}

private struct GearMark: View {
    let color: Color
    let accent: Color
    let unit: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.75))
                .frame(width: unit * 0.085, height: unit * 0.085)
            ForEach(0..<8, id: \.self) { tooth in
                Rectangle()
                    .fill(accent.opacity(0.65))
                    .frame(width: unit * 0.014, height: unit * 0.016)
                    .offset(y: -unit * 0.043)
                    .rotationEffect(.degrees(Double(tooth) / 8 * 360))
            }
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: unit * 0.034, height: unit * 0.034)
            Circle()
                .stroke(color.opacity(0.8), lineWidth: max(0.6, unit * 0.006))
                .frame(width: unit * 0.085, height: unit * 0.085)
        }
    }
}

private struct CrownPoint: View {
    let color: Color
    let accent: Color
    let unit: CGFloat
    let tall: Bool

    var body: some View {
        ZStack {
            PolygonShape(sides: 3)
                .fill(LinearGradient(colors: [color, accent.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: unit * (tall ? 0.075 : 0.058), height: unit * (tall ? 0.115 : 0.088))
                .rotationEffect(.degrees(180))
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: unit * (tall ? 0.020 : 0.015), height: unit * (tall ? 0.020 : 0.015))
                .offset(y: unit * (tall ? 0.028 : 0.021))
        }
    }
}

private struct SnowFlake: View {
    let color: Color
    let accent: Color
    let unit: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { spoke in
                ZStack {
                    Capsule()
                        .fill(color.opacity(0.9))
                        .frame(width: max(0.6, unit * 0.007), height: unit * 0.070)
                        .offset(y: -unit * 0.030)
                    Capsule()
                        .fill(color.opacity(0.55))
                        .frame(width: max(0.5, unit * 0.005), height: unit * 0.022)
                        .offset(y: -unit * 0.052)
                        .rotationEffect(.degrees(38))
                }
                .rotationEffect(.degrees(Double(spoke) / 6 * 360))
            }
            Circle()
                .fill(.white)
                .frame(width: unit * 0.016, height: unit * 0.016)
            Circle()
                .stroke(accent.opacity(0.5), lineWidth: max(0.4, unit * 0.004))
                .frame(width: unit * 0.045, height: unit * 0.045)
        }
    }
}
