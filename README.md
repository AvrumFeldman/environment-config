# Pre requisite
- Install bitwarden secrets tool (bws).
- set BWS_ACCESS_TOKEN env variable.

# Execute the following as admin on new machine.
```
New-Item -ItemType SymbolicLink -Target ".\Powershell_profile.ps1" -Path "$env:userprofile\Documents\PowerShell\Microsoft.VSCode_profile.ps1","$env:userprofile\Documents\PowerShell\Microsoft.PowerShell_profile.ps1","$env:userprofile\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

New-Item -ItemType SymbolicLink -Target "$env:USERPROFILE\Documents\powershelling\ssh_config" -Path "$env:USERPROFILE\.ssh\config"
```