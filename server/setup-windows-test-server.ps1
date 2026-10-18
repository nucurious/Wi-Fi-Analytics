# WiFi Analytics test server for Windows 10/11 (e.g. Dell OptiPlex 7070)
#
# Installs and starts, automatically at every boot (even with nobody logged in):
#   - iperf3 servers on TCP+UDP ports 5201-5205 (one test per port at a time)
#   - a TWAMP-Light reflector (Nokia twampy) on UDP port 862
# and opens those ports in Windows Firewall, and stops the PC from sleeping.
#
# Run once, in PowerShell opened with "Run as administrator":
#   powershell -ExecutionPolicy Bypass -File .\setup-windows-test-server.ps1
#
# Safe to run again (updates/repairs). To remove everything: see the end of this file.

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$Root       = 'C:\TestServer'
$IperfPorts = 5201..5205
$TwampPort  = 862
$IperfUrl   = 'https://github.com/ar51an/iperf3-win-builds/releases/download/3.21/iperf-3.21-win64.zip'
$TwampyUrl  = 'https://github.com/nokia/twampy/archive/refs/heads/main.zip'
$PythonUrl  = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $Root, "$Root\logs" | Out-Null

function Step($n, $text) { Write-Host "`n[$n/6] $text" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 1. iperf3
Step 1 'Downloading iperf3 3.21 for Windows'
$zip = "$Root\iperf3.zip"
Invoke-WebRequest -Uri $IperfUrl -OutFile $zip -UseBasicParsing
Get-ScheduledTask -TaskName 'TestServer iperf3*' -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
Get-Process iperf3 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $zip -DestinationPath "$Root\iperf3" -Force
Remove-Item $zip
$Iperf = Get-ChildItem "$Root\iperf3" -Recurse -Filter 'iperf3.exe' | Select-Object -First 1 -ExpandProperty FullName
if (-not $Iperf) { throw 'iperf3.exe was not found in the download.' }
Write-Host "    iperf3: $Iperf"

# ---------------------------------------------------------------- 2. Python 3.11+ for twampy
Step 2 'Checking for Python 3.11 or newer'
function Find-Python {
    foreach ($cmd in @('py', 'python')) {
        $exe = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($exe) {
            $pyArgs = if ($cmd -eq 'py') { @('-3', '-c') } else { @('-c') }
            try {
                $path = & $exe.Source @pyArgs 'import sys; print(sys.executable if sys.version_info >= (3, 11) else "")' 2>$null
                if ($path -and (Test-Path $path)) { return $path.Trim() }
            } catch { }
        }
    }
    foreach ($p in @("$env:ProgramFiles\Python313\python.exe", "$env:ProgramFiles\Python312\python.exe", "$env:ProgramFiles\Python311\python.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}
$Python = Find-Python
if (-not $Python) {
    Write-Host '    Installing Python 3.12 for all users (about 1 minute)'
    $installer = "$Root\python-installer.exe"
    Invoke-WebRequest -Uri $PythonUrl -OutFile $installer -UseBasicParsing
    Start-Process -FilePath $installer -Wait -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_launcher=1', 'Include_test=0'
    Remove-Item $installer
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $Python = Find-Python
    if (-not $Python) { throw 'Python install failed. Install Python 3.12 from python.org (all users), then run this script again.' }
}
Write-Host "    Python: $Python"

# ---------------------------------------------------------------- 3. twampy in its own environment
Step 3 'Installing the TWAMP reflector (Nokia twampy)'
Get-ScheduledTask -TaskName 'TestServer TWAMP*' -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue
if (-not (Test-Path "$Root\venv\Scripts\python.exe")) { & $Python -m venv "$Root\venv" }
& "$Root\venv\Scripts\python.exe" -m pip install --quiet --upgrade pip
& "$Root\venv\Scripts\python.exe" -m pip install --quiet --upgrade $TwampyUrl
$Twampy = "$Root\venv\Scripts\twampy.exe"
if (-not (Test-Path $Twampy)) { throw 'twampy did not install.' }
Write-Host "    twampy: $Twampy"

# ---------------------------------------------------------------- 4. Windows Firewall
Step 4 'Opening firewall ports'
$portRange = "$($IperfPorts[0])-$($IperfPorts[-1])"
foreach ($rule in @(
        @{ Name = "TestServer iperf3 TCP $portRange"; Protocol = 'TCP'; Port = $portRange },
        @{ Name = "TestServer iperf3 UDP $portRange"; Protocol = 'UDP'; Port = $portRange },
        @{ Name = "TestServer TWAMP UDP $TwampPort";  Protocol = 'UDP'; Port = "$TwampPort" })) {
    Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Profile Any `
        -Protocol $rule.Protocol -LocalPort $rule.Port | Out-Null
    Write-Host "    allowed $($rule.Protocol) $($rule.Port)"
}

# ---------------------------------------------------------------- 5. Start at boot, restart on failure
Step 5 'Creating start-at-boot tasks'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$trigger   = New-ScheduledTaskTrigger -AtStartup

function Register-Server($name, $exe, $arguments) {
    $action = New-ScheduledTaskAction -Execute $exe -Argument $arguments -WorkingDirectory $Root
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $name
    Write-Host "    $name  ($exe $arguments)"
}
foreach ($p in $IperfPorts) {
    Register-Server "TestServer iperf3 $p" $Iperf "-s -p $p --forceflush --logfile `"$Root\logs\iperf3-$p.log`""
}
Register-Server 'TestServer TWAMP reflector' $Twampy "responder :$TwampPort"

# Never sleep or hibernate when plugged in (a sleeping server answers nothing).
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
powercfg /hibernate off | Out-Null

# ---------------------------------------------------------------- 6. Self-test
Step 6 'Testing on this PC'
Start-Sleep -Seconds 3
$ok = $true
try {
    $out = & $Iperf -c 127.0.0.1 -p $IperfPorts[0] -t 2 2>&1 | Out-String
    if ($out -match 'receiver') { Write-Host '    iperf3: OK' -ForegroundColor Green } else { $ok = $false; Write-Host "    iperf3: FAILED`n$out" -ForegroundColor Red }
} catch { $ok = $false; Write-Host "    iperf3: FAILED ($_)" -ForegroundColor Red }
try {
    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = 3000
    $udp.Connect('127.0.0.1', $TwampPort)
    [void]$udp.Send((New-Object byte[] 64), 64)
    $from = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $reply = $udp.Receive([ref]$from)
    $udp.Close()
    if ($reply.Length -ge 36) { Write-Host '    TWAMP reflector: OK' -ForegroundColor Green } else { $ok = $false; Write-Host '    TWAMP reflector: unexpected reply' -ForegroundColor Red }
} catch { $ok = $false; Write-Host "    TWAMP reflector: no reply ($($_.Exception.Message))" -ForegroundColor Red }

$lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
$public = try { (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10) } catch { 'unknown' }

Write-Host "`n------------------------------------------------------------"
Write-Host "This PC's lab (LAN) address : $lan"
Write-Host "Public address seen online  : $public"
Write-Host ''
Write-Host 'On the lab router, forward these to the LAN address above:'
Write-Host "  TCP and UDP $portRange  (iperf3)"
Write-Host "  UDP $TwampPort          (TWAMP)"
Write-Host 'and give this PC a fixed LAN address (DHCP reservation).'
Write-Host ''
Write-Host 'In the app: Settings > iperf3 server = the public address, port 5201'
Write-Host '            Settings > TWAMP reflector  = the public address, port 862'
if (-not $ok) { Write-Host "`nSome checks failed: see messages above, and logs in $Root\logs" -ForegroundColor Yellow }
Write-Host '------------------------------------------------------------'

# ---------------------------------------------------------------- To remove everything
# Get-ScheduledTask -TaskName 'TestServer*' | Unregister-ScheduledTask -Confirm:$false
# Get-NetFirewallRule -DisplayName 'TestServer*' | Remove-NetFirewallRule
# Get-Process iperf3, twampy -ErrorAction SilentlyContinue | Stop-Process -Force
# Remove-Item -Recurse -Force C:\TestServer
