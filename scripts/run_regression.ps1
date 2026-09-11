param(
    [switch]$SkipCpp,
    [switch]$Quartus,
    [switch]$KeepWork
)

$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repository 'build'
$rtlWork = Join-Path $buildRoot 'rtl-regression'
$cppBuild = Join-Path $buildRoot 'unified-cpp-ninja'

function Require-Command([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command -and $Name -eq 'quartus_sh') {
        $configured = if ($env:QUARTUS_ROOTDIR) {
            Join-Path $env:QUARTUS_ROOTDIR 'bin64/quartus_sh.exe'
        } else { '' }
        $fallback = if ($configured -and (Test-Path -LiteralPath $configured)) {
            Get-Item -LiteralPath $configured
        } else {
            Get-ChildItem 'C:/intelFPGA*' -Recurse -Filter quartus_sh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($fallback) {
            return $fallback.FullName
        }
    }
    if (-not $command) {
        throw "Required tool is not available: $Name"
    }
    return $command.Source
}

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed with exit code $LASTEXITCODE"
    }
}

& (Join-Path $PSScriptRoot 'generate_protocol.ps1') -Check

$vlib = Require-Command 'vlib'
$vlog = Require-Command 'vlog'
$vsim = Require-Command 'vsim'

if (Test-Path -LiteralPath $rtlWork) {
    $resolvedBuild = [System.IO.Path]::GetFullPath($buildRoot)
    $resolvedWork = [System.IO.Path]::GetFullPath($rtlWork)
    if (-not $resolvedWork.StartsWith($resolvedBuild,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean an RTL work directory outside build: $resolvedWork"
    }
    Remove-Item -LiteralPath $rtlWork -Recurse -Force
}

New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Invoke-Checked $vlib @($rtlWork)

$rtlSources = Get-ChildItem (Join-Path $repository 'rtl') -Recurse |
    Where-Object { $_.Extension -in '.sv', '.v' } |
    Sort-Object FullName |
    ForEach-Object FullName
$testSources = Get-ChildItem (Join-Path $repository 'sim') -Filter '*_tb.sv' |
    Sort-Object FullName |
    ForEach-Object FullName
$includeArgument = '+incdir+' + (Join-Path $repository 'rtl/common')
Invoke-Checked $vlog (@('-work', $rtlWork, '-sv', '-mfcu', $includeArgument) +
    $rtlSources + $testSources)

$tests = $testSources | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) }
$passed = 0
foreach ($test in $tests) {
    $output = & $vsim -c -L altera_mf -lib $rtlWork $test -do 'onerror {quit -code 1}; run -all; quit -code 0' 2>&1
    $failed = $LASTEXITCODE -ne 0 -or
              ($output -match '(?im)^# \*\* (Fatal|Error):')
    if ($failed) {
        $output | ForEach-Object { Write-Host $_ }
        throw "RTL test failed: $test"
    }
    $passLine = $output | Select-String -Pattern 'PASS' | Select-Object -Last 1
    if (-not $passLine) {
        throw "RTL test ended without a PASS marker: $test"
    }
    Write-Host "PASS $test"
    $passed++
}

$cppSummary = 'protocol check'
if (-not $SkipCpp) {
    $cmake = Require-Command 'cmake'
    $compiler = Require-Command 'clang++'
    $ninjaCommand = Get-Command 'ninja' -ErrorAction SilentlyContinue
    if ($ninjaCommand) {
        $ninja = $ninjaCommand.Source
    } else {
        $ninja = Get-ChildItem 'C:/Program Files/Microsoft Visual Studio' -Recurse -Filter ninja.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $ninja) {
        throw 'Ninja is required for the C++ regression build'
    }
    Invoke-Checked $cmake @('-S', $repository, '-B', $cppBuild, '-G', 'Ninja',
                            "-DCMAKE_MAKE_PROGRAM=$ninja",
                            "-DCMAKE_CXX_COMPILER=$compiler",
                            '-DCMAKE_BUILD_TYPE=Release')
    Invoke-Checked $cmake @('--build', $cppBuild)
    Invoke-Checked 'ctest' @('--test-dir', $cppBuild, '--output-on-failure')
    $cppSummary = 'protocol and C++ checks'
}

if ($Quartus) {
    $quartusExecutable = Require-Command 'quartus_sh'
    $temporaryDrive = 'X:'
    if (Test-Path "$temporaryDrive/") {
        throw "$temporaryDrive is already in use; cannot create the Quartus path alias"
    }
    & subst $temporaryDrive $repository
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the temporary Quartus path alias'
    }
    try {
        Invoke-Checked $quartusExecutable @('--flow', 'compile',
            "$temporaryDrive/Graphics.qpf")
        & (Join-Path $PSScriptRoot 'update_build_stats.ps1')
    } finally {
        & subst $temporaryDrive /D
    }
}

if (-not $KeepWork) {
    Remove-Item -LiteralPath $rtlWork -Recurse -Force
}

Write-Host "Regression passed: $passed RTL tests plus $cppSummary."
