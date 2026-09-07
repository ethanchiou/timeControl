import Foundation

/// Category of a course or event. Fixed in code (a seeded table would duplicate under CloudKit sync).
public enum Kind: String, CaseIterable, Codable, Sendable, Identifiable {
    case course, tutorial, exam, interview, appointment, personal, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .course: "Course"
        case .tutorial: "Tutorial"
        case .exam: "Exam"
        case .interview: "Interview"
        case .appointment: "Appointment"
        case .personal: "Personal"
        case .other: "Other"
        }
    }

    public var pluralName: String {
        switch self {
        case .course: "Courses"
        case .tutorial: "Tutorials"
        case .exam: "Exams"
        case .interview: "Interviews"
        case .appointment: "Appointments"
        case .personal: "Personal"
        case .other: "Other"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .course: "book.closed"
        case .tutorial: "person.2"
        case .exam: "pencil.and.list.clipboard"
        case .interview: "person.crop.rectangle"
        case .appointment: "calendar.badge.clock"
        case .personal: "heart"
        case .other: "tag"
        }
    }

    /// Default colour, hex RGB.
    public var colorHex: String {
        switch self {
        case .course: "#4F7CFF"
        case .tutorial: "#06B6D4"
        case .exam: "#E5484D"
        case .interview: "#F59E0B"
        case .appointment: "#10B981"
        case .personal: "#A855F7"
        case .other: "#6B7280"
        }
    }

    /// Default reminder lead time in minutes; nil = no reminder by default.
    public var defaultReminderMinutes: Int? {
        switch self {
        case .course: 10
        case .tutorial: 10
        case .exam: 60
        case .interview: 60
        case .appointment: 30
        case .personal: nil
        case .other: nil
        }
    }
}
