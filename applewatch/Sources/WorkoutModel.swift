import Foundation
import SwiftUI
import WatchKit

enum Phase: Equatable {
    case loading, needsKey, message, ready, set, hold, rest, done
}

enum CrownTarget {
    case reps, weight
}

// Live mode, as in the Garmin app: the plan and what you've done are kept apart.
//  - `entries` is the plan. The phone can change it at any time (a new weight, a
//    swapped exercise, a set ticked on the phone): the watch re-reads the workout
//    every 15 s and rebuilds it whenever the app has changed it.
//  - `results` is every set finished on the watch. Where you are in the plan is
//    worked out from it (recalcPointer), so a rebuilt plan picks up where you are.
//  - After every set, the results go to the app as one note, updated in place.
@MainActor
final class WorkoutModel: ObservableObject {
    @Published var phase: Phase = .loading
    @Published var message = ""
    @Published var workoutName = ""
    @Published var dayLabel = ""
    @Published var entries: [SetEntry] = []
    @Published var results: [DoneSet] = []
    @Published var idx = 0
    @Published var exCount = 0
    @Published var restLeft = 0
    @Published var restTotal = 0
    @Published var holdLeft = 0
    @Published var holdTotal = 0
    @Published var crownTarget: CrownTarget = .reps
    @Published var synced = ""        // "updated from phone" / "offline" / ""
    @Published var sendStatus = ""
    @Published var heartRate: Int? = nil

    let demo = CommandLine.arguments.contains("-demo")  // built-in sample workout, no network
    private var skipped: [String] = []
    private var date = ICU.today()
    private var eventUpdated = ""
    private var sid = ""
    private var noteId: Int? = nil
    private var sending = false
    private var dirty = false
    private var isFinal = false
    private var polling = false
    private var tick = 0
    private var syncedTick = 0
    private var timer: Timer?
    private let health = WorkoutManager()

