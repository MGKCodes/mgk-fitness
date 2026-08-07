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
#
# **Keep this file UTF-8 with a BOM, and keep string literals ASCII.** Windows
# PowerShell 5.1 decodes a BOM-less .ps1 as CP1252, where the last byte of a
# UTF-8 em dash (0x94) becomes a curly closing quote — which PowerShell honours
# as a string terminator. One em dash inside a quoted string turned the rest of
# the file into a parse error. In comments it is merely mojibake; in strings it
# is fatal.

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
  'session-resting',
  'settings',
  'credits',
  'coach-mark'
)

# _Index.rowHeight, in logical pixels. **Mirrored from lib/preview/main.dart.**
$rowHeight = 56

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

# Relaunches the app and waits until it is actually the foreground activity.
#
# **Not a fixed sleep.** A cold start of a 60 MB release build takes longer than
# you would guess on an emulator under load, and a tap that lands before the
# index has drawn does nothing — after which BACK quits the app and every
# remaining screenshot is of the launcher. That failure is silent: the files are
# all present and all the wrong size.
function Reset-ToIndex {
  adb -s $Serial shell am force-stop $Package
  adb -s $Serial shell monkey -p $Package -c android.intent.category.LAUNCHER 1 |
    Out-Null

  for ($wait = 0; $wait -lt 40; $wait++) {
    Start-Sleep -Milliseconds 250
    $top = adb -s $Serial shell dumpsys activity activities |
      Select-String -Pattern 'topResumedActivity.*' |
      Select-Object -First 1
    if ($top -and "$top".Contains($Package)) {
      # **The Android activity resumes before Flutter draws.** topResumedActivity
      # names the package as soon as the activity is up, which is a second or
      # more before the engine has built a widget tree — and a tap landing in
      # that window hits nothing at all. Waiting on the activity alone is what
      # made every capture in a run come back as the index.
      Start-Sleep -Milliseconds 2500
      return $true
    }
  }
  Write-Warning "  app did not come to the foreground"
  return $false
}

Write-Host "density=$density statusBar=$statusBar rowHeight=$rowHeight -> $out"

$indexPath = Join-Path $out '00-index.png'
Reset-ToIndex | Out-Null
Get-Screenshot $indexPath

# Every screen is captured from the same starting point, so a capture that still
# looks like the index means the tap did not land. Comparing byte length is
# crude, but the index is a plain dark list and every real screen has a photo or
# a card in it, so the sizes are not close.
$indexSize = (Get-Item $indexPath).Length

function Test-LooksLikeIndex([string]$path) {
  $size = (Get-Item $path).Length
  return [Math]::Abs($size - $indexSize) -lt ($indexSize * 0.15)
}

for ($i = 0; $i -lt $screens.Count; $i++) {
  # Relaunch for every screen rather than pressing BACK to return.
  #
  # BACK on the index pops the last route and QUITS the app, so the old
  # tap/capture/BACK loop only worked while every single tap landed. One miss
  # and the app was gone, with the rest of the run quietly photographing the
  # home screen. Relaunching costs a couple of seconds per screen and makes each
  # capture independent of the one before it.
  if (-not (Reset-ToIndex)) { continue }

  $y = $statusBar + [int](($i * $rowHeight + $rowHeight / 2) * $density)
  $x = [int](200 * $density)

  adb -s $Serial shell input tap $x $y
  Start-Sleep -Milliseconds 900   # entrance animations settle

  $name = '{0:d2}-{1}.png' -f ($i + 1), $screens[$i]
  $path = Join-Path $out $name
  Get-Screenshot $path

  # One retry, in place, before giving up on the screen. A missed tap is almost
  # always the app still warming up, and tapping again a second later fixes it.
  if (Test-LooksLikeIndex $path) {
    Start-Sleep -Milliseconds 1500
    adb -s $Serial shell input tap $x $y
    Start-Sleep -Milliseconds 1200
    Get-Screenshot $path
  }

  # Verified rather than assumed. Both failure modes look fine from the outside:
  # a missed tap leaves the index under a screen's name, and a quit app leaves
  # the launcher. Both produce a file of exactly the right name and neither is
  # visible without opening it.
  $kb = [int]((Get-Item $path).Length / 1KB)
  if ($kb -gt 700) {
    Write-Warning "  $name is ${kb}KB, probably the launcher rather than the app"
  } elseif (Test-LooksLikeIndex $path) {
    Write-Warning "  $name still looks like the index, the tap did not land"
  } else {
    Write-Host "  $name"
  }
}

Write-Host "done: $out"
