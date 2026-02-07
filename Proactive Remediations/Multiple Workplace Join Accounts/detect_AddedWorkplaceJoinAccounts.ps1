# Detect extra Workplace Join (WAM) accounts for the CURRENT user.
# Flags DETECTED (exit 1) when:
#   - More than one WAM account exists AND
#   - At least one account != current user's UPN
# Also: if parsing fails but "Accounts found: N" > 1, we still flag DETECTED (conservative).

$ErrorActionPreference = 'Stop'

function Get-CurrentUserUpn
{
	try
	{
		$upn = (whoami /upn 2>$null).Trim()
		if ($upn) { return $upn }
	}
	catch { }
	return ''
}

function Get-WamAccountsForCurrentUser
{
	# Returns: [Hashtable] with Keys:
	#  Usernames = [string[]] parsed UPNs (may be empty)
	#  Count     = [int]      numeric "Accounts found" from dsregcmd (if present)
	$result = @{
		Usernames = @()
		Count	  = 0
		Raw	      = ''
	}
	
	$raw = (dsregcmd /listaccounts 2>$null) | Out-String
	$result.Raw = $raw
	
	if ($raw)
	{
		# Get numeric "Accounts found" if present (handles different spacing/casing)
		$mCount = [regex]::Match($raw, '(?im)^\s*Accounts\s+found\s*:\s*(\d+)\s*$')
		if ($mCount.Success) { $result.Count = [int]$mCount.Groups[1].Value }
		
		# Parse UPNs after "user:" or "Username:"; capture until comma/EOL. Be forgiving on whitespace/case.
		$parsed = @()
		$rx = [regex] '(?im)^\s*(?:user|username)\s*:\s*([^,\r\n]+)'
		foreach ($m in $rx.Matches($raw))
		{
			$val = $m.Groups[1].Value.Trim()
			# Basic email sanity
			if ($val -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
			{
				if ($val -notin $parsed) { $parsed += $val }
			}
		}
		# Extra safety: if none matched, harvest any "user: <email>" that appears inline (not just EOL)
		if ($parsed.Count -eq 0)
		{
			$rxInline = [regex] '(?i)user\s*:\s*([^\s,;]+@[^\s,;]+)'
			foreach ($m in $rxInline.Matches($raw))
			{
				$val = $m.Groups[1].Value.Trim().TrimEnd('.')
				if ($val -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
				{
					if ($val -notin $parsed) { $parsed += $val }
				}
			}
		}
		
		$result.Usernames = $parsed
		return $result
	}
	
	# Fallback path for older builds: try /status (best-effort)
	$status = (dsregcmd /status 2>$null) | Out-String
	if ($status)
	{
		$parsed = @()
		$rx2 = [regex] '(?im)^\s*(?:User(?:Name| Email)?|UPN)\s*:\s*([^\s@]+@[^\s]+)\s*$'
		foreach ($m in $rx2.Matches($status))
		{
			$val = $m.Groups[1].Value.Trim()
			if ($val -notin $parsed) { $parsed += $val }
		}
		$result.Usernames = $parsed
		# /status doesn't give a reliable "Accounts found" number, leave Count as 0
	}
	
	return $result
}

# ---- MAIN ----
$currentUpn = Get-CurrentUserUpn
$wam = Get-WamAccountsForCurrentUser
$wamAccounts = $wam.Usernames
$acctCount = $wam.Count

# Decide detection:
# Preferred logic (when we have UPNs):
$detected = $false
$reason = ''

if ($wamAccounts.Count -gt 1)
{
	if ([string]::IsNullOrWhiteSpace($currentUpn))
	{
		$detected = $true
		$reason = "More than one WAM account exists and current UPN is unknown."
	}
	else
	{
		$others = $wamAccounts | Where-Object { $_ -ne $currentUpn }
		if ($others.Count -gt 0)
		{
			$detected = $true
			$reason = "Found WAM account(s) not matching current user: " + ($others -join ', ')
		}
	}
}
elseif (($wamAccounts.Count -eq 0) -and ($acctCount -gt 1))
{
	# Robust fallback: parsing failed but dsregcmd reports >1 accounts → extra accounts exist.
	$detected = $true
	$reason = "dsregcmd reports $acctCount WAM accounts but none were parsed; treating as DETECTED."
}

# ---- OUTPUT ----
if ($wam.Raw)
{
	if ($wamAccounts.Count -eq 0 -and $acctCount -gt 0)
	{
		Write-Host "Note: dsregcmd reports $acctCount account(s) but none parsed; output format may differ on this build."
	}
}

Write-Host "Current user UPN   : $currentUpn"
Write-Host "Parsed accounts    : $($wamAccounts.Count)"
if ($wamAccounts.Count)
{
	Write-Host "Accounts:"; $wamAccounts | ForEach-Object { Write-Host "  - $_" }
}
if ($acctCount -gt 0)
{
	Write-Host "Accounts found (from dsregcmd summary): $acctCount"
}

if ($detected)
{
	Write-Host ""
	Write-Host "Status: DETECTED - $reason" -ForegroundColor Yellow
	exit 1
}
else
{
	Write-Host ""
	Write-Host "Status: NOT DETECTED" -ForegroundColor Green
	exit 0
}