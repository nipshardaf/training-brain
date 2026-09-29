import SwiftUI

private let accent = Color(red: 0.49, green: 0.36, blue: 1.0)

struct ContentView: View {
    @EnvironmentObject var m: WorkoutModel

    var body: some View {
        NavigationStack {
            switch m.phase {
            case .loading: ProgressView("Loading…")
            case .needsKey: KeyView()
            case .message: MessageView()
            case .ready: ReadyView()
            case .set: SetView()
            case .hold: CountdownView(label: "HOLD", left: m.holdLeft, total: m.holdTotal, isRest: false)
            case .rest: CountdownView(label: "REST", left: m.restLeft, total: m.restTotal, isRest: true)
            case .done: DoneView()
            }
        }
    }
}

// One-time setup: the intervals.icu API key. When the keyboard opens, the paired
// iPhone offers to type it — so it can be pasted there.
struct KeyView: View {
    @EnvironmentObject var m: WorkoutModel
    @State private var key = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("intervals.icu key").font(.headline)
                Text(m.message.isEmpty
                     ? "On intervals.icu: Settings → Developer Settings → API key. You can type or paste it on your iPhone."
                     : m.message)
                    .font(.footnote)
                    .foregroundStyle(m.message.isEmpty ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.center)
                TextField("API key", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save") { m.saveKey(key) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

struct MessageView: View {
    @EnvironmentObject var m: WorkoutModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(m.message).multilineTextAlignment(.center)
                Button("Try again") { Task { await m.load() } }
            }
        }
    }
}

struct ReadyView: View {
    @EnvironmentObject var m: WorkoutModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(m.dayLabel).font(.title3.bold()).foregroundStyle(accent)
                Text("\(m.exCount) exercises · \(m.setsLeft) sets")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    m.begin()
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                ForEach(m.exerciseNames, id: \.self) { n in
                    Text(n).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await m.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

struct SetView: View {
    @EnvironmentObject var m: WorkoutModel
    @State private var crown = 0.0
    @State private var menu = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 3) {
            if let e = m.current {
                Text(e.ex)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                let load = m.loadText(e)
                if !load.isEmpty {
                    Text(load)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(m.crownTarget == .weight ? accent : Color.primary)
                        .onTapGesture { m.toggleCrown() }
                }
                Text(m.repsText(e))
                    .font(.title3)
                    .foregroundStyle(m.crownTarget == .weight ? Color.secondary : Color.primary)
                    .onTapGesture { m.crownTarget = .reps }
                Text("Set \(e.setNo) of \(e.setOf)").font(.footnote).foregroundStyle(accent)
                Button {
                    m.setDone()
                } label: {
                    Text(e.timed > 0 ? "Start hold" : "Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(hintColor)
            }
        }
        .focusable()
        .focused($focused)
        .digitalCrownRotation($crown, from: -100000, through: 100000, by: 1,
                              sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in
            let d = Int((new - old).rounded())
            if d != 0 { m.adjust(d) }
        }
        .onAppear { focused = true }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    menu = true
                } label: {
                    Image(systemName: "pause.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text(header).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Workout", isPresented: $menu) {
            Button("Skip exercise") { m.skipExercise() }
            Button("Finish & save") { m.finish(save: true) }
            Button("Discard", role: .destructive) { m.finish(save: false) }
            Button("Resume", role: .cancel) {}
        }
    }

    private var header: String {
        guard let e = m.current else { return "" }
        var s = "\(e.exNo)/\(m.exCount)"
        if let hr = m.heartRate { s += " ♥\(hr)" }
        return s
    }

    private var hint: String {
        if !m.synced.isEmpty { return m.synced }
        return m.crownTarget == .weight ? "Crown: weight · tap reps to switch" : "Crown: reps · tap weight to switch"
    }

    private var hintColor: Color {
        if m.synced == "updated from phone" { return .green }
        return m.synced.isEmpty ? .secondary : .orange
    }
}

struct CountdownView: View {
    @EnvironmentObject var m: WorkoutModel
    let label: String
    let left: Int
    let total: Int
    let isRest: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.3), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: total > 0 ? CGFloat(max(0, left)) / CGFloat(total) : 0)
                    .stroke(isRest ? accent : Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                VStack(spacing: 0) {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    Text(timeText(left))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(height: 92)
            if isRest, let n = m.current {
                Text("NEXT: \(n.ex)").font(.footnote).lineLimit(1).minimumScaleFactor(0.7)
                Text([m.loadText(n), m.repsText(n)].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Button("+15s") { m.adjust(1) }
                    Button("Skip") { m.toNextSet() }.tint(accent)
                }
            } else if let n = m.current {
                Text(n.ex).font(.footnote).lineLimit(1)
            }
        }
    }

    private func timeText(_ s: Int) -> String {
        let v = max(0, s)
        return v >= 60 ? String(format: "%d:%02d", v / 60, v % 60) : "\(v)"
    }
}

struct DoneView: View {
    @EnvironmentObject var m: WorkoutModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Workout done").font(.headline)
                Text("\(m.results.count) sets").foregroundStyle(.secondary)
                Text(m.sendStatus).font(.footnote).multilineTextAlignment(.center)
                Button("Back to today") { Task { await m.load() } }
            }
        }
    }
}
