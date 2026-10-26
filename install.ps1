[CmdletBinding()]
param(
    [string]$Repository = $(if ($env:DOTFILES_REPO) { $env:DOTFILES_REPO } else { 'https://github.com/RandomNEET/dotfiles' }),
    [string]$RepositoryDirectory = $env:DOTFILES_DIR,
    [switch]$SkipUpdate
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -eq 'Windows_NT') {
    $platform = 'windows'
} else {
    throw 'Unsupported PowerShell environment. Use install.sh in Termux, or native Windows.'
}
if (-not $RepositoryDirectory) {
    $RepositoryDirectory = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git')) {
        $PSScriptRoot
    } else {
        Join-Path $HOME '.local/share/dotfiles'
    }
}
$bootstrap = Join-Path $PSScriptRoot "$platform/install.ps1"
if (-not (Test-Path -LiteralPath $bootstrap)) {
    $bootstrap = Join-Path $RepositoryDirectory "$platform/install.ps1"
}
$temporary = $null
try {
    if (-not (Test-Path -LiteralPath $bootstrap)) {
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-' + [guid]::NewGuid() + '.ps1')
        Invoke-WebRequest "https://raw.githubusercontent.com/RandomNEET/dotfiles/main/$platform/install.ps1" -UseBasicParsing -OutFile $temporary
        $bootstrap = $temporary
    }
    # Scoop and other prerequisites are entirely handled by the selected platform.
    & $bootstrap -PrepareOnly
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryDirectory '.git'))) {
        New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($RepositoryDirectory))) -Force | Out-Null
        & git clone $Repository $RepositoryDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Cloning dotfiles failed.' }
    } elseif (-not $SkipUpdate) {
        & git -C $RepositoryDirectory pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw 'Fast-forward failed; resolve the repository state before retrying.' }
    }
    & git -C $RepositoryDirectory config --local pull.ff only
    if ($LASTEXITCODE -ne 0) { throw 'Setting repository update policy failed.' }
    & (Join-Path $RepositoryDirectory "$platform/install.ps1")
} finally {
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary }
}
