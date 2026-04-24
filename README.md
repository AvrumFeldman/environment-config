# Pre requisite
- Install bitwarden secrets tool (bws).
- set BWS_ACCESS_TOKEN env variable.

# Execute the following as admin on new machine.
```
$Profiles = "$env:userprofile\Documents\PowerShell\Microsoft.VSCode_profile.ps1","$env:userprofile\Documents\PowerShell\Microsoft.PowerShell_profile.ps1","$env:userprofile\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1","$env:userprofile\Documents\WindowsPowerShell\Microsoft.VSCode_profile.ps1"

Get-ChildItem -File $profiles | Rename-Item -NewName {$_.name + ".old"} -erroraction SilentlyContinue

New-Item -ItemType SymbolicLink -Target "$pwd\Powershell_profile.ps1" -Path $profiles

New-Item -ItemType SymbolicLink -Target "$pwd\ssh_config" -Path "$env:USERPROFILE\.ssh\config"
```

In Linux execute the following in Powershell to setup the symbolic link
```
New-Item -ItemType SymbolicLink -Target $pwd/Powershell_profile.ps1 -Path $PROFILE -force
```