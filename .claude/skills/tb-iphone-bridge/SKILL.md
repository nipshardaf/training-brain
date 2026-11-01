---
name: tb-iphone-bridge
description: Change the Training Brain iPhone app in iphone/ (a SwiftUI + WKWebView shell around the live site, with native bridges for Bluetooth and for things a web page can't do on iOS) - add a native capability the web app calls, wire the web-side fallback, edit XcodeGen/Info.plist settings, and verify the build on GitHub's Mac since there's no Swift toolchain in the cloud sandbox. Use this whenever a feature needs background alerts, files or the share sheet, Bluetooth, or other iOS-only behaviour, or Hugo asks about the iPhone, SideStore or TrollStore app.
---

# Extending the iPhone app

The app (`iphone/`) loads https://nipshardaf.github.io/training-brain/ in a WKWebView, so web
changes reach it with no app update. Native code is only for what a web page can't do on iOS:
Web Bluetooth (bike and heart-rate strap), notifications while another app is open, saving or
sharing files. Hugo installs unsigned builds through SideStore or TrollStore (he declined the
$99 Apple program and doesn't use Xcode), so a native change means a new build he updates.

## The bridges
- **`tbble`** (`bridge.js` + `BLEBridge.swift`): a Web Bluetooth subset backed by CoreBluetooth.
  `bridge.js` is injected at document start and defines `navigator.bluetooth`.
- **`tbnative`** (`NativeBridge.swift`): one handler, one `op` per capability:
  `alarm` (schedule a local notification: id, secs, title, body), `cancel` (id),
  `share` (name, text: writes a temp file and opens the share sheet).
  The web side calls `_tbNative({op,...})`, which returns false outside the app.

## Adding a capability
1. Swift: add a `case "yourop":` to `NativeBridge.userContentController`. Message bodies arrive
   as `[String: Any]`; read numbers as `NSNumber`. Handlers run on the main thread; use
   `NativeBridge.topController()` to present UI. Keep `SWIFT_VERSION` 5 code style (no strict
   concurrency annotations).
2. Web (`index.html`): `if(_tbNative({op:'yourop',...}))return;` then a fallback for Safari and
   desktop (Web Share API, a download, or just a toast). Old app builds don't know the op, so
   the fallback must keep working. `_hasNative()` tells you if the bridge exists (for wording).
3. Permissions and settings go in `iphone/project.yml` (XcodeGen `info.properties`, e.g. usage
   strings). Free Apple ID builds can't use push notifications or other paid entitlements;
   local notifications, Bluetooth and the share sheet are fine. Background modes need a reason:
   the web page itself is suspended seconds after the app leaves the screen.
4. Test the web side in the browser with a fake bridge (tb-browser-test: `__seed({native:true})`
   captures every message in `window._native`).

## Verifying the build
There's no Swift compiler in the cloud sandbox. Push (tb-ship skill); any change under
`iphone/` triggers `.github/workflows/iphone.yml` on a GitHub Mac: simulator build, a
screenshot to the `iphone-shots` branch, and an unsigned `TrainingBrain.ipa` + SideStore
`apps.json` published as release `iphone-latest` (version 1.0.<run number>). The repo is
public, so watch it without credentials:
```bash
curl -sS "https://api.github.com/repos/nipshardaf/training-brain/actions/workflows/iphone.yml/runs?per_page=1"
# then wait in the background (Bash run_in_background) until the run is completed:
until s=$(curl -sS https://api.github.com/repos/nipshardaf/training-brain/actions/runs/<id> | python3 -c "import sys,json;j=json.load(sys.stdin);print(j['status'],j['conclusion'])") && [ "${s%% *}" = completed ]; do sleep 45; done; echo "$s"
```
On failure, read the errors (the workflow prints them as annotations; the GitHub MCP
`get_job_logs` tool also works). On success, check the release has the new `.ipa`
(`/releases/tags/iphone-latest`) and tell Hugo to update the app in SideStore (or reinstall the
.ipa with TrollStore), and to allow notifications or other permissions when asked.
