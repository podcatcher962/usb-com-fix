# ============================================================
#  USB 新设备「完全认不出」深度取证
#  只读脚本：不修改任何设置、不删任何记录、不写注册表。
#  唯一一次写操作是在 Enum\USB 下建一个临时探针键并立刻删除。
#  兼容 Windows 7/8/10/11，PowerShell 5.1，32 位 / 64 位
# ============================================================
param(
    [string]$OutDir = '',
    [string]$OutName = 'USB认不出-取证报告.txt',
    [switch]$NoOpen
)

# ---- 报告输出目录（2026-11-04 起不再往桌面写，按顺序回退）----
function Get-ReportDir {
    $here = ''
    try { $here = $PSScriptRoot } catch { }
    if (-not $here) { try { $here = $PSCommandPath } catch { } }
    $base = $here
    if ($here -and (Split-Path -Leaf $here) -eq '_program') { $base = Split-Path -Parent $here }

    $cand = New-Object System.Collections.ArrayList
    if ($env:WB_REPORT_DIR) { [void]$cand.Add($env:WB_REPORT_DIR) }
    if ($base) { [void]$cand.Add((Join-Path $base '报告')) }
    try { [void]$cand.Add([Environment]::GetFolderPath('Desktop')) } catch { }
    [void]$cand.Add($env:TEMP)

    foreach ($c in $cand) {
        if (-not $c) { continue }
        try { if (-not [System.IO.Directory]::Exists($c)) { [void][System.IO.Directory]::CreateDirectory($c) } } catch { }
        if ([System.IO.Directory]::Exists($c)) { return $c }
    }
    return $env:TEMP
}

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936) } catch { }

$script:L = New-Object System.Collections.ArrayList
function W([string]$s) { [void]$script:L.Add($s) }
function WL() { [void]$script:L.Add('') }
function Sep([string]$t) {
    WL
    W ('==================================================')
    W ('  ' + $t)
    W ('==================================================')
}

function Is-Admin {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# ---- 读文件末尾若干字节（日志可能几十 MB） ----
function Read-Tail([string]$path, [int]$maxBytes = 524288) {
    if (-not (Test-Path $path)) { return '' }
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open,
                                     [System.IO.FileAccess]::Read,
                                     [System.IO.FileShare]::ReadWrite)
        $len = $fs.Length
        $start = [Math]::Max(0, $len - $maxBytes)
        [void]$fs.Seek($start, [System.IO.SeekOrigin]::Begin)
        $cnt = [int]($len - $start)
        $buf = New-Object byte[] $cnt
        [void]$fs.Read($buf, 0, $cnt)
        return [System.Text.Encoding]::Default.GetString($buf)
    } catch {
        return ''
    } finally {
        if ($fs) { $fs.Close() }
    }
}

# ---- 注册表读值（不存在返回 $null） ----
function RegGet([string]$key, [string]$name) {
    try {
        $k = Get-Item $key -ErrorAction Stop
        return $k.GetValue($name)
    } catch { return $null }
}

# ---- ConfigFlags 位解释 ----
function CfgText([int]$f) {
    if ($f -eq 0) { return '0（正常）' }
    $m = @()
    if ($f -band 0x0001) { $m += '已禁用' }
    if ($f -band 0x0002) { $m += '已移除' }
    if ($f -band 0x0004) { $m += '手动安装' }
    if ($f -band 0x0008) { $m += '忽略启动配置' }
    if ($f -band 0x0020) { $m += '需重装驱动' }
    if ($f -band 0x0040) { $m += '安装失败' }
    if ($f -band 0x0080) { $m += '启动覆盖' }
    if ($f -band 0x0200) { $m += '需强制配置' }
    if ($m.Count -eq 0) { return ('0x' + ('{0:X2}' -f $f)) }
    return ('0x' + ('{0:X2}' -f $f) + '（' + ($m -join '、') + '）')
}

