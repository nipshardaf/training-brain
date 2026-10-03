import SwiftUI
import WebKit

// Training Brain for iPhone: the live web app (so every update arrives as usual)
// plus native Bluetooth for the bike and heart-rate strap (BLEBridge + bridge.js).

let appURL = URL(string: "https://nipshardaf.github.io/training-brain/")!

@main
struct TrainingBrainPhoneApp: App {
    @StateObject private var ble = BLEBridge()

    var body: some Scene {
        WindowGroup {
            WebView(ble: ble)
                .ignoresSafeArea() // the page handles the notch and home bar itself (viewport-fit=cover)
                .background(Color(red: 9 / 255, green: 9 / 255, blue: 15 / 255).ignoresSafeArea())
                .sheet(item: $ble.picker, onDismiss: { ble.cancelPick() }) { _ in DevicePicker(ble: ble) }
        }
    }
}

struct DevicePicker: View {
    @ObservedObject var ble: BLEBridge

    var body: some View {
        NavigationView {
            List {
                if ble.found.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking for devices… pedal the bike to wake it up.").foregroundColor(.secondary)
                    }
                }
                ForEach(ble.found) { d in
                    Button { ble.choose(d.id) } label: {
                        HStack {
                            Text(d.name)
                            Spacer()
                            if d.rssi != 0 { Text("\(d.rssi) dBm").font(.caption).foregroundColor(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle("Choose a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { ble.cancelPick() } } }
        }
    }
}

struct WebView: UIViewRepresentable {
    let ble: BLEBridge

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // Looks like Safari to sites that refuse in-app browsers (Google sign-in).
        cfg.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1 TrainingBrainApp/1"
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        if let url = Bundle.main.url(forResource: "bridge", withExtension: "js"), let src = try? String(contentsOf: url) {
            cfg.userContentController.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        cfg.userContentController.add(ble, name: "tbble")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.isOpaque = false
        wv.backgroundColor = .clear
        if #available(iOS 16.4, *) { wv.isInspectable = true } // Safari → Develop, for debugging
        ble.webView = wv
        context.coordinator.main = wv
        wv.load(URLRequest(url: appURL))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var main: WKWebView?
        private var popup: UIViewController?

        // No connection when opening: a simple retry page instead of a blank screen.
        func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
            guard wv === main else { return }
            wv.loadHTMLString("""
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
            <body style="background:#09090f;color:#eee;font:17px -apple-system;text-align:center;padding:30vh 24px 0">
            <p>Training Brain couldn't load — check your Wi-Fi.</p>
            <button style="font-size:17px;padding:12px 26px;border-radius:12px;border:0;background:#7c3aed;color:#fff"
             onclick="location.href='\(appURL.absoluteString)'">Try again</button></body></html>
            """, baseURL: nil)
        }

        // Links that open a new window: Google/Firebase sign-in stays in the app (as a
        // sheet, so the page gets the result); anything else opens in Safari.
        func webView(_ wv: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let host = action.request.url?.host ?? ""
            let signIn = host.isEmpty || host.hasSuffix("firebaseapp.com") || host.hasSuffix("google.com")
                || host.hasSuffix("googleapis.com") || host.hasSuffix("web.app")
            if !signIn, let url = action.request.url {
                UIApplication.shared.open(url)
                return nil
            }
            let child = WKWebView(frame: .zero, configuration: cfg)
            child.uiDelegate = self
            child.navigationDelegate = self
            let vc = UIViewController()
            vc.view = child
            popup = vc
            topController()?.present(vc, animated: true)
            return child
        }

        func webViewDidClose(_ wv: WKWebView) {
            if wv !== main { popup?.dismiss(animated: true); popup = nil }
        }

        // alert(), confirm() and prompt() — the web app uses them (e.g. "discard this ride?").
        func webView(_ wv: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(a, orElse: completionHandler)
        }

        func webView(_ wv: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(a) { completionHandler(false) }
        }

        func webView(_ wv: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            present(a) { completionHandler(nil) }
        }

        private func present(_ vc: UIViewController, orElse fallback: @escaping () -> Void) {
            if let top = topController() { top.present(vc, animated: true) } else { fallback() }
        }

        private func topController() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            while let next = top?.presentedViewController { top = next }
            return top
        }
    }
}
