# =====================================================================
#  启动失败报告 —— 由 bat 在主程序异常退出时调用
#  作用：把启动阶段的输出写到桌面，避免「双击闪一下就没了」无从查起
# =====================================================================
param([string]$LogPath = '')

$d = ''
try { $d = [Environment]::GetFolderPath('Desktop') } catch { }
if (-not $d -or -not (Test-Path $d)) { $d = $env:USERPROFILE }

$out = ''
if ($LogPath -ne '' -and (Test-Path $LogPath)) {
    try { $out = [System.IO.File]::ReadAllText($LogPath) } catch { }
}

$L = New-Object System.Collections.ArrayList
[void]$L.Add('USB / 串口 一键修复 —— 启动失败')
[void]$L.Add('================================================')
[void]$L.Add('时间 : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$L.Add('电脑 : ' + $env:COMPUTERNAME)
try { [void]$L.Add('系统 : ' + [Environment]::OSVersion.VersionString) } catch { }
try { [void]$L.Add('位数 : ' + $(if ([Environment]::Is64BitOperatingSystem) { '64 位' } else { '32 位' })) } catch { }
[void]$L.Add('路径 : ' + $PSScriptRoot)
[void]$L.Add('')
[void]$L.Add('---------------- 启动时的输出 ----------------')
if ($out.Trim() -ne '') {
    foreach ($line in ($out -split "`r?`n")) { [void]$L.Add($line) }
} else {
    [void]$L.Add('(程序没有任何输出就退出了)')
}
[void]$L.Add('')
[void]$L.Add('---------------- 常见的三个原因 ----------------')
[void]$L.Add('  1. 被安全软件拦掉了 PowerShell 脚本（360 / 火绒 / 趋势最常见）')
[void]$L.Add('     —— 把这个文件夹加入白名单，或先临时退出安全软件再试')
[void]$L.Add('  2. 直接在压缩包里双击，没有先解压到硬盘')
[void]$L.Add('  3. 系统 PowerShell 被禁用或损坏')
[void]$L.Add('     —— 在「开始 - 运行」里输 powershell 看能不能打开')
[void]$L.Add('')
[void]$L.Add('请把这个文件发给开发，就能定位是哪一种。')

$f = Join-Path $d 'USB修复-启动失败.txt'
$enc = New-Object System.Text.UTF8Encoding($true)
try { [System.IO.File]::WriteAllLines($f, $L, $enc) } catch { }

# 控制台窗口可能是隐藏状态（bat 用 -WindowStyle Hidden 启动），
# 所以这里必须自己弹一个提示框，保证用户知道程序出了问题。
try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $nl  = [Environment]::NewLine
    $msg = '程序异常退出，没能打开窗口。' + $nl + $nl +
           '已在桌面生成：USB修复-启动失败.txt' + $nl +
           '请把这个文件发给开发，就能定位是哪一种原因。' + $nl + $nl +
           'The program exited unexpectedly.' + $nl +
           'A report has been written to the Desktop: USB修复-启动失败.txt'
    [void][System.Windows.Forms.MessageBox]::Show(
        $msg,
        'USB / 串口 一键修复 / USB / COM Port Fix',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
} catch { }
