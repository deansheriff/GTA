# Building Naija Street Life (Android, Godot 4.6.3)

## Toolchain (this PC)
- **Godot 4.6.3:** a portable copy lives in `.tools/godot/`. It's git-ignored and
  self-contained (has a `_sc_` file) with its own `editor_data/` holding the Android
  templates and SDK/JDK paths.
- **Android SDK:** `%LOCALAPPDATA%\Android\Sdk` (build-tools 36.1, platform 36).
- **JDK 17:** `C:\Program Files\Java\jdk-17`.
- **Debug keystore:** `.tools/debug.keystore` (debug only; a release key is made before Play upload).

## Commands
```powershell
.\scripts\build.ps1 -Target test   # import + unit tests
.\scripts\build.ps1                # + debug APK at build\naija-street-life-debug.apk
```
Open the project in the editor with `.tools\godot\Godot_v4.6.3-stable_win64.exe --path game -e`.

## Demo and screenshots (used for automated visual checks)
```powershell
.tools\godot\Godot_v4.6.3-stable_win64_console.exe --path game -- --demo --shots=C:/tmp/shots --preset=medium
```
The demo:
1. Walks to the danfo and drives it.
2. Switches to night, cuts NEPA, then restores it.
3. Prints frame rates and saves PNGs.

## Install on a phone
1. Enable *Install unknown apps* for your file manager or browser.
2. Copy `build/naija-street-life-debug.apk` to the phone and open it.
3. With USB debugging on, you can install from this PC instead:
   ```powershell
   adb install -r build\naija-street-life-debug.apk
   ```

## Release build (Google Play) 🔒
Play needs an **Android App Bundle (AAB)** signed with your **upload key**. Only you should
hold that key. Lose it and you can't update the app, so keep a backup somewhere safe.
1. Create the key once, on your PC. Choose your own strong passwords; never commit or share them:
   ```powershell
   & "C:\Program Files\Java\jdk-17\bin\keytool.exe" -genkeypair -v -keystore $HOME\naija-upload.jks -alias naija -keyalg RSA -keysize 4096 -validity 10000
   ```
2. Install the Gradle build template once:
   ```powershell
   .tools\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path game --install-android-build-template
   ```
3. Export, with the key passed through environment variables (Godot reads these; nothing goes
   into the repo):
   ```powershell
   $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = "$HOME\naija-upload.jks"
   $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "naija"
   $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "<your password>"
   .tools\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path game --export-release "Android Release (AAB)" build\naija-street-life-release.aab
   ```
4. In Play Console:
   - Use **Play App Signing**.
   - Upload the AAB.
   - Fill in the Data safety and content rating answers from `docs/legal/`.
   - Use the listing kit in `docs/store/`.

The release preset targets SDK 35 (min 24), arm64 + armv7, version 1.0.0 (code 100).
Bump `version/code` in `game/export_presets.cfg` for every upload.

## Size notes
- The debug APK is about 56 MB because it carries both ARM architectures and the debug engine.
- A Play Store release uses an Android App Bundle, so each phone downloads one architecture
  and the release engine.
- The painted panels, interiors and portraits are imported as lossy WebP (quality 0.82). That
  cut the imported assets from 44 MB to 16 MB.
- Audio is 2.4 MB of synthesised WAVs.
