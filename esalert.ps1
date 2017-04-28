Get-ChildItem -Path "$PSScriptRoot\rules\*.ps1" | foreach {Start-Process Powershell.exe -ArgumentList "-file $($_.FullName)" -WindowStyle Hidden}

# Replace above for testing purpose
# Get-ChildItem -Path "$PSScriptRoot\rules\*.ps1" | foreach {& $_.FullName}
