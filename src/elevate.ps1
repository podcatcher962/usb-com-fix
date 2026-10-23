# =====================================================================
#  提权启动器 —— 由 bat 在「非管理员」状态下调用
#  作用：以管理员身份重新启动 bat 本身。
#        被拒绝时弹框说清楚，不留下看不见的常驻进程。
# =====================================================================
param([string]$Target = '')

$nl  = [Environment]::NewLine
$ttl = 'USB / 串口 一键修复 · 需要管理员权限'
$msg = '这个工具要修改设备记录和系统设置，必须以管理员身份运行。' + $nl + $nl +
       '如果屏幕上弹出了「用户账户控制」窗口，请点「是」。' + $nl +
       '如果没弹出、或者被拒绝了，请右键这个 bat →「以管理员身份运行」。' + $nl + $nl +
       'Administrator rights are required. Right-click the .bat file ' +
       'and choose "Run as administrator".'

function Show-Fail {
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        [void][System.Windows.Forms.MessageBox]::Show(
            $msg, $ttl,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
    } catch { }
}

if ($Target -eq '' -or -not (Test-Path -LiteralPath $Target)) {
    Show-Fail
    exit 2
}

# 优先最小化启动（不闪黑框）；个别系统不接受这个组合时退回普通方式。
$ok = $false
try {
    Start-Process -FilePath $Target -Verb RunAs -WindowStyle Minimized -ErrorAction Stop | Out-Null
    $ok = $true
} catch {
    try {
        Start-Process -FilePath $Target -Verb RunAs -ErrorAction Stop | Out-Null
        $ok = $true
    } catch {
        $ok = $false
    }
}

if (-not $ok) { Show-Fail; exit 1 }
exit 0
