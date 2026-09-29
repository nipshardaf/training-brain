import Foundation

// intervals.icu is the bridge between the Training Brain app and the watch: the
// app puts each gym day on its calendar (external_id tb-<date>), and the watch
// sends finished sets back as a note (tb-live-<date>-<session>) the app reads.
enum ICUError: Error {
    case unauthorized
    case http(Int)
}

enum KeyStore {
    // The intervals.icu API key, typed in once on the watch.
    static var key: String {
        get { UserDefaults.standard.string(forKey: "icuKey") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "icuKey") }
    }
}

enum ICU {
    static let api = "https://intervals.icu/api/v1"

    static var auth: String {
        "Basic " + Data("API_KEY:\(KeyStore.key)".utf8).base64EncodedString()
    }

    static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (json: Any?, code: Int) {
        guard let url = URL(string: api + path) else { throw ICUError.http(0) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        return (json, code)
    }

    // Today's gym workout from the Training Brain app (the main session first,
    // then an extra one on a ride day).
    static func todayEvent(_ date: String) async throws -> [String: Any]? {
        let r = try await request("/athlete/0/events?oldest=\(date)&newest=\(date)&category=WORKOUT")
        if r.code == 401 || r.code == 403 { throw ICUError.unauthorized }
        guard r.code == 200, let arr = r.json as? [[String: Any]] else { throw ICUError.http(r.code) }
        let tb = arr.filter { (($0["external_id"] as? String) ?? "").hasPrefix("tb-") }
        return tb.first(where: { ($0["external_id"] as? String) == "tb-\(date)" }) ?? tb.first
    }

    static func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
