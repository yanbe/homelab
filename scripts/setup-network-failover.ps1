# scripts/setup-network-failover.ps1
# This script must be run as Administrator on Windows.
# It creates a Scheduled Task to run the Network Failover Manager with highest privileges.

$taskName = "HomelabNetworkFailover"
$scriptPath = "C:\homelab\scripts\manage-network.ps1"

# Check for Admin privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script as an Administrator!"
    exit 1
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""$scriptPath"""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Remove existing task if it exists
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Write-Host "Removing existing task..."
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
} catch {
    Write-Warning "Error during cleanup: $_"
}

Write-Host "Registering new Scheduled Task: $taskName..."
try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop
    Write-Host "Registration SUCCESSFUL."
} catch {
    Write-Error "Registration FAILED: $_"
    exit 1
}

Write-Host "Starting the task now..."
try {
    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Host "Task started successfully."
} catch {
    Write-Error "Failed to start task: $_"
}

$finalState = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $finalState) {
    Write-Host "Final Task State: $($finalState.State)"
} else {
    Write-Error "CRITICAL: Task is MISSING after registration!"
}
