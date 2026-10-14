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

## Size notes
- The debug APK is about 56 MB because it carries both ARM architectures and the debug engine.
- A Play Store release uses an Android App Bundle, so each phone downloads one
  architecture and the release engine. Expect roughly 25–30 MB before art.
