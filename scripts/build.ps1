# TradeSpace - compile the Object Pascal game to JavaScript.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build.ps1
#
# Reads src\tradespace.lpr (and the units in src\core and src\web) and writes
# public\js\tradespace.js. Needs the pas2js compiler: run scripts\setup.ps1 once.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pas2js = Get-ChildItem -Path (Join-Path $root 'tools\pas2js') -Recurse -Filter 'pas2js.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pas2js) { throw 'pas2js not found. Run scripts\setup.ps1 first.' }

$units = Join-Path $root 'build\units'
New-Item -ItemType Directory -Force $units | Out-Null
New-Item -ItemType Directory -Force (Join-Path $root 'public\js') | Out-Null
$js = Join-Path $root 'public\js\tradespace.js'

$opts = @(
  '-Tbrowser',          # target: web browser
  '-Jc',                # one JavaScript file
  '-Jirtl.js',          # include the Pascal run-time library
  '-O1',                # basic optimisation
  '-vw', '-l-',         # show warnings, no banner
  "-Fu$(Join-Path $root 'src\core')",
  "-Fu$(Join-Path $root 'src\web')",
  "-FU$units",
  "-o$js",
  (Join-Path $root 'src\tradespace.lpr')
)
& $pas2js.FullName @opts
if ($LASTEXITCODE -ne 0) { throw "Compile failed (exit $LASTEXITCODE)" }

$size = [math]::Round((Get-Item $js).Length / 1KB)
Write-Host "Built public\js\tradespace.js ($size KB)"
