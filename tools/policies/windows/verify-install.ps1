# Verify the itch.io Safeguard Filter is actually loaded in each installed browser.
# Run any time (no admin needed):
#     powershell -ExecutionPolicy Bypass -File verify-install.ps1
# Exit code 0 = every detected browser is protected, 1 = at least one is not.
$ErrorActionPreference = 'Continue'
$GECKO  = 'itch-filter@qershyahya'
$EXTDIR = Join-Path $env:ProgramData 'itch-filter\extension'

function Test-FirefoxLoaded {
  $hit = $false
  Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object {
    $pdir = Join-Path $_.FullName 'AppData\Roaming\Mozilla\Firefox\Profiles'
    if (Test-Path $pdir) {
      Get-ChildItem $pdir -Directory -EA SilentlyContinue | ForEach-Object {
        $f = Join-Path $_.FullName 'extensions.json'
        if ((Test-Path $f) -and ((Get-Content $f -Raw -EA SilentlyContinue) -like "*$GECKO*")) { $hit = $true }
      }
    }
  }
  $hit
}
function Test-ChromiumLoaded([string]$vendorPath) {
  $hit = $false
  Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue | ForEach-Object {
    $ud = Join-Path $_.FullName $vendorPath
    if (Test-Path $ud) {
      Get-ChildItem $ud -Directory -EA SilentlyContinue | ForEach-Object {
        foreach ($n in 'Preferences','Secure Preferences') {
          $f = Join-Path $_.FullName $n
          if (Test-Path $f) {
            $c = Get-Content $f -Raw -EA SilentlyContinue
            if ($c -and ($c -like '*itch-filter\\\\extension*' -or $c -like '*itch.io Safeguard*' -or $c -like '*itch-filter/extension*')) { $hit = $true }
          }
        }
      }
    }
  }
  $hit
}

$browsers = @{
  firefox = @{ exe = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"); test = { Test-FirefoxLoaded } }
  chrome  = @{ exe = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"); test = { Test-ChromiumLoaded 'AppData\Local\Google\Chrome\User Data' } }
  edge    = @{ exe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"); test = { Test-ChromiumLoaded 'AppData\Local\Microsoft\Edge\User Data' } }
  opera   = @{ exe = @("$env:LOCALAPPDATA\Programs\Opera\opera.exe", "$env:ProgramFiles\Opera\opera.exe"); test = { Test-ChromiumLoaded 'AppData\Roaming\Opera Software\Opera Stable' } }
}

Write-Host "`n=== itch.io Safeguard Filter - verification ===`n"
Write-Host ("extension folder: {0}  [{1}]" -f $EXTDIR, $(if (Test-Path (Join-Path $EXTDIR 'manifest.json')) { 'present' } else { 'MISSING' }))
Write-Host ''

$anyBad = $false; $anyBrowser = $false
foreach ($name in 'firefox','chrome','edge','opera') {
  $b = $browsers[$name]
  $installed = $b.exe | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $installed) { Write-Host ("  {0,-8} not installed" -f $name) -ForegroundColor DarkGray; continue }
  $anyBrowser = $true
  $ok = & $b.test
  if ($ok) { Write-Host ("  {0,-8} PROTECTED" -f $name) -ForegroundColor Green }
  else { Write-Host ("  {0,-8} NOT LOADED" -f $name) -ForegroundColor Red; $anyBad = $true }
}

Write-Host ''
if (-not $anyBrowser) { Write-Host 'No supported browsers found.' -ForegroundColor Yellow; exit 1 }
if ($anyBad) {
  Write-Host 'Some browsers are not protected.' -ForegroundColor Yellow
  Write-Host '  - Close the browser COMPLETELY and reopen it, then re-run this check.'
  Write-Host '  - Chrome: chrome://extensions -> Developer mode -> Load unpacked -> ' -NoNewline; Write-Host $EXTDIR
  Write-Host '  - Firefox: re-run install-all.ps1 as Administrator.'
  exit 1
}
Write-Host 'All installed browsers are protected.' -ForegroundColor Green
exit 0
