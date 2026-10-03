# Training Brain for iPhone

The Training Brain web app in a small native app that adds **Bluetooth** — the
Renpho bike and a heart-rate strap — which Safari can't do. It replaces Bluefy.

- It opens the live app (`nipshardaf.github.io/training-brain`), so every update
  still arrives on its own; this native shell rarely needs reinstalling for features.
- Ride mode's **Connect** buttons show a native device list. A device you picked
  before is taken automatically next time.
- The screen stays on while the bike or strap is connected.
- Sign in inside the app (same account as your other phone) so rides and changes sync.

## Install (MacBook, free Apple ID)

1. You need **Xcode** and **xcodegen** — the same set-up as the Apple Watch app
   (see `../applewatch/README.md`, steps 1–3).
2. In **Terminal**:
   ```
   cd training-brain && git pull
   cd iphone && xcodegen && open TrainingBrainPhone.xcodeproj
   ```
3. In Xcode: click **TrainingBrainPhone** (left) → target **TrainingBrainPhone** →
   **Signing & Capabilities** → **Team**: your name (Personal Team). If the bundle ID
   is taken, change `nipshardaf` in it to something of yours.
4. Plug the iPhone into the Mac, unlock it and tap **Trust**. On the iPhone turn on
   **Settings → Privacy & Security → Developer Mode** when asked (it restarts).
5. At the top of Xcode pick the iPhone as the run destination and press **▶ Run**.
6. First launch only: on the iPhone, **Settings → General → VPN & Device Management**
   → your Apple ID → **Trust**. Then open **Training Brain** and allow Bluetooth.

### Every 7 days

A free Apple ID signs apps for 7 days. When it stops opening, plug in and press
**▶ Run** again (your data stays — it's in your account). To skip that, **SideStore**
(free, sidestore.io) can re-sign it over Wi-Fi each week.

## Updating the native part

```
cd training-brain && git pull && cd iphone && xcodegen
```
then **▶ Run**. Only needed when this folder changes — web app updates arrive by themselves.
