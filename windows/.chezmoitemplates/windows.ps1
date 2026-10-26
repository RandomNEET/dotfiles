$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:BackupRoot = $null

function Get-Entry([string]$Path) {
    # Get-Item also sees dangling junctions, unlike Test-Path.
    Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Test-Reparse($Entry) {
    return (($Entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-BackupRoot {
    if (-not $script:BackupRoot) {
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfff') + '-' + [guid]::NewGuid().ToString('N')
        $script:BackupRoot = Join-Path $DotfilesHome ".local/state/dotfiles/backups/$stamp"
        New-Item -ItemType Directory -Path $script:BackupRoot -Force | Out-Null
    }
    return $script:BackupRoot
}

function Save-Conflict([string]$Path, [string]$MigrationTarget = '') {
    $entry = Get-Entry $Path
    if (-not $entry) { return $null }
    $root = Get-BackupRoot
    $id = [guid]::NewGuid().ToString('N')
    $destination = Join-Path $root $id
    # Rename on the original volume: never traverse a junction while backing up.
    if ([IO.Path]::GetPathRoot($Path) -ne [IO.Path]::GetPathRoot($root)) {
        $destination = $Path + '.dotfiles-backup-' + $id
    }
    $record = [ordered]@{ Original = $Path; Backup = $destination; ReparsePoint = (Test-Reparse $entry) }
    if (Test-Reparse $entry) { $record['Target'] = @($entry.Target) }
    # Write the recovery mapping before moving; a failed move leaves the source intact.
    $record | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $root 'manifest.jsonl') -Encoding UTF8
    if ($MigrationTarget) {
        $journal = Join-Path $DotfilesHome '.local/state/dotfiles/migrations'
        New-Item -ItemType Directory -Path $journal -Force | Out-Null
        [ordered]@{ Original = $Path; Backup = $destination; Target = $MigrationTarget } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $journal ($id + '.json')) -Encoding UTF8
    }
    if ($entry.PSIsContainer) {
        [IO.Directory]::Move($Path, $destination)
    } else {
        [IO.File]::Move($Path, $destination)
    }
    Write-Host "Backed up $Path -> $destination"
    return $destination
}

function Ensure-Directory([string]$Path) {
    $entry = Get-Entry $Path
    if ($entry -and ((Test-Reparse $entry) -or -not $entry.PSIsContainer)) {
        Save-Conflict $Path | Out-Null
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-UnmanagedTree([string]$From, [string]$To, [string]$OriginalFrom = $From) {
    foreach ($item in Get-ChildItem -LiteralPath $From -Force) {
        $destination = Join-Path $To $item.Name
        $existing = Get-Entry $destination
        if (Test-Reparse $item) {
            if (-not $existing) {
                $kind = if ($item.LinkType -eq 'Junction') { 'Junction' } else { 'SymbolicLink' }
                $target = [string]@($item.Target)[0]
                if (-not [IO.Path]::IsPathRooted($target)) {
                    $target = [IO.Path]::GetFullPath((Join-Path $OriginalFrom $target))
                }
                New-Item -ItemType $kind -Path $destination -Target $target | Out-Null
            }
        } elseif ($item.PSIsContainer) {
            if (-not $existing) {
                New-Item -ItemType Directory -Path $destination | Out-Null
            }
            if (-not $existing -or ($existing.PSIsContainer -and -not (Test-Reparse $existing))) {
                Copy-UnmanagedTree $item.FullName $destination (Join-Path $OriginalFrom $item.Name)
            }
        } elseif (-not $existing) {
            $temporary = $destination + '.dotfiles-copy-' + [guid]::NewGuid().ToString('N')
            try {
                Copy-Item -LiteralPath $item.FullName -Destination $temporary
                [IO.File]::Move($temporary, $destination)
            } finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
            }
        }
        # Existing .config content wins here; managed files are applied afterwards.
        # Both originals remain available in the backup if their contents differ.
    }
}

function Resume-Migrations {
    $journal = Join-Path $DotfilesHome '.local/state/dotfiles/migrations'
    if (-not (Test-Path -LiteralPath $journal)) { return }
    foreach ($pending in Get-ChildItem -LiteralPath $journal -Filter '*.json') {
        $migration = Get-Content -Raw -LiteralPath $pending.FullName | ConvertFrom-Json
        if (-not (Get-Entry $migration.Backup)) {
            if (Get-Entry $migration.Original) {
                # The journal was saved but the rename never happened.
                Remove-Item -LiteralPath $pending.FullName
                continue
            }
            throw "Migration source is missing: $($migration.Backup)"
        }
        Ensure-Directory $migration.Target
        Copy-UnmanagedTree $migration.Backup $migration.Target $migration.Original
        # Finish the same-volume rename by restoring the application's path as a junction.
        if (-not (Get-Entry $migration.Original)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $migration.Original) -Force | Out-Null
            New-Item -ItemType Junction -Path $migration.Original -Target $migration.Target | Out-Null
        }
        Remove-Item -LiteralPath $pending.FullName
    }
}

function Migrate-LinkDirectory([string]$Path, [string]$Target) {
    $entry = Get-Entry $Path
    if (-not $entry) { return }
    if (-not $entry.PSIsContainer -or (Test-Reparse $entry)) {
        Save-Conflict $Path | Out-Null
        return
    }
    Save-Conflict $Path $Target | Out-Null
    Resume-Migrations
}

function Test-CorrectLink([string]$Path, [string]$Target) {
    $entry = Get-Entry $Path
    if (-not $entry -or -not (Test-Reparse $entry) -or -not $entry.PSIsContainer) { return $false }
    $actual = [string]@($entry.Target)[0]
    if (-not $actual) { return $false }
    if (-not [IO.Path]::IsPathRooted($actual)) { $actual = Join-Path (Split-Path -Parent $Path) $actual }
    return [IO.Path]::GetFullPath($actual).TrimEnd('\') -ieq [IO.Path]::GetFullPath($Target).TrimEnd('\')
}

function Get-DotfilesLinks {
    @(
        @{ Path = (Join-Path $ScoopRoot 'persist'); Target = (Join-Path $DotfilesHome '.config') },
        @{ Path = (Join-Path $env:LOCALAPPDATA 'nvim'); Target = (Join-Path $DotfilesHome '.config/nvim') },
        @{ Path = (Join-Path $env:APPDATA 'nushell'); Target = (Join-Path $DotfilesHome '.config/nushell') },
        @{ Path = (Join-Path $DotfilesHome '.glzr/glazewm'); Target = (Join-Path $DotfilesHome '.config/glazewm') }
    )
}

function Install-DotfilesPackages {
    $packages = Get-Content -Raw -LiteralPath (Join-Path $DotfilesSource 'dot_config/scoop/packages.json') | ConvertFrom-Json
    foreach ($bucket in $packages.buckets) {
        if (-not (Test-Path -LiteralPath (Join-Path $ScoopRoot "buckets/$($bucket.Name)"))) {
            $global:LASTEXITCODE = 0
            & scoop bucket add $bucket.Name $bucket.Source
            if ($LASTEXITCODE -ne 0) { throw "Adding bucket $($bucket.Name) failed." }
        }
    }
    foreach ($app in $packages.apps) {
        if (-not (Test-Path -LiteralPath (Join-Path $ScoopRoot "apps/$($app.Name)/current"))) {
            $global:LASTEXITCODE = 0
            & scoop install "$($app.Source)/$($app.Name)"
            if ($LASTEXITCODE -ne 0) { throw "Installing $($app.Name) failed." }
        }
    }
}

function Prepare-Dotfiles {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows configuration requires native Windows.' }
    # Refuse a reverse .config -> persist link, which would create a cycle.
    $config = Get-Entry (Join-Path $DotfilesHome '.config')
    if ($config -and (Test-Reparse $config)) {
        throw 'Resolve the existing .config directory link into a real directory before migrating persist.'
    }
    foreach ($link in Get-DotfilesLinks) {
        $path = [IO.Path]::GetFullPath($link.Path).TrimEnd('\')
        $target = [IO.Path]::GetFullPath($link.Target).TrimEnd('\')
        if ($path -ieq $target -or $path.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $target.StartsWith($path + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Overlapping link and target paths: $path -> $target"
        }
    }
    Ensure-Directory (Join-Path $DotfilesHome '.config')
    Resume-Migrations
    Install-DotfilesPackages
    foreach ($link in Get-DotfilesLinks) {
        Ensure-Directory $link.Target
        if (Test-CorrectLink $link.Path $link.Target) { continue }
        Migrate-LinkDirectory $link.Path $link.Target
    }
    # Resolve conflicting directory ancestors first, without following links.
    $directories = @(& chezmoi --source $DotfilesSource --destination $DotfilesHome managed --include dirs --path-style absolute)
    if ($LASTEXITCODE -ne 0) { throw 'Listing managed directories failed.' }
    foreach ($directory in $directories) {
        Ensure-Directory $directory
    }
    $files = @(& chezmoi --source $DotfilesSource --destination $DotfilesHome managed --include files --path-style absolute)
    if ($LASTEXITCODE -ne 0) { throw 'Listing managed files failed.' }
    $scratch = [IO.Path]::GetTempFileName()
    try {
        foreach ($file in $files) {
            $entry = Get-Entry $file
            if (-not $entry) { continue }
            & chezmoi --source $DotfilesSource --destination $DotfilesHome cat --output $scratch $file
            if ($LASTEXITCODE -ne 0) { throw "Rendering $file failed." }
            if ((Test-Reparse $entry) -or $entry.PSIsContainer -or
                ((Get-FileHash -LiteralPath $file).Hash -ne (Get-FileHash -LiteralPath $scratch).Hash)) {
                Save-Conflict $file | Out-Null
            }
        }
    } finally {
        Remove-Item -LiteralPath $scratch
    }
}

function Connect-Dotfiles {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows configuration requires native Windows.' }
    foreach ($link in Get-DotfilesLinks) {
        if (Test-CorrectLink $link.Path $link.Target) { continue }
        # A new conflicting entry after preparation needs another apply, not data loss.
        if (Get-Entry $link.Path) { throw "Path changed during apply: $($link.Path). Retry chezmoi apply." }
        New-Item -ItemType Directory -Path (Split-Path -Parent $link.Path) -Force | Out-Null
        New-Item -ItemType Junction -Path $link.Path -Target $link.Target | Out-Null
        Write-Host "$($link.Path) -> $($link.Target)"
    }
}
