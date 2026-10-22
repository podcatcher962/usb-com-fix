# =====================================================================
#  USB / 串口 一键修复  —— 核心逻辑  v3（双语）
#
#  设计前提：
#    1) 生产必须使用固定 COM 号，不能靠 Windows 自由分配
#    2) 现场可能有好几种机型，其中一部分不是串口，而是纯 USB 设备
#       所以修复范围要能覆盖全部 USB 设备，而不只是 COM 口
#
#  安全铁律（任何模式都不破）：
#    · 只删「离线」记录，插着的在线设备一条都不动
#    · 拿不到在线列表时，整步跳过并报警，绝不猜着删
#    · 集线器 / 控制器（ROOT_HUB 等组）永久保护，永不参与任何删除
#    · 键鼠等输入设备默认不动，需要显式开关才碰
#    · 全程留底，可一键还原
#
#  双语：CF-Log '中文' 'level' 'English'，CF-T '中文' 'English'
#
#  兼容 Windows 7/8/10/11，PowerShell 5.1，32 位 / 64 位
# =====================================================================

$script:CF_LOG    = New-Object System.Collections.ArrayList
$script:CF_OnLog  = $null
$script:CF_ARB    = 'HKLM:\SYSTEM\CurrentControlSet\Control\COM Name Arbiter'
$script:CF_BACKUP = Join-Path $env:ProgramData 'ComFix\backup'
$script:CF_PRESENT_CACHE = $null
$script:CF_ENUM_USB = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB'
$script:CF_ENUM_FTD = 'HKLM:\SYSTEM\CurrentControlSet\Enum\FTDIBUS'
$script:CF_LANG   = 'zh'

# ---------- 语言 ----------
function CF-SetLang([string]$l) {
    if ($l -eq 'en') { $script:CF_LANG = 'en' } else { $script:CF_LANG = 'zh' }
}

function CF-T([string]$zh, [string]$en) {
    if ($script:CF_LANG -eq 'en') { return $en }
    return $zh
}

# ---------- 基础 ----------
function CF-Log([string]$zh, [string]$level = 'info', [string]$en = '') {
    $msg = $zh
    if ($script:CF_LANG -eq 'en' -and $en -ne '') { $msg = $en }
    $t = Get-Date -Format 'HH:mm:ss'
    $line = "[$t] $msg"
    [void]$script:CF_LOG.Add($line)
    if ($script:CF_OnLog) { & $script:CF_OnLog $line $level }
}

function CF-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function CF-EnsureDir([string]$p) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

function CF-RegNum($path, $name, $default = $null) {
    try {
        $v = (Get-ItemProperty $path -Name $name -ErrorAction Stop).$name
        if ($null -eq $v) { return $default }
        return $v
    } catch { return $default }
}

function CF-RegStr($path, $name, $default = '') {
    try {
        $v = (Get-ItemProperty $path -Name $name -ErrorAction Stop).$name
        if ($null -eq $v) { return $default }
        return [string]$v
    } catch { return $default }
}

# ---------- ComDB 位图 ----------
function CF-GetComDB {
    $v = $null
    try { $v = (Get-ItemProperty $script:CF_ARB -Name ComDB -ErrorAction Stop).ComDB } catch { }
    if ($null -eq $v) { return (New-Object byte[] 32) }
    if ($v -is [byte[]]) { return $v }
    return [byte[]]$v
}

function CF-ComDBToNums($db) {
    $list = New-Object System.Collections.ArrayList
    if ($null -eq $db) { return $list }
    for ($b = 0; $b -lt $db.Length; $b++) {
        for ($i = 0; $i -lt 8; $i++) {
            if (($db[$b] -band (1 -shl $i)) -ne 0) { [void]$list.Add($b * 8 + $i + 1) }
        }
    }
    return $list
}

function CF-NumsToComDB($nums, [int]$len = 32) {
    if ($len -lt 32) { $len = 32 }
    $db = New-Object byte[] $len
    foreach ($n in $nums) {
        $x = [int]$n
        if ($x -lt 1 -or $x -gt ($len * 8)) { continue }
        $bit = $x - 1
        $idx = [int][math]::Floor($bit / 8)
        $db[$idx] = [byte]([int]$db[$idx] -bor (1 -shl ($bit % 8)))
    }
    return $db
}

function CF-SetComDB($nums) {
    $old = CF-GetComDB
    $db = CF-NumsToComDB $nums $old.Length
    Set-ItemProperty $script:CF_ARB -Name ComDB -Value $db -ErrorAction Stop
    return $db
}

# ---------- 在线设备集合 ----------
# 三级降级：Get-PnpDevice → CIM → WMI。全都失败则 CF_PresentOk = $false，
# 此时禁止任何删除动作。
$script:CF_PresentOk = $false

function CF-GetPresentIds {
    if ($null -ne $script:CF_PRESENT_CACHE) { return $script:CF_PRESENT_CACHE }
    $set = @{}
    $script:CF_PresentOk = $false

    try {
        $devs = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
        if ($devs.Count -gt 0) {
            foreach ($d in $devs) { $set[$d.InstanceId.ToUpper()] = $true }
            $script:CF_PresentOk = $true
            $script:CF_PRESENT_CACHE = $set
            return $set
        }
    } catch { }

    try {
        $ents = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
        if ($ents.Count -gt 0) {
            foreach ($e in $ents) {
                $id = [string]$e.PNPDeviceID
                if ($id) { $set[$id.ToUpper()] = $true }
            }
            $script:CF_PresentOk = $true
            $script:CF_PRESENT_CACHE = $set
            return $set
        }
    } catch { }

    try {
        $ents2 = @(Get-WmiObject Win32_PnPEntity -ErrorAction Stop)
        if ($ents2.Count -gt 0) {
            foreach ($e in $ents2) {
                $id = [string]$e.PNPDeviceID
                if ($id) { $set[$id.ToUpper()] = $true }
            }
            $script:CF_PresentOk = $true
            $script:CF_PRESENT_CACHE = $set
            return $set
        }
    } catch { }

    return $set
}

function CF-ResetPresentCache { $script:CF_PRESENT_CACHE = $null }

# ---------- 设备分类 ----------
function CF-Classify([string]$svc, [string]$cls, [string]$guid) {
    $s = ([string]$svc).ToLower()
    $c = ([string]$cls).ToLower()
    $g = ([string]$guid).ToLower()

    # 串口：Class=Ports/Serial，或常见 USB 转串口驱动服务名
    if ($c -eq 'ports' -or $c -eq 'serial' -or
        $s -match 'usbser|ch341|silab|ftdi|prolific|usbcdc|msports|serial|vcp|cdc') { return 'Serial' }

    # 输入设备（键鼠类）：默认保护
    if ($g -like '{745a17a0-74d3-11d0-b6fe-00a0c90f57da}*' -or
        $c -match 'hidclass|keyboard|mouse' -or $s -match 'hidusb|kbdhid|mouhid|hidbth') { return 'HID' }

    # 存储类（读卡器 / U 盘 / 移动硬盘）
    if ($c -match 'usbstor|diskdrive|volume|cdrom|scsiadapter|wpd|floppydisk' -or
        $s -match 'usbstor|uaspstor|disk|storport|wudfrd|sdbus') { return 'Storage' }

    if ($c -match 'media|audioendpoint|^sound' -or $s -match 'usbaudio|sysfx') { return 'Audio' }
    if ($c -match 'camera|image' -or $s -match 'usbvideo|usbscan') { return 'Camera' }
    if ($c -match '^net' -or $s -match 'rndis|ndis|wlan|wwan|usb8023|netaapl|qcusbnet') { return 'Network' }
    if ($c -match 'printer' -or $s -match 'usbprint|usbmon') { return 'Printer' }
    if ($c -match 'bluetooth' -or $s -match 'bthusb|bthenum') { return 'Bluetooth' }

    # USB 控制器 / 集线器这类结构性节点：永久保护
    # 只按驱动服务名判断，不看 ClassGUID。
    # 因为 ClassGUID={36fc9e60-...}（"USB" 设备类）也是普通复合设备父节点在用的，
    # 按 GUID 判断会把厂商设备误当成集线器而永久跳过。
    if ($s -match '^(usbhub|usbhub3|usbxhci|usbehci|usbuhci|usbohci|usb3hci)$') { return 'UsbCore' }

    if ($s -eq 'usbccgp') { return 'Composite' }

    # 厂商自定义（生产治具绝大多数落在这里）
    if ($s -match 'winusb|libusb|libusbk|usbdk' -or $c -match 'usbdevice') { return 'Vendor' }
    if ($g -like '{a5dcbf10-6530-11d2-901f-00c04fb951ed}*') { return 'Vendor' }
    if ($c -eq '' -or $c -eq 'usb') { return 'Vendor' }

    return 'Other'
}

function CF-CatName([string]$cat) {
    switch ($cat) {
        'Serial'    { return (CF-T '串口（USB 转 COM）' 'Serial (USB-to-COM)') }
        'HID'       { return (CF-T '输入设备（键鼠等）' 'Input devices') }
        'Storage'   { return (CF-T '存储类（读卡器/U盘）' 'Storage (reader / USB drive)') }
        'Audio'     { return (CF-T '音频设备' 'Audio devices') }
        'Camera'    { return (CF-T '摄像头/扫描仪' 'Camera / scanner') }
        'Network'   { return (CF-T '网络设备' 'Network devices') }
        'Printer'   { return (CF-T '打印机' 'Printers') }
        'Bluetooth' { return (CF-T '蓝牙' 'Bluetooth') }
        'Composite' { return (CF-T '复合设备（多接口）' 'Composite devices') }
        'Vendor'    { return (CF-T '厂商自定义设备' 'Vendor-specific devices') }
        'UsbCore'   { return (CF-T '集线器/控制器' 'Hubs & controllers') }
        default     { return (CF-T '其他' 'Other') }
    }
}

