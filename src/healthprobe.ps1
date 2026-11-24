# =====================================================================
#  启动体检子进程（v3.5 新增）
#
#  为什么单独一个进程：
#    体检里要碰 SetupAPI 和 WMI。这两样在故障机上可能不返回（不是慢，
#    是一直挂着）。放在 UI 线程里跑，窗口就跟着一起躺下，现场只能强关。
#    搬到子进程后，父窗口最多等 N 秒，超时直接放弃，界面照常能用。
#
#  输出：制表符分隔的文本文件，父进程解析后自己排版。
#    格式  <键>\t<字段1>\t<字段2>...
# =====================================================================
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Prog = '',
    [string]$Lang = 'zh'
)

$ErrorActionPreference = 'Stop'

$corePath = Join-Path $PSScriptRoot 'comfix-core.ps1'
. $corePath
CF-SetLang $Lang

$L = New-Object System.Collections.ArrayList
function Emit([string]$k, [string[]]$f) {
    [void]$L.Add(($k + "`t" + ($f -join "`t")))
}

# v3.6：每进入一步就覆盖写一次阶段文件，父窗口轮询读它来画进度。
# 格式：<阶段>	<附带数字>
#   read / stat / env / deep
# 写失败不能影响体检本身，所以整个 try 包住。
$progEnc = New-Object System.Text.UTF8Encoding($false)
function Write-Prog([string]$k, [string]$n = '') {
    if (-not $Prog) { return }
    try { [System.IO.File]::WriteAllText($Prog, ($k + "`t" + $n), $progEnc) } catch { }
}

try {
    CF-ResetPresentCache
    CF-ResetDeviceCache

    Write-Prog 'read'
    $h = CF-HealthCheck
    # 记录条数是「为什么这么慢」最直观的解释，父窗口会把它显示在进度条旁边
    Write-Prog 'read' ([string]($h.UsbTotal + $h.Offline))
    Emit 'hint' @([string]$h.Online)
    Emit 'pool' @([string]$h.Used, [string]$h.Free, [string]$h.MaxUsed)
    Emit 'serial' @([string]$h.Online, [string]$h.Offline, [string]$h.BadFlags)

    $dupN = 0
    foreach ($d in $h.Duplicates) { $dupN++ }
    if ($dupN -gt 0) { Emit 'dup' @([string]$dupN) }
    if ($h.Orphans.Count -gt 0) { Emit 'orphan' @([string]$h.Orphans.Count) }

    Emit 'usbtot' @([string]$h.UsbTotal, [string]$h.UsbOffline)
    foreach ($k in @($h.CatCount.Keys | Sort-Object)) {
        $on = 0; $off = 0
        if ($h.CatOnline.ContainsKey($k)) { $on = $h.CatOnline[$k] }
        if ($h.CatOff.ContainsKey($k)) { $off = $h.CatOff[$k] }
        Emit 'cat' @([string]$k, [string]$h.CatCount[$k], [string]$on, [string]$off)
    }

    Write-Prog 'stat'
    $hot = @(CF-GetUsbGroups | Where-Object { -not $_.Protected -and $_.Offline -ge 20 } |
             Sort-Object -Property Offline -Descending | Select-Object -First 3)
    foreach ($g in $hot) {
        Emit 'hot' @([string]$g.Group, [string]$g.Offline, [string]$g.Category)
    }

    Write-Prog 'env'
    $env2 = CF-CheckEnvironment
    foreach ($i in $env2.Issues) { Emit 'issue' @(([string]$i).Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ')) }

    Write-Prog 'deep'
    $deep = CF-CheckDeep
    foreach ($i in $deep.Issues) { Emit 'deepissue' @(([string]$i).Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' ')) }

    Emit 'end' @('ok')
} catch {
    Emit 'end' @('err')
    Emit 'issue' @(([string]$_.Exception.Message).Replace("`t", ' ').Replace("`r", ' ').Replace("`n", ' '))
}

$enc = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($Out, [string[]]$L.ToArray(), $enc)
