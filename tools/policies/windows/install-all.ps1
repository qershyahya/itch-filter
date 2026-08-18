# itch.io Safeguard Filter — Windows installer (all browsers, no Git Bash needed).
# Run in an ELEVATED PowerShell:
#     powershell -ExecutionPolicy Bypass -File install-all.ps1
#
#   -Browsers all|firefox,chrome,edge,opera   which browsers to install into (default: all)
#   -Quiet                                    skip the interactive menu, use -Browsers
#
#   Firefox            -> force-installed via distribution\policies.json (enforced)
#   Chrome/Edge/Opera  -> auto-loaded via --load-extension on their shortcuts (deterrent)
#
# After installing, each selected browser opens a welcome page confirming the filter
# is active. Re-run any time to update to the latest published version.
param(
  [string]$Browsers = '',
  [switch]$Quiet
)
$ErrorActionPreference = 'Continue'
$REPO   = 'qershyahya/itch-filter'
$BRANCH = 'main'
$GECKO  = 'itch-filter@qershyahya'
$XPI    = "https://raw.githubusercontent.com/$REPO/$BRANCH/itch-filter.xpi"
$EXTDIR = Join-Path $env:ProgramData 'itch-filter\extension'
$WELCOME = Join-Path $env:ProgramData 'itch-filter\welcome.html'

function Say($m){ Write-Host "`n=== $m ===" -ForegroundColor Cyan }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

# ---------- detect installed browsers ----------
$paths = [ordered]@{
  firefox = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe")
  chrome  = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
  edge    = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")
  opera   = @("$env:LOCALAPPDATA\Programs\Opera\opera.exe", "$env:ProgramFiles\Opera\opera.exe", "${env:ProgramFiles(x86)}\Opera\opera.exe")
}
$found = [ordered]@{}
foreach ($k in $paths.Keys) {
  $hit = $paths[$k] | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $hit -and $k -eq 'opera') {
    # Opera installs per-version under Programs\Opera\<ver>\opera.exe on some builds
    $hit = Get-ChildItem "$env:LOCALAPPDATA\Programs\Opera" -Recurse -Filter opera.exe -ErrorAction SilentlyContinue |
             Select-Object -First 1 -ExpandProperty FullName
  }
  if ($hit) { $found[$k] = $hit }
}

Say 'Detected browsers'
if ($found.Count -eq 0) { Write-Host 'No supported browser found. Nothing to do.'; exit 1 }
foreach ($k in $found.Keys) { Write-Host ("  [{0}] {1}" -f $k, $found[$k]) }

# ---------- choose targets ----------
$selected = @()
if ($Browsers) {
  if ($Browsers -eq 'all') { $selected = @($found.Keys) }
  else { $selected = $Browsers.Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $found.Contains($_) } }
} elseif ($Quiet) {
  $selected = @($found.Keys)
} else {
  Write-Host "`nInstall into which browsers?"
  Write-Host "  [Enter] = ALL detected (recommended, system-wide)"
  Write-Host "  or type names separated by commas, e.g. firefox,chrome"
  $ans = Read-Host 'Choice'
  if ([string]::IsNullOrWhiteSpace($ans)) { $selected = @($found.Keys) }
  else { $selected = $ans.Split(',') | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $found.Contains($_) } }
}
if ($selected.Count -eq 0) { Write-Host 'Nothing selected. Exiting.'; exit 1 }
Write-Host ("`nInstalling into: " + ($selected -join ', '))

