# Before anything goes out (a push to a public repository, a release APK): what would be published, checked for what
# must not be (docs/DELIVERY.md "Releasing"). Exit code 1 on any FAIL.
#   powershell -ExecutionPolicy Bypass -File tools\publish-check.ps1 [-Apk <release.apk>] [-NoHistory]
# Checks the tracked files (git ls-files): the GPL-3.0 LICENSE; no BAR artwork (images other than the allowed ones);
# no private data (the terms in ..\worklog-redact.txt, the phone in ..\phone-device.txt, home-network addresses, a
# user profile path, e-mail addresses other than the allowed ones); no keys, keystores or login files; no file over
# 50 MB; a CHANGELOG.md entry for the version in gradle.properties. With -Apk: the APK has the project's own icon and
# is not signed with the public debug key. History: old commits that still hold the owner's icon or private terms
# (the fresh-history question in docs/DELIVERY.md); -NoHistory skips it. -SelfTest: the private-data patterns run
# through git grep over planted data (tools\laptop-tests.ps1).
param([string]$Apk = "", [switch]$NoHistory, [switch]$SelfTest)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$git = Join-Path $TC "git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = "git" }

# Private data in the tracked files of the repository in the current folder: "file: what" for each file holding some.
# git grep -E is POSIX ERE (no \d: it once matched a literal "d" and hid every address); each match is then checked
# on its own against what is allowed, so an allowed address on the same line hides nothing.
$patterns = @{
  'a home-network address' = '\b(192\.168|10\.[0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}\b'
  'a user profile path'    = '[A-Za-z]:\\\\?Users\\\\?[A-Za-z0-9._-]+'
  'an e-mail address'      = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
}
$allowedMail = 'noreply@|@example\.|@users\.noreply\.github\.com|@gnu\.org|@fsf\.org'
$allowed = @{
  'a home-network address' = '^10\.0\.2\.'   # the Android emulator's own network (10.0.2.2 is the host)
  'a user profile path'    = '(?!)'
  'an e-mail address'      = $allowedMail
}
function Find-PrivateData([string[]]$terms) {
  $hits = @()
  foreach ($t in $terms) {
    $hits += @(& $git grep -n -I -i -F -e $t -- . 2>$null | ForEach-Object { ($_ -split ':')[0] + ": a private term" })
  }
  foreach ($name in $patterns.Keys) {
    $hits += @(& $git grep -n -I -E -e $patterns[$name] -- . ':!termux-x11' 2>$null | Where-Object {
        @([regex]::Matches($_, $patterns[$name]) | Where-Object { $_.Value -notmatch $allowed[$name] }).Count -gt 0 } |
      ForEach-Object { ($_ -split ':')[0] + ": $name" })
  }
  return @($hits | Sort-Object -Unique)
}

if ($SelfTest) {
  # planted in a throwaway repository under build\; the values are made up and pieced together so that this file
  # holds none of them
  $ErrorActionPreference = "Continue"
  $dir = Join-Path $App "build\publish-check-selftest"
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  New-Item -ItemType Directory $dir | Out-Null
  Push-Location $dir
  try {
    & $git init -q . 2>$null
    $plant = @{
      'address.txt'   = "adb connect 192.168" + ".77.5:5555"
      'address10.txt' = "the router at 10.4" + ".0.1"
      'profile.txt'   = "C:\" + "Users\someone\Downloads"
      'mail.txt'      = "write to player" + "@mail.test"
      'mixed.txt'     = "noreply" + "@example.com and player" + "@mail.test"
      'term.txt'      = "on the Wi-Fi " + "PlantedNet"
      'allowed.txt'   = "emulator host 10.0.2" + ".2, Claude <noreply" + "@anthropic.com>, $([char]0x40)d and 192.168.d.d"
    }
    foreach ($f in $plant.Keys) { [IO.File]::WriteAllText((Join-Path $dir $f), $plant[$f] + "`n") }
    & $git add -A 2>$null
    $found = Find-PrivateData @("plantednet")
    $want = @('address.txt: a home-network address', 'address10.txt: a home-network address',
      'mail.txt: an e-mail address', 'mixed.txt: an e-mail address', 'profile.txt: a user profile path',
      'term.txt: a private term')
    $missing = @($want | Where-Object { $found -notcontains $_ })
    $extra = @($found | Where-Object { $want -notcontains $_ })
  } finally { Pop-Location; Remove-Item -Recurse -Force $dir }
  $missing | ForEach-Object { Write-Host "FAIL  selftest: not found: $_" }
  $extra | ForEach-Object { Write-Host "FAIL  selftest: found although allowed: $_" }
  if ($missing.Count -or $extra.Count) { exit 1 }
  Write-Host "selftest: ALL PASS"
  exit 0
}

$fails = 0
function Result([bool]$ok, [string]$what, [string[]]$detail = @()) {
  if ($ok) { Write-Host "PASS  $what" } else {
    $script:fails++
    Write-Host "FAIL  $what" -ForegroundColor Red
    $detail | Select-Object -First 15 | ForEach-Object { Write-Host "        $_" }
  }
}

