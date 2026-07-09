<#
.SYNOPSIS
  VesnAI launcher for Windows.

.DESCRIPTION
  Runs the local server and installs / updates / runs the Flutter client.
  On macOS / Linux use scripts/vesnai.sh instead.

.EXAMPLE
  ./scripts/vesnai.ps1 server
  ./scripts/vesnai.ps1 server -Online
  ./scripts/vesnai.ps1 client install
  ./scripts/vesnai.ps1 client update
  ./scripts/vesnai.ps1 client run -Device android
  ./scripts/vesnai.ps1 doctor
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = "help",
  [Parameter(Position = 1)] [string]$Action  = "",
  [int]$Port = 8443,
  [string]$VesnaiHost = "0.0.0.0",
  [string]$KnowledgeDir,
  [string]$DataDir,
  [string]$Device,
  [switch]$Online,
  [switch]$NoTls
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = Split-Path -Parent $ScriptDir
$ServerDir = Join-Path $Root "server"
$AppDir    = Join-Path $Root "app"
$TlsCert   = Join-Path $ServerDir "localhost.pem"
$TlsKey    = Join-Path $ServerDir "localhost-key.pem"

function Info($m) { Write-Host "==> $m" -ForegroundColor Blue }
function Ok($m)   { Write-Host "OK  $m"  -ForegroundColor Green }
function Warn($m) { Write-Host "!   $m"  -ForegroundColor Yellow }
function Die($m)  { Write-Host "X   $m"  -ForegroundColor Red; exit 1 }
function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Ensure-UvToolPath {
  $localBin = Join-Path $env:USERPROFILE ".local\bin"
  if (-not (Test-Path $localBin)) { return }
  $parts = @()
  if ($env:PATH) { $parts = $env:PATH -split [IO.Path]::PathSeparator }
  if ($parts -notcontains $localBin) {
    $env:PATH = "$localBin$([IO.Path]::PathSeparator)$env:PATH"
  }
}

function Persist-UvToolPath {
  if (-not (Have "uv")) { return }
  uv tool update-shell 2>$null | Out-Null
  Ensure-UvToolPath
}

function Need-Uv {
  if (-not (Have "uv")) {
    Warn "uv (Python package manager) is not installed."
    Write-Host '    Install with: powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"'
    Die "uv is required to run the server."
  }
  Ensure-UvToolPath
}
function Need-Flutter {
  if (-not (Have "flutter")) { Die "flutter is not installed. See https://docs.flutter.dev/get-started/install" }
}

function Install-Mkcert {
  Info "Installing mkcert (locally-trusted TLS certificates)..."
  if (Have "choco") {
    choco install mkcert -y
  } elseif (Have "scoop") {
    scoop install mkcert
  } elseif (Have "winget") {
    winget install --id FiloSottile.mkcert -e --accept-source-agreements --accept-package-agreements
  } else {
    Die "Install mkcert manually: https://github.com/FiloSottile/mkcert#windows"
  }
  if (-not (Have "mkcert")) { Die "mkcert install finished but mkcert is still missing." }
  Ok "mkcert installed."
}

function New-TlsCerts {
  if (-not (Have "mkcert")) { Install-Mkcert }
  Info "Installing the local CA into your system trust store (mkcert -install)..."
  mkcert -install
  Info "Generating TLS certificate for VesnAI..."
  New-Item -ItemType Directory -Force -Path $ServerDir | Out-Null
  $hostFqdn = [System.Net.Dns]::GetHostName()
  $sans = @("localhost", "127.0.0.1", "::1")
  if ($hostFqdn -and $hostFqdn -ne "localhost") { $sans += $hostFqdn }
  Push-Location $ServerDir
  try {
    & mkcert -cert-file localhost.pem -key-file localhost-key.pem @sans
  } finally { Pop-Location }
  if (-not ((Test-Path $TlsCert) -and (Test-Path $TlsKey))) { Die "Certificate generation failed." }
  Ok "Certificate: $TlsCert"
  Ok "Private key: $TlsKey"
  Ok "Trusted by browsers on this machine (mkcert CA)."
  Bundle-MobileMkcertCa
}

function Ensure-TlsCerts {
  if ((Test-Path $TlsCert) -and (Test-Path $TlsKey)) { return }
  New-TlsCerts
}

function Cmd-SetupHttps {
  New-TlsCerts
  Write-Host ""
  Ok "HTTPS is ready. Start the server with: ./scripts/vesnai.ps1 server"
  Write-Host "   Then open https://localhost:8443/docs"
}

