import AppKit
import SwiftUI

/// One face is used by the idle island, the menu bar, and the bundled app icon.
struct NobiFace: View {
    var blinking = false
    var outlined = false
    var tint: Color = .cyan
    var thirsty = false

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let line = max(1.4, h * 0.075)
            let capsule = Path(roundedRect: CGRect(x: line / 2, y: line / 2,
                                                    width: w - line, height: h - line),
                               cornerRadius: h / 2)
            context.fill(capsule, with: .color(.black))
            if outlined { context.stroke(capsule, with: .color(tint), lineWidth: line) }

            var eyes = Path()
            if thirsty {
                for x in [CGFloat(0.26), 0.57] {
                    eyes.move(to: CGPoint(x: w * x, y: h * 0.39))
                    eyes.addQuadCurve(to: CGPoint(x: w * (x + 0.17), y: h * 0.45),
                                      control: CGPoint(x: w * (x + 0.08), y: h * 0.49))
                }
            } else if blinking {
                eyes.move(to: CGPoint(x: w * 0.26, y: h * 0.46))
                eyes.addQuadCurve(to: CGPoint(x: w * 0.43, y: h * 0.46),
                                  control: CGPoint(x: w * 0.345, y: h * 0.51))
                eyes.move(to: CGPoint(x: w * 0.57, y: h * 0.46))
                eyes.addQuadCurve(to: CGPoint(x: w * 0.74, y: h * 0.46),
                                  control: CGPoint(x: w * 0.655, y: h * 0.51))
            } else {
                eyes.move(to: CGPoint(x: w * 0.26, y: h * 0.48))
                eyes.addQuadCurve(to: CGPoint(x: w * 0.43, y: h * 0.48),
                                  control: CGPoint(x: w * 0.345, y: h * 0.17))
                eyes.move(to: CGPoint(x: w * 0.57, y: h * 0.48))
                eyes.addQuadCurve(to: CGPoint(x: w * 0.74, y: h * 0.48),
                                  control: CGPoint(x: w * 0.655, y: h * 0.17))
            }
            context.stroke(eyes, with: .color(.white),
                           style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))

            if thirsty {
                let mouth = Path(ellipseIn: CGRect(x: w * 0.46, y: h * 0.61, width: w * 0.08, height: h * 0.17))
                context.stroke(mouth, with: .color(.white), lineWidth: line * 0.75)
            } else {
                var smile = Path()
                smile.move(to: CGPoint(x: w * 0.43, y: h * 0.66))
                smile.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.70),
                                   control: CGPoint(x: w * 0.47, y: h * 0.82))
                smile.addQuadCurve(to: CGPoint(x: w * 0.57, y: h * 0.66),
                                   control: CGPoint(x: w * 0.53, y: h * 0.82))
                context.stroke(smile, with: .color(.white),
                               style: StrokeStyle(lineWidth: line * 0.85, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: w * 0.77, y: h * 0.23,
                                               width: max(2, h * 0.075), height: max(2, h * 0.075))),
                         with: .color(.white))
        }
        .accessibilityLabel(thirsty ? "Nobi kehausan" : blinking ? "Nobi berkedip" : "Nobi")
    }
}

struct ThirstyNobi: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropFell = false

    var body: some View {
        HStack(spacing: 3) {
            NobiFace(outlined: true, thirsty: true).frame(width: 54, height: 32)
            Image(systemName: "drop.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan)
                .offset(y: dropFell && !reduceMotion ? 5 : -5)
        }
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion, !dropFell else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            withAnimation(.easeInOut(duration: 0.65)) { dropFell = true }
        }
    }
}

@MainActor
enum NobiArtwork {
    static func menuBarImage(blinking: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: NobiFace(blinking: blinking, outlined: true,
                                                       tint: Color(red: 0.02, green: 0.85, blue: 0.91))
            .frame(width: 27, height: 17))
        renderer.scale = 2
        return renderer.nsImage
    }
}

struct NobiAppIcon: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24)
                    .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.24, blue: 0.29),
                                                  Color(red: 0.08, green: 0.11, blue: 0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                NobiFace(outlined: true, tint: Color(red: 0.02, green: 0.85, blue: 0.91))
                    .frame(width: side * 0.69, height: side * 0.40)
                    .shadow(color: .cyan.opacity(0.55), radius: side * 0.035)
            }
        }
    }
}
