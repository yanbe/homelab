# scripts/manage-network.ps1
# Dynamically manages network interfaces to prioritize 5GbE and fallback to Wi-Fi.
# Ensures Wi-Fi is disabled when 5GbE is active for gaming latency reasons.

$primaryName = "Realtek USB 5GbE"
$fallbackName = "Wi-Fi"
$logFile = "$env:USERPROFILE\Documents\network_failover.log"

"$(Get-Date): Script starting..." | Out-File -FilePath $logFile -Encoding utf8 -Append

# Set Interface Metrics once
Get-NetIPInterface -InterfaceAlias $primaryName -ErrorAction SilentlyContinue | Set-NetIPInterface -InterfaceMetric 5 -ErrorAction SilentlyContinue 2>> $logFile
Get-NetIPInterface -InterfaceAlias $fallbackName -ErrorAction SilentlyContinue | Set-NetIPInterface -InterfaceMetric 50 -ErrorAction SilentlyContinue 2>> $logFile

while ($true) {
    try {
        $primary = Get-NetAdapter -Name $primaryName -ErrorAction SilentlyContinue
        $fallback = Get-NetAdapter -Name $fallbackName -ErrorAction SilentlyContinue

        if ($null -ne $primary -and $primary.Status -eq "Up") {
            # Primary is active - Ensure Fallback is DISABLED
            if ($null -ne $fallback -and $fallback.Status -ne "Disabled") {
                Write-Output "$(Get-Date): 5GbE is Up. Disabling $fallbackName to ensure low latency..."
                Disable-NetAdapter -Name $fallbackName -Confirm:$false
            }
        } else {
            # Primary is disconnected, not present, or down - Ensure Fallback is ENABLED
            if ($null -ne $fallback -and ($fallback.Status -eq "Disabled" -or $fallback.Status -eq "Disconnected")) {
                Write-Output "$(Get-Date): 5GbE is Down. Enabling $fallbackName as fallback..."
                Enable-NetAdapter -Name $fallbackName -Confirm:$false
            }
        }
    } catch {
        # Silent ignore
    }
    Start-Sleep -Seconds 10
}