# ---- 判断一条实例记录属于哪一类 ----
# 有序列号：USB\VID_x&PID_y\<序列号字符串>
# 无序列号：USB\VID_x&PID_y\5&2f4a1b3c&0&1   （首段为 5& / 6& / 7& / 8&）
#
# v3.7 修正：复合设备的子接口（组名带 &MI_00 / &MI_01）末段同样是 6&xxx&0&000N，
#   但那个 6&xxx 是「父设备实例路径的哈希」—— 父设备带序列号时它也跟着唯一。
#   原来一律算成「无序列号、同口共用一条」，于是把 8064 台成品的 16000 多条
#   正常接口记录说成「空片共用的坏记录」，整段结论方向反了。
function InstKind([string]$grp, [string]$inst) {
    $parts = $inst.Split('\')
    if ($parts.Count -lt 2) { return 'Serial' }
    $last = $parts[$parts.Count - 1]
    if ($last -notmatch '^[5-9]&') { return 'Serial' }
    if ($grp -match '&MI_\d+') { return 'Iface' }
    return 'NoSerial'
}
function NoSerial([string]$inst) {
    $parts = $inst.Split('\')
    if ($parts.Count -lt 2) { return $false }
    $last = $parts[$parts.Count - 1]
    return ($last -match '^[5-9]&')
}

$fails = @()

$isAdmin = Is-Admin
$root    = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB'

W 'USB 新设备「完全认不出」深度取证报告'
W ('生成时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W ('管理员权限：' + $(if ($isAdmin) { '是' } else { '否（部分项目受限，建议右键以管理员身份运行）' }))
W '本报告只读，不会修改任何设置。'

# ============================================================
Sep '一、这台电脑的基本情况'
# ============================================================
try {
    $os = Get-CimInstance Win32_OperatingSystem
    W ('系统版本  ：' + $os.Caption + '  ' + $os.Version + '  Build ' + $os.BuildNumber)
    W ('系统位数  ：' + $os.OSArchitecture + '      进程位数：' + $(if ([Environment]::Is64BitProcess) { '64 位' } else { '32 位' }))
    W ('安装时间  ：' + $os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss') + '（距今 ' + [int]((Get-Date) - $os.InstallDate).TotalDays + ' 天）')
    W ('上次启动  ：' + $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss'))
    # v3.7：完全离线的机器时间经常是错的（CMOS 电池没电、没有对时服务器）。
    # 判据用「系统文件的时间戳有没有跑到未来」——系统文件不可能被写到未来，
    # 一旦出现就说明机器时钟被调慢了。这个判据不会被休眠 / 长任务干扰，不会误报。
    try {
        $now = Get-Date
        $worst = $null
        $worstF = ''
        $cands = @(
            (Join-Path $env:SystemRoot 'System32\ntoskrnl.exe'),
            (Join-Path $env:SystemRoot 'System32\kernel32.dll'),
            (Join-Path $env:SystemRoot 'INF\setupapi.dev.log')
        )
        foreach ($cf in $cands) {
            if (-not (Test-Path $cf)) { continue }
            $mt = (Get-Item $cf).LastWriteTime
            if ($mt -gt $now.AddDays(1)) {
                if ($null -eq $worst -or $mt -gt $worst) { $worst = $mt; $worstF = (Split-Path -Leaf $cf) }
            }
        }
        if ($null -ne $worst) {
            W ('时间校验  ：！' + $worstF + ' 的时间是 ' + $worst.ToString('yyyy-MM-dd HH:mm') + '，比当前系统时间还晚 ' + [int](($worst - $now).TotalDays) + ' 天')
            W '            说明本机时钟被调慢了（离线机器常见，主板电池没电也会这样）。'
            W '            下面所有时间戳只能看先后顺序，不能当真实日期。'
        } else {
            W '时间校验  ：系统文件时间都在当前时间之前，本机时钟没有明显偏差。'
        }
    } catch { }
} catch { W '（系统信息读取失败）' }

# 主板串口（用来区分「主板上真有串口」还是「全靠 USB 转串口」）
$mbPorts = @()
try {
    $mbPorts = @(Get-CimInstance Win32_SerialPort | Where-Object { $_.PNPDeviceID -notlike 'USB*' })
} catch { }
W ('主板自带串口：' + $(if ($mbPorts.Count -gt 0) { ($mbPorts | ForEach-Object { $_.DeviceID }) -join ', ' } else { '无（全部靠 USB 转串口）' }))

# ============================================================
Sep '二、设备安装策略（组策略）—— 新设备装不上的头号嫌疑'
# ============================================================
W '说明：如果这里被设了「禁止安装」，已装好的设备照常能用，'
W '      但任何没装过的新设备都会被直接拒绝安装 ——'
W '      表现就是「老机器能认、新机器一点反应都没有」。'
W ''

$polRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall'
$polHit  = $false

if (Test-Path $polRoot) {
    W ('【发现策略键】' + $polRoot)
    W ''

    $res = Join-Path $polRoot 'Restrictions'
    if (Test-Path $res) {
        foreach ($kv in @(
            @{N='DenyUnspecified';      D='禁止安装「未在允许列表里的设备」'},
            @{N='DenyDeviceIDs';        D='禁止安装指定硬件 ID 的设备'},
            @{N='DenyDeviceIDsRetroactive'; D='（追溯）连已装好的也停用'},
            @{N='DenyDeviceClasses';    D='禁止安装指定设备类'},
            @{N='DenyDeviceClassesRetroactive'; D='（追溯）连已装好的也停用'},
            @{N='AllowDeviceIDs';       D='允许列表（只有这里的才让装）'},
            @{N='AllowDeviceClasses';   D='允许的设备类列表'}
        )) {
            $v = RegGet $res $kv.N
            if ($null -ne $v) {
                $txt = ''
                if ($v -is [array]) { $txt = ($v -join ' | ') } else { $txt = [string]$v }
                if ($txt.Trim() -ne '') {
                    W ('    ' + $kv.N.PadRight(32) + '= ' + $txt)
                    W ('      → ' + $kv.D)
                    if ($kv.N -eq 'DenyUnspecified' -and [string]$v -eq '1') {
                        $polHit = $true
                        W '      ★★★ 这一条就是病因：未列出的设备一律拒绝安装。'
                    }
                    if ($kv.N -match 'DenyDeviceIDs$|DenyDeviceClasses$' -and $txt -ne '') {
                        $polHit = $true
                    }
                }
            }
        }
    } else {
        W '    （没有 Restrictions 子键）'
    }

    $set = Join-Path $polRoot 'Settings'
    if (Test-Path $set) {
        W ''
        W '    Settings 子键下的值：'
        foreach ($n in (Get-Item $set).GetValueNames()) {
            $v = RegGet $set $n
            if ($v -is [array]) { $v = ($v -join ' | ') }
            W ('      ' + $n.PadRight(38) + '= ' + [string]$v)
        }
    }
} else {
    W '未发现设备安装策略键（这一项正常）。'
}
WL
# 其它可能拦截安装的位置
W '其它相关策略位置（有值才列出）：'
$other = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DeviceInstall',
    'HKLM:\SYSTEM\CurrentControlSet\Policies\DeviceInstall'
)
$otherHit = $false
foreach ($o in $other) {
    if (-not (Test-Path $o)) { continue }
    foreach ($n in (Get-Item $o).GetValueNames()) {
        $v = RegGet $o $n
        if ($v -is [array]) { $v = ($v -join ' | ') }
        W ('    ' + $o + ' \ ' + $n + ' = ' + [string]$v)
        $otherHit = $true
        if ($n -eq 'Deny_All' -and [string]$v -eq '1') { $polHit = $true }
    }
}
if (-not $otherHit) { W '    （无）' }

# 客户端「驱动搜索顺序」
$soc = RegGet 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig'
WL
W ('驱动搜索顺序 SearchOrderConfig = ' + $(if ($null -ne $soc) { [string]$soc } else { '未设置（默认 1：允许 Windows Update 找驱动）' }))
if ($null -ne $soc -and [string]$soc -eq '0') {
    W '    ⚠ 设为 0 表示「从不安装驱动程序」，新设备可能装不上。'
}

# ============================================================
Sep '三、驱动安装日志（最硬的证据）'
# ============================================================
$logPath = Join-Path $env:SystemRoot 'INF\setupapi.dev.log'
W ('日志文件：' + $logPath)
if (-not (Test-Path $logPath)) {
    W '！找不到这个日志。可能被清理过，或者系统策略禁止记录。'
} else {
    try {
        $fi = Get-Item $logPath
        W ('文件大小：' + [math]::Round($fi.Length / 1MB, 2) + ' MB    最后写入：' + $fi.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    } catch { }
    WL
    $tail = Read-Tail $logPath 524288
    $lines = $tail -split "`r?`n"

    # 配对解析：>>>  [Device Install ...  →  <<<  [Exit status: ...
    $recs   = New-Object System.Collections.ArrayList
    $pending = $null
    $lastTime = ''
    foreach ($ln in $lines) {
        if ($ln -match '>>>\s+\[Device Install') {
            $dev = ''
            $m = [regex]::Match($ln, '-\s*(.+?)\]\s*$')
            if ($m.Success) { $dev = $m.Groups[1].Value }
            $pending = @{ Dev = $dev; Time = $lastTime }
        } elseif ($ln -match '>>>\s+Section start\s+(.+)$') {
            $lastTime = $matches[1].Trim()
        } elseif ($ln -match '<<<\s+\[Exit status:\s*(.+?)\]') {
            if ($pending) {
                $pending.Status = $matches[1].Trim()
                [void]$recs.Add($pending)
                $pending = $null
            }
        }
    }

    W ('日志中共找到 ' + $recs.Count + ' 次设备安装记录（下面列出最近 20 次）：')
    WL
    if ($recs.Count -eq 0) {
        W '  日志尾部没有 Device Install 记录。'
        W '  说明：日志可能被清理，或系统未记录。请插上新机器后再跑一次本工具。'
    } else {
        $show = @($recs | Select-Object -Last 20)
        W ('  ' + '时间'.PadRight(28) + '结果'.PadRight(26) + '设备')
        W ('  ' + ('-' * 104))
        foreach ($r in $show) {
            $rs  = [string]$r.Status
            $dev = [string]$r.Dev
            if ($dev.Length -gt 48) { $dev = $dev.Substring(0, 48) + '..' }
            W ('  ' + ([string]$r.Time).PadRight(26) + $rs.PadRight(26) + $dev)
        }
    }

    # 失败明细
    $fails = @($recs | Where-Object { [string]$_.Status -match 'FAILURE' })
    WL
    if ($fails.Count -gt 0) {
        W '【安装失败记录】' + $fails.Count + ' 次'
        $codes = @{}
        foreach ($f in $fails) {
            $c = [string]$f.Status
            if ($codes.ContainsKey($c)) { $codes[$c]++ } else { $codes[$c] = 1 }
        }
        W ''
        W '  错误代码统计：'
        foreach ($k in $codes.Keys) {
            W ('    ' + $k.PadRight(34) + '出现 ' + $codes[$k] + ' 次')
        }
        WL
        W '  最近 6 次失败涉及的设备：'
        foreach ($f in @($fails | Select-Object -Last 6)) {
            W ('    ' + [string]$f.Time + '   ' + [string]$f.Dev + '   → ' + [string]$f.Status)
        }
        WL
        W '  常见错误码含义：'
        W '    0xE0000228  本机没有匹配的驱动程序 —— INF 里没有认领这个硬件 ID 的条目'
        W '    0xE0000247  找不到匹配的驱动程序（最常见：新设备没驱动可装）'
        W '    0xE000024B  安装被策略或权限阻断'
        W '    0xE0000203  驱动文件损坏或无法复制'
        W '    0xE0000217  驱动签名未通过'
        W '    0xE0000100  通用失败（需看日志正文）'
        W '    0x80070005  拒绝访问（权限）'
        W '    0x800F0246  驱动包损坏'
    } else {
        W '【安装失败记录】无'
    }

    # 日志里的错误行
    $errc = @($lines | Where-Object { $_ -match '^!!!' })
    WL
    if ($errc.Count -gt 0) {
        W ('日志中的错误行（' + $errc.Count + ' 条，取最后 12 条）：')
        foreach ($e in @($errc | Select-Object -Last 12)) {
            $s = $e.Trim()
            if ($s.Length -gt 150) { $s = $s.Substring(0, 150) + '..' }
            W ('  ' + $s)
        }
    }
}

# ============================================================
Sep '四、系统事件日志（最近的 PnP 失败）'
# ============================================================
$evtShown = 0
try {
    $ev = @(Get-WinEvent -FilterHashtable @{
                LogName   = 'Microsoft-Windows-Kernel-PnP/Configuration'
                StartTime = (Get-Date).AddDays(-7)
             } -MaxEvents 60 -ErrorAction Stop |
             Where-Object { $_.LevelDisplayName -match '错误|Error' })
    if ($ev.Count -gt 0) {
        W ('Kernel-PnP 错误事件 ' + $ev.Count + ' 条（近 7 天，取最近 15 条）：')
        foreach ($e in @($ev | Select-Object -First 15)) {
            $msg = ($e.Message -replace "`r?`n", ' ')
            if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) + '..' }
            W ('  ' + $e.TimeCreated.ToString('MM-dd HH:mm') + '  [' + $e.Id + ']  ' + $msg)
            $evtShown++
        }
    } else {
        W 'Kernel-PnP 近 7 天没有错误事件。'
    }
} catch {
    W 'Kernel-PnP 事件日志读取不到（可能被关闭）。'
}
WL
try {
    $ev2 = @(Get-WinEvent -FilterHashtable @{
                 LogName = 'System'
                 ProviderName = 'Microsoft-Windows-UserPnp'
                 StartTime = (Get-Date).AddDays(-7)
             } -MaxEvents 40 -ErrorAction Stop)
    if ($ev2.Count -gt 0) {
        W ('UserPnp 事件 ' + $ev2.Count + ' 条（近 7 天，取最近 10 条）：')
        foreach ($e in @($ev2 | Select-Object -First 10)) {
            $msg = ($e.Message -replace "`r?`n", ' ')
            if ($msg.Length -gt 110) { $msg = $msg.Substring(0, 110) + '..' }
            W ('  ' + $e.TimeCreated.ToString('MM-dd HH:mm') + '  [' + $e.Id + ']  ' + $msg)
        }
    }
} catch { }

# ============================================================
Sep '五、现在到底有没有「反应」—— 未知设备与报错设备'
# ============================================================
W '说明：插上新机器时设备管理器里「什么都不多」和「多一个未知设备」'
W '      是完全不同的两种病。这一节直接给出答案。'
WL

$unknown  = New-Object System.Collections.ArrayList
$errored  = New-Object System.Collections.ArrayList
$presentUsb = New-Object System.Collections.ArrayList
$nonUsbErr  = New-Object System.Collections.ArrayList

$cimTotal = 0
$cimOk = $false
try {
    $all = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
    $cimTotal = $all.Count
    $cimOk = $true
    foreach ($d in $all) {
        $devId = [string]$d.PNPDeviceID
        if ($devId -eq '') { continue }
        if ($devId -like 'USB\*' -or $devId -like 'USBSTOR\*') {
            [void]$presentUsb.Add($d)
        }
        $code = 0
        try { $code = [int]$d.ConfigManagerErrorCode } catch { $code = 0 }
        if ($code -ne 0) {
            [void]$errored.Add($d)
            $cls = [string]$d.PNPClass
            # v3.7：只把「USB 总线上的设备」算作未知设备。原来没按总线过滤，
            # 主板芯片组的 SM 总线控制器（错误码 28）会被当成本次要找的
            # 「未知 USB 设备」，把结论引到完全相反的方向。
            $onUsb = ($devId -like 'USB\*' -or $devId -like 'USBSTOR\*')
            if ($onUsb) {
                if ($cls -eq '' -or $cls -eq 'Unknown' -or $code -eq 28) {
                    [void]$unknown.Add($d)
                }
            } else {
                [void]$nonUsbErr.Add($d)
            }
        }
    }
} catch { $cimOk = $false }

if (-not $cimOk -or $cimTotal -eq 0) {
    W '！设备信息读取失败（拿不到系统设备列表），本节结论不可用。'
    W '  请用「右键 - 以管理员身份运行」重跑本工具。'
    WL
} else {
    W ('系统里共有设备记录：' + $cimTotal + ' 个（用来确认读取成功，不是 0 就说明读到了）')
    W ('其中 USB 设备       ：' + $presentUsb.Count + ' 个')
    W ('有错误代码的设备    ：' + $errored.Count + ' 个')
    W ('其中「未知/无驱动」 ：' + $unknown.Count + ' 个')
    WL
    # 按设备类粗略分组，证明报告真的读到了东西
    $byClass = @{}
    foreach ($p in $presentUsb) {
        $cn2 = [string]$p.PNPClass
        if ($cn2 -eq '') { $cn2 = '(未分类)' }
        if ($byClass.ContainsKey($cn2)) { $byClass[$cn2]++ } else { $byClass[$cn2] = 1 }
    }
    if ($byClass.Count -gt 0) {
        $parts = @()
        foreach ($k in ($byClass.Keys | Sort-Object)) { $parts += ($k + ' ' + $byClass[$k] + ' 个') }
        W ('  USB 设备分类：' + ($parts -join '，'))
        WL
    }
}
if ($errored.Count -gt 0) {
    W '报错设备清单（最多 20 个）：'
    W ('  ' + '错误码'.PadRight(8) + '含义'.PadRight(26) + '设备名')
    $codeName = @{
        1='设备未配置'; 3='驱动已损坏'; 10='设备无法启动'; 12='资源冲突';
        14='需要重启'; 18='需重装驱动'; 19='注册表损坏'; 21='系统正在移除';
        22='设备已禁用'; 24='设备不存在'; 28='未安装驱动程序'; 31='无法加载驱动';
        32='驱动服务启动失败'; 37='驱动初始化失败'; 39='驱动已损坏或缺失';
        43='设备报错已被停止'; 45='设备未连接'; 52='驱动签名未通过'
    }
    foreach ($e in @($errored | Select-Object -First 20)) {
        $c = 0
        try { $c = [int]$e.ConfigManagerErrorCode } catch { $c = 0 }
        $cn = $(if ($codeName.ContainsKey($c)) { $codeName[$c] } else { '-' })
        $nm = ([string]$e.Name)
        if ($nm.Length -gt 40) { $nm = $nm.Substring(0, 40) + '..' }
        W ('  ' + ([string]$c).PadRight(8) + $cn.PadRight(24) + $nm)
    }
    WL
    W '  「错误码 28 = 未安装驱动程序」= 设备已被系统看到，但没有可用驱动。'
    W '  「错误码 10 / 31」 = 看到了但驱动加载失败。'
    W '  「错误码 43」 = 设备上报故障后系统主动停止它。'
} else {
    W '当前没有任何设备处在错误状态。'
    W '如果此时正插着那台认不出的新机器，说明系统连「新设备来过」都没记录 ——'
    W '问题在 USB 枚举之前，属于硬件/端口/线材层，软件修不了。'
}
WL
if ($nonUsbErr.Count -gt 0) {
    W ('【其它总线上的报错设备】' + $nonUsbErr.Count + ' 个（与 USB 无关，只作参照，别当证据）')
    foreach ($e in @($nonUsbErr | Select-Object -First 8)) {
        $c2 = 0
        try { $c2 = [int]$e.ConfigManagerErrorCode } catch { $c2 = 0 }
        $nm2 = [string]$e.Name
        if ($nm2.Length -gt 44) { $nm2 = $nm2.Substring(0, 44) + '..' }
        W ('  错误码 ' + ([string]$c2).PadRight(6) + $nm2)
    }
}

# ============================================================
Sep '五之二、USB 控制器与根集线器（「插什么都没反应」要看这里）'
# ============================================================
W '说明：如果现场是「插任何 USB 设备都没反应」，而不是某一台认不出，'
W '      病根通常在根集线器 / 主机控制器这一层，不在单个设备的记录上。'
W '      在设备管理器里「删掉所有 USB 设备再重扫」能恢复，就是这一层的证据 ——'
W '      那个操作真正动到的是根集线器和控制器，重扫时系统把整棵 USB 树重建一遍。'
WL

$liveMap = @{}
if ($cimOk) {
    foreach ($d in @($all)) { $liveMap[([string]$d.PNPDeviceID).ToUpper()] = $d }
}

# --- 根集线器实例（ROOT_HUB20 / ROOT_HUB30）---
# 正常一台机器 1~3 条。数量异常偏多 = 这棵树被反复重建过，端口状态可能有残留。
$rhRows = New-Object System.Collections.ArrayList
if (Test-Path $root) {
    foreach ($g in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
        if ($g.PSChildName -notmatch '^ROOT_HUB') { continue }
        foreach ($i in @(Get-ChildItem $g.PSPath -ErrorAction SilentlyContinue)) {
            $iid = 'USB\' + $g.PSChildName + '\' + [string]$i.PSChildName
            $cfg = RegGet $i.PSPath 'ConfigFlags'
            $cf = 0
            if ($null -ne $cfg) { try { $cf = [int]$cfg } catch { $cf = 0 } }
            $st = '离线'
            if ($liveMap.ContainsKey($iid.ToUpper())) {
                $st = '在线'
                $lc = 0
                try { $lc = [int]$liveMap[$iid.ToUpper()].ConfigManagerErrorCode } catch { $lc = 0 }
                if ($lc -ne 0) { $st = '报错' + $lc }
            }
            [void]$rhRows.Add(@{ Iid = $iid; Flags = $cf; St = $st })
        }
    }
}
$rhOff = @($rhRows | Where-Object { $_.St -ne '在线' }).Count
$rhErr = @($rhRows | Where-Object { $_.St -like '报错*' }).Count
$rhOn  = $rhRows.Count - $rhOff - $rhErr
W ('根集线器实例：' + $rhRows.Count + ' 条（在线 ' + $rhOn + '，离线 ' + $rhOff + '，报错 ' + $rhErr + '）')
foreach ($r in $rhRows) {
    W ('  ' + $r.Iid.PadRight(46) + $r.St.PadRight(10) + ('ConfigFlags=' + (CfgText $r.Flags)))
}
# 根集线器是焊在主板上的，正常情况必须全部在线。
# 离线的那几条 = 以前重建 USB 树时留下的空壳，条数越多说明反复出过事。
if ($rhRows.Count -eq 0) {
    W '  ！一条根集线器记录都没有 —— 严重异常，USB 树已经不在系统里。'
} elseif ($rhOn -eq 0) {
    W '  ！没有任何一条根集线器在线 —— 严重异常。'
} elseif ($rhOff -ge 3) {
    W '  ！离线根集线器有 ' + $rhOff + ' 条（正常应为 0）：这棵树被反复重建过，端口状态可能有残留。'
} elseif ($rhOff -ge 1) {
    W '  （' + $rhOff + ' 条离线根集线器记录，一般是历史残留，不影响使用）'
} else {
    W '  （全部在线，正常）'
}
WL

# --- 主机控制器（PCI 上的 xHCI / EHCI / OHCI）---
$ctrls = @()
if ($cimOk) {
    $ctrls = @($all | Where-Object {
        ([string]$_.PNPDeviceID) -like 'PCI\*' -and
        ([string]$_.Service) -match '^(USBXHCI|USBEHCI|USBOHCI|USBHUB3|usbhub|usbccgp)$'
    })
}
W ('USB 主机控制器：' + $ctrls.Count + ' 个')
foreach ($c in $ctrls) {
    $cc = 0
    try { $cc = [int]$c.ConfigManagerErrorCode } catch { $cc = 0 }
    $cn2 = [string]$c.Name
    if ($cn2.Length -gt 44) { $cn2 = $cn2.Substring(0, 44) + '..' }
    W ('  ' + $cn2.PadRight(46) + ('错误码 ' + $cc))
}
if ($ctrls.Count -eq 0 -and $cimOk) {
    W '  ！一个 USB 主机控制器都没读到 —— 要么读不到，要么控制器真的不在。'
}
WL
W '判读：根集线器/控制器这一层出问题，清设备记录是修不好的，'
W '      要「把控制器重启一遍」（本工具菜单：工具 → 重置 USB 控制器）。'
WL

# ============================================================
Sep '六、Enum\USB 权限与「能不能新建记录」实测'
# ============================================================
if (-not (Test-Path $root)) {
    W '！Enum\USB 键不存在，这不正常。'
} else {
    try {
        $acl = Get-Acl $root
        $sys = $false; $adm = $false
        foreach ($r in $acl.Access) {
            if ($r.AccessControlType -ne 'Allow') { continue }
            $who = [string]$r.IdentityReference
            $rgt = [string]$r.RegistryRights
            if ($who -match 'SYSTEM' -and $rgt -match 'FullControl|WriteKey') { $sys = $true }
            if ($who -match 'Administrators' -and $rgt -match 'FullControl|WriteKey') { $adm = $true }
        }
        $deny = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' })
        W ('SYSTEM 可写         ：' + $sys)
        W ('管理员可写         ：' + $adm)
        W ('「拒绝」条目数     ：' + $deny.Count + $(if ($deny.Count -gt 0) { '  ← 偏多就要留意' } else { '' }))
        if ($deny.Count -gt 0) {
            foreach ($d in $deny) {
                W ('    DENY ' + [string]$d.IdentityReference + '  ' + [string]$d.RegistryRights)
            }
        }
    } catch { W 'ACL 读取失败。' }

    WL
    if ($isAdmin) {
        $probe = $root + '\__usbprobe_tmp__'
        $ok = $false
        try {
            New-Item -Path $probe -Force -ErrorAction Stop | Out-Null
            $ok = $true
        } catch { }
        finally {
            try { Remove-Item $probe -Recurse -Force -ErrorAction Stop } catch { }
        }
        if ($ok) {
            W '【写入实测】通过 —— 系统能在这里创建设备实例记录（这一项正常）。'
        } else {
            W '【写入实测】失败 —— 新设备插上无法建立实例记录，'
            W '             这就是「完全认不出」的直接原因，必须优先修。'
        }
    } else {
        W '【写入实测】跳过（需要管理员权限）。请右键以管理员身份运行本工具再跑一次。'
    }
}

# ============================================================
Sep '七、设备类过滤器残留'
# ============================================================
$classes = @(
    @{ G='{36fc9e60-c465-11cf-8056-444553540000}'; N='USB 控制器类' },
    @{ G='{4d36e978-e325-11ce-bfc1-08002be10318}'; N='端口类（COM）' },
    @{ G='{a5dcbf10-6530-11d2-901f-00c04fb951ed}'; N='USB 设备类' },
    @{ G='{4d36e96d-e325-11ce-bfc1-08002be10318}'; N='调制解调器类' },
    @{ G='{ca3e7ab9-b4c3-4ae6-8251-579ef933890f}'; N='摄像头类' }
)
$filterHit = 0
foreach ($c in $classes) {
    $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $c.G
    if (-not (Test-Path $p)) { continue }
    foreach ($f in @('UpperFilters', 'LowerFilters')) {
        $v = RegGet $p $f
        if ($null -eq $v) { continue }
        foreach ($n in @($v)) {
            $nm = ([string]$n).Trim()
            if ($nm -eq '') { continue }
            $svc = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $nm
            $exists = Test-Path $svc
            $flag = ''
            if (-not $exists) { $flag = '   ← 服务已不存在，属于残留'; $filterHit++ }
            W ('  ' + $c.N.PadRight(18) + $f.PadRight(14) + $nm + $flag)
        }
    }
}
if ($filterHit -eq 0) {
    W '（没有发现「服务已被删、过滤项还留着」的残留）'
}

# ============================================================
Sep '七之二、USB 兼容性标志位（usbflags）'
# ============================================================
$ufKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\usbflags'
W '说明：这个键存的是「某个 VID/PID/版本 的 USB 兼容性开关」。'
W '      正常机器上条目很多（见过的每个设备一条），条目多本身不是问题。'
W '      要看的是有没有条目被设了非零值 —— 那等于强行给这个型号加了'
W '      「不按标准走」的行为，严重时会让整批设备一起认不出。'
WL
if (-not (Test-Path $ufKey)) {
    W '（本机没有这个键，属正常）'
} else {
    $ufAll = @(Get-ChildItem $ufKey -ErrorAction SilentlyContinue)
    W ('条目总数：' + $ufAll.Count)
    $ufNZ = New-Object System.Collections.ArrayList
    $ufNormal = 0
    foreach ($k in $ufAll) {
        try {
            foreach ($vn in @($k.GetValueNames())) {
                $vv = $k.GetValue($vn)
                if ($null -eq $vv) { continue }
                $num = 0
                if ($vv -is [byte[]]) {
                    for ($bi = 0; $bi -lt $vv.Length; $bi++) {
                        $num = $num -bor ([int]$vv[$bi] -shl (8 * $bi))
                    }
                } else {
                    try { $num = [int]$vv } catch { $num = 0 }
                }
                if ($num -ne 0) {
                    # osvc / SkipContainerIdQuery 是 Windows 自己按系统版本和设备类型
                    # 写进去的正常兼容设置，几乎每台机器都有一堆，不能当异常报。
                    if ($vn -eq 'osvc' -or $vn -eq 'SkipContainerIdQuery') {
                        $ufNormal++
                    } else {
                        [void]$ufNZ.Add($k.PSChildName + '  ' + $vn + ' = 0x' + ('{0:X}' -f $num))
                    }
                }
            }
        } catch { }
    }
    W ('系统自动写的兼容标记（osvc / SkipContainerIdQuery）：' + $ufNormal + ' 条 —— 属正常，不用管')
    W ('其它非零标志：' + $ufNZ.Count)
    if ($ufNZ.Count -gt 0) {
        W '  （下面这些才是被人为或第三方工具改过的型号，最多列 20 条）'
        foreach ($x in @($ufNZ | Select-Object -First 20)) { W ('    ' + $x) }
        if ($ufNZ.Count -gt 20) { W ('    …… 另有 ' + ($ufNZ.Count - 20) + ' 条') }
    } else {
        W '  （全部为 0，这一项正常）'
    }
}
WL

# ============================================================
Sep '八、设备记录构成：有序列号 / 复合接口 / 真无序列号'
# ============================================================
W '说明：记录分三种，混在一起数会把结论带偏。'
W '  有序列号（烧过固件的成品）：每台一条独立记录，插上就复用，稳定。'
W '  复合设备子接口（&MI_00 / &MI_01）：一台设备占好几条，跟着父设备走；'
W '      父设备带序列号时它也是唯一的，并不是「同一个口共用」。'
W '  真无序列号（空片 / 未烧固件）：Windows 只能按「插在哪个 USB 口」'
W '      生成记录，同一个口的所有空片共用一条。这条坏了，所有空片一起认不出。'
WL

$groups = @()
if (Test-Path $root) {
    $groups = @(Get-ChildItem $root | Where-Object { $_.PSChildName -like 'VID_*' })
}
W ('设备型号组（VID/PID）总数：' + $groups.Count)
WL

$badGroups = New-Object System.Collections.ArrayList
$rows = New-Object System.Collections.ArrayList
$serTotal = 0; $noSerTotal = 0; $ifaceTotal = 0

foreach ($g in $groups) {
    $gName = $g.PSChildName
    $insts = @(Get-ChildItem $g.PSPath)
    $gSer = 0; $gNo = 0; $gIf = 0
    $bad = @()
    foreach ($i in $insts) {
        $iid = $gName + '\' + [string]$i.PSChildName
        switch (InstKind $gName $iid) {
            'Iface'    { $gIf++ }
            'NoSerial' { $gNo++ }
            default    { $gSer++ }
        }
        $cfg = RegGet $i.PSPath 'ConfigFlags'
        $cf  = 0
        if ($null -ne $cfg) { try { $cf = [int]$cfg } catch { $cf = 0 } }
        if (($cf -band 0x0040) -or ($cf -band 0x0020)) {
            $bad += ($iid + '  ConfigFlags=' + (CfgText $cf))
        }
    }
    $serTotal += $gSer
    $noSerTotal += $gNo
    $ifaceTotal += $gIf
    if ($bad.Count -gt 0) {
        [void]$badGroups.Add(@{ G = $gName; N = $insts.Count; Bad = $bad })
    }
    if ($insts.Count -ge 2 -or $bad.Count -gt 0) {
        [void]$rows.Add(@{ G = $gName; Total = $insts.Count; Ser = $gSer; No = $gNo })
    }
}

W ('有序列号的实例记录  ：' + $serTotal + ' 条（每台一条，插上就复用）')
W ('复合设备子接口记录  ：' + $ifaceTotal + ' 条（&MI_xx，跟着父设备走，不是空片共用）')
W ('真无序列号记录      ：' + $noSerTotal + ' 条（按端口位置生成，同一个口共用一条）')
WL

W '记录较多的型号组（≥2 条，按条数排序，取前 20）：'
W ('  ' + '型号(VID/PID)'.PadRight(34) + '总数'.PadRight(8) + '有序列号'.PadRight(10) + '无序列号')
$sorted = @($rows | Sort-Object { $_.Total } -Descending | Select-Object -First 20)
if ($sorted.Count -eq 0) {
    W '  （没有单个型号组累计到 2 条以上，说明记录分布很干净）'
}
foreach ($r in $sorted) {
    W ('  ' + $r.G.PadRight(32) + ([string]$r.Total).PadRight(10) + ([string]$r.Ser).PadRight(12) + [string]$r.No)
}

WL
if ($badGroups.Count -gt 0) {
    W '【异常记录】带「安装失败 / 需重装」标记的型号组：'
    foreach ($b in $badGroups) {
        W ('  型号 ' + $b.G + '（共 ' + $b.N + ' 条）')
        foreach ($x in @($b.Bad | Select-Object -First 6)) { W ('    ' + $x) }
        if ($b.Bad.Count -gt 6) { W ('    …… 另有 ' + ($b.Bad.Count - 6) + ' 条') }
    }
} else {
    W '没有发现带「安装失败 / 需重装」标记的记录。'
}

# 空片类设备（无序列号 + 端口位置生成）的详细清单
WL
W '真无序列号记录明细（最多 25 条）：'
W ('  ' + '型号'.PadRight(30) + '实例（末段=端口位置）'.PadRight(34) + 'PortName')
$noSerShown = 0
foreach ($g in $groups) {
    foreach ($i in @(Get-ChildItem $g.PSPath)) {
        $iid = $g.PSChildName + '\' + [string]$i.PSChildName
        if ((InstKind $g.PSChildName $iid) -ne 'NoSerial') { continue }
        if ($noSerShown -ge 25) { break }
        $pn = RegGet ($i.PSPath + '\Device Parameters') 'PortName'
        $gp = $g.PSChildName
        if ($gp.Length -gt 28) { $gp = $gp.Substring(0, 28) + '..' }
        W ('  ' + $gp.PadRight(30) + ([string]$i.PSChildName).PadRight(34) + $(if ($pn) { [string]$pn } else { '-' }))
        $noSerShown++
    }
}
if ($noSerShown -eq 0) { W '  （无）' }

# ============================================================
Sep '九、驱动库健康'
# ============================================================
$infFound = $false
foreach ($cand in @((Join-Path $env:SystemRoot 'INF\INFCACHE.1'),
                    (Join-Path $env:SystemRoot 'System32\INFCACHE.1'),
                    (Join-Path $env:SystemRoot 'System32\DriverStore\INFCACHE.1'))) {
    if (Test-Path $cand) {
        $sz = (Get-Item $cand).Length
        W ('驱动缓存 INFCACHE.1：' + [math]::Round($sz / 1MB, 2) + ' MB  (' + $cand + ')')
        if ($sz -gt 32MB) { W '    ⚠ 偏大，可能拖慢甚至卡住新设备安装。' }
        $infFound = $true
        break
    }
}
if (-not $infFound) {
    W '驱动缓存 INFCACHE.1：本系统没有这个文件（Win10/11 已不再使用，属正常）。'
}
$oem = @(Get-ChildItem (Join-Path $env:SystemRoot 'INF') -Filter 'oem*.inf')
W ('第三方驱动包（oem*.inf）：' + $oem.Count + ' 个')
if ($oem.Count -gt 120) { W '    ⚠ 数量偏多，驱动库臃肿，新设备匹配驱动会变慢。' }

foreach ($sysf in @('usbser.sys', 'usbccgp.sys', 'usbhub.sys', 'usbport.sys', 'msports.dll')) {
    $p = Join-Path $env:SystemRoot ('System32\drivers\' + $sysf)
    if (-not (Test-Path $p)) { $p = Join-Path $env:SystemRoot ('System32\' + $sysf) }
    W ('  ' + $sysf.PadRight(16) + $(if (Test-Path $p) { '存在' } else { '缺失 ← 需要留意' }))
}

# 设备安装服务状态
$svcName = @{ 0 = '开机加载'; 1 = '系统加载'; 2 = '自动'; 3 = '手动'; 4 = '已禁用' }
foreach ($svc in @('DeviceInstall', 'PlugPlay', 'DsmSvc')) {
    $kp = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $svc
    if (-not (Test-Path $kp)) {
        W ('  服务 ' + $svc.PadRight(16) + '（本系统没有这个服务键）')
        continue
    }
    $raw = $null
    try { $raw = (Get-ItemProperty -Path $kp -Name 'Start' -ErrorAction Stop).Start } catch { $raw = $null }
    if ($null -eq $raw) {
        W ('  服务 ' + $svc.PadRight(16) + 'Start（未设置）')
        continue
    }
    $sv  = [int]$raw
    $txt2 = $(if ($svcName.ContainsKey($sv)) { $svcName[$sv] } else { '?' })
    $warn = ''
    if ($sv -eq 4) { $warn = '   ← 已禁用，新设备装不上' }
    W ('  服务 ' + $svc.PadRight(16) + 'Start=' + $sv + '（' + $txt2 + '）' + $warn)
}

# ============================================================
Sep '十、结论'
# ============================================================
$concl = New-Object System.Collections.ArrayList

if ($polHit) {
    [void]$concl.Add('【头号原因】设备安装策略禁止了新设备安装。')
    [void]$concl.Add('  这一条完全解释「老机器能认、新机器完全没反应」：')
    [void]$concl.Add('  已装好的设备不受影响，任何没装过的设备都会被拒绝。')
    [void]$concl.Add('  修法：删掉策略键后执行 gpupdate /force，再重启。')
}
if ($fails.Count -gt 0) {
    $lastFail = [string]$fails[$fails.Count - 1].Status
    [void]$concl.Add('【日志证据】最近的设备安装以失败结束：' + $lastFail)
    [void]$concl.Add('  这说明「新设备被系统看到了」，但安装驱动这一步没过。')
    [void]$concl.Add('  属于驱动匹配 / 策略 / 权限层，软件层可修。')
}
if (-not $cimOk -or $cimTotal -eq 0) {
    [void]$concl.Add('【注意】设备列表读取失败，无法判断「系统有没有看到新设备」。')
    [void]$concl.Add('  请用「右键 - 以管理员身份运行」重跑本工具。')
} elseif ($unknown.Count -gt 0) {
    [void]$concl.Add('【关键判断】当前有 ' + $unknown.Count + ' 个「未知/无驱动」设备。')
    [void]$concl.Add('  → 系统看到新设备了，只是装不上。方向明确：修驱动安装。')
} else {
    [void]$concl.Add('【关键判断】当前没有任何「未知设备」。')
    [void]$concl.Add('  → 如果此时正插着那台新机器，说明系统压根没枚举到它。')
    [void]$concl.Add('    那问题在 USB 枚举之前（端口 / 线材 / 芯片供电），软件修不了。')
    [void]$concl.Add('  → 如果那台机器没插着，请插上后重新跑一次本工具。')
}
if ($filterHit -gt 0) {
    [void]$concl.Add('【发现】有 ' + $filterHit + ' 个设备类过滤器属于残留（驱动服务已删）。')
    [void]$concl.Add('  会让新设备加载驱动失败，建议清掉。')
}
if ($badGroups.Count -gt 0) {
    [void]$concl.Add('【发现】有 ' + $badGroups.Count + ' 个型号组带「安装失败/需重装」标记。')
    [void]$concl.Add('  这些记录会让 Windows 误以为设备还没装好，反复装不上。')
}
if ($noSerTotal -gt 0) {
    [void]$concl.Add('【结构】系统里有 ' + $noSerTotal + ' 条「真无序列号」记录。')
    [void]$concl.Add('  这类才是空片按端口共用的一条，它坏了会让整批空片认不出。')
}
if ($ifaceTotal -gt 0) {
    [void]$concl.Add('【结构】另有 ' + $ifaceTotal + ' 条复合设备子接口记录（&MI_xx）。')
    [void]$concl.Add('  它们跟着父设备走，每台成品各有一组，属于正常历史记录，不是共用的坏记录。')
}
if ($rhOn -eq 0) {
    [void]$concl.Add('【严重】没有任何一条根集线器在线，USB 树已经不在系统里。')
    [void]$concl.Add('  这不是清记录能解决的：要用「工具 - 重置 USB 控制器」，或直接重启。')
} elseif ($rhOff -ge 3) {
    [void]$concl.Add('【重点】离线根集线器有 ' + $rhOff + ' 条（正常应为 0）。')
    [void]$concl.Add('  「插什么都没反应」常常就是这一层：反复重建留下的端口状态。')
    [void]$concl.Add('  现场手工「删所有 USB 设备再重扫」能好，原因就在这里 ——')
    [void]$concl.Add('  要用「工具 - 重置 USB 控制器」，清设备记录治不了这一层。')
}
if ($null -ne $logLastWrite) {
    $gapH = [math]::Round(((Get-Date) - $logLastWrite).TotalHours, 1)
    if ($gapH -gt 24) {
        [void]$concl.Add('【校验】驱动安装日志最后一次写入，距本次生成 ' + [math]::Round($gapH / 24, 1) + ' 天。')
        [void]$concl.Add('  如果刚插过设备却没留下新记录，说明系统连「尝试安装」都没做 ——')
        [void]$concl.Add('  那种情况下本报告「现在有没有反应」一节不能当证据，需插着设备重跑。')
    }
}
if ($concl.Count -eq 0) {
    [void]$concl.Add('本次检查没有发现明确异常。')
    [void]$concl.Add('建议：插上新机器、保持插着，再跑一次本工具。没有现场设备时，')
    [void]$concl.Add('很多项目查不到真实状态。')
}
foreach ($c in $concl) { W $c }

# ------------------------------------------------------------
# 机器可读判定行（给图形界面用，决定要不要接着自动修；人读时可忽略）
#   FIXABLE  找到明确的可修原因
#   HARDWARE 系统没枚举到设备，软件层修不了
#   UNKNOWN  读不到设备列表，判断不了
# ------------------------------------------------------------
$reasons = 0
if ($polHit) { $reasons++ }
if ($fails.Count -gt 0) { $reasons++ }
if ($unknown.Count -gt 0) { $reasons++ }
if ($filterHit -gt 0) { $reasons++ }
if ($badGroups.Count -gt 0) { $reasons++ }
if ($rhOn -eq 0 -or $rhOff -ge 3) { $reasons++ }
if (-not $cimOk -or $cimTotal -eq 0) { $verdict = 'UNKNOWN' }
elseif ($reasons -gt 0) { $verdict = 'FIXABLE' }
else { $verdict = 'HARDWARE' }
W ''
W ('[VERDICT] ' + $verdict + ' reasons=' + $reasons)

WL
W '--------------------------------------------------'
W '把这份报告发回即可，不需要做任何改动。'
W '--------------------------------------------------'

# ============================================================
# 输出
# ============================================================
$text = ($script:L -join "`r`n")
if ($OutDir -eq '') { $OutDir = Get-ReportDir }
if (-not (Test-Path $OutDir)) { $OutDir = $env:TEMP }
$outFile = Join-Path $OutDir $OutName
$enc = New-Object System.Text.UTF8Encoding($true)
try {
    [System.IO.File]::WriteAllText($outFile, $text, $enc)
} catch {
    $outFile = Join-Path $env:TEMP $OutName
    [System.IO.File]::WriteAllText($outFile, $text, $enc)
}

Write-Host ''
Write-Host '  取证完成，报告已保存：' -ForegroundColor Green
Write-Host ('  ' + $outFile) -ForegroundColor Yellow
Write-Host ''
Write-Host '  ---- 结论摘要 ----' -ForegroundColor Cyan
foreach ($c in $concl) { Write-Host ('  ' + $c) }

if (-not $NoOpen) {
    try { Start-Process notepad.exe $outFile } catch { }
}