function CF-ScopeName([string]$sc, [bool]$InclHid = $false) {
    if ($sc -eq 'VendorOnly') { return (CF-T '厂商自定义设备' 'Vendor-specific') }
    if ($sc -eq 'AllUsb') {
        $n = (CF-T '全部 USB 设备' 'All USB devices')
        if ($InclHid) { $n = $n + (CF-T '（含 HID）' ' (incl. HID)') }
        return $n
    }
    return (CF-T '串口设备' 'Serial ports')
}

# 该类别在本次修复范围内是否允许被清理（仅针对离线记录）
function CF-CatInScope([string]$cat, [string]$Scope, [bool]$IncludeHid) {
    if ($cat -eq 'UsbCore') { return $false }              # 永久保护
    if ($cat -eq 'Serial')  { return $true }               # 三种模式都含
    if ($Scope -eq 'Serial') { return $false }
    if ($cat -eq 'HID') { return $IncludeHid }
    if ($cat -match '^(Audio|Camera|Network|Printer|Bluetooth)$') { return $false }
    if ($Scope -eq 'VendorOnly') { return ($cat -eq 'Vendor' -or $cat -eq 'Composite') }
    return $true                                            # Storage / Vendor / Composite / Other
}

# ---------- 通用 USB 设备枚举 ----------
function CF-GetUsbDevices([string]$Scope = 'Serial') {
    $present = CF-GetPresentIds
    $res = New-Object System.Collections.ArrayList
    $roots = @(
        @{ Path = $script:CF_ENUM_USB; Kind = 'USB' },
        @{ Path = $script:CF_ENUM_FTD; Kind = 'FTDIBUS' }
    )

    foreach ($root in $roots) {
        if (-not (Test-Path $root.Path)) { continue }
        $groups = @(Get-ChildItem $root.Path -ErrorAction SilentlyContinue)
        foreach ($g in $groups) {
            $grpName = [string]$g.PSChildName

            # 只有 VID_xxxx&PID_xxxx 这种真实设备组才可能被清理。
            # ROOT_HUB20 / ROOT_HUB30 等结构性节点一律不参与。
            $isVidPid = ($grpName -match '^VID_[0-9A-Fa-f]{4}&PID_[0-9A-Fa-f]{4}')

            $insts = @(Get-ChildItem $g.PSPath -ErrorAction SilentlyContinue)
            foreach ($inst in $insts) {
                $pn  = CF-RegStr (Join-Path $inst.PSPath 'Device Parameters') 'PortName' ''
                $svc = CF-RegStr $inst.PSPath 'Service' ''
                $cls = CF-RegStr $inst.PSPath 'Class' ''
                $gd  = CF-RegStr $inst.PSPath 'ClassGUID' ''
                $cfg = CF-RegNum $inst.PSPath 'ConfigFlags' 0
                $desc = CF-RegStr $inst.PSPath 'DeviceDesc' ''
                if ($desc -match '^@') { $desc = ($desc -split ';')[-1] }

                $cat = CF-Classify $svc $cls $gd
                if (-not $isVidPid) { $cat = 'UsbCore' }

                if ($Scope -eq 'Serial' -and $cat -ne 'Serial') { continue }

                # 实例 ID 必须带上枚举根名（USB\ 或 FTDIBUS\），否则和
                # Get-PnpDevice 的 InstanceId 对不上，会把在线设备全判成离线。
                $iid = $root.Kind + '\' + $grpName + '\' + [string]$inst.PSChildName
                $num = 0
                if ($pn -match '^COM(\d+)$') { $num = [int]$Matches[1] }

                [void]$res.Add([pscustomobject]@{
                    Group       = $grpName
                    Inst        = [string]$inst.PSChildName
                    InstanceId  = $iid
                    KeyPath     = $inst.PSPath
                    PortName    = $pn
                    PortNum     = $num
                    Service     = $svc
                    Class       = $cls
                    ClassGuid   = $gd
                    Desc        = $desc
                    Category    = $cat
                    CfgFlags    = $(if ($null -ne $cfg) { [int]$cfg } else { 0 })
                    Protected   = (-not $isVidPid)
                    Online      = $present.ContainsKey($iid.ToUpper())
                })
            }
        }
    }
    return $res
}

# 兼容旧接口：只返回串口实例
function CF-GetSerialInstances {
    $all = CF-GetUsbDevices -Scope 'Serial'
    $res = New-Object System.Collections.ArrayList
    foreach ($x in $all) {
        [void]$res.Add([pscustomobject]@{
            Group       = $x.Group
            Inst        = $x.Inst
            InstanceId  = $x.InstanceId
            KeyPath     = $x.KeyPath
            PortName    = $x.PortName
            PortNum     = $x.PortNum
            Service     = $x.Service
            Class       = $x.Class
            ConfigFlags = $x.CfgFlags
            Online      = $x.Online
            IsUsb       = ($x.Group -like 'VID_*')
        })
    }
    return $res
}

function CF-GetUsbGroups {
    $all = @(CF-GetUsbDevices -Scope 'All')
    $map = @{}
    foreach ($x in $all) {
        if (-not $map.ContainsKey($x.Group)) {
            $map[$x.Group] = [pscustomobject]@{
                Group     = $x.Group
                Category  = $x.Category
                Service   = $x.Service
                Total     = 0
                Online    = 0
                Offline   = 0
                Ports     = @()
                Protected = $x.Protected
            }
        }
        $o = $map[$x.Group]
        $o.Total++
        if ($x.Online) { $o.Online++ } else { $o.Offline++ }
        if ($x.Category -eq 'Serial') { $o.Category = 'Serial' }
        if ($x.PortNum -gt 0) { $o.Ports += $x.PortNum }
    }
    return @($map.Values | Sort-Object -Property Offline -Descending)
}

function CF-GetMotherboardPorts {
    $nums = New-Object System.Collections.ArrayList
    try {
        $sp = @(Get-CimInstance Win32_SerialPort -ErrorAction Stop)
        foreach ($p in $sp) {
            $did = [string]$p.DeviceID
            $pid2 = [string]$p.PNPDeviceID
            if ($did -match '^COM(\d+)$' -and $pid2 -notlike 'USB\*') { [void]$nums.Add([int]$Matches[1]) }
        }
    } catch { }
    if ($nums.Count -eq 0) { [void]$nums.Add(1) }
    return $nums
}

# ---------- 环境检查（只读，只在报告里给结论，不自动改） ----------
function CF-CheckEnvironment {
    $issues = New-Object System.Collections.ArrayList
    $facts  = New-Object System.Collections.ArrayList

    # 1) USB 存储服务是否被禁用（读卡器/U盘 类设备会完全不响应）
    $st = CF-RegNum 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR' 'Start' $null
    if ($null -ne $st) {
        if ([int]$st -eq 4) {
            [void]$issues.Add((CF-T 'USB 存储服务 USBSTOR 已被禁用（Start=4）→ 读卡器/U 盘类设备插上不会有任何反应。修法：把 Start 改回 3 并重启。' 'USBSTOR service is disabled (Start=4) -> card readers and USB drives will not respond at all. Fix: set Start back to 3 and reboot.'))
        } elseif ([int]$st -eq 3) {
            [void]$facts.Add((CF-T 'USB 存储服务正常（USBSTOR Start=3）' 'USB storage service OK (USBSTOR Start=3)'))
        }
    }

    # 2) 组策略是否禁止了可移动存储
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
    if (Test-Path $pol) {
        $denyAll = CF-RegNum $pol 'Deny_All' 0
        if ([int]$denyAll -eq 1) {
            [void]$issues.Add((CF-T '组策略禁止了全部可移动存储设备（Deny_All=1）→ 读卡器/U 盘会被直接拦掉。修法：去掉这条策略。' 'Group Policy denies all removable storage (Deny_All=1) -> card readers / USB drives are blocked. Fix: remove that policy.'))
        } else {
            [void]$facts.Add((CF-T '可移动存储策略存在，但未全局禁止' 'Removable storage policy present, but not globally denied'))
        }
    }

    # 3) USB 类 / 磁盘类 / 端口类 过滤器残留
    $clsList = @(
        @{ G = '{36fc9e60-c465-11cf-8056-444553540000}'; N = (CF-T 'USB 控制器类' 'USB controller class') },
        @{ G = '{4d36e967-e325-11ce-bfc1-08002be10318}'; N = (CF-T '磁盘驱动器类' 'Disk drive class') },
        @{ G = '{4d36e978-e325-11ce-bfc1-08002be10318}'; N = (CF-T '端口类' 'Ports class') }
    )
    foreach ($c in $clsList) {
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $c.G
        if (-not (Test-Path $p)) { continue }
        foreach ($f in @('UpperFilters', 'LowerFilters')) {
            $v = $null
            try { $v = (Get-ItemProperty $p -Name $f -ErrorAction Stop).$f } catch { }
            if ($null -ne $v) {
                $arr = @($v)
                if ($arr.Count -gt 0) {
                    [void]$facts.Add(($c.N + ' / ' + $f + ' = ' + ($arr -join ', ')))
                }
            }
        }
    }

    # 4) Enum 规模
    $groups = @(CF-GetUsbGroups)
    $tot = 0; $off = 0
    foreach ($g in $groups) { $tot += $g.Total; $off += $g.Offline }
    [void]$facts.Add((CF-T ('USB 设备记录 ' + $tot + ' 条（在线 ' + ($tot - $off) + ' / 离线 ' + $off + '），设备型号 ' + $groups.Count + ' 种') ('USB device records: ' + $tot + ' (online ' + ($tot - $off) + ' / offline ' + $off + '), models: ' + $groups.Count)))
    if ($off -ge 300) {
        [void]$issues.Add((CF-T ('离线残留已达 ' + $off + ' 条，属于重度累积。Enum 树过大时新设备枚举会变慢甚至失败。') ('Offline residue reached ' + $off + ' records - heavily accumulated. An oversized Enum tree can slow down or break enumeration of new devices.')))
    } elseif ($off -ge 100) {
        [void]$issues.Add((CF-T ('离线残留 ' + $off + ' 条，偏多，建议清理。') ('Offline residue ' + $off + ' records - above normal, cleaning recommended.')))
    }

    # 5) USB 主机控制器数量
    $hc = 0
    try { $hc = @(Get-CimInstance Win32_USBController -ErrorAction Stop).Count } catch { }
    if ($hc -gt 0) { [void]$facts.Add((CF-T ('USB 主机控制器 ' + $hc + ' 个') ('USB host controllers: ' + $hc))) }

    return [pscustomobject]@{ Issues = $issues; Facts = $facts }
}

