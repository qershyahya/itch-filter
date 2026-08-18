# itch.io Safeguard Filter - Windows uninstaller.
# Run in an ELEVATED PowerShell:
#     powershell -ExecutionPolicy Bypass -File uninstall-all.ps1
#
# Removes: Firefox force-install policy, the --load-extension flag from every
# patched shortcut, the extension payload, and any leftover Chrome policy keys.
# Chrome's manually loaded copy must be removed from chrome://extensions by hand
# (Chrome does not let a script remove a user-installed extension).
$ErrorActionPreference = 'Continue'
$GECKO   = 'itch-filter@qershyahya'
$EXTROOT = Join-Path $env:ProgramData 'itch-filter'
$OURID   = 'innfmidphklblkkbhnhhpjkfplbomale'

function Say($m){ Write-Host "`n=== $m ===" -ForegroundColor Cyan }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) { Write-Host 'Run as Administrator.' -ForegroundColor Red; exit 1 }

# ---------- Firefox: drop the policy so the add-on is uninstalled ----------
Say 'Firefox'
$removed = 0
foreach ($d in @("$env:ProgramFiles\Mozilla Firefox", "${env:ProgramFiles(x86)}\Mozilla Firefox")) {
  $f = Join-Path $d 'distribution\policies.json'
  if (Test-Path $f) {
    $c = Get-Content $f -Raw -EA SilentlyContinue
    if ($c -like "*$GECKO*") { Remove-Item $f -Force; Write-Host "removed $f"; $removed++ }
    else { Write-Host "left alone (not ours): $f" }
  }
}
if ($removed -eq 0) { Write-Host 'no Firefox policy found.' }
else { Write-Host 'Restart Firefox once - it will uninstall the add-on automatically.' }

# ---------- shortcuts: strip the --load-extension flag ----------
Say 'Shortcuts'
$roots = @(
  (Join-Path $env:APPDATA     'Microsoft\Windows\Start Menu\Programs'),
  (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
  (Join-Path $env:USERPROFILE 'Desktop'),
  (Join-Path $env:PUBLIC      'Desktop')
)
Get-ChildItem 'C:\Users' -Directory -EA SilentlyContinue |
  Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' } |
  ForEach-Object {
    $roots += (Join-Path $_.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs')
    $roots += (Join-Path $_.FullName 'Desktop')
    $roots += (Join-Path $_.FullName 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
  }
$roots = $roots | Select-Object -Unique | Where-Object { Test-Path $_ }
$sh = New-Object -ComObject WScript.Shell
$fixed = 0
foreach ($r in $roots) {
  Get-ChildItem $r -Recurse -Filter *.lnk -EA SilentlyContinue | ForEach-Object {
    try {
      $lnk = $sh.CreateShortcut($_.FullName)
      if ($lnk.Arguments -like '*--load-extension*') {
        $lnk.Arguments = (($lnk.Arguments -replace '--load-extension=[^"]*itch-filter[^"\s]*','') -replace '\s+',' ').Trim()
        $lnk.Save(); Write-Host "cleaned: $($_.Name)"; $fixed++
      }
    } catch {}
  }
}
if ($fixed -eq 0) { Write-Host 'no patched shortcuts found.' } else { Write-Host "$fixed shortcut(s) cleaned." }

# ---------- leftover Chrome policy / external-install keys ----------
Say 'Registry'
$fl = 'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist'
if (Test-Path $fl) {
  (Get-ItemProperty $fl).PSObject.Properties |
    Where-Object { $_.Name -match '^[0-9]+$' -and $_.Value -like "*$OURID*" } |
    ForEach-Object { Remove-ItemProperty $fl -Name $_.Name -Force; Write-Host "removed forcelist entry $($_.Name)" }
}
foreach ($k in @("HKLM:\SOFTWARE\Google\Chrome\Extensions\$OURID",
                 "HKLM:\SOFTWARE\Wow6432Node\Google\Chrome\Extensions\$OURID")) {
  if (Test-Path $k) { Remove-Item $k -Recurse -Force; Write-Host "removed $k" }
}

# ---------- payload ----------
Say 'Files'
if (Test-Path $EXTROOT) { Remove-Item $EXTROOT -Recurse -Force -EA SilentlyContinue; Write-Host "removed $EXTROOT" }
else { Write-Host 'no payload folder.' }

Say 'Done'
Write-Host 'Firefox/Edge/Opera are clean after the next full restart of each browser.'
Write-Host 'Chrome: open chrome://extensions and click Remove on "itch.io Safeguard Filter"'
Write-Host '        (a script cannot remove a manually loaded extension).'
