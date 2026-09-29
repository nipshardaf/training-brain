# Training Brain for Apple Watch

Today's gym workout from the Training Brain app on the watch: one set per screen,
the Digital Crown for weight and reps, rest countdowns, a Strength workout with
heart rate saved to Apple Health, and every set sent back to the app as you go
(through intervals.icu, the same way the Garmin app does).

## Install on your Apple Watch (MacBook, one time)

1. Install **Xcode** from the Mac App Store and open it once (it installs extra parts).
2. In **Terminal**:
   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install xcodegen
   git clone https://github.com/nipshardaf/training-brain.git
   cd training-brain/applewatch
   xcodegen
   open TrainingBrain.xcodeproj
   ```
3. In Xcode: **Settings → Accounts → +** and sign in with your Apple ID.
4. Click the **TrainingBrain** project (left) → target **TrainingBrain** → **Signing & Capabilities** →
   **Team**: your name. If the bundle ID is taken, change `nipshardaf` in it to something of yours.
5. Plug your iPhone into the Mac (the watch must be paired with it and nearby).
   On the iPhone *and* the watch turn on **Settings → Privacy & Security → Developer Mode** when asked.
6. At the top of Xcode choose your **Apple Watch Ultra** as the run destination, then press **▶ Run**.
7. On the watch, open **Training Brain**, and enter your intervals.icu API key (your iPhone offers to type it).

With a free Apple ID the app has to be re-installed from Xcode every 7 days. With the
Apple Developer Program ($99/year) it can go on **TestFlight** instead and update itself.

## Updating

```
cd training-brain && git pull && cd applewatch && xcodegen
```
then **▶ Run** again in Xcode.