function Cmd-Server {
  if (-not $KnowledgeDir) { $KnowledgeDir = Join-Path $ServerDir "knowledge" }
  if (-not $DataDir)      { $DataDir      = Join-Path $ServerDir "data" }

  Need-Uv
  if ($Online) {
    # Online stack: LLM/embeddings/search/STT in-process; TTS is a separate sidecar
    # the user registers in Settings → Voice service.
    Info "Syncing server dependencies (uv sync --extra ai)..."
    uv sync --extra ai
    # FLUX image gen lives in its own isolated env (torch/numpy pins clash with
    # Chatterbox). Install the mflux-generate CLI tool (idempotent).
    Info "Installing FLUX image CLI (uv tool install mflux)..."
    uv tool install mflux 2>$null
    Persist-UvToolPath
    if (-not (Have "mflux-generate")) {
      Warn "mflux-generate not found after install; image generation will be unavailable"
    }
  } else {
    Info "Syncing server dependencies (uv sync)..."
    uv sync
  }
  Push-Location $ServerDir
  try {
    $serveArgs = @("run", "vesnai", "serve",
      "--knowledge-dir", $KnowledgeDir, "--data-dir", $DataDir, "--port", "$Port", "--host", $VesnaiHost)
    if ($Online) { $serveArgs += "--no-offline" } else { $serveArgs += "--offline" }

    $scheme = "https"
    if (-not $NoTls) {
      Ensure-TlsCerts
      $serveArgs += @("--tls", "--cert", $TlsCert, "--key", $TlsKey)
      Ok "HTTPS enabled - server at https://localhost:$Port (docs: /docs)"
    } else {
      $scheme = "http"
      $serveArgs += "--no-tls"
      Warn "TLS disabled - server at http://localhost:$Port"
    }
    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
      Select-Object -First 1).IPAddress
    if (-not $lanIp) { $lanIp = $VesnaiHost }
    Ok "Pair phones/tablets at: ${scheme}://${lanIp}:$Port  (use this URL in the app, not localhost)"
    Info "Press Ctrl+C to stop."
    Ensure-UvToolPath
    & uv @serveArgs
  } finally { Pop-Location }
}

function Get-MkcertRootCa {
  if (-not (Have "mkcert")) { return $null }
  $caroot = mkcert -CAROOT 2>$null
  if (-not $caroot) { return $null }
  $ca = Join-Path $caroot "rootCA.pem"
  if (Test-Path $ca) { return $ca }
  return $null
}

# Only used together with --dart-define=TRUST_DEV_MKCERT_CA=true (dev builds);
# release/store builds ignore the asset (see lib/data/http_client_factory.dart).
function Bundle-MobileMkcertCa {
  $ca = Get-MkcertRootCa
  if (-not $ca) { Die "mkcert root CA not found. Run: ./scripts/vesnai.ps1 setup-https" }
  $flutterDest = Join-Path $AppDir "assets\certs\mkcert_root_ca.pem"
  New-Item -ItemType Directory -Force -Path (Split-Path $flutterDest) | Out-Null
  Copy-Item -Force $ca $flutterDest
  Ok "Bundled mkcert root CA (assets/certs for app TLS in dev builds)."
}

# Launcher builds are dev builds for your own devices: opt in to trusting the
# dev mkcert CA (release/store builds keep the safe default of public CAs only).
$DevCaDefine = "--dart-define=TRUST_DEV_MKCERT_CA=true"

function Install-MkcertCaOnAndroid {
  if (-not (Have "adb")) { return }
  $ca = Get-MkcertRootCa
  if (-not $ca) { return }
  $devices = adb devices 2>$null | Select-String "`tdevice$" | ForEach-Object { ($_ -split "`t")[0] }
  if (-not $devices) { return }
  $device = $devices | Select-Object -First 1
  Info "Copying mkcert root CA to the device (optional, for system-wide trust)..."
  adb -s $device push $ca /sdcard/Download/mkcert-rootCA.pem | Out-Null
  Ok "Optional: on the phone open Settings > Security > Install certificate > CA certificate."
  Ok "The VesnAI dev build already trusts this CA (bundled asset); installing it"
  Ok "as a user CA additionally covers WebView/native traffic in debug builds."
}