# ---------- 「插上完全没反应」专项检查 ----------
# 症状：设备管理器里什么都不多，没有感叹号，也没有新 COM 口。
# 这和「端口号乱」是两个层次：前者根本没进系统，后者已经进了但号不对。
# 本检查只读，唯一一次写操作是建一个临时探针键、立刻删掉。
function CF-CheckDeep {
    $issues = New-Object System.Collections.ArrayList
    $facts  = New-Object System.Collections.ArrayList
    $admin  = CF-IsAdmin

    # 1) Enum\USB 的权限。新设备要在这里创建实例子键；
    #    没有写权限，枚举就会静默失败 —— 插上一点反应都没有。
    try {
        $acl = Get-Acl $script:CF_ENUM_USB
        $sys = $false; $adm = $false
        foreach ($r in $acl.Access) {
            $who = [string]$r.IdentityReference
            $rgt = [string]$r.RegistryRights
            if ($r.AccessControlType -ne 'Allow') { continue }
            if ($who -match 'SYSTEM' -and $rgt -match 'FullControl|WriteKey') { $sys = $true }
            if ($who -match 'Administrators' -and $rgt -match 'FullControl|WriteKey') { $adm = $true }
        }
        $deny = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' })
        if (-not $sys) {
            [void]$issues.Add((CF-T 'Enum\USB 缺少 SYSTEM 的写权限。新设备插上时无法建立实例记录，表现就是「一点反应都没有」。' 'Enum\USB lacks write permission for SYSTEM. A new device cannot create its instance record, so plugging it in produces no reaction at all.'))
        }
        if ($deny.Count -gt 0) {
            [void]$issues.Add((CF-T ('Enum\USB 上有 ' + $deny.Count + ' 条「拒绝」权限，可能拦掉了新设备枚举。') ('Enum\USB has ' + $deny.Count + ' "Deny" ACE(s), which can block enumeration of new devices.')))
        }
        [void]$facts.Add((CF-T ('Enum\USB 权限：SYSTEM 可写=' + $sys + '，管理员可写=' + $adm + '，拒绝条目=' + $deny.Count) ('Enum\USB permissions: SYSTEM writable=' + $sys + ', Administrators writable=' + $adm + ', deny ACEs=' + $deny.Count)))
    } catch {
        [void]$facts.Add((CF-T 'Enum\USB 权限：读取失败' 'Enum\USB permissions: could not read'))
    }

    # 2) 真刀真枪试一次「能不能建子键」——比读 ACL 更直接
    if ($admin) {
        $probe = $script:CF_ENUM_USB + '\__fixprobe__'
        $okWrite = $false
        try {
            New-Item -Path $probe -Force -ErrorAction Stop | Out-Null
            $okWrite = $true
        } catch { }
        finally {
            try { Remove-Item $probe -Recurse -Force -ErrorAction Stop } catch { }
        }
        if ($okWrite) {
            [void]$facts.Add((CF-T 'Enum\USB 写入测试：通过（能创建设备实例键）' 'Enum\USB write test: PASSED (an instance key can be created)'))
        } else {
            [void]$issues.Add((CF-T 'Enum\USB 写入测试失败！新设备插上无法建立实例记录，这就是「完全认不出」的直接原因。这一条必须优先修。' 'Enum\USB write test FAILED. A new device cannot create its instance record - this directly explains "no reaction at all". Fix this first.'))
        }
    } else {
        [void]$facts.Add((CF-T 'Enum\USB 写入测试：跳过（需要管理员权限）' 'Enum\USB write test: skipped (needs administrator)'))
    }

    # 3) USB 类 / 端口类 过滤器残留。装了又卸的安全软件常留一个不存在的驱动名，
    #    后果是新设备加载驱动失败，可能表现为完全不出现在设备管理器里。
    $clsList = @(
        @{ G = '{36fc9e60-c465-11cf-8056-444553540000}'; N = (CF-T 'USB 控制器类' 'USB controller class') },
        @{ G = '{4d36e978-e325-11ce-bfc1-08002be10318}'; N = (CF-T '端口类' 'Ports class') },
        @{ G = '{a5dcbf10-6530-11d2-901f-00c04fb951ed}'; N = (CF-T 'USB 设备类' 'USB device class') }
    )
    $known = @('usbccgp', 'usbhub', 'usbhub3', 'usbxhci', 'usbehci', 'usbuhci', 'usbohci',
               'usbprint', 'usbstor', 'usbvideo', 'usbaudio', 'winusb', 'libusb0', 'libusbk',
               'usbser', 'msports', 'usbmon', 'usbhub3', 'wudfrd', 'usbccid', 'ccidtwin')
    foreach ($c in $clsList) {
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $c.G
        if (-not (Test-Path $p)) { continue }
        foreach ($f in @('UpperFilters', 'LowerFilters')) {
            $v = $null
            try { $v = (Get-ItemProperty $p -Name $f -ErrorAction Stop).$f } catch { }
            if ($null -eq $v) { continue }
            foreach ($name in @($v)) {
                $nm = ([string]$name).Trim()
                if ($nm -eq '') { continue }
                $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $nm
                if (-not (Test-Path $svcKey)) {
                    [void]$issues.Add((CF-T ('USB 类里有残留过滤器「' + $nm + '」（服务已不存在）。新设备加载驱动会失败，可能导致插上完全没反应。') ('Leftover filter "' + $nm + '" in a USB class (its service no longer exists). New devices can fail to load their driver, which may look like "no reaction at all".')))
                } elseif ($known -notcontains $nm.ToLower()) {
                    [void]$facts.Add(($c.N + ' / ' + $f + ' 含第三方项：' + $nm))
                }
            }
        }
    }

    # 4) 当前 USB 设备的错误状态（0 以外就是有问题）
    $errs = @()
    try {
        $errs = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
                  Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.PNPDeviceID -like 'USB*' })
    } catch { }
    if ($errs.Count -gt 0) {
        foreach ($e in ($errs | Select-Object -First 8)) {
            [void]$issues.Add((CF-T ('USB 设备「' + $e.Name + '」报错，错误代码 ' + $e.ConfigManagerErrorCode + '。') ('USB device "' + $e.Name + '" reports error code ' + $e.ConfigManagerErrorCode + '.')))
        }
    } else {
        [void]$facts.Add((CF-T '当前插着的 USB 设备没有错误代码' 'No USB device currently reports an error code'))
    }

    # 5) 驱动缓存与 Enum 规模
    $inf = ''
    foreach ($cand in @((Join-Path $env:SystemRoot 'INF\INFCACHE.1'),
                        (Join-Path $env:SystemRoot 'System32\INFCACHE.1'))) {
        if (Test-Path $cand) { $inf = $cand; break }
    }
    if ($inf -ne '') {
        $sz = 0
        try { $sz = (Get-Item $inf).Length } catch { }
        if ($sz -gt 32MB) {
            [void]$issues.Add((CF-T ('驱动缓存 INFCACHE.1 已达 ' + [math]::Round($sz / 1MB, 1) + ' MB，偏大，可能拖慢甚至卡住新设备安装。') ('Driver cache INFCACHE.1 is ' + [math]::Round($sz / 1MB, 1) + ' MB - oversized; it can slow down or block new device installation.')))
        } else {
            [void]$facts.Add((CF-T ('驱动缓存 INFCACHE.1：' + [math]::Round($sz / 1MB, 1) + ' MB') ('Driver cache INFCACHE.1: ' + [math]::Round($sz / 1MB, 1) + ' MB')))
        }
    }

    $groups = @(CF-GetUsbGroups)
    $tot = 0
    foreach ($g in $groups) { $tot += $g.Total }
    [void]$facts.Add((CF-T ('Enum\USB 规模：' + $tot + ' 条记录，' + $groups.Count + ' 个设备型号组') ('Enum\USB size: ' + $tot + ' records in ' + $groups.Count + ' model groups')))
    if ($tot -gt 1500) {
        [void]$issues.Add((CF-T ('Enum\USB 已有 ' + $tot + ' 条记录，规模过大。量到几千条时 PnP 枚举会超时，新设备直接不出现。') ('Enum\USB already holds ' + $tot + ' records - oversized. At several thousand, PnP enumeration times out and new devices simply do not appear.')))
    }

    return [pscustomobject]@{ Issues = $issues; Facts = $facts }
}


