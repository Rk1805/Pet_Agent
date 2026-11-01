import EventKit
import Foundation

/// Understands "tomorrow at 5pm", "next friday 3pm", "in 2 hours", "at 6", "on 12 nov" in a sentence.
struct When {
    let date: Date
    let hasTime: Bool
    let duration: TimeInterval?     // "for 1 hour", "for 30 minutes"
    let rest: String                // the sentence with the date words removed

    static func parse(_ text: String, now: Date = Date()) -> When? {
        var rest = text
        var duration: TimeInterval?
        if let r = rest.range(of: #"\s*for\s+(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let part = String(rest[r]).lowercased()
            let n = Double(part.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()) ?? 1
            duration = part.contains("h") && !part.contains("min") ? n * 3600 : n * 60
            rest.removeSubrange(r)
        }
        // "in 20 minutes", "in 2 hours", "in 3 days"
        if let r = rest.range(of: #"\bin\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let part = String(rest[r]).lowercased()
            let n = Double(part.filter(\.isNumber)) ?? 1
            let secs = part.contains("min") ? 60.0 : part.contains("h") ? 3600 : part.contains("week") ? 604_800 : 86_400
            rest.removeSubrange(r)
            return When(date: now.addingTimeInterval(n * secs), hasTime: !part.contains("day") && !part.contains("week"),
                        duration: duration, rest: tidy(rest))
        }
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        if let m = det.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)), var date = m.date,
           let r = Range(m.range, in: rest) {
            let words = String(rest[r]).lowercased()
            let hasTime = words.range(of: #"\d|noon|midnight|morning|evening|night|afternoon|tonight"#, options: .regularExpression) != nil
            // "at 5" with no am/pm: people mean the next 5 o'clock that makes sense (5pm, not 5am)
            if hasTime, words.range(of: #"am|pm|morning|:"#, options: .regularExpression) == nil {
                let h = Calendar.current.component(.hour, from: date)
                if h >= 1 && h <= 7 { date = date.addingTimeInterval(12 * 3600) }
            }
            if hasTime, date < now, words.range(of: #"today|tonight"#, options: .regularExpression) == nil {
                date = date.addingTimeInterval(86_400)      // "at 9" when it's already past 9 → tomorrow
            }
            rest.removeSubrange(r)
            return When(date: date, hasTime: hasTime, duration: duration ?? (m.duration > 0 ? m.duration : nil), rest: tidy(rest))
        }
        // bare "at 6" / "at 6:30"
        if let r = rest.range(of: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#, options: [.regularExpression, .caseInsensitive]) {
            let part = String(rest[r]).lowercased()
            let nums = part.split { !$0.isNumber }.compactMap { Int($0) }
            var h = nums.first ?? 9
            let min = nums.count > 1 ? nums[1] : 0
            if part.hasSuffix("pm") && h < 12 { h += 12 } else if !part.hasSuffix("am") && h >= 1 && h <= 7 { h += 12 }
            var d = Calendar.current.date(bySettingHour: h % 24, minute: min, second: 0, of: now) ?? now
            if d < now { d = d.addingTimeInterval(86_400) }
            rest.removeSubrange(r)
            return When(date: d, hasTime: true, duration: duration, rest: tidy(rest))
        }
        return nil
    }

    private static func tidy(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
            .replacingOccurrences(of: #"^(?:on|at|by|for|to)\s+|\s+(?:on|at|by|for|to)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
    }

    var spoken: String {
        let f = DateFormatter()
        let cal = Calendar.current
        f.dateFormat = cal.isDateInToday(date) ? (hasTime ? "'today at' h:mm a" : "'today'")
            : cal.isDateInTomorrow(date) ? (hasTime ? "'tomorrow at' h:mm a" : "'tomorrow'")
            : (hasTime ? "EEE d MMM 'at' h:mm a" : "EEE d MMM")
        return f.string(from: date)
    }
}

/// Apple Reminders and Calendar through EventKit (macOS asks for permission the first time).
enum Organizer {
    static let store = EKEventStore()

