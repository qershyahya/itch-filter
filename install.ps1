# itch.io Safeguard Filter - one-line remote bootstrap.
#
#   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/qershyahya/itch-filter/main/install.ps1 | iex"
#
# Self-elevates, always downloads a FRESH copy of the installer (CDN cache-busted),
# and refuses to run a stale cached file. Then runs the full multi-browser install.
$ErrorActionPreference = 'Stop'
$REPO   = 'qershyahya/itch-filter'
$BRANCH = 'main'
$BOOT   = "https://raw.githubusercontent.com/$REPO/$BRANCH/install.ps1"
$SRC    = "https://raw.githubusercontent.com/$REPO/$BRANCH/tools/policies/windows/install-all.ps1"

# ---- elevate if needed ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'Elevation required - accept the UAC prompt...' -ForegroundColor Yellow
  $cmd = "irm '$BOOT' | iex"
  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-Command',$cmd
  return
}

Write-Host '=== itch.io Safeguard Filter - installer bootstrap ===' -ForegroundColor Cyan

# ---- always fetch fresh; never fall back to a stale temp file ----
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dest = Join-Path $env:TEMP ('itch-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
  $bust = "$SRC" + '?cb=' + [guid]::NewGuid().ToString('N')   # defeat the raw CDN cache
  Invoke-WebRequest $bust -OutFile $dest -UseBasicParsing -TimeoutSec 40
} catch {
  Write-Host ''
  Write-Host '!! Could not download the installer.' -ForegroundColor Red
  Write-Host ("   $($_.Exception.Message)")
  Write-Host ''
  Write-Host '   If this says "remote name could not be resolved", this device cannot'
  Write-Host '   reach raw.githubusercontent.com (DNS or a network filter).'
  Write-Host '   Offline option - copy the extension folder to the machine, then run:'
  Write-Host '     install-all.ps1 -Source "D:\path\to\itch-filter-extension"'
  return
}
if (-not (Select-String -Path $dest -Pattern 'itch.io Safeguard Filter' -Quiet)) {
  Write-Host '!! Downloaded file does not look like the installer - aborting.' -ForegroundColor Red
  Remove-Item $dest -Force -EA SilentlyContinue
  return
}

# ---- run it ----
try { & $dest @args }
finally { Remove-Item $dest -Force -EA SilentlyContinue }