function CF-Backup {
    try { CF-EnsureDir $script:CF_BACKUP } catch { }
    $dir = Join-Path $script:CF_BACKUP ('fix-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    CF-EnsureDir $dir

    $db = CF-GetComDB
    try { [System.IO.File]::WriteAllBytes((Join-Path $dir 'ComDB.bin'), $db) } catch { }

    $enc2 = New-Object System.Text.UTF8Encoding($true)
    $hex = ($db | ForEach-Object { ('{0:X2}' -f [int]$_) }) -join ' '
    $numsTxt = @(CF-ComDBToNums $db)
    $txt = (CF-T 'ComDB 十六进制: ' 'ComDB hex: ') + $hex + "`r`n`r`n" +
           (CF-T '占用号: ' 'Ports in use: ') + $numsTxt.Count + (CF-T ' 个' '') + "`r`nCOM" + ($numsTxt -join ', COM')
    try { [System.IO.File]::WriteAllText((Join-Path $dir '号池原始值.txt'), $txt, $enc2) } catch { }

    # 全量设备快照（含非串口，便于事后比对）
    $all = @(CF-GetUsbDevices -Scope 'All')
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add((CF-T '# USB 设备记录快照   ' '# USB device records snapshot   ') + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    [void]$lines.Add((CF-T '# 状态 | 类别 | 端口号 | 实例ID | 驱动 | Class | ConfigFlags' '# State | Category | Port | InstanceId | Service | Class | ConfigFlags'))
    foreach ($x in $all) {
        $st = $(if ($x.Online) { CF-T '在线' 'online' } else { CF-T '离线' 'offline' })
        $pn = $(if ($x.PortNum -gt 0) { 'COM' + $x.PortNum } else { '-' })
        [void]$lines.Add($st + ' | ' + $x.Category + ' | ' + $pn + ' | ' + $x.InstanceId + ' | ' +
                         $x.Service + ' | ' + $x.Class + ' | 0x' + ('{0:X2}' -f $x.CfgFlags))
    }
    $enc = New-Object System.Text.UTF8Encoding($true)
    try { [System.IO.File]::WriteAllLines((Join-Path $dir '设备记录快照.txt'), $lines, $enc) } catch { }
    try { [System.IO.File]::Copy((Join-Path $dir '设备记录快照.txt'), (Join-Path $dir '串口记录快照.txt'), $true) } catch { }

    CF-Log ('已留底：' + $dir) 'info' ('Snapshot saved: ' + $dir)
    return $dir
}

function CF-GetLatestBackup {
    if (-not (Test-Path $script:CF_BACKUP)) { return $null }
    $d = @(Get-ChildItem $script:CF_BACKUP -Directory -Filter 'fix-*' | Sort-Object Name -Descending)
    if ($d.Count -eq 0) { return $null }
    return $d[0].FullName
}

function CF-Restore([string]$dir) {
    if (-not $dir) { $dir = CF-GetLatestBackup }
    if (-not $dir -or -not (Test-Path $dir)) {
        CF-Log '找不到留底，无法还原' 'err' 'Snapshot not found, cannot restore'
        return $false
    }

    $bin = Join-Path $dir 'ComDB.bin'
    if (Test-Path $bin) {
        $db = [System.IO.File]::ReadAllBytes($bin)
        Set-ItemProperty $script:CF_ARB -Name ComDB -Value $db -ErrorAction SilentlyContinue
        $lst = ((CF-ComDBToNums $db) -join ', COM')
        CF-Log ('已还原号池：COM' + $lst) 'info' ('Port pool restored: COM' + $lst)
    }

    $snap = Join-Path $dir '设备记录快照.txt'
    if (-not (Test-Path $snap)) { $snap = Join-Path $dir '串口记录快照.txt' }
    if (Test-Path $snap) {
        $n = 0
        foreach ($line in [System.IO.File]::ReadAllLines($snap, [System.Text.Encoding]::UTF8)) {
            if ($line -match '^(在线|离线|online|offline) \| (\S+) \| (COM\d+|\(-\)|-) \| (.+?) \| ') {
                $pn  = $Matches[3]
                $iid = $Matches[4].Trim()
                if ($pn -notmatch '^COM\d+$') { continue }
                $dp = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $iid + '\Device Parameters'
                if (Test-Path $dp) {
                    try { Set-ItemProperty $dp -Name PortName -Value $pn -ErrorAction Stop; $n++ } catch { }
                }
            }
        }
        CF-Log ('已还原 ' + $n + ' 条设备端口号') 'info' ($n.ToString() + ' device port numbers restored')
    }
    return $true
}

# ---------- 系统层拦路项：自动修复 ----------
# 「新设备完全认不出、老设备照常能用」这类问题，根子大多在这几项上。
# 本步骤把它们全部自动修掉，不再只是报告。
# 每项都先记原值到留底目录，随时能还原；DryRun 时只报告不改。
function CF-RepairBlocks {
    param([string]$BackupDir = '', [switch]$DryRun)

    $items  = New-Object System.Collections.ArrayList
    $dn     = New-Object System.Collections.ArrayList   # 记录原值，供还原
    $manual = New-Object System.Collections.ArrayList

    function Note([string]$name, [string]$before, [string]$after, [string]$state) {
        [void]$items.Add([pscustomobject]@{
            Name = $name; Before = $before; After = $after; State = $state
        })
    }

    # ---- 1) 设备安装策略：禁止安装未列出的设备 ----
    $polRes = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
    $du = $null
    try { $du = (Get-ItemProperty -Path $polRes -Name 'DenyUnspecified' -ErrorAction Stop).DenyUnspecified } catch { }
    if ($null -ne $du -and [string]$du -eq '1') {
        [void]$dn.Add('policy|DenyUnspecified|1')
        if ($DryRun) {
            Note ((CF-T '设备安装策略：禁止安装未列出的设备' 'Device install policy: deny unspecified devices')) ((CF-T '已启用' 'enabled')) ((CF-T '将解除' 'would clear')) 'would'
        } else {
            try {
                Remove-ItemProperty -Path $polRes -Name 'DenyUnspecified' -ErrorAction Stop
                Note ((CF-T '设备安装策略：禁止安装未列出的设备' 'Device install policy: deny unspecified devices')) ((CF-T '已启用' 'enabled')) ((CF-T '已解除' 'cleared')) 'fixed'
            } catch {
                Note ((CF-T '设备安装策略：禁止安装未列出的设备' 'Device install policy: deny unspecified devices')) 'enabled' ((CF-T '改动失败' 'failed')) 'fail'
                [void]$manual.Add((CF-T '设备安装策略在受保护位置，需要在 gpedit.msc 里手工关闭「禁止安装未由其他策略设置描述的设备」。' 'The policy key is protected; disable "Prevent installation of devices not described by other policy settings" in gpedit.msc manually.'))
            }
        }
    } else {
        Note ((CF-T '设备安装策略：禁止安装未列出的设备' 'Device install policy: deny unspecified devices')) ((CF-T '未启用' 'not enabled')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # 有针对性的封禁（DenyDeviceIDs）不动，只提示
    try {
        $ddi = (Get-ItemProperty -Path $polRes -Name 'DenyDeviceIDs' -ErrorAction Stop).DenyDeviceIDs
        if ($null -ne $ddi -and @($ddi).Count -gt 0) {
            [void]$manual.Add((CF-T ('检测到「按硬件 ID 封禁」共 ' + @($ddi).Count + ' 条（DenyDeviceIDs）。这是有针对性的封禁，工具不会自动删，需要人工确认是否解除。') ('Found ' + @($ddi).Count + ' hardware-ID deny entries (DenyDeviceIDs). These are targeted blocks; the tool will not remove them automatically.')))
        }
    } catch { }

    # ---- 2) 可移动存储被全局禁止 ----
    $polRm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
    $da = $null
    try { $da = (Get-ItemProperty -Path $polRm -Name 'Deny_All' -ErrorAction Stop).Deny_All } catch { }
    if ($null -ne $da -and [string]$da -eq '1') {
        [void]$dn.Add('policy|Deny_All|1')
        if ($DryRun) {
            Note ((CF-T '组策略：禁止全部可移动存储' 'Policy: deny all removable storage')) ((CF-T '已启用' 'enabled')) ((CF-T '将解除' 'would clear')) 'would'
        } else {
            try {
                Remove-ItemProperty -Path $polRm -Name 'Deny_All' -ErrorAction Stop
                Note ((CF-T '组策略：禁止全部可移动存储' 'Policy: deny all removable storage')) ((CF-T '已启用' 'enabled')) ((CF-T '已解除' 'cleared')) 'fixed'
            } catch {
                Note ((CF-T '组策略：禁止全部可移动存储' 'Policy: deny all removable storage')) 'enabled' ((CF-T '改动失败' 'failed')) 'fail'
            }
        }
    } else {
        Note ((CF-T '组策略：禁止全部可移动存储' 'Policy: deny all removable storage')) ((CF-T '未启用' 'not enabled')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # ---- 3) USB 存储驱动被停用 ----
    $kUs = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
    $stUs = $null
    try { $stUs = (Get-ItemProperty -Path $kUs -Name 'Start' -ErrorAction Stop).Start } catch { }
    if ($null -ne $stUs -and [int]$stUs -eq 4) {
        [void]$dn.Add('reg|' + $kUs + '|Start|' + [string]$stUs)
        if ($DryRun) {
            Note ((CF-T 'USB 存储驱动（USBSTOR）' 'USB storage driver (USBSTOR)')) ((CF-T '已停用' 'disabled')) ((CF-T '将启用' 'would enable')) 'would'
        } else {
            try {
                Set-ItemProperty -Path $kUs -Name 'Start' -Value 3 -Type DWord -ErrorAction Stop
                Note ((CF-T 'USB 存储驱动（USBSTOR）' 'USB storage driver (USBSTOR)')) ((CF-T '已停用' 'disabled')) ((CF-T '已启用' 'enabled')) 'fixed'
            } catch {
                Note ((CF-T 'USB 存储驱动（USBSTOR）' 'USB storage driver (USBSTOR)')) 'disabled' ((CF-T '改动失败' 'failed')) 'fail'
            }
        }
    } else {
        Note ((CF-T 'USB 存储驱动（USBSTOR）' 'USB storage driver (USBSTOR)')) ((CF-T '正常' 'OK')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # ---- 4) 设备安装相关服务被停用 ----
    # 这三个服务任一被设为「已禁用」，新设备就装不上，老设备却照常能用。
    $svcFix = @()
    foreach ($s in @('DeviceInstall', 'PlugPlay', 'DsmSvc')) {
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $s
        $v = $null
        try { $v = (Get-ItemProperty -Path $k -Name 'Start' -ErrorAction Stop).Start } catch { }
        if ($null -eq $v) { continue }
        if ([int]$v -eq 4) {
            [void]$dn.Add('reg|' + $k + '|Start|4')
            if ($DryRun) {
                $svcFix += ($s + '→' + (CF-T '将启用' 'would enable'))
            } else {
                try {
                    Set-ItemProperty -Path $k -Name 'Start' -Value 3 -Type DWord -ErrorAction Stop
                    $svcFix += ($s + '→' + (CF-T '已启用' 'enabled'))
                } catch {
                    $svcFix += ($s + '→' + (CF-T '改动失败' 'failed'))
                }
            }
        }
    }
    if ($svcFix.Count -gt 0) {
        Note ((CF-T '设备安装服务被停用' 'Device install services disabled')) ((CF-T '已禁用' 'disabled')) ($svcFix -join '，') $(if ($DryRun) { 'would' } else { 'fixed' })
    } else {
        Note ((CF-T '设备安装服务（DeviceInstall / PlugPlay / DsmSvc）' 'Device install services (DeviceInstall / PlugPlay / DsmSvc)')) ((CF-T '正常' 'OK')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # ---- 5) 驱动搜索顺序：从不安装驱动 ----
    $kDs = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
    $soc = $null
    try { $soc = (Get-ItemProperty -Path $kDs -Name 'SearchOrderConfig' -ErrorAction Stop).SearchOrderConfig } catch { }
    if ($null -ne $soc -and [string]$soc -eq '0') {
        [void]$dn.Add('reg|' + $kDs + '|SearchOrderConfig|0')
        if ($DryRun) {
            Note ((CF-T '驱动搜索顺序：从不安装驱动' 'Driver search order: never install')) '0' ((CF-T '将改为 1' 'would set to 1')) 'would'
        } else {
            try {
                Set-ItemProperty -Path $kDs -Name 'SearchOrderConfig' -Value 1 -Type DWord -ErrorAction Stop
                Note ((CF-T '驱动搜索顺序：从不安装驱动' 'Driver search order: never install')) '0' '1' 'fixed'
            } catch {
                Note ((CF-T '驱动搜索顺序：从不安装驱动' 'Driver search order: never install')) '0' ((CF-T '改动失败' 'failed')) 'fail'
            }
        }
    } else {
        Note ((CF-T '驱动搜索顺序' 'Driver search order')) ((CF-T '正常' 'OK')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # ---- 6) 设备类过滤器残留（服务已删，过滤项还留着） ----
    # 这类残留会让新设备加载驱动失败，而老设备因为早就加载过、不受影响。
    $clsList = @(
        @{ G = '{36fc9e60-c465-11cf-8056-444553540000}'; N = 'USB 控制器类' },
        @{ G = '{4d36e978-e325-11ce-bfc1-08002be10318}'; N = '端口类' },
        @{ G = '{a5dcbf10-6530-11d2-901f-00c04fb951ed}'; N = 'USB 设备类' },
        @{ G = '{4d36e96d-e325-11ce-bfc1-08002be10318}'; N = '调制解调器类' }
    )
    $fRes = @()
    foreach ($c in $clsList) {
        $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $c.G
        if (-not (Test-Path $p)) { continue }
        foreach ($f in @('UpperFilters', 'LowerFilters')) {
            $v = $null
            try { $v = (Get-ItemProperty -Path $p -Name $f -ErrorAction Stop).$f } catch { }
            if ($null -eq $v) { continue }
            $all2 = @($v)
            $good = @($all2 | Where-Object { $_ -and (Test-Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $_)) })
            $bad  = @($all2 | Where-Object { $_ -and -not (Test-Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $_)) })
            if ($bad.Count -eq 0) { continue }
            $fRes += ($c.N + '/' + $f + '=' + ($bad -join ','))
            [void]$dn.Add('filters|' + $p + '|' + $f + '|' + ($all2 -join ','))
            if ($DryRun) { continue }
            try {
                if ($good.Count -eq 0) {
                    Remove-ItemProperty -Path $p -Name $f -ErrorAction Stop
                } else {
                    New-ItemProperty -Path $p -Name $f -Value ([string[]]$good) -PropertyType MultiString -Force -ErrorAction Stop | Out-Null
                }
            } catch {
                [void]$manual.Add((CF-T ('过滤器「' + ($bad -join ',') + '」改动失败，需手工清理。') ('Failed to clear filter "' + ($bad -join ',') + '"; needs manual cleanup.')))
            }
        }
    }
    if ($fRes.Count -gt 0) {
        Note ((CF-T '设备类过滤器残留' 'Leftover device-class filters')) ((CF-T '有残留' 'leftovers present')) $(if ($DryRun) { (CF-T '将清除' 'would clear') } else { (CF-T '已清除' 'cleared') }) $(if ($DryRun) { 'would' } else { 'fixed' })
    } else {
        Note ((CF-T '设备类过滤器残留' 'Leftover device-class filters')) ((CF-T '无' 'none')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # ---- 7) Enum\USB 权限：新设备要在这里建记录 ----
    # 权限被改坏，枚举会静默失败 —— 插上一点反应都没有，这是最隐蔽的一类。
    $aclFixed = 0
    $aclFail  = 0
    $aclChecked = 0
    $subs = New-Object System.Collections.ArrayList
    [void]$subs.Add('SYSTEM\CurrentControlSet\Enum')
    [void]$subs.Add('SYSTEM\CurrentControlSet\Enum\USB')
    try {
        foreach ($g in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -ErrorAction Stop)) {
            [void]$subs.Add('SYSTEM\CurrentControlSet\Enum\USB\' + $g.PSChildName)
            if ($subs.Count -ge 240) { break }
        }
    } catch { }

    $sid  = $null
    try { $sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18') } catch { }

    foreach ($sub in $subs) {
        $aclChecked++
        $needFix = $false
        try {
            $rk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    $sub,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadSubTree,
                    [System.Security.AccessControl.RegistryRights]::ReadPermissions)
            if ($null -eq $rk) { continue }
            $acl = $rk.GetAccessControl()
            $rk.Close()
            $hasWrite = $false
            foreach ($ace in $acl.Access) {
                if ($ace.AccessControlType -ne 'Allow') { continue }
                $who = ''
                try { $who = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { $who = [string]$ace.IdentityReference }
                if ($who -eq 'S-1-5-18' -and ([string]$ace.RegistryRights -match 'FullControl|WriteKey')) { $hasWrite = $true }
            }
            $deny = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' })
            if (-not $hasWrite -or $deny.Count -gt 0) { $needFix = $true }
        } catch {
            continue
        }
        if (-not $needFix) { continue }

        if ($DryRun) { $aclFixed++; continue }
        try {
            $rk = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
                    $sub,
                    [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
                    [System.Security.AccessControl.RegistryRights]::ChangePermissions)
            if ($null -eq $rk) { $aclFail++; continue }
            $acl = $rk.GetAccessControl()
            foreach ($ace in @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' })) {
                try { [void]$acl.RemoveAccessRule($ace) } catch { }
            }
            if ($null -ne $sid) {
                $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $sid,
                    [System.Security.AccessControl.RegistryRights]::FullControl,
                    [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow)
                $acl.SetAccessRule($rule)
            }
            $rk.SetAccessControl($acl)
            $rk.Close()
            $aclFixed++
        } catch {
            $aclFail++
        }
    }

    if ($aclFixed -gt 0) {
        Note ((CF-T '注册表 Enum 权限' 'Registry Enum permissions')) ((CF-T ($aclFixed.ToString() + ' 处不可写 / 有拒绝项') ($aclFixed.ToString() + ' key(s) unwritable or denied'))) $(if ($DryRun) { (CF-T '将修复' 'would fix') } else { (CF-T '已修复' 'fixed') }) $(if ($DryRun) { 'would' } else { 'fixed' })
    } elseif ($aclFail -gt 0) {
        Note ((CF-T '注册表 Enum 权限' 'Registry Enum permissions')) ((CF-T ($aclFail.ToString() + ' 处异常') ($aclFail.ToString() + ' key(s) abnormal'))) ((CF-T '修复失败' 'fix failed')) 'fail'
        [void]$manual.Add((CF-T 'Enum 权限修复失败：需要以 SYSTEM 权限操作（可用 PsExec -s 或 pe 环境），或重装系统。' 'Enum permission repair failed; it needs SYSTEM-level access.'))
    } else {
        Note ((CF-T '注册表 Enum 权限' 'Registry Enum permissions')) ((CF-T '正常' 'OK')) ((CF-T '不用动' 'no action')) 'ok'
    }

    # ---- 8) 设备安装日志过大（setupapi.dev.log） ----
    # 这个文件每装一次设备就追加一段。长到十几 MB 之后，给新设备建记录会明显变慢，
    # 极端情况直接失败，而设备管理器只表现成"插上没反应"。
    # 重装系统之所以"能好"，很大一部分原因是顺手把这个日志一起清空了。
    $bigLog = @()
    foreach ($n in @('setupapi.dev.log', 'setupapi.setup.log')) {
        $lp = Join-Path $env:WINDIR ('INF\' + $n)
        if (-not (Test-Path $lp)) { continue }
        try {
            $sz = (Get-Item -LiteralPath $lp -ErrorAction Stop).Length
            if ($sz -gt 8MB) { $bigLog += [pscustomobject]@{ Path = $lp; Name = $n; Size = $sz } }
        } catch { }
    }
    if ($bigLog.Count -eq 0) {
        Note ((CF-T '设备安装日志（setupapi）' 'Device install log (setupapi)')) ((CF-T '大小正常' 'size OK')) ((CF-T '不用动' 'no action')) 'ok'
    } elseif ($DryRun) {
        Note ((CF-T '设备安装日志（setupapi）' 'Device install log (setupapi)')) (([math]::Round(($bigLog | Measure-Object Size -Sum).Sum / 1MB, 1).ToString() + ' MB')) ((CF-T '将轮转' 'would rotate')) 'would'
    } else {
        $rot = 0
        foreach ($lf in $bigLog) {
            $dst = $lf.Path + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
            try {
                Move-Item -LiteralPath $lf.Path -Destination $dst -Force -ErrorAction Stop
                [void]$rot++
            } catch {
                [void]$manual.Add((CF-T ($lf.Name + ' 正被占用，本轮没能轮转；重启后再跑一次即可。') ($lf.Name + ' is in use and was not rotated; run again after a reboot.')))
            }
        }
        if ($rot -gt 0) {
            Note ((CF-T '设备安装日志（setupapi）' 'Device install log (setupapi)')) (([math]::Round(($bigLog | Measure-Object Size -Sum).Sum / 1MB, 1).ToString() + ' MB')) ((CF-T '已轮转（原文件留作 .bak）' 'rotated (kept as .bak)')) 'fixed'
        }
    }

    # ---- 顺带体检：第三方驱动包堆积 ----
    # 装了又卸的旧驱动包会一直留在 INF 目录里，新设备有可能匹配到已经坏掉的旧包。
    # 这里只提示，不自动删 —— 删错驱动包会直接影响在用的设备。
    try {
        $oemN = @(Get-ChildItem -Path (Join-Path $env:WINDIR 'INF\oem*.inf') -ErrorAction SilentlyContinue).Count
        if ($oemN -ge 60) {
            $msgZh = '第三方驱动包已积累 ' + $oemN + ' 个（INF\oem*.inf）。装过又卸掉的旧驱动会留在这里，新设备可能匹配到坏掉的旧包。建议用 pnputil /enum-drivers 核对后清理不用的旧包；本工具不自动删。'
            $msgEn = 'Third-party driver packages accumulated: ' + $oemN + ' (INF\oem*.inf). A new device may match a broken old driver. Review them with pnputil /enum-drivers; this tool does not delete them automatically.'
            [void]$manual.Add((CF-T $msgZh $msgEn))
        }
    } catch { }

    # ---- 把原值写到留底目录，方便还原 ----
    if ($BackupDir -ne '' -and (Test-Path $BackupDir) -and $dn.Count -gt 0) {
        try {
            $enc = New-Object System.Text.UTF8Encoding($true)
            $txt = (CF-T '# 系统层改动原值（用于还原）' '# Original values of system-level changes (for restore)') + "`r`n" +
                   (CF-T '# 格式：类型|键或路径|值名|原值' '# Format: type|key|value name|original') + "`r`n" +
                   ($dn -join "`r`n")
            [System.IO.File]::WriteAllText((Join-Path $BackupDir '系统层原值.txt'), $txt, $enc)
        } catch { }
    }

    $fixedN = @($items | Where-Object { $_.State -eq 'fixed' }).Count
    $wouldN = @($items | Where-Object { $_.State -eq 'would' }).Count
    $failN  = @($items | Where-Object { $_.State -eq 'fail' }).Count

    foreach ($it in $items) {
        $mark = '·'
        if ($it.State -eq 'fixed') { $mark = '√' }
        elseif ($it.State -eq 'would') { $mark = '→' }
        elseif ($it.State -eq 'fail') { $mark = '×' }
        CF-Log ('  ' + $mark + ' ' + $it.Name + '：' + $it.Before + ' → ' + $it.After) $(if ($it.State -eq 'fail') { 'err' } elseif ($it.State -eq 'fixed') { 'ok' } else { 'info' })
    }

    return [pscustomobject]@{
        Items  = @($items)
        Fixed  = $fixedN
        Would  = $wouldN
        Fail   = $failN
        Manual = @($manual)
    }
}

# ---------- 修复步骤 ----------
function CF-Step_CleanDead {
    param([string]$Scope = 'Serial', [switch]$IncludeHid, [switch]$DryRun)

    $all = @(CF-GetUsbDevices -Scope 'All')

    # 祖先保护：复合设备的父节点一旦被删，Windows 会把它的所有子接口一起删掉。
    # 所以只要某个 &MI_xx 子接口属于「本次不清理」的类别（键鼠/声卡/网卡等），
    # 它的父组也一起跳过，否则会连带删到不该动的东西。
    $protectGroups = @{}
    foreach ($x in $all) {
        if ($x.Group -notmatch '&MI_\d+') { continue }
        if (CF-CatInScope $x.Category $Scope ([bool]$IncludeHid)) { continue }
        $parent = ($x.Group -replace '&MI_\d+.*$', '')
        $protectGroups[$parent] = $true
    }
    if ($protectGroups.Count -gt 0) {
        CF-Log ('因含受保护子接口，父设备一并跳过 ' + $protectGroups.Count + ' 组') 'info' ($protectGroups.Count.ToString() + ' parent group(s) skipped because they contain protected child interfaces')
    }

    $inScope = @($all | Where-Object {
        (-not $_.Protected) -and
        (-not $protectGroups.ContainsKey($_.Group)) -and
        (CF-CatInScope $_.Category $Scope ([bool]$IncludeHid))
    })
    $skippedCat = @{}
    foreach ($x in $all) {
        if ($x.Protected) { continue }
        if ($protectGroups.ContainsKey($x.Group)) { continue }
        if (-not (CF-CatInScope $x.Category $Scope ([bool]$IncludeHid))) {
            if (-not $x.Online) {
                if (-not $skippedCat.ContainsKey($x.Category)) { $skippedCat[$x.Category] = 0 }
                $skippedCat[$x.Category]++
            }
        }
    }

    if (-not $script:CF_PresentOk) {
        CF-Log '无法判断设备是否在线，为避免误删，已跳过清理。' 'err' 'Cannot determine which devices are online - cleaning skipped to avoid deleting live devices.'
        CF-Log '（请用管理员身份运行，或检查系统是否禁用了 PnP 查询）' 'warn' '(Run as administrator, or check whether PnP queries are disabled)'
        return @{Ok = 0; Fail = 0; Total = 0; Skipped = $true; ByCat = @{}; Held = $skippedCat }
    }

    # 在线判定自检：根集线器焊在主板上，任何时候都在线。
    # 如果连它们都被判成离线，说明判定本身失效了，此时删任何东西都属于误删。
    $rootHubs = @($all | Where-Object { $_.Group -match '^ROOT_HUB' })
    if ($rootHubs.Count -gt 0) {
        $hubOn = @($rootHubs | Where-Object { $_.Online }).Count
        if ($hubOn -eq 0) {
            CF-Log '在线判定自检失败：连主板根集线器都被判成离线，判定结果不可信。' 'err' 'Self-check failed: even the on-board root hub was reported offline, so online detection is unreliable.'
            CF-Log '为避免误删正在使用的设备，本次拒绝执行任何删除。' 'err' 'Refusing to delete anything, to avoid removing devices currently in use.'
            return @{Ok = 0; Fail = 0; Total = 0; Skipped = $true; ByCat = @{}; Held = $skippedCat }
        }
    }

    $dead = @($inScope | Where-Object { -not $_.Online })
    if ($dead.Count -eq 0) {
        CF-Log '本次范围内没有离线残留记录，跳过' 'info' 'No offline residue in this range - nothing to clean'
        if ($skippedCat.Count -gt 0) {
            $parts = @()
            foreach ($k in $skippedCat.Keys) { $parts += ((CF-CatName $k) + ' ' + $skippedCat[$k]) }
            CF-Log ('  （另有未处理的离线记录：' + ($parts -join (CF-T '，' ', ')) + '）') 'warn' ('  (other offline records left untouched: ' + ($parts -join ', ') + ')')
        }
        return @{Ok = 0; Fail = 0; Total = 0; ByCat = @{}; Held = $skippedCat }
    }

    $byCat = @{}
    foreach ($d in $dead) {
        if (-not $byCat.ContainsKey($d.Category)) { $byCat[$d.Category] = 0 }
        $byCat[$d.Category]++
    }
    $summary = @()
    foreach ($k in $byCat.Keys) { $summary += ((CF-CatName $k) + ' ' + $byCat[$k]) }
    CF-Log ('发现离线残留 ' + $dead.Count + ' 条（' + ($summary -join (CF-T '，' ', ')) + '），开始清理') 'info' ('Found ' + $dead.Count + ' offline records (' + ($summary -join ', ') + '), cleaning...')

    $ok = 0; $fail = 0
    foreach ($d in $dead) {
        if ($DryRun) {
            CF-Log ('[试运行] 将删除 ' + $d.InstanceId) 'info' ('[dry run] would delete ' + $d.InstanceId)
            $ok++
            continue
        }
        $out = ''
        try { $out = (& pnputil.exe /remove-device $d.InstanceId 2>&1 | Out-String) } catch { $out = "$_" }
        if ($LASTEXITCODE -eq 0 -or $out -match '成功|Success|success') {
            $ok++
        } else {
            $out2 = ''
            try { $out2 = (& pnputil.exe /remove-device $d.InstanceId /subtree 2>&1 | Out-String) } catch { $out2 = "$_" }
            if ($LASTEXITCODE -eq 0 -or $out2 -match '成功|Success|success') {
                $ok++
            } else {
                $fail++
                CF-Log ('  删不掉：' + $d.InstanceId) 'warn' ('  cannot delete: ' + $d.InstanceId)
            }
        }
    }
    CF-Log ('清理完成：成功 ' + $ok + ' 条，失败 ' + $fail + ' 条') 'info' ('Cleaning done: ' + $ok + ' removed, ' + $fail + ' failed')
    if ($skippedCat.Count -gt 0) {
        $parts = @()
        foreach ($k in $skippedCat.Keys) { $parts += ((CF-CatName $k) + ' ' + $skippedCat[$k]) }
        CF-Log ('按保护规则未动：' + ($parts -join (CF-T '，' ', '))) 'info' ('Left untouched by protection rules: ' + ($parts -join ', '))
    }
    return @{Ok = $ok; Fail = $fail; Total = $dead.Count; ByCat = $byCat; Held = $skippedCat }
}

function CF-Step_ClearFailedFlags {
    param([string]$Scope = 'Serial', [switch]$IncludeHid, [switch]$DryRun)

    $all = @(CF-GetUsbDevices -Scope 'All')
    $bad = @($all | Where-Object {
        (-not $_.Protected) -and
        (CF-CatInScope $_.Category $Scope ([bool]$IncludeHid)) -and
        (($_.CfgFlags -band 0x60) -ne 0)
    })
    if ($bad.Count -eq 0) {
        CF-Log '没有「安装失败 / 待重装」标记，跳过' 'info' 'No "failed install / reinstall pending" flags - nothing to do'
        return @{Ok = 0; Total = 0 }
    }

    CF-Log ('发现异常标记 ' + $bad.Count + ' 条，开始清除') 'info' ('Found ' + $bad.Count + ' abnormal flags, clearing...')
    $ok = 0
    foreach ($x in $bad) {
        $new = [int]($x.CfgFlags -band (-bnot 0x60))
        if ($DryRun) {
            CF-Log ('[试运行] 将清标记 ' + $x.InstanceId) 'info' ('[dry run] would clear flags on ' + $x.InstanceId)
            $ok++
            continue
        }
        try {
            Set-ItemProperty $x.KeyPath -Name ConfigFlags -Value $new -Type DWord -ErrorAction Stop
            $ok++
            CF-Log ('  已清标记：' + $x.InstanceId) 'info' ('  flags cleared: ' + $x.InstanceId)
        } catch {
            CF-Log ('  清不掉：' + $x.InstanceId) 'warn' ('  cannot clear: ' + $x.InstanceId)
        }
    }
    return @{Ok = $ok; Total = $bad.Count }
}

function CF-Step_RebuildArbiter {
    param([switch]$DryRun, [int]$KeepPort = 0)

    $before = CF-GetComDB
    $beforeNums = @(CF-ComDBToNums $before)

    $inst = @(CF-GetSerialInstances)
    $keep = New-Object System.Collections.ArrayList

    foreach ($x in $inst) {
        if ($x.PortNum -gt 0) { [void]$keep.Add($x.PortNum) }
    }
    foreach ($n in (CF-GetMotherboardPorts)) { [void]$keep.Add([int]$n) }
    [void]$keep.Add(1)
    # 注意：这里绝不预占目标号。号池里的「已占」位会让 Windows 跳过该号，
    # 反而导致新设备拿不到目标号。目标号由 CF-PinDevice 给设备实例写
    # PortName 来占住，那才是真正生效的固定方式。

    $keepU = @($keep | Sort-Object -Unique)
    $drop = @($beforeNums | Where-Object { $keepU -notcontains $_ })

    CF-Log ('号池原占用 ' + $beforeNums.Count + ' 个，需要保留 ' + $keepU.Count + ' 个，可回收 ' + $drop.Count + ' 个') 'info' ('Port pool: ' + $beforeNums.Count + ' in use, ' + $keepU.Count + ' to keep, ' + $drop.Count + ' reclaimable')
    if ($drop.Count -gt 0) {
        CF-Log ('  回收：COM' + ($drop -join ', COM')) 'info' ('  reclaiming: COM' + ($drop -join ', COM'))
    }

    if ($DryRun) {
        CF-Log '[试运行] 不写入号池' 'info' '[dry run] port pool not written'
        return @{Before = $beforeNums.Count; After = $keepU.Count; Freed = $drop.Count }
    }

    CF-SetComDB $keepU
    CF-Log ('号池已重建，现在占用 ' + $keepU.Count + ' 个：COM' + ($keepU -join ', COM')) 'info' ('Port pool rebuilt: ' + $keepU.Count + ' in use: COM' + ($keepU -join ', COM'))
    return @{Before = $beforeNums.Count; After = $keepU.Count; Freed = $drop.Count }
}

# 重新扫描硬件（让系统把刚清干净的口重新走一遍枚举）
function CF-Step_Rescan([switch]$DryRun) {
    if ($DryRun) {
        CF-Log '[试运行] 将触发硬件重新扫描' 'info' '[dry run] would trigger a hardware rescan'
        return @{Ok = $true }
    }
    $done = $false
    try {
        $o = (& pnputil.exe /scan-devices 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0) { $done = $true }
    } catch { }
    if (-not $done) {
        try {
            $o = (& pnputil.exe /scan 2>&1 | Out-String)
            if ($LASTEXITCODE -eq 0) { $done = $true }
        } catch { }
    }
    if (-not $done) {
        try { $null = (& devcon.exe rescan 2>&1); $done = $true } catch { }
    }
    if ($done) {
        CF-Log '已触发硬件重新扫描' 'info' 'Hardware rescan triggered'
    } else {
        CF-Log '系统不支持自动重扫，重启后同样生效' 'warn' 'This system does not support an automatic rescan; a reboot has the same effect'
    }
    CF-ResetPresentCache
    return @{Ok = $done }
}

# ---------- 固定端口号 ----------
function CF-PinDevice {
    param($Instance, [int]$Target, [switch]$DryRun, [switch]$NoRestart)
    if ($Target -lt 3 -or $Target -gt 256) {
        CF-Log ('目标号 COM' + $Target + ' 不合法（3~256）') 'err' ('Target port COM' + $Target + ' is invalid (3-256)')
        return $false
    }
    $iid  = $Instance.InstanceId
    $key  = $Instance.KeyPath
    $dp   = Join-Path $key 'Device Parameters'
    $old  = $Instance.PortNum

    $others = @(CF-GetSerialInstances | Where-Object { $_.Online -and $_.PortNum -eq $Target -and $_.InstanceId -ne $iid })
    if ($others.Count -gt 0) {
        CF-Log ('  目标号 COM' + $Target + ' 正被另一台在线设备占用，跳过：' + $iid) 'warn' ('  COM' + $Target + ' is used by another online device, skipping: ' + $iid)
        return $false
    }

    if ($DryRun) {
        CF-Log ('[试运行] 将把 ' + $iid + ' 从 COM' + $old + ' 固定到 COM' + $Target) 'info' ('[dry run] would pin ' + $iid + ' from COM' + $old + ' to COM' + $Target)
        return $true
    }

    if (-not (Test-Path $dp)) {
        try { New-Item -Path $dp -Force -ErrorAction Stop | Out-Null } catch {
            CF-Log ('  无法创建设备参数键：' + $iid) 'err' ('  cannot create Device Parameters key: ' + $iid)
            return $false
        }
    }

    try {
        Set-ItemProperty $dp -Name PortName -Value ('COM' + $Target) -ErrorAction Stop
    } catch {
        CF-Log ('  写端口号失败：' + $iid + ' -> ' + $_.Exception.Message) 'err' ('  failed to write port name: ' + $iid + ' -> ' + $_.Exception.Message)
        return $false
    }

    $nums = @(CF-ComDBToNums (CF-GetComDB))
    $inst2 = @(CF-GetSerialInstances | Where-Object { $_.Online -and $_.PortNum -eq $old -and $_.InstanceId -ne $iid })
    if ($old -gt 0 -and $old -ne $Target -and $inst2.Count -eq 0) {
        $nums = @($nums | Where-Object { $_ -ne $old })
        CF-Log ('  释放旧号 COM' + $old) 'info' ('  released old port COM' + $old)
    }
    if ($nums -notcontains $Target) { $nums += $Target }
    try { CF-SetComDB $nums } catch { }

    if (-not $NoRestart) { CF-RestartDevice $iid }
    CF-Log ('已固定 ' + $iid + ' -> COM' + $Target) 'info' ('Pinned ' + $iid + ' -> COM' + $Target)
    return $true
}

function CF-RestartDevice([string]$iid) {
    try {
        Disable-PnpDevice -InstanceId $iid -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 400
        Enable-PnpDevice  -InstanceId $iid -Confirm:$false -ErrorAction Stop
        Start-Sleep -Milliseconds 600
        return $true
    } catch {
        return $false
    }
}

function CF-PinAllOnline([int]$Target, [switch]$DryRun) {
    $inst = @(CF-GetSerialInstances | Where-Object { $_.Online })
    if ($inst.Count -eq 0) {
        CF-Log '当前没有插着串口设备' 'info' 'No serial device is currently plugged in'
        return @{Ok = 0; Total = 0 }
    }

    $ok = 0
    foreach ($x in $inst) {
        if ($x.PortNum -eq $Target) {
            CF-Log ('已是 COM' + $Target + '：' + $x.InstanceId) 'info' ('Already COM' + $Target + ': ' + $x.InstanceId)
            $ok++
            continue
        }
        if (CF-PinDevice -Instance $x -Target $Target -DryRun:$DryRun -NoRestart) { $ok++ }
        Start-Sleep -Milliseconds 200
    }
    return @{Ok = $ok; Total = $inst.Count }
}

# ---------- 一键全修 ----------
function CF-FullFix {
    param(
        [int]$KeepPort = 3,
        [ValidateSet('Serial', 'VendorOnly', 'AllUsb')][string]$Scope = 'Serial',
        [switch]$IncludeHid,
        [switch]$DryRun
    )
    $r = [ordered]@{}
    CF-Log ('修复范围：' + (CF-ScopeName $Scope ([bool]$IncludeHid))) 'info' ('Scope: ' + (CF-ScopeName $Scope ([bool]$IncludeHid)))

    CF-Log '──── 第 1 步：留底 ────' 'info' '──── Step 1: snapshot ────'
    if ($DryRun) {
        CF-Log '[试运行] 跳过留底' 'info' '[dry run] snapshot skipped'
    } else {
        $r.Backup = CF-Backup
    }

    # 这一步是「新设备认不出」的真正要害：装不上的原因多半在系统层，
    # 只清记录是修不掉的，必须连策略、权限、过滤驱动一起处理。
    CF-Log '──── 第 2 步：自动修复系统层拦路项 ────' 'info' '──── Step 2: repair system-level blockers ────'
    $r.Blocks = CF-RepairBlocks -BackupDir ([string]$r.Backup) -DryRun:$DryRun
    foreach ($m in $r.Blocks.Manual) { CF-Log ('  ! ' + $m) 'warn' }
    if ($r.Blocks.Fixed -gt 0) {
        CF-Log ('  共自动修复 ' + $r.Blocks.Fixed + ' 项系统层问题') 'ok' ('  ' + $r.Blocks.Fixed + ' system-level issue(s) fixed')
    } elseif ($r.Blocks.Would -gt 0) {
        CF-Log ('  [试运行] 将有 ' + $r.Blocks.Would + ' 项需要修复') 'info'
    } else {
        CF-Log '  系统层各项均正常，无需改动' 'info' '  System level is clean, nothing to change'
    }

    CF-ResetPresentCache
    CF-Log '──── 第 3 步：清理离线残留设备 ────' 'info' '──── Step 3: clean offline devices ────'
    $r.Dead = CF-Step_CleanDead -Scope $Scope -IncludeHid:$IncludeHid -DryRun:$DryRun

    CF-Log '──── 第 4 步：清除「安装失败」标记 ────' 'info' '──── Step 4: clear failed-install flags ────'
    $r.Flags = CF-Step_ClearFailedFlags -Scope $Scope -IncludeHid:$IncludeHid -DryRun:$DryRun

    CF-Log '──── 第 5 步：重建 COM 号池 ────' 'info' '──── Step 5: rebuild COM port pool ────'
    $r.Arb = CF-Step_RebuildArbiter -DryRun:$DryRun -KeepPort $KeepPort

    CF-Log '──── 第 6 步：重新扫描硬件 ────' 'info' '──── Step 6: rescan hardware ────'
    $r.Rescan = CF-Step_Rescan -DryRun:$DryRun

    CF-Log ('──── 第 7 步：把插着的串口设备固定到 COM' + $KeepPort + ' ────') 'info' ('──── Step 7: pin plugged-in serial devices to COM' + $KeepPort + ' ────')
    $r.Pin = CF-PinAllOnline -Target $KeepPort -DryRun:$DryRun

    CF-Log '──── 完成 ────' 'info' '──── Done ────'
    return $r
}

# ---------- 体检 ----------
function CF-HealthCheck {
    $db    = CF-GetComDB
    $nums  = @(CF-ComDBToNums $db)
    $all   = @(CF-GetUsbDevices -Scope 'All')
    $inst  = @($all | Where-Object { $_.Category -eq 'Serial' })
    $on    = @($inst | Where-Object { $_.Online })
    $off   = @($inst | Where-Object { -not $_.Online })
    $bad   = @($all | Where-Object { (-not $_.Protected) -and (($_.CfgFlags -band 0x60) -ne 0) })
    $dup   = @($inst | Where-Object { $_.PortNum -gt 0 } | Group-Object PortNum | Where-Object { $_.Count -gt 1 })

    $declared = @{}
    foreach ($x in $inst) { if ($x.PortNum -gt 0) { $declared[$x.PortNum] = $true } }
    $legacy = @()
    $pk = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Ports'
    if (Test-Path $pk) { $legacy = @((Get-Item $pk).GetValueNames() | Where-Object { $_ -match '^COM(\d+):$' }) }
    foreach ($p in $legacy) { if ($p -match '^COM(\d+):$') { $declared[[int]$Matches[1]] = $true } }
    $orphan = @($nums | Where-Object { -not $declared.ContainsKey($_) })

    $catCount = @{}
    $catOnline = @{}
    $catOff = @{}
    foreach ($x in $all) {
        if ($x.Protected) { continue }
        if (-not $catCount.ContainsKey($x.Category)) { $catCount[$x.Category] = 0; $catOnline[$x.Category] = 0; $catOff[$x.Category] = 0 }
        $catCount[$x.Category]++
        if ($x.Online) { $catOnline[$x.Category]++ } else { $catOff[$x.Category]++ }
    }

    return [pscustomobject]@{
        Used       = $nums.Count
        Free       = 256 - $nums.Count
        MaxUsed    = $(if ($nums.Count -gt 0) { ($nums | Measure-Object -Maximum).Maximum } else { 0 })
        Online     = $on.Count
        Offline    = $off.Count
        BadFlags   = $bad.Count
        Duplicates = $dup
        Orphans    = $orphan
        Instances  = $inst
        Nums       = $nums
        AllDevices = $all
        CatCount   = $catCount
        CatOnline  = $catOnline
        CatOff     = $catOff
        UsbTotal   = @($all | Where-Object { -not $_.Protected }).Count
        UsbOffline = @($all | Where-Object { (-not $_.Protected) -and (-not $_.Online) }).Count
        PresentOk  = $script:CF_PresentOk
    }
}

function CF-WriteReport([string]$path) {
    $h = CF-HealthCheck
    $env2 = CF-CheckEnvironment
    $L = New-Object System.Collections.ArrayList

    [void]$L.Add((CF-T 'USB / 串口 一键修复 —— 检查报告' 'USB / Serial Fix - Inspection Report'))
    [void]$L.Add((CF-T '时间     : ' 'Time     : ') + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    [void]$L.Add((CF-T '电脑     : ' 'Computer : ') + $env:COMPUTERNAME)
    [void]$L.Add((CF-T '在线判定 : ' 'Detection: ') + $(if ($h.PresentOk) { CF-T '正常' 'OK' } else { CF-T '失败（本次不会删任何东西）' 'FAILED (nothing will be deleted)' }))
    [void]$L.Add('')

    [void]$L.Add((CF-T '══════ 一、串口 / COM 号 ══════' '====== 1. Serial ports / COM numbers ======'))
    [void]$L.Add((CF-T '号池占用 : ' 'Port pool  : ') + $h.Used + ' / 256' + (CF-T '　剩余 ' '  free ') + $h.Free + (CF-T '　最高 COM' '  highest COM') + $h.MaxUsed)
    [void]$L.Add((CF-T '在线串口 : ' 'Online     : ') + $h.Online)
    [void]$L.Add((CF-T '离线残留 : ' 'Offline    : ') + $h.Offline)
    [void]$L.Add((CF-T '异常标记 : ' 'Bad flags  : ') + $h.BadFlags)
    [void]$L.Add((CF-T '孤儿号   : ' 'Orphaned   : ') + $h.Orphans.Count)
    [void]$L.Add('')
    if ($h.Orphans.Count -gt 0) {
        [void]$L.Add((CF-T '孤儿号（号池里占着、但没有任何设备认领）：COM' 'Orphaned ports (in use but claimed by no device): COM') + ($h.Orphans -join ', COM'))
        [void]$L.Add('')
    }
    [void]$L.Add((CF-T '端口号明细（每条设备记录）：' 'Port details (per device record):'))
    foreach ($d in ($h.Duplicates)) {
        [void]$L.Add('  COM' + $d.Name + (CF-T ' 被 ' ' used by ') + $d.Count + (CF-T ' 条记录同时占用  <<< 冲突' ' records at once  <<< CONFLICT'))
    }
    foreach ($x in ($h.Instances | Sort-Object PortNum)) {
        $st = $(if ($x.Online) { CF-T '在线' 'online ' } else { CF-T '离线' 'offline' })
        $pn = $(if ($x.PortNum -gt 0) { 'COM' + $x.PortNum } else { (CF-T '(无号)' '(none)') })
        [void]$L.Add('  ' + $pn.PadRight(9) + $st + '  ' + $x.InstanceId)
    }
    [void]$L.Add('')

    [void]$L.Add((CF-T '══════ 二、全部 USB 设备（按类别） ══════' '====== 2. All USB devices (by category) ======'))
    $cats = @($h.CatCount.Keys | Sort-Object)
    foreach ($k in $cats) {
        [void]$L.Add('  ' + (CF-CatName $k).PadRight(26) + (CF-T '共 ' 'total ') + $h.CatCount[$k] +
                     (CF-T ' 条　在线 ' '   online ') + $h.CatOnline[$k] + (CF-T '　离线 ' '   offline ') + $h.CatOff[$k])
    }
    [void]$L.Add('')
    [void]$L.Add((CF-T ('合计：' + $h.UsbTotal + ' 条记录，其中离线 ' + $h.UsbOffline + ' 条') ('Total: ' + $h.UsbTotal + ' records, ' + $h.UsbOffline + ' offline')))
    [void]$L.Add((CF-T '（ROOT_HUB 这类主板节点已排除，不参与统计与清理）' '(ROOT_HUB and similar on-board nodes excluded from stats and cleaning)'))
    [void]$L.Add('')

    [void]$L.Add((CF-T '══════ 三、积累最多的设备型号 TOP 15 ══════' '====== 3. Most accumulated models (TOP 15) ======'))
    $grp = @(CF-GetUsbGroups |
             Where-Object { (-not $_.Protected) -and ($_.Group -notmatch '&MI_\d+') } |
             Sort-Object -Property Offline -Descending | Select-Object -First 15)
    foreach ($g in $grp) {
        [void]$L.Add('  ' + $g.Group.PadRight(30) + ' ' + (CF-CatName $g.Category).PadRight(26) +
                     (CF-T ' 共 ' ' total ') + $g.Total + (CF-T ' / 在线 ' ' / online ') + $g.Online + (CF-T ' / 离线 ' ' / offline ') + $g.Offline)
    }
    [void]$L.Add('')

    [void]$L.Add((CF-T '══════ 四、系统层面的可疑项 ══════' '====== 4. System-level findings ======'))
    if ($env2.Issues.Count -eq 0) {
        [void]$L.Add((CF-T '  没有发现系统层面的拦截项。' '  No system-level blockers found.'))
    } else {
        foreach ($i in $env2.Issues) { [void]$L.Add('  [!] ' + $i) }
    }
    [void]$L.Add('')
    [void]$L.Add((CF-T '  环境事实：' '  Environment facts:'))
    foreach ($f in $env2.Facts) { [void]$L.Add('    - ' + $f) }
    [void]$L.Add('')

    # ---- 插上完全没反应：专项 ----
    $deep = CF-CheckDeep
    [void]$L.Add((CF-T '══════ 五、「插上完全没反应」专项 ══════' '====== 5. "Nothing happens when plugged in" check ======'))
    if ($deep.Issues.Count -eq 0) {
        [void]$L.Add((CF-T '  没发现问题。如果新设备仍然完全认不出，说明问题不在软件记录这一层，' '  Nothing found. If a new device is still not detected at all, the problem is not in the software record layer.'))
        [void]$L.Add((CF-T '  要把排查方向转到：USB 端口物理层 / 供电 / 主机控制器驱动。' '  Shift the investigation to: USB port physical layer / power / host controller driver.'))
    } else {
        foreach ($i in $deep.Issues) { [void]$L.Add('  [!] ' + $i) }
    }
    [void]$L.Add('')
    [void]$L.Add((CF-T '  检查事实：' '  Facts:'))
    foreach ($f in $deep.Facts) { [void]$L.Add('    - ' + $f) }
    [void]$L.Add('')

    [void]$L.Add((CF-T '══════ 六、操作日志 ══════' '====== 6. Operation log ======'))
    if ($script:CF_LOG.Count -eq 0) {
        [void]$L.Add((CF-T '  （本次没有执行修复动作）' '  (no repair action was performed)'))
    }
    foreach ($t in $script:CF_LOG) { [void]$L.Add('  ' + $t) }

    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllLines($path, $L, $enc)
}
