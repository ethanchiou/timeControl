import Foundation

/// Category of a course or event. Fixed in code (a seeded table would duplicate under CloudKit sync).
public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
    case course, tutorial, assignment, exam, interview, appointment, hangout, personal, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .course: "Course"
        case .tutorial: "Tutorial"
        case .assignment: "Assignment"
        case .exam: "Exam"
        case .interview: "Interview"
        case .appointment: "Appointment"
        case .hangout: "Hangout"
        case .personal: "Personal"
        case .other: "Other"
        }
    }

    public var pluralName: String {
        switch self {
        case .course: "Courses"
        case .tutorial: "Tutorials"
        case .assignment: "Assignments"
        case .exam: "Exams"
        case .interview: "Interviews"
        case .appointment: "Appointments"
        case .hangout: "Hangouts"
        case .personal: "Personal"
        case .other: "Other"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .course: "book.closed"
        case .tutorial: "person.2"
        case .assignment: "doc.text"
        case .exam: "pencil.and.list.clipboard"
        case .interview: "person.crop.rectangle"
        case .appointment: "calendar.badge.clock"
        case .hangout: "person.2.wave.2"
        case .personal: "heart"
        case .other: "tag"
        }
    }

    /// Default colour, hex RGB.
    public var colorHex: String {
        switch self {
        case .course: "#4F7CFF"
        case .tutorial: "#06B6D4"
        case .assignment: "#F97316"
        case .exam: "#E5484D"
        case .interview: "#F59E0B"
        case .appointment: "#10B981"
        case .hangout: "#EC4899"
        case .personal: "#A855F7"
        case .other: "#6B7280"
        }
    }

    /// Default reminder lead time in minutes; nil = no reminder by default.
    public var defaultReminderMinutes: Int? {
        switch self {
        case .course: 10
        case .tutorial: 10
        case .assignment: 1440
        case .exam: 60
        case .interview: 60
        case .appointment: 30
        case .hangout: 30
        case .personal: nil
        case .other: nil
        }
    }
}
