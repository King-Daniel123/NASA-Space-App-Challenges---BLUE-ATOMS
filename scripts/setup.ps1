# Atomic Space - one-time setup: fetch the pas2js compiler.
#
#   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#
# pas2js is the free, open-source Object Pascal to JavaScript compiler from the
# Free Pascal project (https://getpas2js.freepascal.org/). It is the same
# engine that TMS Web Core uses inside Delphi. This script downloads the
# official Windows build (about 13 MB) into tools\pas2js, which git ignores.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dl = Join-Path $root 'tools\_download'
$dest = Join-Path $root 'tools\pas2js'
$url = 'https://getpas2js.freepascal.org/downloads/windows/pas2js-win64-x86_64-current.zip'

$existing = Get-ChildItem -Path $dest -Recurse -Filter 'pas2js.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
  Write-Host "pas2js is already installed: $($existing.FullName)"
  exit 0
}

New-Item -ItemType Directory -Force $dl | Out-Null
New-Item -ItemType Directory -Force $dest | Out-Null
$zip = Join-Path $dl 'pas2js-win64-x86_64-current.zip'

Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $zip
Write-Host 'Unpacking'
Expand-Archive -Path $zip -DestinationPath $dest -Force

$exe = Get-ChildItem -Path $dest -Recurse -Filter 'pas2js.exe' | Select-Object -First 1
if (-not $exe) { throw 'pas2js.exe was not found after unpacking.' }
Write-Host "Ready: $($exe.FullName)"
& $exe.FullName -iV
