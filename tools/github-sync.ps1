# The project on its private GitHub repositories (Kailil, 2026-11-18: "Get this project fully on github as private and
# make sure that our new builds and work is reflected via github as well. Log our conversation history there if
# possible too as an archive so they can see how the project is supported long term"):
#   UnderarmCape/bar-droid         this repository: every branch, the work log and its day pages (docs/WORKLOG.md,
#                                  docs/worklog/: the conversation archive, tools/worklog.py) with them
#   UnderarmCape/bar-droid-engine  the phone engine's source: the bardroid/* branches of ..\hailmary-work\recoil-src
#                                  (Recoil, BAR's engine; the APK carries a build of bardroid/combined)
# Run after each commit; with -Release also after a build goes on the Fold7: the phone APK as the rolling pre-release
# "latest-build", its tag moved to this repository's HEAD, its notes naming the commit and the phone engine.
# Never forces a branch (a rejected push stops with its message); only latest-build's own tag moves. Git through the
# portable GitHub CLI's credential helper, per command: no global git config, nothing stored.
#   powershell -ExecutionPolicy Bypass -File tools\github-sync.ps1 [-Release [-Apk <file.apk>] [-WhatsNew <text>] [-NoLatest]] [-NoEngine]
# -Apk: the APK that went on the Fold7 (a train build, tools\phone-round.ps1), else apk\bar-droid-phone-debug.apk.
# Each -Release also keeps that build as a release of its own (Kailil, 2026-11-24: "why is there only 1 release in
# github"; the rolling latest-build had replaced every checkpoint's APK): tag build-<yyyy.MM.dd>-<commit> on the commit
# the APK was built from, titled with its date and what changed (-WhatsNew, a line or a few for players), the APK as
# bar-droid-<tag>.apk. -NoLatest: only that release (an older build kept after the fact; latest-build left as it is).
param([switch]$Release, [switch]$NoEngine, [string]$Apk, [string]$WhatsNew = "", [switch]$NoLatest)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Root = Split-Path -Parent $App
$gh = "C:\Tools\GitHubCLI\gh\bin\gh.exe"   # (gh.bat's own settings, set here: through cmd a release title with "|" or quotes broke the call)
$env:GH_CONFIG_DIR = "C:\Tools\GitHubCLI\config"; $env:GH_NO_UPDATE_NOTIFIER = "1"
$git = Join-Path $Root "toolchain\git\cmd\git.exe"
if (-not (Test-Path $git)) { $git = (Get-Command git -ErrorAction Stop).Source }
$owner = "UnderarmCape"
$env:GIT_TERMINAL_PROMPT = "0"

