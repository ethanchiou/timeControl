import Foundation

// MARK: - Public API

/// The three records quick-add can create. The palette shows one chip per case and Tab cycles them.
public enum CommandType: String, CaseIterable, Sendable {
    case course, event, todo
}

/// Everything the parser needs to know about the app to resolve relative dates and project tags.
public struct QuickAddContext: Sendable {
    /// The day `today`, `tomorrow` and bare weekday names resolve against.
    public var today: DayKey
    /// Only used for the `NSDataDetector` fallback (and its time zone).
    public var calendar: Calendar
    /// Known project names; `#Tag` is matched against these case-insensitively.
    public var projectNames: [String]
    /// Courses need a term to live in; when false, course-shaped input falls through to event/todo.
    public var hasCurrentTerm: Bool

    public init(today: DayKey, calendar: Calendar = .app, projectNames: [String] = [], hasCurrentTerm: Bool = true) {
        self.today = today
        self.calendar = calendar
        self.projectNames = projectNames
        self.hasCurrentTerm = hasCurrentTerm
    }
}

/// A recurring course the palette is about to create. Week bounds are term-relative; nil = term default.
public struct CourseDraft: Hashable, Sendable {
    public var title: String
    public var kind: Kind
    public var weekdays: Set<Weekday>
    public var startMinute: Int
    public var endMinute: Int
    /// 1 = weekly, 2 = biweekly.
    public var intervalWeeks: Int
    public var startWeek: Int?
    public var endWeek: Int?
    public var location: String

    public init(
        title: String,
        kind: Kind = .course,
        weekdays: Set<Weekday> = [],
        startMinute: Int = 540,
        endMinute: Int = 600,
        intervalWeeks: Int = 1,
        startWeek: Int? = nil,
        endWeek: Int? = nil,
        location: String = ""
    ) {
        self.title = title
        self.kind = kind
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.intervalWeeks = intervalWeeks
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.location = location
    }
}

/// A one-off event. `startMinute == nil` means all-day; a start with no end means "caller applies 60 minutes".
public struct EventDraft: Hashable, Sendable {
    public var title: String
    public var kind: Kind
    public var day: DayKey
    public var startMinute: Int?
    public var endMinute: Int?
    public var location: String

    public init(title: String, kind: Kind = .other, day: DayKey, startMinute: Int? = nil, endMinute: Int? = nil, location: String = "") {
        self.title = title
        self.kind = kind
        self.day = day
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.location = location
    }
}

/// A todo. `day` pins it to a date, `week` buckets it into the week starting on that Monday; both nil = someday.
public struct TodoDraft: Hashable, Sendable {
    public var title: String
    /// 1 = urgent … 4 = low.
    public var priority: Int
    public var day: DayKey?
    /// Monday of the week bucket.
    public var week: DayKey?
    public var projectName: String?

    public init(title: String, priority: Int = 3, day: DayKey? = nil, week: DayKey? = nil, projectName: String? = nil) {
        self.title = title
        self.priority = priority
        self.day = day
        self.week = week
        self.projectName = projectName
    }
}

/// A "clear weeks 8–9" blackout. Week numbers are term-relative; empty `kinds` means every kind.
public struct BlackoutDraft: Hashable, Sendable {
    public var kinds: Set<Kind>
    public var startWeek: Int
    public var endWeek: Int
    public var reason: String

    public init(kinds: Set<Kind> = [], startWeek: Int, endWeek: Int, reason: String = "") {
        self.kinds = kinds
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.reason = reason
    }
}

/// Where the palette should navigate instead of creating something.
public enum Navigation: Hashable, Sendable {
    case today
    /// Term week number.
    case week(Int)
    /// "today" | "week" | "todos" | "projects" | "terms" | "settings".
    case section(String)
}

/// The result of parsing one line of quick-add text.
public enum ParsedCommand: Hashable, Sendable {
    case course(CourseDraft)
    case event(EventDraft)
    case todo(TodoDraft)
    case blackout(BlackoutDraft)
    case navigate(Navigation)

    /// The creator type, or nil for blackouts and navigation.
    public var type: CommandType? {
        switch self {
        case .course: .course
        case .event: .event
        case .todo: .todo
        case .blackout, .navigate: nil
        }
    }
}

/// Turns one line of natural-language text into a `ParsedCommand`.
///
/// The parser is total: it never throws, returns nil only for blank input, and falls back to a todo
/// when nothing else matches, so the palette can preview the result on every keystroke.
public enum QuickAddParser {

