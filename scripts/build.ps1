# Naija Street Life build script (Windows). Decision D-005: Android-only, Godot 4.6.3.
#   .\scripts\build.ps1            # import, tests, debug APK
#   .\scripts\build.ps1 -Target test
param([ValidateSet('test','android')][string]$Target = 'android')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root '.tools\godot\Godot_v4.6.3-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $godot)) { throw 'Portable Godot missing in .tools\godot (see docs/BUILD.md).' }
$game = Join-Path $root 'game'
& $godot --headless --path $game --import | Out-Null
$log = & $godot --headless --path $game --script res://tests/run_tests.gd 2>&1 | Out-String
Write-Output $log
if ($LASTEXITCODE -ne 0 -or $log -match 'SCRIPT ERROR') { throw 'Unit tests failed.' }
if ($Target -eq 'test') { exit 0 }
New-Item -ItemType Directory -Path (Join-Path $root 'build') -Force | Out-Null
& $godot --headless --path $game --export-debug Android (Join-Path $root 'build\naija-street-life-debug.apk')
if ($LASTEXITCODE -ne 0) { throw 'Android export failed. See docs/BUILD.md for SDK/JDK setup.' }
Write-Output "APK: build\naija-street-life-debug.apk"
