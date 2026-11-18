# VoiceChat.java (speak to chat) on the toolchain's JDK, with stand-ins for Android's speech recognition: a cancelled
# or past session's late callbacks dropped, restarts, the screen going away, the microphone question (no microphone).
#   powershell -ExecutionPolicy Bypass -File tools\voice-chat-test.ps1
$ErrorActionPreference = "Stop"
$App = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "toolchain.ps1")
$Work = Join-Path $App "build\voice-chat-test"
$classes = Join-Path $Work "classes"
Remove-Item -Recurse -Force $classes -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$javac = (Get-ChildItem (Join-Path $TC "jdk") -Recurse -Filter javac.exe | Select-Object -First 1).FullName
$java = Join-Path (Split-Path $javac) "java.exe"
$env:JAVA_TOOL_OPTIONS = "-Duser.home=$(Join-Path $TC 'home') -Djava.io.tmpdir=$Work"
$sources = @(Get-ChildItem (Join-Path $PSScriptRoot "voice-chat-test\src") -Recurse -Filter *.java | ForEach-Object FullName) +
  (Join-Path $App "app\src\main\java\com\underarmcape\bardroid\VoiceChat.java")
& $javac -nowarn -d $classes $sources
if ($LASTEXITCODE -ne 0) { throw "javac failed" }
& $java -cp $classes com.underarmcape.bardroid.VoiceChatTest
exit $LASTEXITCODE
