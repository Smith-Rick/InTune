$TargetKB = 'KB5132043'
$TargetKBNumber = '5132043'
$WindowHours = 24
$StartTime = (Get-Date).AddHours(-$WindowHours)

try {
    # Find the Hotpatch error events.
    $Events = @(
        Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Microsoft-Windows-Hotpatch-Monitor'
            Id           = 107
            StartTime    = $StartTime
        } -ErrorAction SilentlyContinue
    )

    # Get servicing packages associated with the target KB.
    $Packages = @(
        Get-WindowsPackage -Online -ErrorAction Stop |
        Where-Object {
            $_.PackageName -match $TargetKBNumber -or
            $_.Description -match $TargetKBNumber -or
            $_.ReleaseType -match $TargetKBNumber
        }
    )

    # Get-HotFix is included as a secondary validation source.
    $HotFix = Get-HotFix -Id $TargetKB -ErrorAction SilentlyContinue

    $KBInstalled = ($Packages.Count -gt 0) -or ($null -ne $HotFix)

    if ($Events.Count -gt 0 -and $KBInstalled) {
        $LatestEvent = $Events |
            Sort-Object TimeCreated -Descending |
            Select-Object -First 1

        $PackageNames = if ($Packages.Count -gt 0) {
            ($Packages.PackageName -join '|')
        }
        else {
            'DetectedByGetHotFix'
        }

        Write-Output (
            "Detected=True; KB={0}; EventCount={1}; LatestEvent={2}; Packages={3}" -f
            $TargetKB,
            $Events.Count,
            $LatestEvent.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'),
            $PackageNames
        )

        # Causes the Intune remediation script to run.
        exit 1
    }

    if ($Events.Count -gt 0 -and -not $KBInstalled) {
        Write-Output (
            "Detected=False; Reason=EventFoundButKBNotDetected; KB={0}; EventCount={1}" -f
            $TargetKB,
            $Events.Count
        )

        exit 0
    }

    Write-Output (
        "Detected=False; KBInstalled={0}; EventCount={1}; WindowHours={2}" -f
        $KBInstalled,
        $Events.Count,
        $WindowHours
    )

    #exit 0
}
catch {
    Write-Output (
        "Detected=Unknown; ErrorType={0}; Error={1}" -f
        $_.Exception.GetType().FullName,
        $_.Exception.Message
    )

    # Do not attempt remediation when detection fails.
    #exit 0
}