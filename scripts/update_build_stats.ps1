param([switch]$Check)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$fitPath = Join-Path $repository 'output_files/Graphics.fit.summary'
$timingPath = Join-Path $repository 'output_files/Graphics.sta.summary'
$readmePath = Join-Path $repository 'README.md'

foreach ($path in $fitPath, $timingPath, $readmePath) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required build report is missing: $path"
    }
}

$fit = Get-Content -LiteralPath $fitPath -Raw
$timing = Get-Content -LiteralPath $timingPath -Raw

function Capture([string]$Text, [string]$Pattern, [string]$Label) {
    $match = [regex]::Match($Text, $Pattern, 'Multiline')
    if (-not $match.Success) {
        throw "Could not read $Label from the Quartus report"
    }
    return $match.Groups[1].Value.Trim()
}

$logic = Capture $fit '^Total logic elements\s*:\s*([^\r\n]+)' 'logic elements'
$registers = Capture $fit '^Total registers\s*:\s*([^\r\n]+)' 'registers'
$memory = Capture $fit '^Total memory bits\s*:\s*([^\r\n]+)' 'memory bits'
$multipliers = Capture $fit '^Embedded Multiplier 9-bit elements\s*:\s*([^\r\n]+)' 'multipliers'
$plls = Capture $fit '^Total PLLs\s*:\s*([^\r\n]+)' 'PLLs'
$slackMatch = [regex]::Match($timing,
    "Type\s*:\s*Slow 1200mV 85C Model Setup 'CLOCK_50'[\s\S]*?Slack\s*:\s*([^\r\n]+)")
if (-not $slackMatch.Success) {
    throw 'Could not read the 85 C CLOCK_50 setup slack'
}
$slack = $slackMatch.Groups[1].Value.Trim()

$block = @"
<!-- BUILD_STATS:START -->
- Logic elements: $logic
- Registers: $registers
- Memory bits: $memory
- Embedded 9-bit multipliers: $multipliers
- PLLs: $plls
- Worst 85 C `CLOCK_50` setup slack: $slack ns
<!-- BUILD_STATS:END -->
"@.Replace("`r`n", "`n").TrimEnd()

$readme = (Get-Content -LiteralPath $readmePath -Raw).Replace("`r`n", "`n")
$pattern = '<!-- BUILD_STATS:START -->[\s\S]*?<!-- BUILD_STATS:END -->'
if (-not [regex]::IsMatch($readme, $pattern)) {
    throw 'README.md does not contain BUILD_STATS markers'
}
$updated = [regex]::Replace($readme, $pattern, $block)

if ($Check) {
    if ($updated -ne $readme) {
        throw 'README build statistics are stale; run scripts/update_build_stats.ps1'
    }
    Write-Host 'README build statistics are current.'
} else {
    [System.IO.File]::WriteAllText($readmePath, $updated,
        [System.Text.UTF8Encoding]::new($false))
    Write-Host 'README build statistics updated from Quartus reports.'
}
