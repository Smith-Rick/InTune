# =====================================================================
# Remediation: Remove KB5132043 Hotpatch
#
# Purpose:
#   Remove the KB5132043 Hotpatch package from affected systems.
#
# Important:
#   - Does NOT remove the October/November baseline.
#   - Does NOT remove servicing stack updates.
#   - Does NOT automatically restart the computer.
#   - Intended to run as SYSTEM through Microsoft Intune Remediations.
# =====================================================================

$TargetKB = 'KB5132043'
$TargetPackagePattern = 'Package_for_HotpatchFix_9911~*'

$LogDirectory = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogPath = Join-Path $LogDirectory 'KB5132043-Removal.log'


function Write-RemediationLog {

    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Entry = '{0} {1}' -f (
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ), $Message

    Add-Content `
        -Path $LogPath `
        -Value $Entry `
        -Encoding UTF8
}


try {

    # -------------------------------------------------------------
    # Ensure Intune log directory exists
    # -------------------------------------------------------------

    if (-not (Test-Path -Path $LogDirectory)) {

        New-Item `
            -Path $LogDirectory `
            -ItemType Directory `
            -Force |
        Out-Null
    }


    Write-RemediationLog "Starting remediation for $TargetKB."


    # -------------------------------------------------------------
    # Confirm KB5132043 is installed
    # -------------------------------------------------------------

    $InstalledHotFix = Get-HotFix `
        -Id $TargetKB `
        -ErrorAction SilentlyContinue


    if ($null -eq $InstalledHotFix) {

        Write-RemediationLog "$TargetKB is not installed."

        Write-Output (
            "Removal=NotRequired; KB={0}; Reason=KBNotInstalled" -f
            $TargetKB
        )

        #exit 0
    }


    Write-RemediationLog "$TargetKB confirmed installed."


    # -------------------------------------------------------------
    # Locate the actual Hotpatch CBS package
    # -------------------------------------------------------------

    $Packages = @(
        Get-WindowsPackage `
            -Online `
            -ErrorAction Stop |
        Where-Object {

            $_.PackageName -like $TargetPackagePattern -and
            $_.PackageState -eq 'Installed'

        }
    )


    # -------------------------------------------------------------
    # Safety check: package not found
    # -------------------------------------------------------------

    if ($Packages.Count -eq 0) {

        Write-RemediationLog (
            "$TargetKB is installed but no installed package matched " +
            "$TargetPackagePattern."
        )

        Write-Output (
            "Removal=Blocked; KB={0}; Reason=HotpatchPackageNotFound; Pattern={1}" -f
            $TargetKB,
            $TargetPackagePattern
        )

       # exit 1
    }


    # -------------------------------------------------------------
    # Safety check: more than one package matched
    # -------------------------------------------------------------

    if ($Packages.Count -gt 1) {

        $PackageList = $Packages.PackageName -join '|'

        Write-RemediationLog (
            "Multiple Hotpatch packages matched. Removal stopped. " +
            "Packages=$PackageList"
        )

        Write-Output (
            "Removal=Blocked; KB={0}; Reason=MultipleHotpatchPackagesFound; Packages={1}" -f
            $TargetKB,
            $PackageList
        )

        #exit 1
    }


    # -------------------------------------------------------------
    # We have exactly one installed Hotpatch package
    # -------------------------------------------------------------

    $Package = $Packages[0]

    Write-RemediationLog (
        "Target package found: $($Package.PackageName)"
    )


    # -------------------------------------------------------------
    # Remove only the Hotpatch package
    #
    # NoRestart is intentional. Restart should be controlled
    # separately through the organization's maintenance process.
    # -------------------------------------------------------------

    Write-RemediationLog (
        "Beginning removal of $($Package.PackageName)."
    )


    $Result = Remove-WindowsPackage `
        -Online `
        -PackageName $Package.PackageName `
        -NoRestart `
        -ErrorAction Stop


    $RestartRequired = [bool]$Result.RestartNeeded


    Write-RemediationLog (
        "Remove-WindowsPackage completed. " +
        "RestartRequired=$RestartRequired"
    )


    # -------------------------------------------------------------
    # Query package state after removal attempt
    # -------------------------------------------------------------

    $CurrentPackage = Get-WindowsPackage `
        -Online `
        -PackageName $Package.PackageName `
        -ErrorAction SilentlyContinue


    if ($null -eq $CurrentPackage) {

        $CurrentState = 'NotPresent'

    }
    else {

        $CurrentState = [string]$CurrentPackage.PackageState
    }


    Write-RemediationLog (
        "Package state after removal: $CurrentState."
    )


    # -------------------------------------------------------------
    # Determine successful removal states
    # -------------------------------------------------------------

    $SuccessfulStates = @(
        'NotPresent'
        'UninstallPending'
        'Superseded'
    )


    if ($CurrentState -in $SuccessfulStates) {

        Write-RemediationLog (
            "Remediation successful. " +
            "PackageState=$CurrentState; " +
            "RestartRequired=True"
        )

        Write-Output (
            "Removal=Successful; KB={0}; Package={1}; PackageState={2}; RestartRequired=True" -f
            $TargetKB,
            $Package.PackageName,
            $CurrentState
        )

        #exit 0
    }


    # -------------------------------------------------------------
    # Package remains installed or in unexpected state
    # -------------------------------------------------------------

    Write-RemediationLog (
        "Removal did not reach an expected state. " +
        "PackageState=$CurrentState"
    )


    Write-Output (
        "Removal=PendingOrFailed; KB={0}; Package={1}; PackageState={2}; RestartRequired={3}; Log={4}" -f
        $TargetKB,
        $Package.PackageName,
        $CurrentState,
        $RestartRequired,
        $LogPath
    )

    #exit 1
}


catch {

    $ErrorMessage = $_.Exception.Message

    Write-RemediationLog (
        "Removal failed: $ErrorMessage"
    )


    Write-Output (
        "Removal=Failed; KB={0}; ErrorType={1}; Error={2}; Log={3}" -f
        $TargetKB,
        $_.Exception.GetType().FullName,
        $ErrorMessage,
        $LogPath
    )

    #exit 1
}