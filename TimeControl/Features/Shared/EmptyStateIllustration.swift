import SwiftUI

/// The spot illustration above an empty section: gray strokes for the structure and one accent-coloured
/// element for the thing you are about to add. Drawn in a 96-unit space and scaled to `size`, so it
/// follows the accent colour and appearance like the rest of the app instead of shipping as a bitmap.
struct EmptyStateIllustration: View {
    enum Subject {
        case calendar, terms, courses, today, projects
    }

    var subject: Subject
    var size: CGFloat = 88

    init(_ subject: Subject, size: CGFloat = 88) {
        self.subject = subject
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 96
            context.scaleBy(x: scale, y: scale)
            let pen = Pen(context: context)
            switch subject {
            case .calendar: drawCalendar(pen)
            case .terms: drawTerms(pen)
            case .courses: drawCourses(pen)
            case .today: drawToday(pen)
            case .projects: drawProjects(pen)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Subjects

    /// A week grid with two placeholder blocks and one being added.
    private func drawCalendar(_ pen: Pen) {
        pen.stroke(.rounded(10, 14, 76, 70, radius: 8))
        pen.stroke(.line(10, 30, 86, 30))
        for x in [25.2, 40.4, 55.6, 70.8] {
            pen.stroke(.line(x, 30, x, 84), opacity: 0.45)
        }
        pen.stroke(.rounded(13.5, 36, 8.2, 18, radius: 2.5), dashed: true)
        pen.stroke(.rounded(59, 44, 8.2, 20, radius: 2.5), dashed: true)
        let block = Path.rounded(28.6, 36, 8.2, 26, radius: 2.5)
        pen.fill(block, .accent, opacity: 0.14)
        pen.stroke(block, .accent)
        pen.stroke(.line(32.7, 45, 32.7, 53), .accent)
        pen.stroke(.line(28.7, 49, 36.7, 49), .accent)
    }

    /// A mortarboard over the span of weeks a term covers.
    private func drawTerms(_ pen: Pen) {
        var cap = Path()
        cap.move(to: CGPoint(x: 48, y: 18))
        cap.addLine(to: CGPoint(x: 78, y: 31))
        cap.addLine(to: CGPoint(x: 48, y: 44))
        cap.addLine(to: CGPoint(x: 18, y: 31))
        cap.closeSubpath()
        pen.stroke(cap)
        var band = Path()
        band.move(to: CGPoint(x: 30, y: 36))
        band.addLine(to: CGPoint(x: 30, y: 48))
        band.addQuadCurve(to: CGPoint(x: 66, y: 48), control: CGPoint(x: 48, y: 58))
        band.addLine(to: CGPoint(x: 66, y: 36))
        pen.stroke(band)
        pen.stroke(.line(78, 31, 78, 47), .accent)
        pen.fill(.circle(78, 51, radius: 3.5), .accent)
        pen.stroke(.line(16, 74, 80, 74))
        for x in stride(from: 24.0, through: 72, by: 8) {
            pen.stroke(.line(x, 70, x, 78), opacity: 0.45)
        }
        pen.stroke(.line(16, 66, 16, 82))
        pen.stroke(.line(80, 66, 80, 82))
    }

    /// A closed book with a bookmark.
    private func drawCourses(_ pen: Pen) {
        pen.stroke(.rounded(26, 14, 44, 68, radius: 5))
        pen.stroke(.line(34, 14, 34, 82))
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: 54, y: 14))
        ribbon.addLine(to: CGPoint(x: 62, y: 14))
        ribbon.addLine(to: CGPoint(x: 62, y: 40))
        ribbon.addLine(to: CGPoint(x: 58, y: 36))
        ribbon.addLine(to: CGPoint(x: 54, y: 40))
        ribbon.closeSubpath()
        pen.fill(ribbon, .accent, opacity: 0.14)
        pen.stroke(ribbon, .accent)
        pen.stroke(.line(42, 56, 62, 56), opacity: 0.45)
        pen.stroke(.line(42, 66, 56, 66), opacity: 0.45)
    }

    /// An empty day column with the now line running through it.
    private func drawToday(_ pen: Pen) {
        pen.stroke(.rounded(30, 10, 36, 76, radius: 6))
        for y in [22.0, 34, 58, 70] {
            pen.stroke(.line(18, y, 26, y), opacity: 0.45)
        }
        pen.stroke(.line(18, 46, 82, 46), .accent)
        pen.fill(.circle(18, 46, radius: 4), .accent)
    }

    /// A two-by-two board of project cards, the first carrying a progress ring.
    private func drawProjects(_ pen: Pen) {
        pen.stroke(.rounded(14, 14, 30, 30, radius: 7))
        pen.stroke(.rounded(52, 14, 30, 30, radius: 7), dashed: true)
        pen.stroke(.rounded(14, 52, 30, 30, radius: 7), dashed: true)
        pen.stroke(.rounded(52, 52, 30, 30, radius: 7), dashed: true)
        pen.stroke(.circle(29, 29, radius: 8), .accent, opacity: 0.25)
        var arc = Path()
        arc.addArc(center: CGPoint(x: 29, y: 29), radius: 8, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
        pen.stroke(arc, .accent)
    }

    // MARK: Drawing helpers

    private enum Ink {
        case structure, accent

        var color: Color {
            switch self {
            case .structure: .secondary
            case .accent: .accentColor
            }
        }
    }

    /// 3-unit round-capped strokes, the one weight every illustration shares.
    private struct Pen {
        var context: GraphicsContext

        func stroke(_ path: Path, _ ink: Ink = .structure, dashed: Bool = false, opacity: Double = 1) {
            let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: dashed ? [5, 5] : [])
            context.stroke(path, with: .color(ink.color.opacity(opacity)), style: style)
        }

        func fill(_ path: Path, _ ink: Ink, opacity: Double = 1) {
            context.fill(path, with: .color(ink.color.opacity(opacity)))
        }
    }
}

private extension Path {
    static func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        return path
    }

    static func rounded(_ x: Double, _ y: Double, _ width: Double, _ height: Double, radius: Double) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius)
    }

    static func circle(_ cx: Double, _ cy: Double, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
    }
}

#Preview("All subjects") {
    HStack(spacing: 32) {
        EmptyStateIllustration(.calendar)
        EmptyStateIllustration(.terms)
        EmptyStateIllustration(.courses)
        EmptyStateIllustration(.today)
        EmptyStateIllustration(.projects)
    }
    .padding(32)
}
