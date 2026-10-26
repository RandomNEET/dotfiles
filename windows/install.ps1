[CmdletBinding()]
param([switch]$PrepareOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'This installer requires native Windows.' }

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    # Download first so that network failure cannot execute an incomplete script.
    $installer = Join-Path ([IO.Path]::GetTempPath()) ('scoop-' + [guid]::NewGuid() + '.ps1')
    try {
        Invoke-WebRequest 'https://get.scoop.sh' -UseBasicParsing -OutFile $installer
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } finally {
            $identity.Dispose()
        }
        $installerArguments = @{}
        if ($isElevated) { $installerArguments['RunAsAdmin'] = $true }
        & $installer @installerArguments
        if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw 'Scoop installation failed.' }
    } finally {
        if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer }
    }
}
foreach ($name in @('git', 'chezmoi')) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        $global:LASTEXITCODE = 0
        & scoop install $name
        if ($LASTEXITCODE -ne 0) { throw "scoop install $name failed." }
    }
}
if ($PrepareOnly) { return }
& chezmoi init --source $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'chezmoi init failed.' }
& chezmoi apply
if ($LASTEXITCODE -ne 0) { throw 'chezmoi apply failed. Review the reported error and run chezmoi diff before retrying.' }