function Git([string]$dir, [string[]]$gitArgs) {
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (git's progress goes to stderr)
  try {
    $out = & $git -C $dir -c credential.helper= -c "credential.helper=!'C:/Tools/GitHubCLI/gh.bat' auth git-credential" @gitArgs 2>&1 |
      ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $eap }
  if ($code -ne 0) { $out | ForEach-Object { "  $_" }; throw "git $($gitArgs -join ' ') failed in $dir" }
  return $out
}
function Remote([string]$dir, [string]$name, [string]$url) {
  $have = & $git -C $dir remote 2>$null
  if ($have -notcontains $name) { Git $dir @("remote", "add", $name, $url) | Out-Null }
}

# 1. this repository, every branch
Remote $App "origin" "https://github.com/$owner/bar-droid.git"
Git $App @("push", "--porcelain", "origin", "--all") | Where-Object { $_ -match '^[!*+-=]' -or $_ -match 'rejected' } |
  ForEach-Object { "[github] bar-droid $_" }
"[github] bar-droid: every branch pushed"

# 2. the phone engine's source
$engine = Join-Path $Root "hailmary-work\recoil-src"
if (-not $NoEngine -and (Test-Path (Join-Path $engine ".git"))) {
  Remote $engine "github" "https://github.com/$owner/bar-droid-engine.git"   # (origin is BAR's RecoilEngine)
  Git $engine @("push", "--porcelain", "github", "refs/heads/bardroid/*:refs/heads/bardroid/*") |
    Where-Object { $_ -match '^[!*+-=]' -or $_ -match 'rejected' } | ForEach-Object { "[github] bar-droid-engine $_" }
  "[github] bar-droid-engine: the bardroid/* branches pushed"
}

# 3. the build, as the rolling pre-release
if ($Release) {
  $apk = if ($Apk) { $Apk } else { Join-Path $Root "apk\bar-droid-phone-debug.apk" }
  if (-not (Test-Path $apk)) { throw "no APK at ${apk}: build it first" }
  $head = (& $git -C $App rev-parse HEAD).Trim()
  $short = $head.Substring(0, 8)
  $engineBuild = ""
  # (the commit the APK was built from: its Termux:X11 version line in its dex, "... from BAR Droid <commit>[ + changes]"
  # (patches 0012, 0016); HEAD here can be a later commit of docs only, 2026-11-18: built from ab66c2d7, HEAD 91b45544)
  $builtFrom = ""
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($apk)
  try {
    $e = $z.Entries | Where-Object { $_.FullName -like "assets/phone-engine/*/BUILD.txt" } | Select-Object -First 1
    if ($e) { $r = New-Object IO.StreamReader($e.Open()); $engineBuild = ($r.ReadLine()); $r.Close() }
    foreach ($d in ($z.Entries | Where-Object { $_.FullName -like "classes*.dex" })) {
      $ms = New-Object IO.MemoryStream; $s = $d.Open(); $s.CopyTo($ms); $s.Close()
      $txt = [Text.Encoding]::GetEncoding(28591).GetString($ms.ToArray())
      $i = $txt.IndexOf("from BAR Droid ")
      if ($i -ge 0) {
        $j = $txt.IndexOf([char]0, $i)
        if ($j -gt $i) { $builtFrom = $txt.Substring($i + 15, $j - $i - 15).Trim(); break }
      }
    }
  } finally { $z.Dispose() }
  $when = (Get-Item $apk).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
  $subject = (& $git -C $App log -1 --format=%s).Trim()
  $from = "this repository at ``$short`` ($subject)"
  if ($builtFrom) {
    $b = ($builtFrom -split " ")[0]
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # (a commit not here: git's stderr, no stop)
    $bSubject = (& $git -C $App log -1 --format=%s $b 2>$null)
    if ($LASTEXITCODE -ne 0) { $bSubject = $null }
    $ErrorActionPreference = $eap
    $changes = if ($builtFrom -match "\+ changes") { ", with changes not yet committed" } else { "" }
    $from = "from ``$b`` ($(if ($bSubject) { $bSubject.Trim() } else { 'not in this repository' })$changes); this repository at ``$short`` when it went up"
  }
  $notes = @"
The newest phone build: the APK built $when $from.

- Phone engine: $engineBuild (source: the bardroid/* branches of $owner/bar-droid-engine)
- A debug build, signed with the project's public dev key (app/bardroid-debug.jks): it installs over the app built
  the same way. Not a release for others: the release build is signed with the publisher's own key.
- What changed: the commits up to ``$short``; docs/DELIVERY.md, newest first; the conversation archive in
  docs/WORKLOG.md and docs/worklog/.
"@
  if ($WhatsNew) { $notes = "**What's new:** $WhatsNew`n`n" + $notes }
  $notesFile = Join-Path $Root "toolchain\tmp\bardroid-release-notes.md"
  [IO.File]::WriteAllText($notesFile, $notes, (New-Object Text.UTF8Encoding $false))

  # 3a. this build kept as a release of its own: its tag on the commit it was built from (never moved once made)
  $bc = if ($builtFrom) { ($builtFrom -split " ")[0] } else { $short }
  $bc = $bc.Substring(0, [Math]::Min(8, $bc.Length))
  $tag = "build-" + (Get-Item $apk).LastWriteTime.ToString("yyyy.MM.dd") + "-" + $bc
  $full = "$(& $git -C $App rev-parse --verify --quiet "$bc^{commit}" 2>$null)".Trim()
  if (-not $full) { $full = $head }   # (built from a commit not here: the tag on HEAD as it went up)
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & $git -C $App ls-remote --exit-code --tags origin "refs/tags/$tag" 2>$null | Out-Null
  $tagThere = $LASTEXITCODE -eq 0
  & $gh release view $tag -R "$owner/bar-droid" 2>$null | Out-Null
  $relThere = $LASTEXITCODE -eq 0
  $ErrorActionPreference = $eap
  if (-not $tagThere) { Git $App @("push", "origin", "${full}:refs/tags/$tag") | Out-Null }
  $dir = Join-Path $Root "toolchain\tmp\release"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $named = Join-Path $dir "bar-droid-$tag.apk"
  Copy-Item $apk $named -Force
  $bSubj = "$(& $git -C $App log -1 --format=%s $full 2>$null)".Trim()
  $title = "Build " + (Get-Item $apk).LastWriteTime.ToString("yyyy-MM-dd HH:mm") + " ($bc)" + $(if ($WhatsNew) { ": " + ($WhatsNew -split '[.;]')[0].Trim() } elseif ($bSubj) { ": $bSubj" } else { "" })
  if ($title.Length -gt 120) { $title = $title.Substring(0, 117) + "..." }
  if ($relThere) {
    & $gh release edit $tag -R "$owner/bar-droid" --title $title --notes-file $notesFile --prerelease | Out-Null
    & $gh release upload $tag $named -R "$owner/bar-droid" --clobber
  } else {
    & $gh release create $tag $named -R "$owner/bar-droid" --title $title --notes-file $notesFile --prerelease --verify-tag --latest=false
  }
  if ($LASTEXITCODE -ne 0) { throw "the build's own release ($tag) did not go up" }
  "[github] $tag`: its own release, $title"
  if ($NoLatest) { return }

  Git $App @("push", "--force", "origin", "${head}:refs/tags/latest-build") | Out-Null   # (this tag alone moves)
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & $gh release view latest-build -R "$owner/bar-droid" 2>$null | Out-Null
  $exists = $LASTEXITCODE -eq 0
  $ErrorActionPreference = $eap
  # (the asset takes the file's name: a train build goes up as a copy under the usual name, so --clobber replaces it)
  $upload = $apk
  if ((Split-Path -Leaf $apk) -ne "bar-droid-phone-debug.apk") {
    $dir = Join-Path $Root "toolchain\tmp\release"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $upload = Join-Path $dir "bar-droid-phone-debug.apk"
    Copy-Item $apk $upload -Force
  }
  if ($exists) {
    & $gh release edit latest-build -R "$owner/bar-droid" --title "Latest build ($when)" --notes-file $notesFile --prerelease | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "the release's notes did not go up" }   # (the upload's code alone was checked)
    & $gh release upload latest-build $upload -R "$owner/bar-droid" --clobber
  } else {
    & $gh release create latest-build $upload -R "$owner/bar-droid" --title "Latest build ($when)" --notes-file $notesFile --prerelease --verify-tag
  }
  if ($LASTEXITCODE -ne 0) { throw "the release did not go up" }
  "[github] latest-build: $short, built from $(if ($builtFrom) { $builtFrom } else { '?' }), $([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB, engine $engineBuild"
}
