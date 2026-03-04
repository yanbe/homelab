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

$idleSeconds = [User32]::GetIdleTicks()
$timeoutSeconds = 1800 # 30 minutes of idle time

$reqs = @(powercfg /requests 2>$null)
$isDisplayBlocked = $false
foreach ($i in 0..($reqs.Count - 1)) {
    if ($reqs[$i] -match "\[(DISPLAY|SYSTEM)\]") {
        if (($i + 1) -lt $reqs.Count) {
            $next = $reqs[$i + 1].Trim()
            if ($next -ne "" -and $next -notmatch "(None|なし)") {
                $isDisplayBlocked = $true
                break
            }
        }
    }
}

if ($isDisplayBlocked) {
    Write-Output "True"
} elseif ($idleSeconds -ge $timeoutSeconds) {
    Write-Output "False"
} else {
    Write-Output "True"
}
