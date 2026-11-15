# Atomic Space - compile the mission engine for Node.js and run its tests.
#
#   powershell -ExecutionPolicy Bypass -File scripts\test.ps1
#
# Needs: the pas2js compiler (run scripts\setup.ps1 once) and Node.js.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pas2js = Get-ChildItem -Path (Join-Path $root 'tools\pas2js') -Recurse -Filter 'pas2js.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pas2js) { throw 'pas2js not found. Run scripts\setup.ps1 first.' }

$out = Join-Path $root 'tests\out'
New-Item -ItemType Directory -Force $out | Out-Null
$js = Join-Path $out 'coretests.js'

$opts = @(
  '-Tnodejs', '-Jc', '-Jirtl.js', '-vw', '-l-',
  "-Fu$(Join-Path $root 'src\core')",
  "-FU$out",
  "-o$js",
  (Join-Path $root 'tests\coretests.lpr')
)
& $pas2js.FullName @opts
if ($LASTEXITCODE -ne 0) { throw "Compile failed (exit $LASTEXITCODE)" }

& node $js
exit $LASTEXITCODE