    /// Parse `input`. `forcing` (the palette's Tab key) reinterprets the same text as a course/event/todo
    /// and wins over an explicit `todo:`/`course:`/`event:` prefix.
    public static func parse(_ input: String, context: QuickAddContext, forcing: CommandType? = nil) -> ParsedCommand? {
        let text = normalize(input)
        guard !text.isEmpty else { return nil }

        if forcing == nil {
            if let nav = navigationCommand(text) { return .navigate(nav) }
            if let out = blackoutCommand(text) { return .blackout(out) }
        }

        var toks = tokenize(text)
        var type = forcing
        if let (prefixed, count) = explicitPrefix(toks) {
            for i in 0..<count { toks[i].role = .filler }
            if type == nil { type = prefixed }
        }

        var ex = Extraction()
        extractAll(&toks, &ex, context)

        let handDay = ex.explicitDay ?? weekdayDay(ex, context)
        let hasRange = ex.timeIsRange && ex.startMinute != nil && ex.endMinute != nil

        switch type {
        case .course where context.hasCurrentTerm:
            return .course(buildCourse(toks, ex))
        case .event:
            return .event(buildEvent(&toks, ex, handDay, text, context))
        case .todo:
            return .todo(buildTodo(toks, ex, handDay, context))
        default:
            break
        }

        // 2. Weekday list + a time range is a course (when a term exists).
        if hasRange, !ex.weekdays.isEmpty, context.hasCurrentTerm {
            return .course(buildCourse(toks, ex))
        }

        // 3. A date plus a time, an event-ish title, or an explicit #kind tag.
        var day = handDay
        var detected: DetectorHit?
        if day == nil {
            detected = detectDate(text, context)
            day = detected?.day
        }
        if day != nil {
            let inferred = inferKind(from: title(toks, keep: [.free]))
            if ex.startMinute != nil || inferred != .other || ex.kindTag != nil {
                return .event(buildEvent(&toks, ex, handDay, text, context, detected: detected))
            }
        }

        // 4. Everything else is a todo.
        return .todo(buildTodo(toks, ex, handDay, context))
    }
}

// MARK: - Builders

private func buildCourse(_ toks: [Tok], _ ex: Extraction) -> CourseDraft {
    let start = ex.startMinute ?? 540
    let end = ex.endMinute ?? (ex.startMinute == nil ? 600 : start + 60)
    return CourseDraft(
        title: title(toks, keep: [.free]),
        kind: ex.kindTag ?? .course,
        weekdays: ex.weekdays,
        startMinute: start,
        endMinute: max(end, start),
        intervalWeeks: ex.intervalWeeks,
        startWeek: ex.startWeek,
        endWeek: ex.endWeek,
        location: ex.location
    )
}

private func buildEvent(
    _ toks: inout [Tok],
    _ ex: Extraction,
    _ handDay: DayKey?,
    _ text: String,
    _ context: QuickAddContext,
    detected: DetectorHit? = nil
) -> EventDraft {
    var day = handDay
    if day == nil {
        let hit = detected ?? detectDate(text, context)
        if let hit {
            day = hit.day
            markDetected(&toks, hit.range)
            stripFillers(&toks)
        }
    }
    let words = title(toks, keep: [.free])
    var end = ex.endMinute
    if end == nil, let start = ex.startMinute, let dur = ex.durationMinutes { end = start + dur }
    return EventDraft(
        title: words,
        kind: ex.kindTag ?? inferKind(from: words),
        day: day ?? context.today,
        startMinute: ex.startMinute,
        endMinute: end,
        location: ex.location
    )
}

private func buildTodo(_ toks: [Tok], _ ex: Extraction, _ handDay: DayKey?, _ context: QuickAddContext) -> TodoDraft {
    var day: DayKey?
    var week: DayKey?
    switch ex.bucket {
    case .someday:
        break
    case .thisWeek:
        week = context.today.weekStart
    case .nextWeek:
        week = context.today.weekStart + 7
    case nil:
        day = handDay ?? context.today
    }
    return TodoDraft(
        title: title(toks, keep: [.free, .weeks, .interval, .time, .duration]),
        priority: ex.priority ?? 3,
        day: day,
        week: week,
        projectName: ex.tags.first.map { matchProject($0, context.projectNames) }
    )
}

