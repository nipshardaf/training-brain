# Training Brain for iPhone

The Training Brain web app in a small native app that adds **Bluetooth** — the
Renpho bike and a heart-rate strap — which Safari can't do. It replaces Bluefy.

- It opens the live app (`nipshardaf.github.io/training-brain`), so every update
  still arrives on its own; the installed app rarely needs updating.
- Ride mode's **Connect** buttons show a native device list. A device you picked
  before is taken automatically next time.
- The screen stays on while the bike or strap is connected.
- Sign in inside the app (username + password, same account as your other phone).

GitHub builds a ready-to-install **TrainingBrain.ipa** after every change:
<https://github.com/nipshardaf/training-brain/releases/tag/iphone-latest>

## Install without Xcode

First check the iPhone's version: **Settings → General → About → iOS Version**.

### iOS 14.0 – 16.6.1 or 17.0 → TrollStore (permanent, never expires)

TrollStore installs apps for good using a bug Apple fixed in later versions — no
certificate, no weekly renewal.

1. Install TrollStore with the guide at **ios.cfw.guide/installing-trollstore** (pick
   your iOS version; it takes about 10 minutes and doesn't erase anything).
2. On the iPhone, open the release page above in Safari, download **TrainingBrain.ipa**,
   tap **Share → TrollStore → Install**.
3. Open **Training Brain**, allow Bluetooth, sign in.

To update the installed app later: download the new .ipa and install it the same way.

### Any other iOS version → SideStore (free, renews itself)

SideStore signs the app with your free Apple ID and renews it over Wi-Fi, so after
a one-time set-up with your PC you never plug in again.

1. Set up SideStore with the guide at **docs.sidestore.io** (needs your PC once).
2. In SideStore: **Sources → +** and add
   `https://github.com/nipshardaf/training-brain/releases/download/iphone-latest/apps.json`
   then install **Training Brain** from it (updates show up there too).
3. Open **Training Brain**, allow Bluetooth, sign in.

A free Apple ID's apps last 7 days; SideStore renews them when you open it (or
automatically with an iOS Shortcuts automation — its docs show how).

### With Xcode (fallback)

```
cd training-brain && git pull && cd iphone && xcodegen && open TrainingBrainPhone.xcodeproj
```
Set **Signing & Capabilities → Team** to your Apple ID, plug in the iPhone, press **▶ Run**.