Push-Location $App
try {
  $files = @(& $git ls-files)

  # licence
  $lic = Join-Path $App "LICENSE"
  Result ((Test-Path $lic) -and ((Get-Content $lic -TotalCount 2) -join " ") -match "GNU GENERAL PUBLIC LICENSE\s+Version 3") `
    "LICENSE is the GPL-3.0 text"

  # pictures: only the ones known to be the project's own or third parties' with a licence (NOTICE.md)
  $allowedImages = '^(app/src/main/assets/gamepad/|termux-x11/)'
  $images = @($files | Where-Object { $_ -match '\.(png|jpe?g|webp|gif|bmp|ico|dds|tga)$' -and $_ -notmatch $allowedImages })
  Result ($images.Count -eq 0) "no pictures outside the allowed places (BAR artwork must never be in the repository)" $images

  # private data
  $terms = @()
  $redact = Join-Path (Split-Path $TC) "worklog-redact.txt"
  if (Test-Path $redact) { $terms += Get-Content $redact | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") } }
  $phone = Join-Path (Split-Path $TC) "phone-device.txt"
  if (Test-Path $phone) {
    $terms += Get-Content $phone | ForEach-Object { ($_.Trim() -split ':')[0] } | Where-Object { $_ -and -not $_.StartsWith("#") }
  }
  $hits = Find-PrivateData $terms
  Result ($hits.Count -eq 0) "no private data in the tracked files" $hits

  # keys, keystores, logins
  $secrets = @($files | Where-Object {
      ($_ -match '\.(jks|keystore|p12|pem|key)$' -and $_ -ne 'app/bardroid-debug.jks') -or
      $_ -match '(^|/)(local\.properties|CLAUDE\.local\.md|bar-lobby-login[^/]*|phone-device\.txt|worklog-redact\.txt)$' })
  Result ($secrets.Count -eq 0) "no keys, keystores, logins or local settings tracked" $secrets

  # size
  $big = @($files | Where-Object { (Test-Path -LiteralPath $_) -and (Get-Item -LiteralPath $_).Length -gt 50MB })
  Result ($big.Count -eq 0) "no file over 50 MB" $big

  # version and changelog
  $version = (Select-String -Path (Join-Path $App "gradle.properties") -Pattern '^bardroidVersionName=(.+)$').Matches[0].Groups[1].Value.Trim()
  $changelog = Join-Path $App "CHANGELOG.md"
  $entry = (Test-Path $changelog) -and (Select-String -Path $changelog -Pattern ("^##\s+\[?" + [regex]::Escape($version) + "\]?(\s|$)") -Quiet)
  Result $entry "CHANGELOG.md has an entry for version $version"

  # the APK
  if ($Apk) {
    # by the resource table: release builds shorten the files' paths, not the resources' names
    $bt = Get-ChildItem (Join-Path $TC "android-sdk\build-tools") | Sort-Object Name | Select-Object -Last 1
    $table = @(& (Join-Path $bt.FullName "aapt2.exe") dump resources $Apk 2>$null)
    $personal = @($table | Select-String 'ic_fg_personal' | ForEach-Object { $_.Line.Trim() })
    Result ($table.Count -gt 0 -and $personal.Count -eq 0) "the APK has the project's own icon" $personal
    $env:JAVA_HOME = Join-Path $TC "jdk"
    $certs = cmd /c "`"$($bt.FullName)\apksigner.bat`" verify --print-certs `"$Apk`" 2>&1" |
      Where-Object { $_ -notmatch 'JAVA_TOOL_OPTIONS' }
    $debugCert = & (Join-Path $TC "jdk\bin\keytool.exe") -list -v -keystore (Join-Path $App "app\bardroid-debug.jks") -storepass bardroid 2>$null |
      Select-String 'SHA256: ([0-9A-F:]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value.Replace(':', '').ToLower() }
    $signed = ($certs | Select-String 'certificate SHA-256 digest: ([0-9a-f]+)') | ForEach-Object { $_.Matches[0].Groups[1].Value }
    if (-not $debugCert) { $certs = @("(could not read the debug key's certificate from app\bardroid-debug.jks)") + $certs }
    Result ($debugCert -and $signed -and -not ($signed -contains $debugCert)) "the APK is signed, and not with the public debug key" $certs
  }

  # who the commits name: public once pushed
  $mails = @(& $git log --format='%ae%n%ce' | Sort-Object -Unique | Where-Object { $_ -and $_ -notmatch $allowedMail })
  if ($mails.Count) {
    Write-Host "NOTE  the commits name $($mails.Count) e-mail address(es) other than noreply ones, public once pushed (GitHub's noreply address keeps one private)"
  }

  # history
  if (-not $NoHistory) {
    $old = @()
    $iconCommits = @(& $git log --all --format=%h -- 'app/src/main/res/drawable-xxhdpi/ic_fg.png' 'app/src/main/res/drawable-xxxhdpi/ic_fg.png')
    if ($iconCommits.Count) { $old += "the owner's icon (BAR-derived) in $($iconCommits.Count) commits" }
    foreach ($t in $terms) {
      $n = @(& $git log --all -i --format=%h -S $t).Count
      if ($n) { $old += "a private term in $n commits" }
      $m = @(& $git log --all -i -F --format=%h "--grep=$t").Count
      if ($m) { $old += "a private term in $m commit messages" }
    }
    Result ($old.Count -eq 0) "the history holds none of it (else: publish a fresh history or rewrite it, docs/DELIVERY.md)" $old
  }
} finally { Pop-Location }

if ($fails) { Write-Host "`n$fails check(s) failed: not ready to publish." -ForegroundColor Red; exit 1 }
Write-Host "`nReady to publish."
