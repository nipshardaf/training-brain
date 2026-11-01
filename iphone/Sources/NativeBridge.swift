import UIKit
import UserNotifications
import WebKit

// Phone notifications for the web app. A web page stops running a few seconds after you
// switch to another app, so the page asks the app to schedule one instead. The rest timer
// (web app v3.97) posts to the "tbnative" handler:
//   {op: "alarm", id, secs, title, body}  schedule (replaces an earlier one with the same id)
//   {op: "cancel", id}                    take it back (rest skipped, workout finished)
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
        default:
            break
        }
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
