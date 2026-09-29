import Foundation

// One planned set. Built from the steps of the workout the Training Brain app puts
// on the intervals.icu calendar, e.g. the step "Bench Press 135lb x8" inside the
// repeat "Bench Press 4x". Same format the Garmin watch app reads.
struct SetEntry: Equatable {
    var ex = ""
    var w = 0.0          // 0 = no weight given
    var unit = ""        // "lb" or "kg"
    var assist = false
    var bw = false
    var reps = 0         // target reps; 0 when timed or unknown
    var timed = 0        // seconds, for holds like plank
    var side = ""        // "", "each", "left", "right"
    var rest = 0         // seconds after this set
    var setNo = 1
    var setOf = 1
    var exNo = 1
    var done = false     // already ticked on the phone ("done" in the step text)
}

// A set finished on the watch, as sent back to the app.
struct DoneSet {
    var ex: String
    var w: Double
    var u: String
    var r: Int
    var f: String        // flags: a assisted, b bodyweight, t timed, E each side, L/R side
}

enum PlanParser {
    static func entries(from doc: [String: Any]) -> [SetEntry] {
        var out: [SetEntry] = []
        guard let steps = doc["steps"] as? [[String: Any]] else { return out }
        for item in steps {
            if let inner = item["steps"] as? [[String: Any]] {
                let times = max(1, num(item["reps"]))
                let block = stripRepeat((item["text"] as? String) ?? "")
                for _ in 0..<times {
                    for st in inner { addStep(st, block: block, into: &out) }
                }
            } else {
                addStep(item, block: "", into: &out)
            }
        }
        number(&out)
        return out
    }

    static func num(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    static func addStep(_ st: [String: Any], block: String, into out: inout [SetEntry]) {
        let text = (st["text"] as? String) ?? ""
        let secs = num(st["duration"])
        if text == "Rest" {
            if !out.isEmpty { out[out.count - 1].rest = secs }
            return
        }
        var e = parseText(text)
        if !block.isEmpty { e.ex = block }
        let lap = (st["until_lap_press"] as? Bool) ?? false
        if !lap && secs > 1 { e.timed = secs }
        out.append(e)
    }

    // "Bench Press 4x" → "Bench Press"
    static func stripRepeat(_ s: String) -> String {
        var words = s.split(separator: " ").map(String.init)
        if let last = words.last, last.count > 1, last.hasSuffix("x"), last.first?.isNumber == true {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    static func parseText(_ text: String) -> SetEntry {
        var e = SetEntry()
        let words = text.split(separator: " ").map(String.init)
        var i = 0
        while i < words.count && !isAttr(words[i]) { i += 1 }
        e.ex = words[0..<i].joined(separator: " ")
        while i < words.count {
            let w = words[i]
            if let wt = weight(w) {
                e.w = wt.value
                e.unit = wt.unit
            } else if w == "bodyweight" {
                e.bw = true
            } else if w == "assist" {
                e.assist = true
            } else if isReps(w) {
                e.reps = repsFrom(String(w.dropFirst()))
            } else if w == "done" {
                e.done = true
            } else if w == "each" {
                e.side = "each"
            } else if w == "left" || w == "right" {
                e.side = w
            }
            i += 1
        }
        return e
    }

    static func weight(_ w: String) -> (value: Double, unit: String)? {
        for u in ["lb", "kg"] where w.hasSuffix(u) && w.count > 2 {
            if let v = Double(w.dropLast(2)) { return (v, u) }
        }
        return nil
    }

    static func isReps(_ w: String) -> Bool {
        w.count > 1 && w.first == "x" && w.dropFirst().first?.isNumber == true
    }

    static func isAttr(_ w: String) -> Bool {
        weight(w) != nil || isReps(w) || ["bodyweight", "assist", "each", "left", "right", "done"].contains(w)
    }

    // "8" → 8, "6-8" → 8 (aim for the top of the range), "10-sec" → 10
    static func repsFrom(_ s: String) -> Int {
        let nums = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = nums.first else { return 0 }
        if s.contains("sec") || s.contains("min") { return first }
        return nums.count >= 2 ? nums[1] : first
    }

    // Set and exercise numbers, per run of the same exercise. A left/right pair
    // counts as one set.
    static func number(_ es: inout [SetEntry]) {
        var exCount = 0
        var i = 0
        while i < es.count {
            var j = i
            while j + 1 < es.count && es[j + 1].ex == es[i].ex { j += 1 }
            exCount += 1
            let total = (i...j).filter { es[$0].side != "right" }.count
            var n = 0
            for k in i...j {
                if es[k].side != "right" { n += 1 }
                es[k].setNo = max(1, n)
                es[k].setOf = total
                es[k].exNo = exCount
            }
            i = j + 1
        }
    }
}
