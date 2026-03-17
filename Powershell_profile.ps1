function Sync-Env {
    <#
    .SYNOPSIS
    Refreshes the current process environment variables from the registry.
    #>
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
    $machineVars = [Environment]::GetEnvironmentVariables('Machine')
    $userVars    = [Environment]::GetEnvironmentVariables('User')

    # Handle PATH specifically
    $processPath = $machineVars['Path'] + ';' + $userVars['Path']
    $processPath = ($processPath -split ';' | Where-Object { $_ -match '\S' } | Select-Object -Unique) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $processPath, 'Process')

    # Combine all unique variable names
    $allKeys = ($machineVars.Keys + $userVars.Keys) | Select-Object -Unique
    
    # Define variables to explicitly SKIP
    $skipVars = @('Path', 'PSModulePath', 'PROMPT')

    foreach ($key in $allKeys) {
        if ($key -in $skipVars) { continue }
        
        $value = if ($null -ne $userVars[$key]) { $userVars[$key] } else { $machineVars[$key] }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
    
    Write-Host "Local environment variables refreshed safely." -ForegroundColor Green

    # ==========================================
    # 2. Bitwarden Secrets Manager Integration
    # ==========================================
    Write-Host "Fetching secrets from Bitwarden (bws)..." -ForegroundColor Cyan
    
    # Verify the Bitwarden CLI is installed and in the PATH
    if (Get-Command "bws" -ErrorAction SilentlyContinue) {
        try {
            # Execute BWS, capture the JSON output, and convert it to PowerShell objects
            $bwsSecrets = bws secret list | ConvertFrom-Json
            
            $importedCount = 0
            foreach ($secret in $bwsSecrets) {
                # Check for a valid key name to prevent errors
                if (-not [string]::IsNullOrWhiteSpace($secret.key)) {
                    # Inject into Process scope ONLY
                    [Environment]::SetEnvironmentVariable($secret.key, $secret.value, 'Process')
                    $importedCount++
                }
            }
            Write-Host "Successfully loaded $importedCount secrets from Bitwarden into the current process." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to retrieve or parse secrets from Bitwarden."
            Write-Warning "Ensure 'BWS_ACCESS_TOKEN' is set or you are authenticated."
            Write-Warning $_.Exception.Message
        }
    } else {
        Write-Warning "Bitwarden Secrets CLI ('bws') was not found. Skipping secrets import."
    }
}
function Set-Env {
    param(
        [Parameter(Mandatory=$true)] [string]$Name,
        [Parameter(Mandatory=$true)] [string]$Value
    )
    # 1. Save it permanently to the registry
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    
    # 2. Apply it immediately to the current session so you don't have to restart
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

Sync-Env