# ---------- download the extension ----------
Say 'Downloading extension'
$tmp = Join-Path $env:TEMP ('itchf-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $zip = Join-Path $tmp 'repo.zip'
  Invoke-WebRequest "https://github.com/$REPO/archive/refs/heads/$BRANCH.zip" -OutFile $zip -UseBasicParsing
  Expand-Archive $zip -DestinationPath $tmp -Force
  New-Item -ItemType Directory -Path $EXTDIR -Force | Out-Null
  Copy-Item (Join-Path $tmp "itch-filter-$BRANCH\itch-filter-extension\*") $EXTDIR -Force -Recurse
  Write-Host "Extension -> $EXTDIR"
} catch { Write-Host "!! download failed: $($_.Exception.Message)"; exit 1 }
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# ---------- welcome page ----------
@'
<!doctype html><meta charset="utf-8"><title>itch.io Safeguard Filter</title>
<style>body{background:#1b1733;color:#f4f1e8;font:16px/1.6 system-ui,sans-serif;display:flex;
align-items:center;justify-content:center;height:100vh;margin:0}
.card{max-width:620px;text-align:center;padding:32px}
h1{color:#ffc247;font-size:30px;margin:0 0 8px}.ok{font-size:52px}
p{color:#d9d2f0}small{color:#a99fce}</style>
<div class="card"><div class="ok">&#10004;</div>
<h1>itch.io Safeguard Filter installed</h1>
<p>This browser is now protected. Games, jams, assets, devlogs and comments on
itch.io are checked before they are shown, and blocked content is hidden.</p>
<p><small>Settings are protected by a secret key held by the administrator.<br>
Need something unblocked? Contact +20 110 119 6911 &middot; qershyahya@gmail.com</small></p></div>
'@ | Set-Content $WELCOME -Encoding UTF8
$welcomeUrl = ([Uri](New-Object Uri($WELCOME))).AbsoluteUri

# ---------- Firefox ----------
if ($selected -contains 'firefox') {
  Say 'Firefox'
  if (-not $isAdmin) { Write-Host 'NOT elevated — re-run as Administrator to force-install into Firefox.' }
  else {
    $policy = @{ policies = @{ ExtensionSettings = @{ "$GECKO" = @{ installation_mode = 'force_installed'; install_url = $XPI } } } }
    $dist = Join-Path (Split-Path $found['firefox']) 'distribution'
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    # must be BOM-less UTF-8 — a BOM makes Firefox silently ignore the policy file
    [IO.File]::WriteAllText((Join-Path $dist 'policies.json'),
                            ($policy | ConvertTo-Json -Depth 6),
                            (New-Object Text.UTF8Encoding $false))
    Write-Host "force-installed via $dist\policies.json"
  }
}

# ---------- Chromium browsers ----------
$chromium = $selected | Where-Object { $_ -ne 'firefox' }
if ($chromium) {
  Say ('Chromium browsers: ' + ($chromium -join ', '))
  $exeFor = @{ chrome = 'chrome'; edge = 'msedge'; opera = @('opera','launcher') }
  $targets = @(); foreach ($c in $chromium) { $targets += $exeFor[$c] }
  $flag = "--load-extension=$EXTDIR"

  $roots = @(
    (Join-Path $env:APPDATA     'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:PUBLIC      'Desktop')
  )
  Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' } |
    ForEach-Object {
      $roots += (Join-Path $_.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs')
      $roots += (Join-Path $_.FullName 'Desktop')
      # taskbar pins are the launch point most people actually click
      $roots += (Join-Path $_.FullName 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    }
  $roots = $roots | Select-Object -Unique | Where-Object { Test-Path $_ }

  $sh = New-Object -ComObject WScript.Shell
  $patched = 0
  foreach ($r in $roots) {
    Get-ChildItem $r -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $lnk = $sh.CreateShortcut($_.FullName)
        $exe = [IO.Path]::GetFileNameWithoutExtension($lnk.TargetPath).ToLower()
        if (($targets -contains $exe) -and ($lnk.Arguments -notlike '*--load-extension*')) {
          $lnk.Arguments = ($lnk.Arguments + ' ' + $flag).Trim()
          $lnk.Save(); Write-Host "patched: $($_.Name)"; $patched++
        }
      } catch {}
    }
  }
  if ($patched -eq 0) { Write-Host 'No shortcuts needed patching (already done, or none found).' }
  else { Write-Host "$patched shortcut(s) patched." }
}

# ---------- show the welcome page in each selected browser ----------
# NOTE: --load-extension is ignored if that browser is ALREADY running (the new
# window just attaches to the existing process). Close them first, or the filter
# will appear "not installed" until the next full restart of the browser.
Say 'Opening welcome page'
foreach ($b in $selected) {
  $proc = @{ chrome='chrome'; edge='msedge'; opera='opera'; firefox='firefox' }[$b]
  if (Get-Process $proc -ErrorAction SilentlyContinue) {
    Write-Host "NOTE: $b is running — close ALL its windows and re-open it, or the extension will not load." -ForegroundColor Yellow
  }
}
foreach ($b in $selected) {
  try {
    if ($b -eq 'firefox') { Start-Process $found[$b] -ArgumentList $welcomeUrl }
    else { Start-Process $found[$b] -ArgumentList "--load-extension=$EXTDIR", $welcomeUrl }
    Write-Host "opened in $b"
    Start-Sleep -Seconds 2
  } catch { Write-Host "could not open $b : $($_.Exception.Message)" }
}

Say 'Done'
Write-Host 'Firefox is enforced. Chromium loading is a deterrent (an admin can remove the flag).'
Write-Host 'Re-run this script any time to update to the latest published version.'