// MARK: - Tokens

private enum Role {
    case free, tag, weeks, interval, priority, date, weekday, time, duration, bucket, location, filler
}

private struct Tok {
    let raw: String
    let lower: String
    /// Lowercased with surrounding punctuation trimmed. Leading `#`, `@` and `!` are kept.
    let clean: String
    /// UTF-16 offsets into the normalized string, for the `NSDataDetector` fallback.
    let start: Int
    let end: Int
    var role: Role = .free
}

private func normalize(_ s: String) -> String {
    s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

private func cleanToken(_ s: String) -> String {
    var t = Substring(s.lowercased())
    while let c = t.last, ",.;:!?)]\"'".contains(c) { t = t.dropLast() }
    while let c = t.first, "([\"'".contains(c) { t = t.dropFirst() }
    return String(t)
}

private func tokenize(_ text: String) -> [Tok] {
    var out: [Tok] = []
    var offset = 0
    for piece in text.split(separator: " ") {
        let s = String(piece)
        let len = s.utf16.count
        out.append(Tok(raw: s, lower: s.lowercased(), clean: cleanToken(s), start: offset, end: offset + len))
        offset += len + 1
    }
    return out
}

private func title(_ toks: [Tok], keep: Set<Role>) -> String {
    toks.filter { keep.contains($0.role) }.map(\.raw).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Extraction

private enum Bucket {
    case thisWeek, nextWeek, someday
}

private struct Extraction {
    var tags: [String] = []
    var kindTag: Kind?
    var weekdays: Set<Weekday> = []
    /// 1 when the weekday was qualified with "next".
    var weekdayJumpsAWeek = false
    var startWeek: Int?
    var endWeek: Int?
    var intervalWeeks = 1
    var priority: Int?
    var explicitDay: DayKey?
    var startMinute: Int?
    var endMinute: Int?
    var timeIsRange = false
    var durationMinutes: Int?
    var bucket: Bucket?
    var location = ""
    var locationIndex: Int?
}

private func extractAll(_ toks: inout [Tok], _ ex: inout Extraction, _ ctx: QuickAddContext) {
    reserveLocation(&toks, &ex)
    extractTags(&toks, &ex)
    extractBucket(&toks, &ex)
    extractWeeks(&toks, &ex)
    extractInterval(&toks, &ex)
    extractPriority(&toks, &ex)
    extractDate(&toks, &ex, ctx)
    extractWeekdays(&toks, &ex)
    extractTime(&toks, &ex)
    extractDuration(&toks, &ex)
    expandLocation(&toks, &ex)
    stripFillers(&toks)
}

/// Claims the `@` head token up front so no other pass can eat it. `bob@example.com` is not a location.
private func reserveLocation(_ toks: inout [Tok], _ ex: inout Extraction) {
    for i in toks.indices {
        guard toks[i].raw.hasPrefix("@") else { continue }
        guard toks[i].raw.count > 1 || i + 1 < toks.count else { continue }
        toks[i].role = .location
        ex.locationIndex = i
        return
    }
}

private func extractTags(_ toks: inout [Tok], _ ex: inout Extraction) {
    for i in toks.indices where toks[i].role == .free {
        guard toks[i].clean.hasPrefix("#"), toks[i].clean.count > 1 else { continue }
        let tag = String(toks[i].clean.dropFirst())
        // Preserve the user's casing for project names.
        var raw = Substring(toks[i].raw.dropFirst())
        while let c = raw.last, ",.;:!?".contains(c) { raw = raw.dropLast() }
        ex.tags.append(String(raw))
        if ex.kindTag == nil, let k = kindNamed(tag) { ex.kindTag = k }
        toks[i].role = .tag
    }
}

private func extractBucket(_ toks: inout [Tok], _ ex: inout Extraction) {
    for i in toks.indices where toks[i].role == .free {
        let c = toks[i].clean
        if ["someday", "later", "backlog", "eventually"].contains(c) {
            ex.bucket = .someday
            toks[i].role = .bucket
            return
        }
        guard c == "this" || c == "next", i + 1 < toks.count, toks[i + 1].role == .free else { continue }
        guard ["week", "wk"].contains(toks[i + 1].clean) else { continue }
        ex.bucket = c == "this" ? .thisWeek : .nextWeek
        toks[i].role = .bucket
        toks[i + 1].role = .bucket
        return
    }
}

/// `weeks 1-14`, `week 8`, `wk 8–9`, `weeks 3 to 10`, `w1-14`.
private func weekSpec(_ toks: [Tok], at i: Int) -> (start: Int, end: Int, next: Int)? {
    guard i < toks.count else { return nil }
    let glued = #/^(?:weeks?|wks?|w)(\d{1,2})(?:[-–—](\d{1,2}))?$/#
    if let m = toks[i].clean.wholeMatch(of: glued), let a = Int(m.1) {
        return (a, m.2.flatMap { Int($0) } ?? a, i + 1)
    }
    guard ["week", "weeks", "wk", "wks"].contains(toks[i].clean), i + 1 < toks.count else { return nil }
    let dashed = #/^(\d{1,2})[-–—](\d{1,2})$/#
    if let m = toks[i + 1].clean.wholeMatch(of: dashed), let a = Int(m.1), let b = Int(m.2) {
        return (a, b, i + 2)
    }
    guard let a = Int(toks[i + 1].clean) else { return nil }
    if i + 3 < toks.count, ["to", "-", "–", "—", "through", "until"].contains(toks[i + 2].clean), let b = Int(toks[i + 3].clean) {
        return (a, b, i + 4)
    }
    return (a, a, i + 2)
}

private func extractWeeks(_ toks: inout [Tok], _ ex: inout Extraction) {
    for i in toks.indices where toks[i].role == .free {
        guard let spec = weekSpec(toks, at: i) else { continue }
        guard toks[i..<spec.next].allSatisfy({ $0.role == .free }) else { continue }
        ex.startWeek = min(spec.start, spec.end)
        ex.endWeek = max(spec.start, spec.end)
        for k in i..<spec.next { toks[k].role = .weeks }
        return
    }
}

private func extractInterval(_ toks: inout [Tok], _ ex: inout Extraction) {
    for i in toks.indices where toks[i].role == .free {
        let c = toks[i].clean
        if ["biweekly", "bi-weekly", "fortnightly", "fortnight"].contains(c) {
            ex.intervalWeeks = 2
            toks[i].role = .interval
            return
        }
        if c == "weekly" {
            toks[i].role = .interval
            return
        }
        guard c == "every", i + 2 < toks.count, toks[i + 1].role == .free, toks[i + 2].role == .free else { continue }
        guard ["week", "weeks"].contains(toks[i + 2].clean) else { continue }
        guard ["other", "2", "two"].contains(toks[i + 1].clean) else { continue }
        ex.intervalWeeks = 2
        for k in i...(i + 2) { toks[k].role = .interval }
        return
    }
}

private func extractPriority(_ toks: inout [Tok], _ ex: inout Extraction) {
    let words: [String: Int] = ["urgent": 1, "high": 2, "normal": 3, "medium": 3, "low": 4]
    for i in toks.indices where toks[i].role == .free {
        let c = toks[i].clean
        if let m = c.wholeMatch(of: #/^[!p]([1-4])$/#), let n = Int(m.1) {
            ex.priority = n
            toks[i].role = .priority
            return
        }
        if c.hasPrefix("!"), let n = words[String(c.dropFirst())] {
            ex.priority = n
            toks[i].role = .priority
            return
        }
    }
}

private func extractDate(_ toks: inout [Tok], _ ex: inout Extraction, _ ctx: QuickAddContext) {
    let iso = #/^(\d{4})-(\d{1,2})-(\d{1,2})$/#
    let slash = #/^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$/#
    let dayNum = #/^(\d{1,2})(?:st|nd|rd|th)?$/#

    func setDay(_ d: DayKey, _ range: ClosedRange<Int>) {
        ex.explicitDay = d
        for k in range { toks[k].role = .date }
    }

    for i in toks.indices where toks[i].role == .free {
        let c = toks[i].clean
        if c == "today" { setDay(ctx.today, i...i); return }
        if ["tomorrow", "tmr", "tmrw", "tmw", "tom"].contains(c) { setDay(ctx.today + 1, i...i); return }
        if c == "yesterday" { setDay(ctx.today - 1, i...i); return }
        if let m = c.wholeMatch(of: iso), let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3),
           (1...12).contains(mo), (1...31).contains(d) {
            setDay(DayKey(year: y, month: mo, day: d), i...i)
            return
        }
        if let m = c.wholeMatch(of: slash), let mo = Int(m.1), let d = Int(m.2),
           (1...12).contains(mo), (1...31).contains(d) {
            var y = ctx.today.year
            if let ys = m.3, let v = Int(ys) { y = v < 100 ? 2000 + v : v }
            setDay(DayKey(year: y, month: mo, day: d), i...i)
            return
        }
        // "Sep 14" / "September 14 2026"
        if let mo = monthNumber(c), i + 1 < toks.count, toks[i + 1].role == .free,
           let m = toks[i + 1].clean.wholeMatch(of: dayNum), let d = Int(m.1), (1...31).contains(d) {
            var y = ctx.today.year
            var last = i + 1
            if i + 2 < toks.count, toks[i + 2].role == .free, let v = Int(toks[i + 2].clean), v >= 1000 {
                y = v
                last = i + 2
            }
            setDay(DayKey(year: y, month: mo, day: d), i...last)
            return
        }
        // "14 Sep" / "14 September 2026"
        if let m = c.wholeMatch(of: dayNum), let d = Int(m.1), (1...31).contains(d),
           i + 1 < toks.count, toks[i + 1].role == .free, let mo = monthNumber(toks[i + 1].clean) {
            var y = ctx.today.year
            var last = i + 1
            if i + 2 < toks.count, toks[i + 2].role == .free, let v = Int(toks[i + 2].clean), v >= 1000 {
                y = v
                last = i + 2
            }
            setDay(DayKey(year: y, month: mo, day: d), i...last)
            return
        }
    }
}

private func extractWeekdays(_ toks: inout [Tok], _ ex: inout Extraction) {
    guard let j = toks.indices.first(where: { toks[$0].role == .free && weekdaySet(from: toks[$0].clean) != nil }) else { return }
    var days = weekdaySet(from: toks[j].clean)!
    toks[j].role = .weekday
    if j > 0, toks[j - 1].role == .free {
        let c = toks[j - 1].clean
        if c == "next" {
            ex.weekdayJumpsAWeek = true
            toks[j - 1].role = .weekday
        } else if ["this", "on", "every"].contains(c) {
            toks[j - 1].role = .weekday
        }
    }
    var k = j + 1
    while k < toks.count {
        if toks[k].role == .free, ["and", "&", "+", ","].contains(toks[k].clean),
           k + 1 < toks.count, toks[k + 1].role == .free, let more = weekdaySet(from: toks[k + 1].clean) {
            toks[k].role = .weekday
            toks[k + 1].role = .weekday
            days.formUnion(more)
            k += 2
            continue
        }
        if toks[k].role == .free, let more = weekdaySet(from: toks[k].clean) {
            toks[k].role = .weekday
            days.formUnion(more)
            k += 1
            continue
        }
        break
    }
    ex.weekdays = days
}

private func extractTime(_ toks: inout [Tok], _ ex: inout Extraction) {
    // `10-11:30`, `1-2:30pm`, `14:00–15:30`, `3pm-4:30pm`
    let range = #/^(\d{1,2}(?::\d{2})?(?:a\.?m\.?|p\.?m\.?)?)[-–—](\d{1,2}(?::\d{2})?(?:a\.?m\.?|p\.?m\.?)?)$/#
    for i in toks.indices where toks[i].role == .free {
        guard let m = toks[i].clean.wholeMatch(of: range),
              let a = timeLiteral(String(m.1)), let b = timeLiteral(String(m.2)) else { continue }
        let (s, e) = resolveRange(a, b)
        ex.startMinute = s
        ex.endMinute = e
        ex.timeIsRange = true
        toks[i].role = .time
        return
    }
    // `10 to 11:30`, `10 - 11:30`
    let separators = ["to", "-", "–", "—", "until", "till", "through"]
    for i in toks.indices where toks[i].role == .free {
        guard i + 2 < toks.count, toks[i + 1].role == .free, toks[i + 2].role == .free else { continue }
        guard separators.contains(toks[i + 1].clean) else { continue }
        guard let a = timeLiteral(toks[i].clean), let b = timeLiteral(toks[i + 2].clean) else { continue }
        let (s, e) = resolveRange(a, b)
        ex.startMinute = s
        ex.endMinute = e
        ex.timeIsRange = true
        for k in i...(i + 2) { toks[k].role = .time }
        return
    }
    // `at 3`, `3pm`, `15:00`
    for i in toks.indices where toks[i].role == .free {
        if ["at", "from", "@"].contains(toks[i].clean), i + 1 < toks.count, toks[i + 1].role == .free,
           let t = timeLiteral(toks[i + 1].clean) {
            ex.startMinute = resolve(t, inheriting: nil)
            toks[i].role = .time
            toks[i + 1].role = .time
            return
        }
        if let t = timeLiteral(toks[i].clean), t.isDefinite {
            ex.startMinute = resolve(t, inheriting: nil)
            toks[i].role = .time
            return
        }
    }
}

private func extractDuration(_ toks: inout [Tok], _ ex: inout Extraction) {
    let hours = #/^(\d{1,3})h(?:rs?|ours?)?(\d{1,2})?$/#
    let minutes = #/^(\d{1,3})(?:m|mins?|minutes?)$/#
    let units: [String: Int] = ["h": 60, "hr": 60, "hrs": 60, "hour": 60, "hours": 60,
                                "m": 1, "min": 1, "mins": 1, "minute": 1, "minutes": 1]
    for i in toks.indices where toks[i].role == .free {
        guard toks[i].clean == "for", i + 1 < toks.count, toks[i + 1].role == .free else { continue }
        let c = toks[i + 1].clean
        if let m = c.wholeMatch(of: hours), let h = Int(m.1) {
            ex.durationMinutes = h * 60 + (m.2.flatMap { Int($0) } ?? 0)
            toks[i].role = .duration
            toks[i + 1].role = .duration
            return
        }
        if let m = c.wholeMatch(of: minutes), let v = Int(m.1) {
            ex.durationMinutes = v
            toks[i].role = .duration
            toks[i + 1].role = .duration
            return
        }
        if let n = Int(c), i + 2 < toks.count, toks[i + 2].role == .free, let unit = units[toks[i + 2].clean] {
            ex.durationMinutes = n * unit
            for k in i...(i + 2) { toks[k].role = .duration }
            return
        }
    }
}

/// The location runs from `@` to the end of the input or to the next token another pass already claimed.
private func expandLocation(_ toks: inout [Tok], _ ex: inout Extraction) {
    guard let i = ex.locationIndex else { return }
    var parts: [String] = []
    let head = String(toks[i].raw.dropFirst())
    if !head.isEmpty { parts.append(head) }
    var k = i + 1
    while k < toks.count, toks[k].role == .free {
        parts.append(toks[k].raw)
        toks[k].role = .location
        k += 1
    }
    ex.location = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Drops prepositions left stranded next to something a pass consumed ("Call mom **on** Tuesday").
private func stripFillers(_ toks: inout [Tok]) {
    let fillers: Set<String> = ["on", "at", "from", "in", "of", "by", "due", "the", "starting",
                                "every", "this", "next", "for", "to", "until", "till", "around", "@"]
    let consumed: Set<Role> = [.date, .weekday, .time, .duration, .bucket, .weeks, .interval, .filler, .location]
    for i in toks.indices.reversed() {
        guard toks[i].role == .free, fillers.contains(toks[i].clean) else { continue }
        guard i + 1 < toks.count, consumed.contains(toks[i + 1].role) else { continue }
        toks[i].role = .filler
    }
}

// MARK: - Times

private struct TimeLiteral {
    var hour: Int
    var minute: Int?
    /// 0 = am, 1 = pm.
    var meridiem: Int?
    var isDefinite: Bool { minute != nil || meridiem != nil }
}

private func timeLiteral(_ s: String) -> TimeLiteral? {
    guard let m = s.wholeMatch(of: #/^(\d{1,2})(?::(\d{2}))?(a\.?m\.?|p\.?m\.?)?$/#), let h = Int(m.1) else { return nil }
    guard (0...23).contains(h) else { return nil }
    var minute: Int?
    if let ms = m.2 {
        guard let v = Int(ms), (0...59).contains(v) else { return nil }
        minute = v
    }
    var meridiem: Int?
    if let mer = m.3 { meridiem = mer.hasPrefix("p") ? 1 : 0 }
    return TimeLiteral(hour: h, minute: minute, meridiem: meridiem)
}

/// Bare hours 1–7 read as pm, 8–11 as am, 12 as noon; explicit or inherited meridiems win.
private func resolve(_ t: TimeLiteral, inheriting inherited: Int?) -> Int {
    var h = t.hour
    if let mer = t.meridiem ?? inherited {
        h = h % 12
        if mer == 1 { h += 12 }
    } else if (1...7).contains(h) {
        h += 12
    }
    return h * 60 + (t.minute ?? 0)
}

private func resolveRange(_ a: TimeLiteral, _ b: TimeLiteral) -> (Int, Int) {
    let start = resolve(a, inheriting: a.meridiem == nil ? b.meridiem : nil)
    var end = resolve(b, inheriting: b.meridiem == nil ? a.meridiem : nil)
    if end <= start, b.meridiem == nil, end + 720 < 24 * 60 { end += 720 }
    return (start, end)
}

// MARK: - Weekdays, months, kinds

private let weekdayNames: [String: Weekday] = [
    "mon": .monday, "mon.": .monday, "monday": .monday, "mondays": .monday,
    "tue": .tuesday, "tues": .tuesday, "tuesday": .tuesday, "tuesdays": .tuesday, "tu": .tuesday,
    "wed": .wednesday, "weds": .wednesday, "wednesday": .wednesday, "wednesdays": .wednesday,
    "thu": .thursday, "thur": .thursday, "thurs": .thursday, "thursday": .thursday, "thursdays": .thursday, "th": .thursday,
    "fri": .friday, "friday": .friday, "fridays": .friday, "fr": .friday,
    "sat": .saturday, "saturday": .saturday, "saturdays": .saturday, "sa": .saturday,
    "sun": .sunday, "sunday": .sunday, "sundays": .sunday, "su": .sunday
]

private let weekdayCodePairs: [String: Weekday] = ["th": .thursday, "tu": .tuesday, "sa": .saturday, "su": .sunday]
private let weekdayCodeLetters: [Character: Weekday] = ["m": .monday, "t": .tuesday, "w": .wednesday, "f": .friday, "s": .saturday]

/// `MWF`, `TTh`, `TuTh`. Repeats are rejected so ordinary words ("stuff") don't read as weekdays.
private func weekdayCode(_ s: String, allowSingle: Bool) -> Set<Weekday>? {
    let chars = Array(s)
    guard chars.count >= (allowSingle ? 1 : 2), chars.count <= 6 else { return nil }
    var out: [Weekday] = []
    var i = 0
    while i < chars.count {
        if i + 1 < chars.count, let w = weekdayCodePairs[String(chars[i...(i + 1)])] {
            out.append(w)
            i += 2
            continue
        }
        guard let w = weekdayCodeLetters[chars[i]] else { return nil }
        out.append(w)
        i += 1
    }
    guard !out.isEmpty, Set(out).count == out.count else { return nil }
    return Set(out)
}

private func weekdaySet(from token: String) -> Set<Weekday>? {
    let t = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
    guard !t.isEmpty else { return nil }
    if let w = weekdayNames[t] { return [w] }
    let parts = t.split(whereSeparator: { "/,+&".contains($0) }).map(String.init)
    if parts.count > 1 {
        var out: Set<Weekday> = []
        for p in parts {
            if let w = weekdayNames[p] { out.insert(w) }
            else if let more = weekdayCode(p, allowSingle: true) { out.formUnion(more) }
            else { return nil }
        }
        return out.isEmpty ? nil : out
    }
    return weekdayCode(t, allowSingle: false)
}

private func weekdayDay(_ ex: Extraction, _ ctx: QuickAddContext) -> DayKey? {
    guard !ex.weekdays.isEmpty else { return nil }
    if ex.weekdayJumpsAWeek {
        let monday = ctx.today.weekStart + 7
        return ex.weekdays.map { monday + $0.rawValue }.min()
    }
    return ex.weekdays.map { w -> DayKey in
        let delta = ((w.rawValue - ctx.today.weekday.rawValue) % 7 + 7) % 7
        return ctx.today + delta
    }.min()
}

private let monthNumbers: [String: Int] = [
    "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
    "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
    "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
    "dec": 12, "december": 12
]

private func monthNumber(_ s: String) -> Int? { monthNumbers[s] }

private func kindNamed(_ s: String) -> Kind? {
    let t = s.lowercased()
    if t == "class" || t == "classes" { return .course }
    for k in Kind.allCases where t == k.rawValue || t == k.rawValue + "s" || t == k.pluralName.lowercased() {
        return k
    }
    return nil
}

private let interviewWords: Set<String> = ["interview", "interviews"]
private let examWords: Set<String> = ["exam", "exams", "midterm", "midterms", "final", "finals", "quiz", "test"]
private let appointmentWords: Set<String> = ["dentist", "doctor", "dr", "appointment", "appt", "meeting", "haircut"]

private func inferKind(from title: String) -> Kind {
    let words = Set(title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    if !words.isDisjoint(with: interviewWords) { return .interview }
    if !words.isDisjoint(with: examWords) { return .exam }
    if !words.isDisjoint(with: appointmentWords) { return .appointment }
    return .other
}

private func matchProject(_ tag: String, _ names: [String]) -> String {
    names.first { $0.lowercased() == tag.lowercased() } ?? tag
}

// MARK: - Prefixes, navigation, blackouts

private func explicitPrefix(_ toks: [Tok]) -> (CommandType, Int)? {
    guard let first = toks.first else { return nil }
    let c = first.clean
    let type: CommandType?
    switch c {
    case "todo", "todos", "task": type = .todo
    case "course", "class": type = .course
    case "event": type = .event
    default: type = nil
    }
    guard let type, toks.count > 1 else { return nil }
    return (type, 1)
}

private let sectionNames: [String: String] = [
    "today": "today", "week": "week", "weeks": "week", "todo": "todos", "todos": "todos",
    "project": "projects", "projects": "projects", "term": "terms", "terms": "terms",
    "setting": "settings", "settings": "settings", "preferences": "settings", "prefs": "settings"
]

private func navigationCommand(_ text: String) -> Navigation? {
    let parts = text.split(separator: " ").map { cleanToken(String($0)) }.filter { !$0.isEmpty }
    guard !parts.isEmpty else { return nil }
    if parts == ["today"] { return .today }
    if parts.count == 1, let m = parts[0].wholeMatch(of: #/^(?:weeks?|wks?|w)(\d{1,2})$/#), let n = Int(m.1) {
        return .week(n)
    }
    if parts.count == 2, ["week", "weeks", "wk", "wks", "w"].contains(parts[0]), let n = Int(parts[1]) {
        return .week(n)
    }
    if parts.count >= 2, ["go", "goto", "open", "show", "jump"].contains(parts[0]) {
        var rest = Array(parts.dropFirst())
        if rest.first == "to" { rest.removeFirst() }
        if rest.count == 1, let s = sectionNames[rest[0]] { return .section(s) }
    }
    return nil
}

private func blackoutCommand(_ text: String) -> BlackoutDraft? {
    let toks = tokenize(text)
    guard let first = toks.first, ["clear", "hide", "block", "blackout"].contains(first.clean) else { return nil }
    var kinds: Set<Kind> = []
    var i = 1
    var sawAll = false
    while i < toks.count {
        let c = toks[i].clean
        if c.isEmpty || ["and", "&", ",", "out", "the"].contains(c) { i += 1; continue }
        if c == "all" || c == "everything" { sawAll = true; i += 1; continue }
        if let k = kindNamed(c) { kinds.insert(k); i += 1; continue }
        break
    }
    guard let spec = weekSpec(toks, at: i) else { return nil }
    if sawAll { kinds = [] }
    let reason = toks[spec.next...].map(\.raw).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return BlackoutDraft(kinds: kinds, startWeek: min(spec.start, spec.end), endWeek: max(spec.start, spec.end), reason: reason)
}

// MARK: - NSDataDetector fallback

private struct DetectorHit {
    var day: DayKey
    var range: NSRange
}

/// Last resort when hand parsing finds no date, so the common cases stay deterministic.
private func detectDate(_ text: String, _ context: QuickAddContext) -> DetectorHit? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
    let range = NSRange(location: 0, length: (text as NSString).length)
    guard let match = detector.firstMatch(in: text, options: [], range: range), let date = match.date else { return nil }
    // The detector resolves unqualified text in the current time zone; read the civil date back out of the
    // same zone so the answer does not shift with the host's zone. A zone named in the text wins.
    var calendar = context.calendar
    if match.timeZone == nil { calendar.timeZone = .current }
    return DetectorHit(day: DayKey(date, calendar: calendar), range: match.range)
}

private func markDetected(_ toks: inout [Tok], _ range: NSRange) {
    let lower = range.location
    let upper = range.location + range.length
    for i in toks.indices where toks[i].role == .free {
        if toks[i].start < upper && toks[i].end > lower { toks[i].role = .date }
    }
}
