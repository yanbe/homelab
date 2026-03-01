param (
    [string]$MacAddress,
    [string]$IpAddress = "255.255.255.255"
)
$mac = $MacAddress -split ':' | ForEach-Object { [byte]('0x' + $_) }
$packet = [byte[]]::new(102)
for ($i = 0; $i -lt 6; $i++) { $packet[$i] = 255 }
for ($i = 0; $i -lt 16; $i++) {
    for ($j = 0; $j -lt 6; $j++) {
        $packet[6 + $i * 6 + $j] = $mac[$j]
    }
}
$UdpClient = New-Object System.Net.Sockets.UdpClient
$UdpClient.Connect([System.Net.IPAddress]::Parse($IpAddress), 9)
$UdpClient.Send($packet, 102) | Out-Null
$UdpClient.Close()
