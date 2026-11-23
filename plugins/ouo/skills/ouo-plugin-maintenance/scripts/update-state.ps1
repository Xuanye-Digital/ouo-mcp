[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Begin', 'Record', 'Failed', 'Notified', 'Snooze', 'Ignore')]
    [string]$Action,
    [Parameter(Mandatory = $true)][string]$StateDirectory,
    [Parameter(Mandatory = $true)][string]$ConfigurationIdentity,
    [Parameter(Mandatory = $true)][string]$SourceIdentity,
    [string]$EvidenceIdentity = 'unknown',
    [string]$LeaseId,
    [string]$ReleaseId,
    [string]$AvailableVersion,
    [string]$CatalogRevision,
    [ValidateSet('update_available', 'up_to_date', 'ahead', 'unknown', 'unsupported_source', 'not_installed')]
    [string]$Comparison = 'unknown',
    [ValidateSet('verified', 'not_checked', 'mismatch')]
    [string]$ContentVerification = 'not_checked',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lock = $null
$temporaryPath = $null

function Get-Hash([string]$Value) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-Instant($Value) {
    if (-not $Value) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}

function Test-Notice($Record, [DateTimeOffset]$Instant) {
    if (-not $Record.releaseId -or -not $Record.availableVersion) { return $false }
    if ($Record.comparison -notin @('update_available', 'unknown') -and $Record.contentVerification -ne 'mismatch') { return $false }
    if ($Record.ignoredVersion -eq $Record.availableVersion) { return $false }
    $snooze = Get-Instant $Record.snoozeUntilUtc
    if ($Record.snoozedReleaseId -eq $Record.releaseId -and $snooze -and $snooze -gt $Instant) { return $false }
    $noticeKey = $Record.releaseId + ':' + $Record.contentVerification
    return $Record.notifiedNoticeKey -ne $noticeKey
}

function Write-State($Record) {
    $script:temporaryPath = Join-Path $directory ('.' + $stateKey + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $text = ($Record | ConvertTo-Json -Depth 5) + [Environment]::NewLine
    [IO.File]::WriteAllText($script:temporaryPath, $text, (New-Object Text.UTF8Encoding($false)))
    if ([IO.File]::Exists($statePath)) {
        [IO.File]::Replace($script:temporaryPath, $statePath, [NullString]::Value)
    } else {
        [IO.File]::Move($script:temporaryPath, $statePath)
    }
    $script:temporaryPath = $null
}

try {
    if (-not [IO.Path]::IsPathRooted($StateDirectory)) { throw 'An absolute host state directory is required.' }
    $directory = [IO.Path]::GetFullPath($StateDirectory)
    $pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($directory -eq $pluginRoot -or $directory.StartsWith($pluginRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'State must be outside the plugin cache.'
    }
    [void][IO.Directory]::CreateDirectory($directory)
    if (([IO.File]::GetAttributes($directory) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'State directory must not be a link.' }
    $stateKey = Get-Hash ($ConfigurationIdentity + "`n" + $SourceIdentity)
    $evidenceKey = Get-Hash $EvidenceIdentity
    $statePath = Join-Path $directory ($stateKey + '.json')
    $lockPath = Join-Path $directory ($stateKey + '.lock')
    foreach ($path in @($statePath, $lockPath)) {
        if ([IO.File]::Exists($path) -and (([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'State files must not be links.' }
    }
    try {
        $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch [IO.IOException] {
        @{ contract = 'ouo-plugin-update-state-v1'; persistence = 'busy'; shouldCheck = $false; shouldNotify = $false } | ConvertTo-Json -Compress
        exit 0
    }
    $state = @{
        schemaVersion = 1; stateKey = $stateKey; evidenceKey = $null
        successfulCheckAtUtc = $null; releaseId = $null; availableVersion = $null
        catalogRevision = $null; comparison = 'unknown'; contentVerification = 'not_checked'
        notifiedNoticeKey = $null; ignoredVersion = $null; snoozedReleaseId = $null; snoozeUntilUtc = $null
        leaseId = $null; leaseUntilUtc = $null
    }
    if ([IO.File]::Exists($statePath)) {
        try {
            if ((Get-Item -LiteralPath $statePath).Length -gt 32768) { throw 'State exceeds its size limit.' }
            $stored = [IO.File]::ReadAllText($statePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($stored.schemaVersion -eq 1 -and $stored.stateKey -eq $stateKey) {
                foreach ($key in @($state.Keys)) {
                    if ($stored.PSObject.Properties.Name -contains $key) { $state[$key] = $stored.$key }
                }
            }
        } catch {
            # A corrupt cache is never evidence of a successful check.
        }
    }
    $now = [DateTimeOffset]::UtcNow
    $reply = @{ contract = 'ouo-plugin-update-state-v1'; persistence = 'file'; shouldCheck = $false; shouldNotify = $false }
    switch ($Action) {
        'Begin' {
            $leaseUntil = Get-Instant $state.leaseUntilUtc
            $lastSuccess = Get-Instant $state.successfulCheckAtUtc
            if ($leaseUntil -and $leaseUntil -gt $now -and ($leaseUntil - $now).TotalSeconds -le 30 -and (-not $lastSuccess -or $lastSuccess -le $now)) {
                $reply.reason = 'in_flight'
            } elseif (-not $Force -and $state.evidenceKey -eq $evidenceKey -and $lastSuccess -and $lastSuccess -le $now -and ($now - $lastSuccess).TotalHours -lt 24) {
                $reply.reason = 'cached'
                $reply.shouldNotify = Test-Notice $state $now
                if ($reply.shouldNotify) {
                    $state.leaseId = [Guid]::NewGuid().ToString('N')
                    $state.leaseUntilUtc = $now.AddSeconds(30).ToString('o')
                    Write-State $state
                }
            } else {
                $state.leaseId = [Guid]::NewGuid().ToString('N')
                $state.leaseUntilUtc = $now.AddSeconds(30).ToString('o')
                Write-State $state
                $reply.reason = 'check'
                $reply.shouldCheck = $true
                $reply.leaseId = $state.leaseId
            }
        }
        'Record' {
            if (-not $LeaseId -or $state.leaseId -ne $LeaseId) { throw 'Check lease is missing or was superseded.' }
            foreach ($value in @($ReleaseId, $AvailableVersion, $CatalogRevision)) {
                if (-not $value -or $value.Length -gt 256 -or $value -notmatch '^[A-Za-z0-9._:+-]+$') { throw 'Invalid public release identity.' }
            }
            $state.successfulCheckAtUtc = $now.ToString('o')
            $state.evidenceKey = $evidenceKey
            $state.releaseId = $ReleaseId
            $state.availableVersion = $AvailableVersion
            $state.catalogRevision = $CatalogRevision
            $state.comparison = $Comparison
            $state.contentVerification = $ContentVerification
            $reply.shouldNotify = Test-Notice $state $now
            if ($reply.shouldNotify) {
                $state.leaseUntilUtc = $now.AddSeconds(30).ToString('o')
            } else {
                $state.leaseId = $null
                $state.leaseUntilUtc = $null
            }
            Write-State $state
        }
        'Failed' {
            if ($LeaseId -and $state.leaseId -eq $LeaseId) {
                $state.leaseId = $null
                $state.leaseUntilUtc = $null
                Write-State $state
            }
        }
        'Notified' {
            if (-not $ReleaseId -or $state.releaseId -ne $ReleaseId) { throw 'Notification does not match the checked release.' }
            $state.notifiedNoticeKey = $state.releaseId + ':' + $state.contentVerification
            $state.leaseId = $null
            $state.leaseUntilUtc = $null
            Write-State $state
        }
        'Snooze' {
            if (-not $ReleaseId -or $state.releaseId -ne $ReleaseId) { throw 'Snooze does not match the checked release.' }
            $state.snoozedReleaseId = $ReleaseId
            $state.snoozeUntilUtc = $now.AddHours(24).ToString('o')
            $state.notifiedNoticeKey = $null
            $state.leaseId = $null
            $state.leaseUntilUtc = $null
            Write-State $state
        }
        'Ignore' {
            if (-not $ReleaseId -or $state.releaseId -ne $ReleaseId) { throw 'Ignore does not match the checked release.' }
            $state.ignoredVersion = $state.availableVersion
            $state.leaseId = $null
            $state.leaseUntilUtc = $null
            Write-State $state
        }
    }
    $reply.releaseId = $state.releaseId
    $reply.availableVersion = $state.availableVersion
    $reply.comparison = $state.comparison
    $reply.contentVerification = $state.contentVerification
    $reply.catalogRevision = $state.catalogRevision
    $reply | ConvertTo-Json -Compress
} catch {
    @{ contract = 'ouo-plugin-update-state-v1'; persistence = 'session'; shouldCheck = $true; shouldNotify = $false; reason = 'state_unavailable' } | ConvertTo-Json -Compress
    exit 0
} finally {
    if ($lock) { $lock.Dispose() }
    if ($temporaryPath -and [IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
}
