$ErrorActionPreference = "Stop"

$candidates = @(
  "lua",
  "lua5.1",
  "luajit"
)

$lua = $null
foreach ($candidate in $candidates) {
  $command = Get-Command $candidate -ErrorAction SilentlyContinue
  if ($command) {
    $lua = $command.Source
    break
  }
}

if (-not $lua) {
  Write-Error "No Lua interpreter found. Install Lua 5.1 or LuaJIT, then run this script again."
}

& $lua "TwAuras/tests/run.lua"
