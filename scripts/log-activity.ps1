# scripts/log-activity.ps1
# Records user idle time every minute to build a dataset for predictive power management.

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class User32 {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleTicks() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        GetLastInputInfo(ref lii);
        return ((uint)Environment.TickCount - lii.dwTime) / 1000;
    }
}
'@

$logFile = "$env:USERPROFILE\Documents\homelab_activity.csv"

# Initialize CSV header if the file is new
if (-not (Test-Path $logFile)) {
    "Timestamp,IdleSeconds,IsLocked" | Out-File -FilePath $logFile -Encoding utf8
}

while ($true) {
    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $idleSeconds = [User32]::GetIdleTicks()
        
        # Determine if the workstation is locked (LogonUI process is active)
        $isLocked = (Get-Process LogonUI -ErrorAction SilentlyContinue) -ne $null
        
        "$timestamp,$idleSeconds,$isLocked" | Out-File -FilePath $logFile -Encoding utf8 -Append
    } catch {
        # Silently ignore transient errors to keep the background loop alive
    }
    Start-Sleep -Seconds 60
}