    init() {
        health.onHeartRate = { [weak self] bpm in
            Task { @MainActor in self?.heartRate = Int(bpm.rounded()) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        Task {
            await load()
            await sendStored()
        }
    }

    // MARK: Loading today's workout

    func load() async {
        date = ICU.today()
        if demo {
            apply(doc: Demo.doc, name: Demo.name, updated: "demo")
            afterLoad()
            return
        }
        if KeyStore.key.isEmpty {
            phase = .needsKey
            return
        }
        phase = .loading
        do {
            guard let ev = try await ICU.todayEvent(date) else {
                message = "No gym workout today.\nGym days come from the Training Brain app."
                phase = .message
                return
            }
            apply(event: ev)
            afterLoad()
        } catch ICUError.unauthorized {
            message = "intervals.icu didn't accept that key."
            phase = .needsKey
        } catch {
            message = "Can't reach intervals.icu.\nCheck your connection."
            phase = .message
        }
    }

    func saveKey(_ key: String) {
        KeyStore.key = key
        message = ""
        Task { await load() }
    }

    private func afterLoad() {
        if entries.isEmpty {
            message = "Today's workout has no sets."
            phase = .message
            return
        }
        idx = 0
        phase = .ready
        // Test screens for the simulator: -demo -demoState set|weight|rest|done
        let args = CommandLine.arguments
        if demo, let i = args.firstIndex(of: "-demoState"), i + 1 < args.count {
            let s = args[i + 1]
            if s != "ready" { begin() }
            if s == "weight" { crownTarget = .weight }
            if s == "rest" { completeSet() }
            if s == "done" { finish(save: true) }
        }
    }

    private func apply(event ev: [String: Any]) {
        apply(doc: (ev["workout_doc"] as? [String: Any]) ?? [:],
              name: (ev["name"] as? String) ?? "Workout",
              updated: (ev["updated"] as? String) ?? "")
    }

    private func apply(doc: [String: Any], name: String, updated: String) {
        workoutName = name
        dayLabel = name.components(separatedBy: ":").first ?? name
        eventUpdated = updated
        entries = PlanParser.entries(from: doc)
        exCount = entries.last?.exNo ?? 0
    }

    var exerciseNames: [String] {
        var seen: [String] = []
        for e in entries where !seen.contains(e.ex) { seen.append(e.ex) }
        return seen
    }

    var setsLeft: Int { entries.filter { $0.side != "right" && !$0.done }.count }

    // MARK: Where am I?

    // The first planned set not already covered by a finished set of the same
    // exercise, not ticked on the phone, and not in a skipped exercise.
    func recalcPointer() {
        var done: [String: Int] = [:]
        for r in results { done[r.ex, default: 0] += 1 }
        for (i, e) in entries.enumerated() {
            if e.done || skipped.contains(e.ex) { continue }
            if let c = done[e.ex], c > 0 {
                done[e.ex] = c - 1
                continue
            }
            idx = i
            return
        }
        idx = entries.count
    }

    var current: SetEntry? { idx < entries.count ? entries[idx] : nil }

    // MARK: Workout flow

    func begin() {
        if !demo {
            Task {
                await health.requestAuth()
                health.start()
            }
        }
        sid = String(Int(Date().timeIntervalSince1970))
        results = []
        skipped = []
        noteId = nil
        isFinal = false
        crownTarget = .reps
        recalcPointer()
        phase = idx < entries.count ? .set : .done
        sendLive() // no sets yet: tells the app a watch session has started
    }

    // Done on a set: timed holds start their countdown, everything else is logged.
    func setDone() {
        guard let e = current else { return }
        if e.timed > 0 {
            holdLeft = e.timed
            holdTotal = e.timed
            phase = .hold
            haptic(.start)
            return
        }
        completeSet()
    }

    func completeSet() {
        guard let e = current else { return }
        var f = ""
        if e.assist { f += "a" }
        if e.bw { f += "b" }
        if e.timed > 0 { f += "t" }
        if e.side == "each" { f += "E" } else if e.side == "left" { f += "L" } else if e.side == "right" { f += "R" }
        results.append(DoneSet(ex: e.ex, w: e.w, u: e.unit, r: e.timed > 0 ? e.timed : e.reps, f: f))
        crownTarget = .reps
        let rest = e.rest
        let prev = e
        recalcPointer()
        sendLive()
        guard let nxt = current else {
            finish(save: true)
            return
        }
        if nxt.ex == prev.ex && nxt.side == "right" && nxt.timed > 0 && rest == 0 {
            // side plank: the right side follows the left with no rest
            holdLeft = nxt.timed
            holdTotal = nxt.timed
            phase = .hold
            haptic(.start)
        } else if rest > 0 {
            restLeft = rest
            restTotal = rest
            phase = .rest
            haptic(.success)
        } else {
            phase = .set
        }
    }

    // End of rest (or Skip): on to the set that is next.
    func toNextSet() {
        crownTarget = .reps
        phase = idx < entries.count ? .set : .done
    }

    // Digital Crown: reps (or weight) on a set, carried to the rest of this
    // exercise's sets; ±15 s during rest.
    func adjust(_ steps: Int) {
        if phase == .rest {
            restLeft = max(5, restLeft + steps * 15)
            restTotal = max(restTotal, restLeft)
            return
        }
        guard phase == .set, let e = current, e.timed == 0 else { return }
        var k = idx
        if crownTarget == .weight && !e.bw {
            let step = e.unit == "kg" ? 2.5 : 5.0
            let nw = max(0, e.w + Double(steps) * step)
            while k < entries.count && entries[k].ex == e.ex {
                entries[k].w = nw
                if entries[k].unit.isEmpty { entries[k].unit = "lb" }
                k += 1
            }
        } else {
            let nr = max(1, e.reps + steps)
            while k < entries.count && entries[k].ex == e.ex {
                entries[k].reps = nr
                k += 1
            }
        }
    }

    func toggleCrown() {
        guard let e = current, !e.bw, e.timed == 0 else { return }
        crownTarget = crownTarget == .weight ? .reps : .weight
    }

    func skipExercise() {
        guard let e = current else { return }
        skipped.append(e.ex)
        recalcPointer()
        if idx >= entries.count {
            finish(save: true)
        } else {
            crownTarget = .reps
            phase = .set
        }
    }

    func finish(save: Bool) {
        if !demo { health.end(save: save) }
        phase = .done
        if save && !results.isEmpty {
            isFinal = true
            sendStatus = "Sending to Training Brain…"
            sendLive()
        } else if !save && noteId != nil {
            // Discarded: take back the live sets the app may already be showing.
            results = []
            isFinal = true
            sendStatus = "Discarded"
            sendLive()
        } else {
            sendStatus = save ? "Nothing logged" : "Discarded"
        }
    }

    // MARK: Every second

    private func onTick() {
        tick += 1
        if synced == "updated from phone" && tick - syncedTick > 6 { synced = "" }
        if (phase == .set || phase == .rest) && tick % 15 == 0 {
            Task { await poll() }
        }
        switch phase {
        case .rest:
            restLeft -= 1
            if restLeft == 10 { haptic(.click) }
            if restLeft <= 0 {
                haptic(.start)
                toNextSet()
            }
        case .hold:
            holdLeft -= 1
            if holdLeft <= 0 {
                haptic(.stop)
                completeSet()
            }
        default:
            break
        }
    }

    // Has the app changed today's plan?
    private func poll() async {
        if demo || polling { return }
        polling = true
        defer { polling = false }
        do {
            guard let ev = try await ICU.todayEvent(date) else { return }
            if synced == "offline" { synced = "" }
            let up = (ev["updated"] as? String) ?? ""
            if up == eventUpdated { return }
            apply(event: ev)
            if phase == .set || phase == .rest {
                recalcPointer()
                if idx >= entries.count {
                    phase = .set // the plan got shorter than what's done — let them finish
                    idx = max(0, entries.count - 1)
                }
                synced = "updated from phone"
                syncedTick = tick
                haptic(.notification)
            }
        } catch {
            synced = "offline"
        }
    }

    // MARK: Sending sets to the app

    private func buildResult() -> String {
        var s = "TB2;\(date);\(sid);\(isFinal ? 1 : 0);\(clean(workoutName))"
        for r in results {
            s += ";\(clean(r.ex))|\(fmtW(r.w))|\(r.u)|\(r.r)|\(r.f)"
        }
        return s
    }

    private func clean(_ s: String) -> String {
        s.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "|", with: "/")
    }

    func fmtW(_ w: Double) -> String {
        w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w)
    }

