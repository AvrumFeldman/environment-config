function Sync-Env {
    [CmdletBinding()]
    param()
    <#
    .SYNOPSIS
    Refreshes the current process environment variables from the registry.
    #>
    Write-Verbose "Starting Sync-Env. Refreshing process environment from machine/user scopes."
    Write-Host "Refreshing environment variables from registry..." -ForegroundColor Cyan

    # $vars = @{}
    # (Get-Item "hklm:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment","HKCU:\Environment").GetValueNames() | % {
    #     $vars[$_] += ((Get-ItemProperty -Path "hklm:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\" -Name $_).$_)
    # }
    # foreach ($var in $vars.GetEnumerator()) {
    #     [Environment]::SetEnvironmentVariable($var.Key, $var.Value, 'Process')
    # }
     

    # ==========================================
    # 1. Standard Windows Environment Refresh
    # ==========================================
    Write-Verbose "Reading machine and user environment variables."
    $machineVars = [Environment]::GetEnvironmentVariables('Machine')
    $userVars    = [Environment]::GetEnvironmentVariables('User')
    Write-Debug ("Machine variable count: {0}; User variable count: {1}" -f $machineVars.Count, $userVars.Count)

    # Handle PATH specifically
    Write-Verbose "Rebuilding process PATH from machine and user PATH values."
    $processPath = $machineVars['Path'] + ';' + $userVars['Path']
    $processPath = ($processPath -split ';' | Where-Object { $_ -match '\S' } | Select-Object -Unique) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $processPath, 'Process')
    Write-Debug ("Process PATH entries after dedupe: {0}" -f (($processPath -split ';').Count))

    # Combine all unique variable names
    $allKeys = ($machineVars.Keys + $userVars.Keys) | Select-Object -Unique
    Write-Debug ("Total distinct env var keys discovered: {0}" -f $allKeys.Count)
    
    # Define variables to explicitly SKIP
    $skipVars = @('Path', 'PSModulePath', 'PROMPT')
    Write-Verbose ("Skipping protected variables: {0}" -f ($skipVars -join ', '))

    $appliedCount = 0
    $skippedCount = 0
    foreach ($key in $allKeys) {
        if ($key -in $skipVars) {
            $skippedCount++
            Write-Debug ("Skipped variable: {0}" -f $key)
            continue
        }
        
        $value = if ($null -ne $userVars[$key]) { $userVars[$key] } else { $machineVars[$key] }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
        $appliedCount++
        Write-Debug ("Applied variable to process scope: {0}" -f $key)
    }
    Write-Verbose ("Applied {0} variables; skipped {1}." -f $appliedCount, $skippedCount)
    
    Write-Host "Local environment variables refreshed safely." -ForegroundColor Green

    # ==========================================
    # 2. Bitwarden Secrets Manager Integration
    # ==========================================
    Write-Verbose "Attempting Bitwarden Secrets Manager import."
    Write-Host "Fetching secrets from Bitwarden (bws)..." -ForegroundColor Cyan
    
    # Verify the Bitwarden CLI is installed and in the PATH
    if (Get-Command "bws" -ErrorAction SilentlyContinue) {
        Write-Debug "Bitwarden CLI found in PATH."
        try {
            # Execute BWS, capture the JSON output, and convert it to PowerShell objects
            Write-Verbose "Requesting secret list from bws."
            $bwsSecrets = bws secret list | ConvertFrom-Json
            Write-Debug ("Secrets returned by bws: {0}" -f @($bwsSecrets).Count)
            
            $importedCount = 0
            foreach ($secret in $bwsSecrets) {
                # Check for a valid key name to prevent errors
                if (-not [string]::IsNullOrWhiteSpace($secret.key)) {
                    # Inject into Process scope ONLY
                    [Environment]::SetEnvironmentVariable($secret.key, $secret.value, 'Process')
                    $importedCount++
                    Write-Debug ("Imported Bitwarden secret key into process scope: {0}" -f $secret.key)
                } else {
                    Write-Debug "Skipped Bitwarden secret with empty key."
                }
            }
            Write-Verbose ("Imported {0} Bitwarden secrets into process scope." -f $importedCount)
            Write-Host "Successfully loaded $importedCount secrets from Bitwarden into the current process." -ForegroundColor Green
        } catch {
            Write-Debug ("Bitwarden exception: {0}" -f $_.Exception)
            Write-Warning "Failed to retrieve or parse secrets from Bitwarden."
            Write-Warning "Ensure 'BWS_ACCESS_TOKEN' is set or you are authenticated."
            Write-Warning $_.Exception.Message
        }
    } else {
        Write-Debug "Bitwarden CLI not found in PATH."
        Write-Warning "Bitwarden Secrets CLI ('bws') was not found. Skipping secrets import."
    }

    Write-Verbose "Sync-Env completed."
}
function Set-Env {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$Value,
        [ValidateSet("User","Machine")]
        [string[]]$Scope = "User",
        [string]$BWSprojectID = "0ac76307-39e6-4524-bcff-b41000f52a19"
    )
    Write-Verbose ("Starting Set-Env for variable '{0}' with scope(s): {1}" -f $Name, ($Scope -join ', '))
    Write-Debug ("Incoming value length for '{0}': {1}" -f $Name, $Value.Length)
    
    # 1. Save it permanently to the registry
    switch ($Scope) {
        "User" {
            Write-Verbose ("Persisting '{0}' to User scope." -f $Name)
            
            set-ItemProperty -Path "hkcu:\Environment"  -Name $Name -Value $Value
            # [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        }
        "Machine" {
            Write-Verbose ("Persisting '{0}' to Machine scope." -f $Name)
            try {
                set-ItemProperty -Path "hklm:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name $Name -Value $Value
                # [Environment]::SetEnvironmentVariable($Name, $Value, 'Machine')
            } catch {
                Write-Verbose ("Failed to set '{0}' in Machine scope: {1}" -f $Name, $_.Exception.Message)
                Write-Warning ("Unable to set environment variable '{0}' in Machine scope. Try running this script with elevated permissions." -f $Name)
            }
        }
    }
    
    # 2. Apply it immediately to the current session so you don't have to restart
    Write-Verbose ("Applying '{0}' to Process scope for immediate use." -f $Name)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    Write-Debug ("Process scope update complete for '{0}'." -f $Name)

    if (Get-Command "bws" -ErrorAction SilentlyContinue) {
        Write-Verbose "Bitwarden CLI found. Attempting to sync secret value."
        $bws = (bws secret list | convertfrom-json) | Where-Object key -Match $name
        Write-Debug ("Bitwarden secret matches for '{0}': {1}" -f $Name, @($bws).Count)
        
        foreach ($secret in $bws) {
            Write-Verbose ("Updating existing Bitwarden secret id '{0}' for key '{1}'." -f $secret.id, $secret.key)
            $SetBWS = bws secret edit --key $secret.key --value $Value $secret.id
        }
        if ($bws.Count -eq 0) {
            Write-Verbose ("Creating new Bitwarden secret for key '{0}'." -f $Name)
            $SetBWS = bws secret create $name $Value $BWSprojectID
            $setbwsObj = $SetBWS | ConvertFrom-Json
            Write-Verbose ("Created new Bitwarden secret with id '{0}' for key '{1}'." -f $setbwsObj.id, $setbwsObj.key)
        }
        Write-Debug ($SetBWS | Out-String)
    } else {
        Write-Verbose "Bitwarden CLI not found. Skipping Bitwarden sync."
    }

    Write-Verbose ("Set-Env completed for '{0}'." -f $Name)
}

Sync-Env