# Screenshots every preview screen from the Android emulator.
#
#   flutter run -d emulator-5554 -t lib/preview/main.dart --release
#   pwsh tool/capture_screens.ps1
#
# The harness opens on a plain list of screens (`_Index` in lib/preview/main.dart)
# with fixed-height rows and no header, so row N always sits at a predictable y.
# That is what makes `adb shell input tap` reliable here rather than a guess.
#
# **Screenshots must round-trip through the device's filesystem.** PowerShell's
# `>` re-encodes a native command's stdout as text, so `adb exec-out screencap
# -p > file.png` produces a plausible-looking file that will not decode. Pull it
# instead.

param(
  # Defaults to today, so a review folder is self-dating.
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$Serial = 'emulator-5554',
  [string]$Package = 'com.mgkcodes.fitness.lift'
)

# Must match the order of the `screens` map in lib/preview/main.dart.
$screens = @(
  'track',
  'track-open',
  'plan',
  'plan-entitled',
  'profile',
  'profile-empty',
  'session-empty',
  'session',
  'session-long',
  'settings',
  'credits',
  'coach-mark'
)

# _Index.rowHeight, in logical pixels.
$rowHeight = 72

$out = Join-Path $PSScriptRoot "../screenshots/$Date-lift-review"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Emptied first, so a run that adds or reorders screens leaves one coherent set
# rather than the new numbering laid over the old — which silently keeps a
# stale screen under a name nothing writes any more.
Remove-Item (Join-Path $out '*.png') -ErrorAction SilentlyContinue

# Device pixels per logical pixel, read from the device rather than assumed —
# a different AVD has a different density and every tap would miss.
$density = [int]((adb -s $Serial shell wm density) -replace '.*:\s*', '') / 160

# The status bar the harness's SafeArea pushes the first row below.
$statusBar = [int]((adb -s $Serial shell dumpsys window displays |
  Select-String -Pattern 'cutout=.*top=(\d+)' | ForEach-Object {
    $_.Matches[0].Groups[1].Value
  } | Select-Object -First 1))
if (-not $statusBar) { $statusBar = [int](24 * $density) }

function Get-Screenshot([string]$path) {
  adb -s $Serial shell screencap -p /sdcard/_cap.png
  adb -s $Serial pull /sdcard/_cap.png $path | Out-Null
  adb -s $Serial shell rm /sdcard/_cap.png
}

Write-Host "density=$density statusBar=$statusBar -> $out"

# Restart to reach the index, rather than pressing BACK until we get there:
# BACK on the index pops the last route and **quits the app**, so a run that
# started from a clean launch used to walk out to the home screen and then
# screenshot the launcher ten times.
adb -s $Serial shell am force-stop $Package
adb -s $Serial shell monkey -p $Package -c android.intent.category.LAUNCHER 1 |
  Out-Null
Start-Sleep -Seconds 3

Get-Screenshot (Join-Path $out '00-index.png')

for ($i = 0; $i -lt $screens.Count; $i++) {
  $y = $statusBar + [int](($i * $rowHeight + $rowHeight / 2) * $density)
  $x = [int](200 * $density)

  adb -s $Serial shell input tap $x $y
  Start-Sleep -Milliseconds 900   # entrance animations settle

  $name = '{0:d2}-{1}.png' -f ($i + 1), $screens[$i]
  Get-Screenshot (Join-Path $out $name)
  Write-Host "  $name"

  adb -s $Serial shell input keyevent KEYCODE_BACK
  Start-Sleep -Milliseconds 500
}

Write-Host "done: $out"
