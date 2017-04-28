<# Change log

#>
# ---------------------- Variables ----------------------
$callerName = (Get-Item $MyInvocation.PSCommandPath).BaseName

$fromAddress = "esalert@example.com"
$smtpServer = "smtp.example.com"

$logDir = "$PSScriptRoot\log"
$callerDir = "$logDir\$callerName"
$log = "$logDir\$callerName.log"
$executionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# ---------------------- Functions ----------------------
# Create cache files and folders
New-Item -ItemType Directory -ea SilentlyContinue $logDir | Out-Null
New-Item -ItemType Directory -ea SilentlyContinue $callerDir | Out-Null

# Write to script log
Function Write-Log {
    Add-Content -Path $log "$executionTime $Term $Value : $args" -PassThru
}

# Rotate log files
Function Invoke-LogRotation {
    If ($logRotation -and (Test-Path -Path $log)) {
        Get-Content -Path $log | Add-Content -Path "$logDir\$callerName.$($runTime.ToString("yyyy-MM")).log"        
        Clear-Content -Path $log -Force -ErrorAction SilentlyContinue
    }
}

# Send out email alerts
Function Send-Email {    
    $Body = "Rule: $me
        `nAlert Time: $runTime
        `nTime Frame: $($runTime.AddMinutes(-$bufferTime)) to $runTime        
        `nExecution Time: $($esResponse.took) ms
        "
    # Set subject based on ruleType
    switch ($ruleType) {
        "any" {$Subject = "[$alertLevel] ${Term}: $ruleName $Value within last $bufferTime min(s)"}
        "blacklist" {$Subject = "[$alertLevel] ${Term}: $ruleName in blacklist within last $bufferTime min(s)"}
        "threshold" {$Subject = "[$alertLevel] ${Term}: $ruleName $Value > $eventThreshold threshold within last $bufferTime min(s)"}
        "whitelist" {$Subject = "[$alertLevel] ${Term}: $ruleName not in whitelist within last $bufferTime min(s)"}
        default {$Subject = "[$alertLevel] ${Term}: $ruleName $Value within last $bufferTime min(s)"}        
    }                       

    If ($emailEnabled) {        
        foreach ($email in $recipients) {
            Send-MailMessage -From $fromAddress -To $email -Subject $Subject -Body $Body -SmtpServer $smtpServer            
        }
        
        Write-Log "Alert emailed - $Subject"       
    }
}

# Check if an alert should be fired for a term
Function Test-AlertAttempt {
    param (
        [string]$Term,
        [int]$Value       
    )
    
    # $true: fire alert
    # $false: suppress alert

    # Skip certain timeframes. Feel free to define more schedules
    foreach ($schedule in $offSchedules) {

        # weeknight schedule
        If ($schedule -eq "weeknight") {
            If ($runTime.Hour -ge 18 -or $runTime.Hour -le 4) {
                return $false
            }
        }

        # weekend schedule
        If ($schedule -eq "weekend") {
            If ($runTime.DayOfWeek -in "Saturday", "Sunday") {
                return $false
            }
        }
    }

    # Ignore specified terms
    If ($Term -in $ignoredTerms) {
        Write-Log "Term is ignored"
        return $false
    }

    # Define cache variables
    $alertIntervalPath = "$callerDir\$Term.alertInterval"
    $lastAlertTimePath = "$callerDir\$Term.lastAlertTime"
    
    # If $alertInterval is set to 0 for testing purpose, fire alert
    If ($alertInterval -eq 0) {
        Write-Output $verboseLog "Testing mode - RealertAfter is 0. Fire alert"
        return $true
    }

    # Set elapsed time threshold for a new term and fire alert
    If (!(Test-Path $alertIntervalPath)) {
        Set-Content -Path $alertIntervalPath $alertInterval
        Set-Content -Path $lastAlertTimePath $runTime
        Write-Log "New term. Fire alert"
        return $true
    }

    # Update $alertIntervalPath when $alertInterval is increased by users
    If ($alertInterval -gt [int](Get-Content $alertIntervalPath)) {
        Set-Content -Path $alertIntervalPath $alertInterval
    }
    
    # If realertAfter > maxAlertInterval (not 0), reset threshold and fire alert
    If ($maxAlertInterval -ne 0 -and ([int](Get-Content $alertIntervalPath) -ge $maxAlertInterval)) {
        Set-Content -Path $alertIntervalPath $alertInterval
        Set-Content -Path $lastAlertTimePath $runTime
        Write-Log "Realertafter exceeds maxAlertInterval. Fire alert and reset threshold"
        return $true
    }

    # If last alert time is not recorded, fire alert
    If (!(Test-Path $lastAlertTimePath)) {
        Set-Content -Path $lastAlertTimePath $runTime
        Write-Log "Last alert is not recorded. Fire alert."        
        return $true
    } Else {
        # Calculate elapsed minutes from last alert
        $elapsedMinutes = ($runTime - [datetime](Get-Content $lastAlertTimePath)).TotalMinutes
        Write-Output "Elapsed minutes: $elapsedMinutes"
    }        

    # Check elapsed time against RealertAfter and maxAlertInterval thresholds
    If ($elapsedMinutes -lt [int](Get-Content $alertIntervalPath)) {
        Write-Log "An alert was fired $elapsedMinutes minutes ago. Skip alert"
        return $false
    } ElseIf ($maxAlertInterval -eq 0) {
        # Alert exponential suppression is disabled, fire alert
        Set-Content -Path $lastAlertTimePath $runTime
        Write-Output "Exponential alert feature is disabled. Fire alert."
        return $true
    } ElseIf ($elapsedMinutes -lt ([int](Get-Content $alertIntervalPath) * 2)) {
        # Double the threshold to prevent continuous alerts and fire alert
        Set-Content -Path $alertIntervalPath ([int](Get-Content $alertIntervalPath) * 2)
        Set-Content -Path $lastAlertTimePath $runTime
        Write-Log "Exponential alerting. Double RealertAfter and fire alert"
        return $true
    } ElseIf ($elapsedMinutes -ge $maxAlertInterval) {
        # If elapsed time exceeds maxAlertInterval, fire alert and reset threshold
        Set-Content -Path $lastAlertTimePath $runTime
        Set-Content -Path $alertIntervalPath $alertInterval
        Write-Log "Elapsed time exceeds maxAlertInterval. Fire alert and reset threshold"
        return $true
    } Else {
        # If elapsed time is greater than both thresholds, fire alert
        Set-Content -Path $lastAlertTimePath $runTime
        Write-Log "Elapsed time exceeds both thresholds. Fire alert"
        return $true
    }
}