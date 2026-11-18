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
#   powershell -ExecutionPolicy Bypass -File tools\github-sync.ps1 [-Release] [-NoEngine]
param([switch]$Release, [switch]$NoEngine)
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
$Root = Split-Path -Parent $App
$gh = "C:\Tools\GitHubCLI\gh.bat"
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
  $apk = Join-Path $Root "apk\bar-droid-phone-debug.apk"
  if (-not (Test-Path $apk)) { throw "no APK at ${apk}: build it first" }
  $head = (& $git -C $App rev-parse HEAD).Trim()
  $short = $head.Substring(0, 8)
  $engineBuild = ""
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($apk)
  try {
    $e = $z.Entries | Where-Object { $_.FullName -like "assets/phone-engine/*/BUILD.txt" } | Select-Object -First 1
    if ($e) { $r = New-Object IO.StreamReader($e.Open()); $engineBuild = ($r.ReadLine()); $r.Close() }
  } finally { $z.Dispose() }
  $when = (Get-Item $apk).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
  $subject = (& $git -C $App log -1 --format=%s).Trim()
  $notes = @"
The newest phone build, as installed on the Fold7: built $when from ``$short`` ($subject).

- Phone engine: $engineBuild (source: the bardroid/* branches of $owner/bar-droid-engine)
- A debug build, signed with the project's public dev key (app/bardroid-debug.jks): it installs over the app built
  the same way. Not a release for others: the release build is signed with the publisher's own key.
- What changed: the commits up to ``$short``; docs/DELIVERY.md, newest first; the conversation archive in
  docs/WORKLOG.md and docs/worklog/.
"@
  Git $App @("push", "--force", "origin", "${head}:refs/tags/latest-build") | Out-Null   # (this tag alone moves)
  $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & $gh release view latest-build -R "$owner/bar-droid" 2>$null | Out-Null
  $exists = $LASTEXITCODE -eq 0
  $ErrorActionPreference = $eap
  $notesFile = Join-Path $env:TEMP "bardroid-release-notes.md"
  [IO.File]::WriteAllText($notesFile, $notes, (New-Object Text.UTF8Encoding $false))
  if ($exists) {
    & $gh release edit latest-build -R "$owner/bar-droid" --title "Latest build ($when)" --notes-file $notesFile --prerelease | Out-Null
    & $gh release upload latest-build $apk -R "$owner/bar-droid" --clobber
  } else {
    & $gh release create latest-build $apk -R "$owner/bar-droid" --title "Latest build ($when)" --notes-file $notesFile --prerelease --verify-tag
  }
  if ($LASTEXITCODE -ne 0) { throw "the release did not go up" }
  "[github] latest-build: $short, $([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB, engine $engineBuild"
}
