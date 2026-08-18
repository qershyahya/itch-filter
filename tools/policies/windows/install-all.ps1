# Windows installer for the itch.io Content Filter — all browsers, no Git Bash needed.
# Run in an ELEVATED PowerShell:   powershell -ExecutionPolicy Bypass -File install-all.ps1
#
#   Firefox            -> force-installed via distribution\policies.json (enforced)
#   Chrome/Edge/Opera  -> auto-loaded via --load-extension on their shortcuts (deterrent)
#
# Downloads the current extension from GitHub, so re-running installs the latest.
$ErrorActionPreference = 'Continue'
$REPO    = 'qershyahya/itch-filter'
$BRANCH  = 'main'
$GECKO   = 'itch-filter@qershyahya'
$XPI     = "https://raw.githubusercontent.com/$REPO/$BRANCH/itch-filter.xpi"
# Machine-wide so every user profile resolves the same path (and so it works the
# same whether launched as the user, elevated, or by a deployment tool).
$EXTDIR  = Join-Path $env:ProgramData 'itch-filter\extension'

function Say($m){ Write-Host "`n=== $m ===" }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

# ---------- 1. download the extension ----------
Say 'Downloading extension'
$tmp = Join-Path $env:TEMP ('itchf-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$zip = Join-Path $tmp 'repo.zip'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest "https://github.com/$REPO/archive/refs/heads/$BRANCH.zip" -OutFile $zip -UseBasicParsing
  Expand-Archive $zip -DestinationPath $tmp -Force
  $src = Join-Path $tmp "itch-filter-$BRANCH\itch-filter-extension"
  New-Item -ItemType Directory -Path $EXTDIR -Force | Out-Null
  Copy-Item "$src\*" $EXTDIR -Force -Recurse
  Write-Host "Extension -> $EXTDIR"
} catch { Write-Host "!! download failed: $($_.Exception.Message)"; exit 1 }
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# ---------- 2. Firefox: force-install (enforced) ----------
Say 'Firefox'
$ffDirs = @("$env:ProgramFiles\Mozilla Firefox", "${env:ProgramFiles(x86)}\Mozilla Firefox") | Where-Object { Test-Path $_ }
if (-not $ffDirs) { Write-Host 'Firefox not installed — skipped.' }
elseif (-not $isAdmin) { Write-Host 'Firefox found but NOT elevated — re-run as Administrator to force-install.' }
else {
  $policy = @{ policies = @{ ExtensionSettings = @{ "$GECKO" = @{ installation_mode = 'force_installed'; install_url = $XPI } } } }
  foreach ($d in $ffDirs) {
    $dist = Join-Path $d 'distribution'
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    # NOTE: must be BOM-less UTF-8 — Windows PowerShell's -Encoding UTF8 adds a BOM
    # and Firefox then silently ignores the whole policy file.
    [IO.File]::WriteAllText((Join-Path $dist 'policies.json'),
                            ($policy | ConvertTo-Json -Depth 6),
                            (New-Object Text.UTF8Encoding $false))
    Write-Host "wrote $dist\policies.json  (force-installed)"
  }
}

# ---------- 3. Chromium browsers: --load-extension on shortcuts ----------
Say 'Chromium browsers (Chrome / Edge / Opera / Brave / Vivaldi)'
$flag    = "--load-extension=$EXTDIR"
$targets = 'chrome','msedge','opera','launcher','brave','vivaldi'   # opera's exe is launcher.exe on some builds
# Scan every real user profile too, so an elevated/SYSTEM run still patches the
# shortcuts that the actual users click.
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
        $lnk.Save()
        Write-Host "patched: $($_.Name)"
        $patched++
      }
    } catch {}
  }
}
if ($patched -eq 0) { Write-Host 'No Chromium shortcuts found to patch.' } else { Write-Host "$patched shortcut(s) patched." }

Say 'Done'
Write-Host 'Restart any open browsers to apply.'
Write-Host 'Firefox is enforced. Chromium loading is a deterrent (an admin can remove the flag).'
