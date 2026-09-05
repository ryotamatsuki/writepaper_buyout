$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cache = Join-Path $root ".tex-cache"

if (-not (Test-Path $cache)) {
    New-Item -ItemType Directory -Path $cache | Out-Null
}

$env:TEXMFCACHE = $cache
$env:TEXMFVAR = $cache
$env:LUAOTFLOAD_CACHE = $cache

Push-Location $root
try {
    & lualatex -interaction=nonstopmode -halt-on-error paper_explanation_math.tex
    & lualatex -interaction=nonstopmode -halt-on-error paper_explanation_math.tex
}
finally {
    Pop-Location
}
