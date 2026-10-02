# vesslet installer for Windows.
#
#   irm https://raw.githubusercontent.com/vesslet/vesslet-releases/main/install.ps1 | iex
#
# Environment:
#   $env:VESSLET_VERSION = "v0.4.2"   install this version instead of the latest
#   $env:VESSLET_YES = "1"            install missing tools without asking
#   $env:VESSLET_NO_SETUP = "1"       only install the binary
#
# installer — implements BR-1, BR-2, BR-3, BR-4, BR-7, BR-8
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ReleasesUrl = if ($env:VESSLET_RELEASES_URL) { $env:VESSLET_RELEASES_URL } else { "https://github.com/vesslet/vesslet-releases" }
$Version = $env:VESSLET_VERSION

function Fail($msg) { Write-Host "vesslet installer: $msg" -ForegroundColor Red; exit 1 }

# ── platform (BR-2) ──
$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
if ($arch -ne "AMD64") { Fail "unsupported processor $arch — vesslet for Windows is built for x86-64 (AMD64) only" }
$asset = "vesslet-windows-amd64.exe"

# ── version (BR-7) ──
if (-not $Version) {
  try {
    $req = [System.Net.WebRequest]::Create("$ReleasesUrl/releases/latest")
    $req.Method = "HEAD"; $req.AllowAutoRedirect = $false
    $resp = $req.GetResponse(); $location = $resp.Headers["Location"]; $resp.Close()
  } catch { Fail "couldn't reach $ReleasesUrl" }
  if ($location -notmatch "/releases/tag/(v[0-9][^/]*)$") { Fail "couldn't find the latest release at $ReleasesUrl" }
  $Version = $Matches[1]
}
if (-not $Version.StartsWith("v")) { $Version = "v$Version" }

# ── download + verify (BR-3) ──
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vesslet-" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  Write-Host "Downloading vesslet $Version (windows/amd64)..."
  try { Invoke-WebRequest -UseBasicParsing -Uri "$ReleasesUrl/releases/download/$Version/$asset" -OutFile "$tmp\$asset" }
  catch { Fail "download failed — is $Version published for Windows?" }
  try { Invoke-WebRequest -UseBasicParsing -Uri "$ReleasesUrl/releases/download/$Version/checksums.txt" -OutFile "$tmp\checksums.txt" }
  catch { Fail "couldn't download checksums.txt for $Version" }
  $want = (Get-Content "$tmp\checksums.txt" | Where-Object { ($_ -split '\s+')[1] -in @($asset, "*$asset") } | ForEach-Object { ($_ -split '\s+')[0] }) | Select-Object -First 1
  if (-not $want) { Fail "$asset isn't listed in checksums.txt — refusing to install it" }
  $got = (Get-FileHash -Algorithm SHA256 "$tmp\$asset").Hash.ToLower()
  if ($got -ne $want.ToLower()) { Fail "checksum mismatch for $asset — the download isn't the published file; nothing was installed" }

  # ── install (BR-4, BR-8): the same place the companion runs from ──
  $binDir = Join-Path $HOME ".vesslet\bin"
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  $target = Join-Path $binDir "vesslet.exe"
  if (Test-Path $target) {
    $old = "$target.old"
    Remove-Item -Force $old -ErrorAction SilentlyContinue
    Move-Item -Force $target $old   # a running vesslet.exe can be renamed, not overwritten
  }
  Copy-Item "$tmp\$asset" "$target.new"
  Move-Item -Force "$target.new" $target
  Write-Host "vesslet $Version installed: $target"

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (($userPath -split ';') -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(';') + ";" + $binDir), "User")
    Write-Host "Added $binDir to your PATH — open a new terminal to use 'vesslet'."
  }
  $env:Path = "$env:Path;$binDir"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ── setup: tools + harbor (BR-5, BR-6) ──
if ($env:VESSLET_NO_SETUP) { exit 0 }
Write-Host ""
$setupArgs = @('setup')
if ($env:VESSLET_YES) { $setupArgs += '--yes' }
if ($env:VESSLET_WITH) { $setupArgs += @('--with', $env:VESSLET_WITH) }  # capabilities — BR-3
& $target @setupArgs