function Client-Deploy([string]$Verb, [string]$Target) {
  Need-Flutter
  Info "Fetching Flutter packages (flutter pub get)..."
  Push-Location $AppDir
  try {
    flutter pub get

    switch ($Target) {
      "android" {
        Ensure-TlsCerts
        Bundle-MobileMkcertCa
        Info "Building Android release APK..."
        flutter build apk --release $DevCaDefine
        $apk = Join-Path $AppDir "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path $apk)) { Die "Build succeeded but APK not found at $apk" }
        if (-not (Have "adb")) { Die "adb not found. Install Android SDK platform-tools." }
        $deviceLine = adb devices 2>$null | Select-String "`tdevice$" | Select-Object -First 1
        if (-not $deviceLine) { Die "No Android device or emulator connected (check: adb devices)." }
        $device = ($deviceLine -split "`t")[0]
        Info "$Verb release APK on $device..."
        adb -s $device install -r $apk
        Install-MkcertCaOnAndroid
        Ok "VesnAI installed on Android ($device)."
      }
      default {
        if (-not (Test-Path (Join-Path $AppDir "windows"))) {
          Info "Adding missing 'windows' platform to the Flutter project..."
          flutter create --platforms=windows .
        }
        Info "Building Windows release..."
        flutter build windows --release $DevCaDefine

        $rel = Get-ChildItem -Path (Join-Path $AppDir "build\windows") -Recurse -Directory `
                -Filter "Release" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "runner\\Release$" } | Select-Object -First 1
        if (-not $rel) { Die "Build succeeded but no Release folder was found under build\windows." }

        $dest = Join-Path $env:LOCALAPPDATA "Programs\VesnAI"
        Info "$Verb to $dest"
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -Path (Join-Path $rel.FullName "*") -Destination $dest -Recurse -Force

        $exe = Get-ChildItem -Path $dest -Filter "*.exe" | Select-Object -First 1
        if ($exe) {
          $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\VesnAI.lnk"
          $ws = New-Object -ComObject WScript.Shell
          $sc = $ws.CreateShortcut($startMenu)
          $sc.TargetPath = $exe.FullName
          $sc.WorkingDirectory = $dest
          $sc.Save()
          Ok "$($exe.Name) installed in $dest (Start Menu shortcut: VesnAI)."
        } else {
          Ok "Installed to $dest."
        }
      }
    }
  } finally { Pop-Location }
}

function Cmd-Client {
  if (-not $Action) { $Action = "run" }
  $target = if ($Device) { $Device.ToLower() } else { "windows" }
  switch ($Action) {
    "install" { Client-Deploy "Installing" $target }
    "update"  { Client-Deploy "Updating" $target }
    "run" {
      Need-Flutter
      Info "Fetching Flutter packages (flutter pub get)..."
      Push-Location $AppDir
      try {
        flutter pub get
        if ($target -eq "android") {
          Ensure-TlsCerts
          Bundle-MobileMkcertCa
        }
        if ($Device) {
          Info "Launching the client on '$Device'..."
          flutter run $DevCaDefine -d $Device
        } else {
          Info "Launching the client (Flutter will pick a device)..."
          flutter run $DevCaDefine
        }
      } finally { Pop-Location }
    }
    default { Die "Unknown client action: $Action (use run|install|update)" }
  }
}

function Cmd-Pair {
  if (-not $DataDir) { $DataDir = Join-Path $ServerDir "data" }
  $args = @("pair", "--data-dir", $DataDir)
  Push-Location $ServerDir
  try { uv run vesnai @args } finally { Pop-Location }
}

function Cmd-Doctor {
  Info "Detected OS: Windows"
  Write-Host "`nPrerequisites:"
  if (Have "uv")      { Ok "uv         $(uv --version)" }      else { Warn "uv         missing (needed for the server)" }
  if (Have "flutter") { Ok "flutter    present" }             else { Warn "flutter    missing (needed for the client)" }
  if (Have "mkcert") { Ok "mkcert     present" } else { Warn "mkcert     missing (run: ./scripts/vesnai.ps1 setup-https)" }
  if (Test-Path $TlsCert) { Ok "tls cert   $TlsCert" } else { Warn "tls cert   missing (run: ./scripts/vesnai.ps1 setup-https)" }
  if (Have "ollama")  { Ok "ollama     present (local models)" } else { Warn "ollama     missing (optional, for -Online local models)" }
  if (Have "adb")     { Ok "adb        present" } else { Warn "adb        missing (needed for Android install)" }
  Write-Host "`nPaths:"
  Write-Host "  server: $ServerDir"
  Write-Host "  app:    $AppDir"
}

function Show-Usage {
  @"
VesnAI launcher (Windows)

Usage: ./scripts/vesnai.ps1 <command> [options]

Commands:
  setup-https               Install mkcert (if needed) and generate a trusted dev certificate
  server                    Run the local server over HTTPS (syncs deps first)
    -Port N                 Port (default 8443)
    -KnowledgeDir DIR       OKF bundle directory (default server\knowledge)
    -DataDir DIR            State/index directory (default server\data)
    -Online                 Use local models (Ollama); default is offline
    -NoTls                  Disable HTTPS (default: HTTPS with mkcert)

  client <run|install|update> [-Device <windows|android|...>]
    run                     Hot-run the app on a device/emulator (default)
    install                 Build a release and install (Windows, Android APK)
    update                  Rebuild and replace an existing install

  doctor                    Check installed prerequisites
  pair                      Mint a pairing code (run on the server host)
    -DataDir DIR             State directory (default server\data)

  Voice output (TTS) is not bundled: register any HTTP TTS service or an
  OpenAI-compatible speech API in the app (Settings -> Voice service).
  See docs/TTS_SIDECAR.md.

Examples:
  ./scripts/vesnai.ps1 setup-https
  ./scripts/vesnai.ps1 server -Online
  ./scripts/vesnai.ps1 pair
  ./scripts/vesnai.ps1 client install
  ./scripts/vesnai.ps1 client install -Device android
  ./scripts/vesnai.ps1 client run -Device android
"@ | Write-Host
}

switch ($Command.ToLower()) {
  "server" { Cmd-Server }
  "setup-https" { Cmd-SetupHttps }
  "client" { Cmd-Client }
  "doctor" { Cmd-Doctor }
  "pair" { Cmd-Pair }
  default  { Show-Usage }
}