    private static func access(_ type: EKEntityType) async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                return type == .event ? try await store.requestFullAccessToEvents() : try await store.requestFullAccessToReminders()
            } catch { return false }
        }
        return (try? await store.requestAccess(to: type)) ?? false
    }

    private static func denied(_ what: String) -> ActionResult {
        .fail("I'm not allowed to use \(what). Turn on Pet Agents in System Settings → Privacy & Security → \(what).")
    }

    // MARK: reminders

    static func addReminder(_ title: String, when: String, list: String) async -> ActionResult {
        guard await access(.reminder) else { return denied("Reminders") }
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = When.parse(when.isEmpty ? name : when)
        if when.isEmpty, let w { name = w.rest }
        guard !name.isEmpty else { return .fail("What should the reminder say?") }
        let r = EKReminder(eventStore: store)
        r.title = name.prefix(1).uppercased() + name.dropFirst()
        r.calendar = calendar(named: list, type: .reminder) ?? store.defaultCalendarForNewReminders()
        if let w {
            let parts: Set<Calendar.Component> = w.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(parts, from: w.date)
            if w.hasTime { r.addAlarm(EKAlarm(absoluteDate: w.date)) }
        }
        do { try store.save(r, commit: true) } catch { return .fail("Couldn't save the reminder: \(error.localizedDescription)") }
        return .ok("Added \"\(r.title ?? name)\" to Reminders" + (w.map { " for \($0.spoken)" } ?? "") + ".")
    }

    static func listReminders(today: Bool) async -> ActionResult {
        guard await access(.reminder) else { return denied("Reminders") }
        let end = today ? Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400) : nil
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let items: [EKReminder] = await withCheckedContinuation { c in store.fetchReminders(matching: pred) { c.resume(returning: $0 ?? []) } }
        if items.isEmpty { return .ok(today ? "Nothing due today." : "No open reminders.") }
        let sorted = items.sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
        let names = sorted.prefix(8).compactMap(\.title)
        return .ok("\(items.count) reminder\(items.count == 1 ? "" : "s"): " + names.joined(separator: ", ") + (items.count > 8 ? "…" : "."))
    }

    // MARK: calendar

    static func addEvent(_ title: String, when: String, minutes: Int?, location: String) async -> ActionResult {
        guard await access(.event) else { return denied("Calendars") }
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let w = When.parse(when.isEmpty ? name : when) ?? (when.isEmpty ? nil : When.parse(name)) else {
            return .fail("When is it? Say something like \"tomorrow at 3pm\".")
        }
        if when.isEmpty { name = w.rest }
        guard !name.isEmpty else { return .fail("What's the event called?") }
        let e = EKEvent(eventStore: store)
        e.title = name.prefix(1).uppercased() + name.dropFirst()
        e.calendar = store.defaultCalendarForNewEvents
        if w.hasTime {
            e.startDate = w.date
            e.endDate = w.date.addingTimeInterval(minutes.map { Double($0) * 60 } ?? w.duration ?? 3600)
        } else {
            e.isAllDay = true
            e.startDate = Calendar.current.startOfDay(for: w.date)
            e.endDate = e.startDate.addingTimeInterval(86_400)
        }
        if !location.isEmpty { e.location = location }
        do { try store.save(e, span: .thisEvent) } catch { return .fail("Couldn't add the event: \(error.localizedDescription)") }
        return .ok("Added \"\(e.title ?? name)\" to your calendar for \(w.spoken).")
    }

    static func listEvents(day: String) async -> ActionResult {
        guard await access(.event) else { return denied("Calendars") }
        let d = day.isEmpty ? Date() : (When.parse(day)?.date ?? Date())
        let start = Calendar.current.startOfDay(for: d)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: start.addingTimeInterval(86_400), calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        let label = Calendar.current.isDateInToday(d) ? "today" : Calendar.current.isDateInTomorrow(d) ? "tomorrow"
            : d.formatted(.dateTime.weekday(.wide).day().month())
        if events.isEmpty { return .ok("Nothing on your calendar \(label).") }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let list = events.prefix(8).map { ($0.isAllDay ? "all day" : f.string(from: $0.startDate)) + " " + ($0.title ?? "event") }
        return .ok("\(events.count) event\(events.count == 1 ? "" : "s") \(label): " + list.joined(separator: ", ") + ".")
    }

    private static func calendar(named name: String, type: EKEntityType) -> EKCalendar? {
        guard !name.isEmpty else { return nil }
        return store.calendars(for: type).first { $0.title.lowercased() == name.lowercased() }
    }
}
