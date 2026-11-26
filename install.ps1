$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*tv-dimmer.ps1*' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "ปิดตัวเก่า PID $($_.ProcessId)" }

$oldLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'tv-dimmer.lnk'
if (Test-Path $oldLnk) { Remove-Item $oldLnk; Write-Host "ลบ $oldLnk" }

$key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM'
$cur = (Get-ItemProperty -Path $key -Name GdiIcmGammaRange -ErrorAction SilentlyContinue).GdiIcmGammaRange
if ($cur -ne 256) {
    Write-Host 'ขอสิทธิ์ admin เพื่อตั้งค่า GdiIcmGammaRange = 256'
    $cmd = "if (-not (Test-Path '$key')) { New-Item -Path '$key' | Out-Null }; New-ItemProperty -Path '$key' -Name GdiIcmGammaRange -PropertyType DWord -Value 256 -Force | Out-Null"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -EncodedCommand $enc"
    $cur = (Get-ItemProperty -Path $key -Name GdiIcmGammaRange -ErrorAction SilentlyContinue).GdiIcmGammaRange
}
Write-Host "GdiIcmGammaRange = $cur"

$vbs = Join-Path $dir 'launch.vbs'
$desktop = [Environment]::GetFolderPath('Desktop')
$tmpLnk = Join-Path $desktop 'tv-dimmer.lnk'
$lnk = Join-Path $desktop 'ความสว่างจอ.lnk'
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($tmpLnk)
$s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$s.Arguments = "`"$vbs`""
$s.WorkingDirectory = $dir
$s.IconLocation = (Join-Path $env:WINDIR 'System32\DisplaySwitch.exe') + ',0'
$s.Save()
Move-Item -LiteralPath $tmpLnk -Destination $lnk -Force
Write-Host "สร้างไอคอนที่ $lnk"

Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList "`"$vbs`""
Write-Host 'เปิดหน้าต่างปรับความสว่างแล้ว'
