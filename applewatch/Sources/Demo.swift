import Foundation

// A sample workout for the simulator (launch argument -demo), in the same shape
// intervals.icu returns. The first Bench Press set is marked as ticked on the phone.
enum Demo {
    static let name = "Push: Bench Press, OHP, Incline DB Press, Lat Raise, Plank"

    static let json = """
    {"steps":[
      {"text":"Bench Press 135lb x8 done","duration":1,"until_lap_press":true},
      {"text":"Rest","duration":120},
      {"text":"Bench Press 3x","reps":3,"steps":[
        {"text":"Bench Press 135lb x8","duration":1,"until_lap_press":true},
        {"text":"Rest","duration":120}]},
      {"text":"Overhead Press 3x","reps":3,"steps":[
        {"text":"Overhead Press 85lb x8-10","duration":1,"until_lap_press":true},
        {"text":"Rest","duration":90}]},
      {"text":"Incline DB Press 3x","reps":3,"steps":[
        {"text":"Incline DB Press 45lb x10","duration":1,"until_lap_press":true},
        {"text":"Rest","duration":75}]},
      {"text":"Plank","duration":45},
      {"text":"Rest","duration":45}
    ]}
    """

    static var doc: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }
}
