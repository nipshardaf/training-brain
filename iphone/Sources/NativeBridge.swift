import UIKit
import UserNotifications
import WebKit

// Phone notifications for the web app. A web page stops running a few seconds after you
// switch to another app, so the page asks the app to schedule one instead. The rest timer
// (web app v3.97) posts to the "tbnative" handler:
//   {op: "alarm", id, secs, title, body}  schedule (replaces an earlier one with the same id)
//   {op: "cancel", id}                    take it back (rest skipped, workout finished)
//   {op: "share", name, text}             open the share sheet with that text as a file (v3.98 backup)
// The first alarm asks for permission. While the app is open the page shows and beeps the
// timer itself, so no banner is shown on top of it.
final class NativeBridge: NSObject, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    static let shared = NativeBridge()
    private let center = UNUserNotificationCenter.current()

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let op = m["op"] as? String else { return }
        let id = (m["id"] as? String) ?? "tb"
        switch op {
        case "alarm":
            let secs = max(1, (m["secs"] as? NSNumber)?.doubleValue ?? 60)
            let title = (m["title"] as? String) ?? "Training Brain"
            let body = (m["body"] as? String) ?? ""
            let center = self.center
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                center.removePendingNotificationRequests(withIdentifiers: [id])
                center.removeDeliveredNotifications(withIdentifiers: [id])
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: secs, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        case "cancel":
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
        case "share":
            // A file from the page (the full backup): the web view can't save downloads, so
            // write it to a temporary file and open the share sheet (Save to Files, AirDrop…).
            let raw = (m["name"] as? String) ?? "training-brain.json"
            let name = String(raw.filter { $0.isLetter || $0.isNumber || "._-".contains($0) }.prefix(80))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name.isEmpty ? "training-brain.json" : name)
            guard let data = ((m["text"] as? String) ?? "").data(using: .utf8), (try? data.write(to: url, options: .atomic)) != nil,
                  let top = NativeBridge.topController() else { return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = top.view
            top.present(sheet, animated: true)
        default:
            break
        }
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    // The app is open: the page already shows the timer, so no banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    // Tapping the notification just opens the app, where the timer bar is waiting.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
