param(
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot) 'dist'),

    [string]$InnoCompiler = 'ISCC.exe'
)

$ErrorActionPreference = 'Stop'

function Invoke-ReleaseCommand {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This release script requires Windows with GHC, cabal and Inno Setup.'
}

$workspace = Split-Path $PSScriptRoot
$project = Join-Path $workspace 'apps/git-puller/git-puller.cabal'
$versionFields = @(Select-String -LiteralPath $project -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$')
if ($versionFields.Count -ne 1) {
    throw "Expected exactly one version: MAJOR.MINOR.PATCH field in $project."
}
$Version = $versionFields[0].Matches[0].Groups[1].Value

$null = Get-Command ghc, cabal, git -CommandType Application
$InnoCompiler = @(
    (Get-Command $InnoCompiler -CommandType Application -ErrorAction SilentlyContinue).Source
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $InnoCompiler) {
    throw 'Inno Setup 6 compiler (ISCC.exe) not found. Install it with: winget install JRSoftware.InnoSetup'
}

$compiler = Invoke-ReleaseCommand ghc @('--numeric-version')
if ($compiler -ne '9.10.3') {
    throw "Expected GHC 9.10.3, got $compiler."
}

$architecture, $windowsArchitecture = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64', 'x64os' }
    'ARM64' { 'aarch64', 'arm64' }
    default { throw "Unsupported Windows architecture $env:PROCESSOR_ARCHITECTURE." }
}

$output = (New-Item -Path $OutputDirectory -ItemType Directory -Force).FullName
$staging = Join-Path ([IO.Path]::GetTempPath()) ("git-puller-" + [guid]::NewGuid())
$null = New-Item -Path $staging -ItemType Directory

Push-Location $workspace
try {
    Write-Host '==> Build'
    Invoke-ReleaseCommand cabal @('build', '-O2', 'exe:git-puller')
    $executable = Invoke-ReleaseCommand cabal @('list-bin', '-O2', 'exe:git-puller')

    Write-Host "`n==> Bundle"
    $windowsName = "git-puller-$Version-windows-$architecture"
    $bundle = Join-Path $staging 'bundle'
    $bin = (New-Item -Path (Join-Path $bundle 'bin') -ItemType Directory).FullName
    Copy-Item -LiteralPath $executable -Destination (Join-Path $bin 'git-puller.exe')
    Copy-Item -LiteralPath (Join-Path $workspace 'LICENSE') -Destination $bundle
    Invoke-ReleaseCommand (Join-Path $bin 'git-puller.exe') @('--dry-run', $staging)

    Write-Host "`n==> Package"
    $packaging = Join-Path $PSScriptRoot 'packaging'
    $definition = Join-Path $staging 'windows.iss'
    Copy-Item -LiteralPath (Join-Path $packaging 'windows.iss') -Destination $definition
    @'
Git Puller requires Git for Windows available on PATH.
Open a new terminal after installation and run git-puller with a Windows project path.
'@ | Set-Content -LiteralPath (Join-Path $staging 'requirements.txt') -Encoding Ascii
    Invoke-ReleaseCommand $InnoCompiler @(
        "/DReleaseVersion=$Version",
        "/DReleaseArch=$architecture",
        "/DWindowsArch=$windowsArchitecture",
        "/O$staging",
        $definition
    )
    $zip = Join-Path $staging "$windowsName.zip"
    Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip
    Move-Item -LiteralPath $zip, (Join-Path $staging "$windowsName-setup.exe") -Destination $output -Force
    Write-Host "`nArtifacts written to $output"
} finally {
    Pop-Location
    Remove-Item -LiteralPath $staging -Recurse -Force
}
