# Variables contain script attributes
$scriptDir = Split-Path -parent $MyInvocation.MyCommand.Definition

Get-ChildItem -Path "$scriptDir\rules\*.ps1" | foreach {Start-Process Powershell.exe -ArgumentList "-file $($_.FullName)" -WindowStyle Hidden}

# Replace above for testing purpose
# Get-ChildItem -Path "$scriptDir\rules\*.ps1" | foreach {& $_.FullName}