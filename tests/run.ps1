param(
  [string]$LuaPath = "",
  [string]$OutputPath = "tests/output/latest-run.txt"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$runLua = Join-Path $scriptDir "run.lua"

if (-not (Test-Path $runLua)) {
  Write-Error "Could not find run.lua at: $runLua"
}

if (-not $LuaPath) {
  $candidates = @(
    "lua",
    "lua5.1",
    "luajit"
  )

  foreach ($candidate in $candidates) {
    $command = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($command) {
      $LuaPath = $command.Source
      break
    }
  }
}

if (-not $LuaPath) {
  Write-Error "No Lua interpreter found. Install Lua 5.1 or LuaJIT, then run this script again."
}

$outputFile = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath
} else {
  Join-Path $repoRoot $OutputPath
}

$outputDir = Split-Path -Parent $outputFile
if ($outputDir -and -not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Push-Location $repoRoot
try {
  & $LuaPath $runLua 2>&1 | Tee-Object -FilePath $outputFile
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}

Write-Host "Saved test output to: $outputFile"