    private func sendLive() {
        if demo || sid.isEmpty { return }
        if sending {
            dirty = true // send again with the newer sets once this one lands
            return
        }
        dirty = false
        sending = true
        let body: [String: Any] = [
            "category": "NOTE",
            "start_date_local": date + "T00:00:00",
            "name": "Training Brain sets",
            "external_id": "tb-live-\(date)-\(sid)",
            "description": buildResult()
        ]
        let wasFinal = isFinal
        let id = noteId
        Task {
            var ok = false
            do {
                let path = id.map { "/athlete/0/events/\($0)" } ?? "/athlete/0/events"
                let r = try await ICU.request(path, method: id == nil ? "POST" : "PUT", body: body)
                if r.code == 200, let d = r.json as? [String: Any], let newId = (d["id"] as? NSNumber)?.intValue {
                    noteId = newId
                }
                if r.code == 404 { noteId = nil } // the app already tidied it up — start a new one
                ok = r.code == 200
            } catch {}
            sending = false
            synced = ok ? "" : "offline"
            if dirty {
                sendLive()
                return
            }
            if wasFinal {
                if ok {
                    sendStatus = results.isEmpty ? "Discarded" : "Sent to Training Brain"
                    UserDefaults.standard.removeObject(forKey: "pendingFinal")
                } else {
                    UserDefaults.standard.set(body, forKey: "pendingFinal")
                    sendStatus = "Saved — sends when you're back online"
                }
            }
        }
    }

    // A finished workout that couldn't be sent (no signal) goes at the next launch.
    private func sendStored() async {
        guard !demo, !KeyStore.key.isEmpty,
              let body = UserDefaults.standard.dictionary(forKey: "pendingFinal") else { return }
        if let r = try? await ICU.request("/athlete/0/events", method: "POST", body: body), r.code == 200 {
            UserDefaults.standard.removeObject(forKey: "pendingFinal")
        }
    }

    // MARK: Display helpers

    func loadText(_ e: SetEntry) -> String {
        if e.bw { return "Bodyweight" }
        if e.w > 0 || crownTarget == .weight {
            return (e.assist ? "Assist " : "") + fmtW(e.w) + " " + (e.unit.isEmpty ? "lb" : e.unit)
        }
        return ""
    }

    func repsText(_ e: SetEntry) -> String {
        var s = e.timed > 0 ? "\(e.timed) s hold" : (e.reps > 0 ? "× \(e.reps) reps" : "")
        if e.side == "each" { s += " each side" } else if !e.side.isEmpty { s += " \(e.side)" }
        return s
    }

    private func haptic(_ t: WKHapticType) {
        if !demo { WKInterfaceDevice.current().play(t) }
    }
}
