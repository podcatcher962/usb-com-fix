# =====================================================================
#  USB / 串口 一键修复  —— 图形界面  v3（中英双语 + 菜单栏）
#  用法：双击「请双击这个-USB串口一键修复.bat」
#  参数：-Shot <png路径>    截图测试
#        -SelfTest         只测报告生成，不开窗口
#        -Lang zh|en       强制语言
# =====================================================================
param(
    [switch]$Elevated,
    [string]$Shot = '',
    [switch]$AutoFixTest,
    [int]$TestPort = 3,
    [string]$TestScope = 'AllUsb',
    [switch]$SelfTest,
    [string]$Lang = '',
    [string]$ShotDlg = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$corePath = Join-Path $PSScriptRoot 'comfix-core.ps1'
. $corePath

# ---------- 提权 ----------
if (-not (CF-IsAdmin)) {
    if ($Shot -ne '' -or $AutoFixTest -or $SelfTest) {
        # 截图/测试模式不提权
    } else {
        try {
            $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Elevated'
            if ($Lang -ne '') { $a += ' -Lang ' + $Lang }
            Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs | Out-Null
            exit
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "修复 USB / 串口设备需要管理员权限。`n`n请右键 →「以管理员身份运行」。`n`nAdministrator rights are required.",
                '权限不足 / Administrator required', 'OK', 'Warning') | Out-Null
            exit
        }
    }
}

# ---------- 配色 ----------
$C_BG      = [System.Drawing.Color]::FromArgb(240, 240, 240)
$C_PANEL   = [System.Drawing.Color]::FromArgb(250, 250, 250)
$C_TEXT    = [System.Drawing.Color]::FromArgb(33, 33, 33)
$C_SUB     = [System.Drawing.Color]::FromArgb(110, 110, 110)
$C_GREEN   = [System.Drawing.Color]::FromArgb(46, 125, 50)
$C_BLUE    = [System.Drawing.Color]::FromArgb(21, 101, 192)
$C_GRAY    = [System.Drawing.Color]::FromArgb(96, 125, 139)
$C_RED     = [System.Drawing.Color]::FromArgb(198, 40, 40)

# =====================================================================
#  语言
# =====================================================================
$LangArg = $Lang
$REG_APP = 'HKCU:\Software\ComFix'

function Get-SystemLang {
    try {
        $n = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($n -eq 'zh') { return 'zh' }
        return 'en'
    } catch { return 'zh' }
}

function Load-LangPref {
    $l = ''
    try { $l = [string](Get-ItemProperty $REG_APP -Name Lang -ErrorAction Stop).Lang } catch { }
    if ($l -eq 'zh' -or $l -eq 'en') { return $l }
    return (Get-SystemLang)
}

function Save-LangPref([string]$l) {
    try {
        if (-not (Test-Path $REG_APP)) { New-Item -Path $REG_APP -Force | Out-Null }
        Set-ItemProperty $REG_APP -Name Lang -Value $l -ErrorAction Stop
    } catch { }
}

# 注意：$script:LANG 和参数 $Lang 在脚本作用域里是同一个变量，
# 所以这里不能先给它一个默认值，否则会把命令行传入的 -Lang 覆盖掉。
if ($LangArg -eq 'zh' -or $LangArg -eq 'en') {
    $script:LANG = $LangArg
} else {
    $script:LANG = Load-LangPref
}
CF-SetLang $script:LANG

$script:TXT = @{
    'zh' = @{
        'app.title'   = 'USB / 串口 一键修复'
        'app.sub'     = '让插上认不出的新设备重新被识别，并固定到你指定的串口号'
        'app.author'  = '© 永远的兰兰'
        'lbl.port'    = '固定到'
        'lbl.scope'   = '修复范围'
        'scope.0'     = '串口设备（COM 口）'
        'scope.1'     = '厂商自定义设备'
        'scope.2'     = '全部 USB 设备'
'scope.3'     = '全部 USB 设备（含 HID）'
        'btn.fix'     = '一  键  修  复'
        'btn.watch.off' = '固定守护：关'
        'btn.watch.on'  = '固定守护：开'
        'btn.check'   = '只检查'
        'btn.undo'    = '还原上次'
        'foot'        = '报告自动保存到桌面（{a}）　　留底在 C:\ProgramData\ComFix\backup'
        'admin.ok'    = '管理员权限：已获得　|　只删「离线」的历史记录，插着的设备一条都不动'
        'admin.no'    = '管理员权限：未获得（修复会失败）'
        'menu.lang'   = '语言'
        'menu.help'   = '使用说明'
        'menu.disc'   = '免责声明'
        'menu.about'  = '关于'
        'menu.tools'  = '工具'
        'menu.probe'  = '深度取证（只读，插着新机器跑）'
        'log.probe.run'    = '深度取证中…（只读，不改任何设置）'
        'log.probe.done'   = '取证完成，报告在桌面：USB认不出-取证报告.txt'
        'log.probe.nofile' = '找不到取证脚本 usbprobe.ps1，程序目录不完整。'
        'log.probe.result' = '取证结论'
        'menu.zh'     = '中文'
        'menu.en'     = 'English'
        'st.ready'    = '就绪'
        'st.fixing'   = '正在修复…'
        'st.fixdone'  = '修复完成，请重启电脑'
        'st.fixerr'   = '修复出错（已生成出错报告）'
        'st.checking' = '正在检查…'
        'st.checkdone'= '检查完成'
        'st.restoring'= '正在还原…'
        'st.restored' = '还原完成，请重启电脑'
        'st.restoreerr'='还原出错（已生成出错报告）'
        'st.watching' = '守护中，新设备自动固定到 COM{n}'
        'st.watchoff' = '守护已停止'
        'st.watcherr' = '守护出错，已停止'
        'l.ready1'    = '就绪。本工具主要用来修复「插上认不出的新设备」。'
        'l.ready2'    = '建议顺序：先点「只检查」看一眼，再点「一键修复」，修完重启。'
        'l.pool'      = '号池占用 {a} / 256，剩余 {b}，最高 COM{c}'
        'l.serial'    = '串口：插着 {a} 台，历史残留 {b} 条，异常标记 {c} 条'
        'l.dup'       = '发现 {a} 个端口号被多条记录占用（会冲突）'
        'l.orphan'    = '发现 {a} 个孤儿号可以回收'
        'l.usbtot'    = '全部 USB：{a} 条记录，其中历史残留 {b} 条'
        'l.catrow'    = '  {name}　共 {a} 条（在线 {b} / 离线 {c}）'
        'l.hot'       = '积累最多：{a} 离线 {b} 条（{c}）'
        'l.start'     = '====== 开始修复：{a}，目标 COM{b} ======'
        'l.done'      = '====== 修复完成 ======'
        'l.blocks'    = '系统层自动修复：{a} 项已修好'
        'l.blocksfail'= '系统层自动修复：{a} 项失败（见上方逐项说明）'
        'l.skipped'   = '注意：在线状态判断失败，清理步骤已跳过，修复不完整。'
        'l.dead'      = '清理离线残留：成功 {a} / {b}'
        'l.deadcat'   = '  · {name}：{a} 条'
        'l.flags'     = '清除异常标记：{a} / {b}'
        'l.arb'       = '号池：原 {a} 个 → 现 {b} 个（回收 {c} 个）'
        'l.pin'       = '固定到 COM{a}：{b} / {c} 台'
        'l.nopin'     = '本次没有插着设备，已完成前 5 步（把挡住新设备的东西清掉）。'
        'l.next'      = '重启后把新设备插上：'
        'l.next1'     = '  · 如果能认出来、串口号正好是 COM{a}，就齐了'
        'l.next2'     = '  · 如果认出来了但串口号不对，点「固定守护」，它 2 秒内会把号改对'
        'l.next3'     = '  · 如果还是完全不认，点「只检查」，把报告发回来'
        'l.saved'     = '报告已保存到桌面：{a}'
        'l.notsaved'  = '报告写不到桌面（桌面可能不可写），上面的内容就是全部结果。'
        'l.checkhdr'  = '====== 检查 ======'
        'l.restorehdr'= '====== 还原：{a} ======'
        'l.errfix'    = '修复出错：{a}'
        'l.errcheck'  = '检查出错：{a}'
        'l.errrestore'= '还原出错：{a}'
        'l.errwatch'  = '守护出错，已自动停止：{a}'
        'l.errfile'   = '错误详情已写到桌面：{a}'
        'l.errfilebad'= '错误详情写文件失败，请把上面的内容截图发回。'
        'l.watchon'   = '====== 固定守护已开启，目标 COM{a} ======'
        'l.watchhint' = ' 插上新的空片，会自动把它的串口号固定到目标号，不用手动改。'
        'l.watchoff'  = '====== 固定守护已停止 ======'
        'l.already'   = '  已就位：{a} = COM{b}'
        'l.found'     = '  发现设备在 COM{a}，正在固定到 COM{b} …'
        'l.pinned'    = '  已固定：{a}'
        'd.fix.title' = '确认修复'
        'd.fix.q'     = '继续吗？'
        'd.fix.s1'    = '为了让新设备能被认出，将执行（范围：{a}）：'
        'd.fix.l0'    = '  1. 留底（原始状态存下来，随时能还原）'
        'd.fix.lb'    = '  2. 自动修掉系统层拦路项（安装策略 / 注册表权限 / 过滤驱动残留 / 服务被停用）'
        'd.fix.l1s'   = '  3. 清掉挡住新设备的离线串口残留'
        'd.fix.l1'    = '  3. 清掉挡住新设备的历史记录（该范围内所有「已拔掉」的）'
        'd.fix.l2'    = '  4. 清除「安装失败 / 待重装」标记（新设备装不上常卡在这）'
        'd.fix.l3'    = '  5. 修正串口号占用表（号被占死时，新设备分不到号）'
        'd.fix.l4'    = '  6. 重新扫描硬件，让系统重新识别'
        'd.fix.l5'    = '  7. 把当前插着的设备固定到 COM{a}'
        'd.fix.safe'  = '安全说明：'
        'd.fix.safeA' = '  · 只删拔掉的旧记录，插着的设备一条都不动'
        'd.fix.safeB' = '  · 集线器 / 控制器、键鼠、声卡、摄像头、网卡、打印机一律不碰'
        'd.fix.only'  = '只动 USB / 串口设备，不碰其他硬件。'
        'd.done.title'= '修复完成'
        'd.done.pin'  = '修复完成，共固定 {a} 台设备到 COM{b}。'
        'd.done.nopin'= '已完成清场（没有插着设备，第 6 步跳过）。重启后插上新设备，就能看出修好没有。'
        'd.done.tip'  = '为了让改动完全生效，建议现在就重启电脑。'
        'd.done.after'= '请重启电脑，然后把新设备插上试试：'
        'd.done.a1'   = '  · 号对了 → 正常生产'
        'd.done.a2'   = '  · 号不对 → 开「固定守护」自动改'
        'd.done.a3'   = '  · 还不认 → 点「只检查」发报告'
        'd.reboot'    = '现在重启吗？'
        'd.undo.title'= '确认还原'
        'd.undo.body' = '将还原到这次留底的原始状态：'
        'd.undo.none.t' = '提示'
        'd.undo.none.b' = '还没有留底记录，无法还原。'
        'd.exit.t'    = '确认'
        'd.exit.b'    = '固定守护还在运行，确定退出？'
        'd.err.t'     = '出错了'
        'd.err.b'     = "程序遇到一个意外错误，已经自动停下来。`n`n详细信息已写到桌面：`nUSB修复-出错报告.txt`n`n错误摘要：`n{a}`n`n请把这个文件发给开发。"
        'd.stop'      = '请停下'
        'd.stopb'     = '正在处理中，请等这一步结束。'
        'hdr.help'    = '使用说明'
        'hdr.disc'    = '免责声明'
        'hdr.about'   = '关于'
        'btn.ok'      = '知道了'
    }
    'en' = @{
        'app.title'   = 'USB / Serial Port Fix'
        'app.sub'     = 'Make unrecognized new devices detectable again, pinned to your COM port'
        'app.author'  = '© Lanlan Eternal'
        'lbl.port'    = 'Pin to'
        'lbl.scope'   = 'Scope'
        'scope.0'     = 'Serial ports (COM)'
        'scope.1'     = 'Vendor-specific devices'
        'scope.2'     = 'All USB devices'
'scope.3'     = 'All USB devices (incl. HID)'
        'btn.fix'     = 'F I X   N O W'
        'btn.watch.off' = 'Auto-pin: OFF'
        'btn.watch.on'  = 'Auto-pin: ON'
        'btn.check'   = 'Check only'
        'btn.undo'    = 'Restore'
        'foot'        = 'Report is saved to the Desktop ({a})　　Snapshots in C:\ProgramData\ComFix\backup'
        'admin.ok'    = 'Administrator: yes  |  Only "offline" records are removed; plugged-in devices are never touched'
        'admin.no'    = 'Administrator: NO (repair will fail)'
        'menu.lang'   = 'Language'
        'menu.help'   = 'Instructions'
        'menu.disc'   = 'Disclaimer'
        'menu.about'  = 'About'
        'menu.tools'  = 'Tools'
        'menu.probe'  = 'Deep Diagnosis (read-only, run with the new device plugged in)'
        'log.probe.run'    = 'Running deep diagnosis... (read-only, changes nothing)'
        'log.probe.done'   = 'Done. Report on Desktop: USB-Not-Detected-Report.txt'
        'log.probe.nofile' = 'usbprobe.ps1 not found - the program folder is incomplete.'
        'log.probe.result' = 'Diagnosis summary'
        'menu.zh'     = '中文'
        'menu.en'     = 'English'
        'st.ready'    = 'Ready'
        'st.fixing'   = 'Repairing...'
        'st.fixdone'  = 'Done - please reboot'
        'st.fixerr'   = 'Failed (error report saved)'
        'st.checking' = 'Checking...'
        'st.checkdone'= 'Check complete'
        'st.restoring'= 'Restoring...'
        'st.restored' = 'Restored - please reboot'
        'st.restoreerr'='Restore failed (error report saved)'
        'st.watching' = 'Watching - new devices auto-pinned to COM{n}'
        'st.watchoff' = 'Watch stopped'
        'st.watcherr' = 'Watch failed and stopped'
        'l.ready1'    = 'Ready. Main job: fix new devices that are not detected when plugged in.'
        'l.ready2'    = 'Suggested order: "Check only" first, then "FIX NOW", then reboot.'
        'l.pool'      = 'Port pool {a} / 256 in use, {b} free, highest COM{c}'
        'l.serial'    = 'Serial: {a} plugged in, {b} leftover records, {c} bad flags'
        'l.dup'       = '{a} port number(s) claimed by more than one record (conflict)'
        'l.orphan'    = '{a} orphaned port number(s) can be reclaimed'
        'l.usbtot'    = 'All USB: {a} records, {b} of them leftover'
        'l.catrow'    = '  {name}  {a} total ({b} online / {c} offline)'
        'l.hot'       = 'Most accumulated: {a} with {b} offline records ({c})'
        'l.start'     = '====== Repair started: {a}, target COM{b} ======'
        'l.done'      = '====== Repair finished ======'
        'l.blocks'    = 'System-level auto-repair: {a} issue(s) fixed'
        'l.blocksfail'= 'System-level auto-repair: {a} item(s) failed (details above)'
        'l.skipped'   = 'Note: online detection failed, so cleaning was skipped. Repair is incomplete.'
        'l.dead'      = 'Leftover records removed: {a} / {b}'
        'l.deadcat'   = '  - {name}: {a}'
        'l.flags'     = 'Bad flags cleared: {a} / {b}'
        'l.arb'       = 'Port pool: {a} -> {b} in use ({c} reclaimed)'
        'l.pin'       = 'Pinned to COM{a}: {b} / {c} device(s)'
        'l.nopin'     = 'No serial device was plugged in, so only cleaning was done (steps 1-5).'
        'l.next'      = 'After rebooting, plug in a new device:'
        'l.next1'     = '  - It shows up and the port is COM{a} -> all good'
        'l.next2'     = '  - It shows up but the port is wrong -> turn on "Auto-pin", fixed in 2 seconds'
        'l.next3'     = '  - It still does not show up -> click "Check only" and send the report back'
        'l.saved'     = 'Report saved to the Desktop: {a}'
        'l.notsaved'  = 'Could not write the report to the Desktop; the log above is the full result.'
        'l.checkhdr'  = '====== Check ======'
        'l.restorehdr'= '====== Restore: {a} ======'
        'l.errfix'    = 'Repair error: {a}'
        'l.errcheck'  = 'Check error: {a}'
        'l.errrestore'= 'Restore error: {a}'
        'l.errwatch'  = 'Watch failed and stopped automatically: {a}'
        'l.errfile'   = 'Details written to the Desktop: {a}'
        'l.errfilebad'= 'Could not write the error file. Please take a screenshot of the log above.'
        'l.watchon'   = '====== Auto-pin enabled, target COM{a} ======'
        'l.watchhint' = ' Plug in a blank device and its port is pinned automatically - no manual registry editing.'
        'l.watchoff'  = '====== Auto-pin stopped ======'
        'l.already'   = '  In place: {a} = COM{b}'
        'l.found'     = '  Device on COM{a}, pinning to COM{b} ...'
        'l.pinned'    = '  Pinned: {a}'
        'd.fix.title' = 'Confirm repair'
        'd.fix.q'     = 'Continue?'
        'd.fix.s1'    = 'To make new devices detectable again, this will run (scope: {a}):'
        'd.fix.l0'    = '  1. Take a snapshot (so it can be restored at any time)'
        'd.fix.lb'    = '  2. Auto-fix system-level blockers (install policy / registry permissions / stale filters / disabled services)'
        'd.fix.l1s'   = '  3. Clear leftover serial records that block new devices'
        'd.fix.l1'    = '  3. Clear leftover records blocking new devices (all "unplugged" in scope)'
        'd.fix.l2'    = '  4. Clear "failed install / reinstall pending" flags (a common blocker)'
        'd.fix.l3'    = '  5. Repair the COM port pool (a locked pool leaves no number for new devices)'
        'd.fix.l4'    = '  6. Rescan hardware so the system detects devices again'
        'd.fix.l5'    = '  7. Pin the currently plugged-in device to COM{a}'
        'd.fix.safe'  = 'Safety:'
        'd.fix.safeA' = '  - Only unplugged records are removed; live devices are never touched'
        'd.fix.safeB' = '  - Hubs, controllers, keyboard/mouse, audio, camera, network and printers are never touched'
        'd.fix.only'  = 'Only USB / serial devices are touched; no other hardware.'
        'd.done.title'= 'Repair finished'
        'd.done.pin'  = 'Finished. {a} device(s) pinned to COM{b}.'
        'd.done.nopin'= 'Cleaning finished (no serial device was plugged in, so only cleaning and pool rebuild were done).'
        'd.done.tip'  = 'A reboot is recommended so the changes take full effect.'
        'd.done.after'= 'Please reboot, then plug in a new device:'
        'd.done.a1'   = '  - Correct port -> ready for production'
        'd.done.a2'   = '  - Wrong port -> turn on "Auto-pin"'
        'd.done.a3'   = '  - Still not detected -> "Check only" and send the report'
        'd.reboot'    = 'Reboot now?'
        'd.undo.title'= 'Confirm restore'
        'd.undo.body' = 'Restore to the state captured in this snapshot:'
        'd.undo.none.t' = 'Notice'
        'd.undo.none.b' = 'No snapshot found, nothing to restore.'
        'd.exit.t'    = 'Confirm'
        'd.exit.b'    = 'Auto-pin is still running. Exit anyway?'
        'd.err.t'     = 'Error'
        'd.err.b'     = "The program hit an unexpected error and stopped.`n`nDetails were written to the Desktop:`nUSB-Fix-Error-Report.txt`n`nSummary:`n{a}`n`nPlease send that file to the developer."
        'd.stop'      = 'Please wait'
        'd.stopb'     = 'An operation is in progress. Let it finish first.'
        'hdr.help'    = 'Instructions'
        'hdr.disc'    = 'Disclaimer'
        'hdr.about'   = 'About'
        'btn.ok'      = 'OK'
    }
}

function T([string]$k) {
    $d = $script:TXT[$script:LANG]
    if ($d -and $d.ContainsKey($k)) { return $d[$k] }
    $z = $script:TXT['zh']
    if ($z.ContainsKey($k)) { return $z[$k] }
    return $k
}

# 带占位符的模板：Fmt 'l.pool' @{a=1;b=2;c=3}
function Fmt([string]$k, $map) {
    $s = T $k
    foreach ($key in $map.Keys) { $s = $s.Replace('{' + $key + '}', [string]$map[$key]) }
    return $s
}

$script:Busy = $false

# =====================================================================
#  桌面报告
# =====================================================================
function Get-DeskPath {
    $d = ''
    try { $d = [Environment]::GetFolderPath('Desktop') } catch { }
    if (-not $d -or -not (Test-Path $d)) { $d = Join-Path $env:USERPROFILE 'Desktop' }
    if (-not (Test-Path $d)) { $d = $env:TEMP }
    return $d
}

function Format-ErrText($er) {
    if ($null -eq $er) { return '(no error object)' }
    $t = ''
    try {
        $t = (T 'app.title') + ' | ' + (T 'd.err.t') + ': ' + $er.Exception.Message
        try {
            $ln = [string]$er.InvocationInfo.ScriptLineNumber
            $cmd = ([string]$er.InvocationInfo.Line).Trim()
            if ($ln -ne '') { $t += "`r`nline: " + $ln }
            if ($cmd -ne '') { $t += "`r`ncommand: " + $cmd }
        } catch { }
        if ($er.ScriptStackTrace) { $t += "`r`n`r`nstack:`r`n" + $er.ScriptStackTrace }
        if ($er.Exception.StackTrace) { $t += "`r`n`r`.NET:`r`n" + $er.Exception.StackTrace }
    } catch {
        try { $t = [string]$er } catch { $t = '(unreadable error)' }
    }
    return $t
}

function Rep-Name {
    # 报告文件名跟随界面语言，英文模式下不留中文
    if ($script:LANG -eq 'en') { return 'Device-Check-Report.txt' }
    return '设备检查报告.txt'
}

function Save-DeskReport {
    param([string]$Kind = 'ok', [string]$ErrText = '')
    $desk = Get-DeskPath
    $main = Join-Path $desk (Rep-Name)

    try { CF-WriteReport $main } catch { }

    if ($Kind -ne 'err') {
        if (Test-Path $main) { return $main }
        return ''
    }

    $L = New-Object System.Collections.ArrayList
    $en = ($script:LANG -eq 'en')
    if ($en) {
        [void]$L.Add('USB / Serial Port Fix - ERROR REPORT')
        [void]$L.Add('================================================')
        [void]$L.Add('Time     : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        [void]$L.Add('Computer : ' + $env:COMPUTERNAME)
        try { [void]$L.Add('OS       : ' + [Environment]::OSVersion.VersionString) } catch { }
        try { [void]$L.Add('Bitness  : ' + $(if ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' })) } catch { }
        [void]$L.Add('Admin    : ' + $(if (CF-IsAdmin) { 'yes' } else { 'NO (repair will always fail)' }))
        try { [void]$L.Add('Language : ' + $script:LANG) } catch { }
        try { [void]$L.Add('Scope    : ' + (CF-ScopeName (Get-Scope) (Get-IncludeHid)) + '   target COM' + (Get-TargetPort)) } catch { }
        [void]$L.Add('')
        [void]$L.Add('------ Error details ------')
        if ($ErrText -eq '') { $ErrText = '(no error captured - see the operation log below)' }
        foreach ($line in ($ErrText -split "`r?`n")) { [void]$L.Add('  ' + $line) }
        [void]$L.Add('')
        [void]$L.Add('------ Operation log ------')
        if ($script:CF_LOG.Count -eq 0) { [void]$L.Add('  (no action was performed)') }
        foreach ($t in $script:CF_LOG) { [void]$L.Add('  ' + $t) }
        [void]$L.Add('')
        [void]$L.Add('------ How to report ------')
        [void]$L.Add('  Send this file together with "Device-Check-Report.txt" from the Desktop.')
        [void]$L.Add('  Also describe one thing: when you plug in a new device, does Device')
        [void]$L.Add('  Manager stay completely silent, or does a yellow exclamation mark appear?')
        [void]$L.Add('  If there is an exclamation mark, double-click it and note the error code.')
    } else {
        [void]$L.Add('USB / 串口 一键修复 —— 出错报告')
        [void]$L.Add('================================================')
        [void]$L.Add('时间 : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        [void]$L.Add('电脑 : ' + $env:COMPUTERNAME)
        try { [void]$L.Add('系统 : ' + [Environment]::OSVersion.VersionString) } catch { }
        try { [void]$L.Add('位数 : ' + $(if ([Environment]::Is64BitOperatingSystem) { '64 位' } else { '32 位' })) } catch { }
        [void]$L.Add('权限 : ' + $(if (CF-IsAdmin) { '管理员' } else { '普通用户（修复一定会失败）' }))
        try { [void]$L.Add('范围 : ' + (CF-ScopeName (Get-Scope) (Get-IncludeHid)) + '　目标 COM' + (Get-TargetPort)) } catch { }
        [void]$L.Add('')
        [void]$L.Add('══════ 错误详情 ══════')
        if ($ErrText -eq '') { $ErrText = '(没有捕获到具体错误，请看下面的操作日志)' }
        foreach ($line in ($ErrText -split "`r?`n")) { [void]$L.Add('  ' + $line) }
        [void]$L.Add('')
        [void]$L.Add('══════ 操作日志 ══════')
        if ($script:CF_LOG.Count -eq 0) { [void]$L.Add('  (本次没有执行任何动作)') }
        foreach ($t in $script:CF_LOG) { [void]$L.Add('  ' + $t) }
        [void]$L.Add('')
        [void]$L.Add('══════ 怎么反馈 ══════')
        [void]$L.Add('  把这个文件连同桌面上的「设备检查报告.txt」一起发给开发。')
        [void]$L.Add('  再补一句现场观察：插上新机器时，设备管理器里是「完全没动静」，')
        [void]$L.Add('  还是「多了一个黄色感叹号」？如果是感叹号，双击看错误代码是几。')
    }

    $repErr = $(if ($en) { 'USB-Fix-Error-Report.txt' } else { 'USB修复-出错报告.txt' })
    $f = Join-Path $desk $repErr
    $enc = New-Object System.Text.UTF8Encoding($true)
    try { [System.IO.File]::WriteAllLines($f, $L, $enc) } catch { }
    return $f
}

# =====================================================================
#  窗体
# =====================================================================
$form = New-Object System.Windows.Forms.Form
$form.ClientSize = New-Object System.Drawing.Size(720, 522)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $C_BG
$form.ForeColor = $C_TEXT
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

# ---------- 菜单栏 ----------
$menu = New-Object System.Windows.Forms.MenuStrip
$menu.BackColor = [System.Drawing.Color]::FromArgb(232, 232, 232)
$menu.ForeColor = $C_TEXT
$menu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$menu.RenderMode = 'System'
$form.MainMenuStrip = $menu

$mTools = New-Object System.Windows.Forms.ToolStripMenuItem
$mProbe = New-Object System.Windows.Forms.ToolStripMenuItem
$mHelp  = New-Object System.Windows.Forms.ToolStripMenuItem
$mDisc  = New-Object System.Windows.Forms.ToolStripMenuItem
$mAbout = New-Object System.Windows.Forms.ToolStripMenuItem

# 语言切换：菜单栏右侧两个分段按键，不放在下拉菜单里。
# 这样英文用户不必认识「语言」两个字，看到 English 就能直接点；
# 当前语言那个按键是蓝色加粗的，一眼能看出现在是哪种语言。
$mZh = New-Object System.Windows.Forms.ToolStripButton
$mEn = New-Object System.Windows.Forms.ToolStripButton
foreach ($lb in @($mZh, $mEn)) {
    $lb.DisplayStyle = 'Text'
    $lb.CheckOnClick = $false
    $lb.AutoToolTip = $false
    $lb.ToolTipText = 'Language / 语言'
    $lb.Alignment   = [System.Windows.Forms.ToolStripItemAlignment]::Right
    $lb.Padding     = New-Object System.Windows.Forms.Padding(7, 0, 7, 0)
    $lb.Margin      = New-Object System.Windows.Forms.Padding(0)
}
$mZh.Text = '中文'
$mEn.Text = 'English'

[void]$mTools.DropDownItems.Add($mProbe)

[void]$menu.Items.Add($mTools)
[void]$menu.Items.Add($mHelp)
[void]$menu.Items.Add($mDisc)
[void]$menu.Items.Add($mAbout)
# Right 对齐的项从右往左排列，所以先加 English 才显示成「中文 | English」
[void]$menu.Items.Add($mEn)
[void]$menu.Items.Add($mZh)
$form.Controls.Add($menu)

# ---------- 标题 ----------
$lbTitle = New-Object System.Windows.Forms.Label
$lbTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$lbTitle.ForeColor = $C_TEXT
$lbTitle.Location = New-Object System.Drawing.Point(24, 38)
$lbTitle.Size = New-Object System.Drawing.Size(430, 34)
$form.Controls.Add($lbTitle)

$lbAuthor = New-Object System.Windows.Forms.Label
$lbAuthor.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$lbAuthor.ForeColor = $C_SUB
$lbAuthor.Location = New-Object System.Drawing.Point(470, 50)
$lbAuthor.Size = New-Object System.Drawing.Size(226, 20)
$lbAuthor.TextAlign = 'MiddleRight'
$form.Controls.Add($lbAuthor)

$lbSub = New-Object System.Windows.Forms.Label
$lbSub.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$lbSub.ForeColor = $C_SUB
$lbSub.Location = New-Object System.Drawing.Point(26, 74)
$lbSub.Size = New-Object System.Drawing.Size(670, 20)
$form.Controls.Add($lbSub)

# ---------- 目标号 + 范围 ----------
$lbPort = New-Object System.Windows.Forms.Label
$lbPort.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$lbPort.Location = New-Object System.Drawing.Point(26, 106)
$lbPort.Size = New-Object System.Drawing.Size(58, 22)
$form.Controls.Add($lbPort)

$cbPort = New-Object System.Windows.Forms.ComboBox
$cbPort.DropDownStyle = 'DropDownList'
$cbPort.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$cbPort.Location = New-Object System.Drawing.Point(84, 103)
$cbPort.Size = New-Object System.Drawing.Size(88, 26)
for ($i = 3; $i -le 30; $i++) { [void]$cbPort.Items.Add('COM' + $i) }
$cbPort.SelectedIndex = 0
$form.Controls.Add($cbPort)

$lbScope = New-Object System.Windows.Forms.Label
$lbScope.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$lbScope.Location = New-Object System.Drawing.Point(190, 106)
$lbScope.Size = New-Object System.Drawing.Size(62, 22)
$form.Controls.Add($lbScope)

$cbScope = New-Object System.Windows.Forms.ComboBox
$cbScope.DropDownStyle = 'DropDownList'
$cbScope.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$cbScope.Location = New-Object System.Drawing.Point(254, 103)
$cbScope.Size = New-Object System.Drawing.Size(198, 26)
[void]$cbScope.Items.Add('')
[void]$cbScope.Items.Add('')
[void]$cbScope.Items.Add('')
[void]$cbScope.Items.Add('')
$cbScope.SelectedIndex = 2
$form.Controls.Add($cbScope)

$lbStatus = New-Object System.Windows.Forms.Label
$lbStatus.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$lbStatus.ForeColor = $C_SUB
$lbStatus.Location = New-Object System.Drawing.Point(458, 108)
$lbStatus.Size = New-Object System.Drawing.Size(238, 22)
$lbStatus.TextAlign = 'MiddleRight'
$form.Controls.Add($lbStatus)

# ---------- 日志 ----------
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.WordWrap = $true
$logBox.BackColor = $C_PANEL
$logBox.ForeColor = $C_TEXT
$logBox.BorderStyle = 'FixedSingle'
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$logBox.Location = New-Object System.Drawing.Point(24, 136)
$logBox.Size = New-Object System.Drawing.Size(672, 240)
$form.Controls.Add($logBox)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(24, 384)
$bar.Size = New-Object System.Drawing.Size(672, 8)
$bar.Style = 'Continuous'
$bar.Minimum = 0
$bar.Maximum = 100
$bar.Value = 0
$form.Controls.Add($bar)

function Set-Status([string]$t, [string]$color = '') {
    $lbStatus.Text = (T 'st.ready') + ':' + $t
    if ($script:LANG -eq 'zh') { $lbStatus.Text = '状态：' + $t } else { $lbStatus.Text = 'Status: ' + $t }
    if ($color -eq 'ok')   { $lbStatus.ForeColor = $C_GREEN }
    elseif ($color -eq 'err') { $lbStatus.ForeColor = $C_RED }
    elseif ($color -eq 'run') { $lbStatus.ForeColor = $C_BLUE }
    else { $lbStatus.ForeColor = $C_SUB }
    [System.Windows.Forms.Application]::DoEvents()
}

function Add-LogLine([string]$line, [string]$level) {
    $logBox.AppendText($line + "`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

$script:CF_OnLog = { param($line, $level) Add-LogLine $line $level }

function Set-Busy([bool]$b) {
    $script:Busy = $b
    $btnFix.Enabled   = -not $b
    $btnWatch.Enabled = -not $b
    $btnCheck.Enabled = -not $b
    $btnUndo.Enabled  = -not $b
    $cbPort.Enabled   = -not $b
    $cbScope.Enabled  = -not $b
    $mZh.Enabled      = -not $b
    $mEn.Enabled      = -not $b
    if ($b) { $bar.Style = 'Marquee' } else { $bar.Style = 'Continuous'; $bar.Value = 0 }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-TargetPort {
    $s = [string]$cbPort.SelectedItem
    if ($s -match '(\d+)') { return [int]$Matches[1] }
    return 3
}

function Get-Scope {
    switch ($cbScope.SelectedIndex) {
        0 { return 'Serial' }
        1 { return 'VendorOnly' }
        default { return 'AllUsb' }
    }
}

# 第 4 项「全部 USB 设备（含 HID）」才把 HID 设备的离线记录也纳入清理
function Get-IncludeHid {
    return ($cbScope.SelectedIndex -eq 3)
}

# ---------- 按钮 ----------
function New-Btn($x, $w, $color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, 410)
    $b.Size = New-Object System.Drawing.Size($w, 44)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $b.Cursor = 'Hand'
    return $b
}

$btnFix   = New-Btn 24 170 $C_GREEN
$btnWatch = New-Btn 206 148 $C_BLUE
$btnCheck = New-Btn 366 112 $C_GRAY
$btnUndo  = New-Btn 490 112 $C_GRAY
$form.Controls.AddRange(@($btnFix, $btnWatch, $btnCheck, $btnUndo))

$lbFoot = New-Object System.Windows.Forms.Label
$lbFoot.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$lbFoot.ForeColor = $C_SUB
$lbFoot.Location = New-Object System.Drawing.Point(26, 470)
$lbFoot.Size = New-Object System.Drawing.Size(672, 20)
$form.Controls.Add($lbFoot)

$lbAdmin = New-Object System.Windows.Forms.Label
$lbAdmin.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$lbAdmin.Location = New-Object System.Drawing.Point(26, 492)
$lbAdmin.Size = New-Object System.Drawing.Size(672, 20)
if ((CF-IsAdmin) -or ($Shot -ne '') -or $SelfTest) {
    $lbAdmin.ForeColor = $C_GREEN
    $script:AdminOk = $true
} else {
    $lbAdmin.ForeColor = $C_RED
    $script:AdminOk = $false
}
$form.Controls.Add($lbAdmin)

# =====================================================================
#  应用语言
# =====================================================================
function Apply-Lang {
    CF-SetLang $script:LANG

    $form.Text   = T 'app.title'
    $lbTitle.Text = T 'app.title'
    $lbSub.Text   = T 'app.sub'
    $lbAuthor.Text = T 'app.author'
    $lbPort.Text  = T 'lbl.port'
    $lbScope.Text = T 'lbl.scope'
    $lbFoot.Text  = Fmt 'foot' @{a = (Rep-Name)}
    $lbAdmin.Text = $(if ($script:AdminOk) { T 'admin.ok' } else { T 'admin.no' })

    $i = $cbScope.SelectedIndex
    $cbScope.Items.Clear()
[void]$cbScope.Items.Add((T 'scope.0'))
[void]$cbScope.Items.Add((T 'scope.1'))
[void]$cbScope.Items.Add((T 'scope.2'))
[void]$cbScope.Items.Add((T 'scope.3'))
    $cbScope.SelectedIndex = $(if ($i -lt 0) { 2 } else { $i })

    $btnFix.Text   = T 'btn.fix'
    $btnCheck.Text = T 'btn.check'
    $btnUndo.Text  = T 'btn.undo'
    if ($script:Watching) {
        $btnWatch.Text = T 'btn.watch.on'
        $btnWatch.BackColor = $C_RED
    } else {
        $btnWatch.Text = T 'btn.watch.off'
        $btnWatch.BackColor = $C_BLUE
    }

    $mTools.Text = T 'menu.tools'
    $mProbe.Text = T 'menu.probe'
    $mHelp.Text  = T 'menu.help'
    $mDisc.Text  = T 'menu.disc'
    $mAbout.Text = T 'menu.about'
    # 语言按键的文字固定为「中文 / English」，不随界面语言变化——
    # 两种语言的用户都能直接找到自己那一个，当前语言蓝色加粗。
    $mZh.Checked = ($script:LANG -eq 'zh')
    $mEn.Checked = ($script:LANG -eq 'en')
    if ($script:LANG -eq 'zh') {
        $mZh.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
        $mEn.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular)
        $mZh.ForeColor = $C_BLUE
        $mEn.ForeColor = $C_TEXT
    } else {
        $mZh.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular)
        $mEn.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
        $mZh.ForeColor = $C_TEXT
        $mEn.ForeColor = $C_BLUE
    }

    Set-Status (T 'st.ready')
}

# =====================================================================
#  说明 / 免责 / 关于 —— 长文本
# =====================================================================
function Get-HelpLines {
    if ($script:LANG -eq 'en') {
        return @(
            'WHAT THIS TOOL DOES',
            '',
            'On production PCs, USB device records pile up and get corrupted. Result:',
            '  - machines already tested are still detected',
            '  - brand-new machines / blank chips are NOT detected',
            '  - COM numbers drift and no longer match the production software',
            '  - reinstalling Windows fixes it for a while, then it happens again',
            '',
            'One click runs all seven steps automatically:',
            '  1. Take a snapshot (restorable at any time)',
            '  2. Auto-fix system-level blockers: device install policy, registry Enum',
            '     permissions, stale filter drivers, disabled USB/install services',
            '  3. Remove "unplugged" device records in the selected scope',
            '  4. Clear "failed install / reinstall pending" flags',
            '  5. Rebuild the COM port pool',
            '  6. Rescan hardware',
            '  7. Pin plugged-in serial devices to the chosen port',
            '',
            '* Step 2 is the key one: when a device cannot install or shows no reaction',
            '  at all, the cause is usually at that layer - cleaning records alone',
            '  cannot fix it. That is why the older version failed.',
            '',
            'WHY THERE IS A "SCOPE"',
            '  A production line usually has more than one model:',
            '    - some are USB-to-serial (they create a COM port)',
            '    - some are plain USB devices with no COM port at all',
            '  Cleaning only serial ports would miss the second kind, so:',
            '    Serial ports (COM)   - most conservative; use when sure it is serial',
            '    Vendor-specific      - covers burners / test fixtures',
            '    All USB devices      - covers both; use this when unsure (default)',
            '    All USB + HID        - pick this when the new model is HID-based',
            '',
            '  Only offline records are removed; plugged-in devices are never touched.',
            '  Hubs, controllers, keyboards, mice, audio, network stay protected.',
            '',
            'HOW TO USE',
            '  1. Double-click "请双击这个-USB串口一键修复.bat", approve the UAC prompt',
            '  2. Click "Check only" and look at the report on the Desktop',
            '  3. Choose the port and scope, click "FIX NOW"',
            '  4. Reboot when asked',
            '  5. Plug in a new device and see whether it is detected',
            '',
            'CAN I RUN IT WITHOUT ANY DEVICE PLUGGED IN?',
            '  Yes. With nothing plugged in, steps 1-6 still run (a "clean sweep").',
            '  After rebooting, plug in a new device:',
            '    - detected with the right port -> done',
            '    - detected with a wrong port    -> turn on "Auto-pin"',
            '    - still not detected            -> "Check only" and send the report',
            '',
            'AUTO-PIN (keep it on during production)',
            '  Click "Auto-pin: OFF" and it turns red / ON. From then on, every',
            '  newly plugged device is pinned to the target port within 2 seconds -',
            '  this replaces the old .bat that pinned ports through the registry.',
            '',
            'PURE USB vs SERIAL DEVICES',
            '  - Pure USB != HID: also vendor-specific (WinUSB), storage, network, audio',
            '  - Port writing only applies to devices Windows already sees as serial:',
            '      1) candidates come only from the serial category - HID / vendor /',
            '         storage devices never enter the list',
            '      2) it must already own a COM number, or its class must be Ports',
            '  - Pure USB devices never get a port name and never occupy the port pool',
            '  - Both kinds can share one PC; serial models are still pinned as before',
            '',
            'ONE PHYSICAL LIMIT (no software can bypass it)',
            '  A device without a serial number gets a record per USB port it is plugged',
            '  into. Move it to another port and Windows treats it as a new device and',
            '  assigns a new number. Keep the same port, or leave Auto-pin running.',
            '',
            'SAFETY',
            '  - Only "unplugged" records are removed; live devices are never touched',
            '  - Hubs and USB controllers are permanently protected',
            '  - Keyboard/mouse, audio, camera, network, printers, Bluetooth: untouched',
            '  - If a composite device has a protected child interface, the parent is',
            '    skipped too, so nothing protected is removed indirectly',
            '  - Three self-checks: no online list -> no deletion; even the on-board',
            '    root hub reported offline -> no deletion',
            '  - Everything is logged and snapshotted',
            '',
            'REPORTS',
            '  Desktop\Device-Check-Report.txt  - full inspection report (always refreshed)',
            '  Desktop\USB-Fix-Error-Report.txt  - only when something goes wrong',
            '  Snapshots: C:\ProgramData\ComFix\backup\fix-YYYYMMDD-HHMMSS\',
            '',
            'IMPORTANT',
            '  - Administrator rights are required',
            '  - Reboot after repair or restore',
            '  - It never touches firmware, chips, the product itself, or production software',
            '  - Test on ONE machine before rolling out to the whole line'
        )
    }
    return @(
        '这个工具解决什么',
        '',
        '生产电脑上，USB 设备的记录会越积越多、越积越乱，结果：',
        '  · 测过的机器插上还能认',
        '  · 没刷过机的新机器 / 没固件的空片插上认不出',
        '  · 串口号跳来跳去，跟生产软件对不上',
        '  · 重装系统能好一阵，过段时间又犯',
        '',
        '一次点完，七步全自动做完，不用你挑：',
        '  1. 先留底（把当前状态原样存下来，随时能还原）',
        '  2. 自动修掉系统层拦路项：设备安装策略、注册表 Enum 权限、',
        '     过滤驱动残留、USB 存储与设备安装服务被停用',
        '  3. 清掉该范围内所有「已拔掉」的旧设备记录',
        '  4. 清掉「安装失败 / 待重装」的异常标记',
        '  5. 重建 COM 号池（回收占用不放的号）',
        '  6. 让系统重新扫一遍硬件',
        '  7. 把插着的串口设备固定到你选的号',
        '',
        '★ 第 2 步是重点：设备装不上、插上完全没反应，根子大多在这一层，',
        '  只清设备记录修不掉。老版本修不好的原因就在这里。',
        '',
        '为什么有「修复范围」',
        '  生产现场往往不止一种机型：',
        '    · 有的是 USB 转串口（会生成 COM 口）',
        '    · 有的直接就是 USB 设备，根本没有 COM 口',
        '  只清串口的话，第二种机型的问题就碰不到。所以给了四个范围：',
        '    串口设备（COM 口）    最保守，确定是串口机型时用',
        '    厂商自定义设备        烧录器、测试治具这类',
        '    全部 USB 设备         两种都覆盖，不确定机型时用这个（默认）',
        '    全部 USB 设备(含HID)  新机型走 HID 免驱时选这个',
        '',
        '  · 只删「已经拔掉」的记录，插着的一条不动',
        '  · 集线器、控制器、键鼠、声卡、网卡永久保护',
        '',
        '怎么用',
        '  1. 双击「请双击这个-USB串口一键修复.bat」，弹权限点「是」',
        '  2. 先点「只检查」，看桌面生成的报告',
        '  3. 选好端口号和修复范围，点「一 键 修 复」',
        '  4. 问要不要重启时点「是」',
        '  5. 重启后插一台新机器，看认不认',
        '',
        '可以不插设备直接跑吗',
        '  可以。不插设备时第 1~6 步照常执行，相当于「清场」。',
        '  重启后插一台新的，按下面三种情况判断：',
        '    · 认出来了、号也对   → 齐了',
        '    · 认出来了、号不对   → 开「固定守护」',
        '    · 还是完全不认       → 点「只检查」把报告发回来',
        '',
        '固定守护（生产时开着）',
        '  点「固定守护：关」，按钮变红即开启。',
        '  之后每插上一台设备，2 秒内自动把串口号固定到目标号。',
        '  这就是原来那个 bat 干的事，现在有界面、有日志、能随时关。',
        '',
        '纯 USB 设备与串口设备怎么分开',
        '  · 纯 USB 设备不等于 HID：还有厂商自定义（WinUSB）、存储、网卡、声卡',
        '  · 写端口号只对「系统已认定是串口」的设备生效，两道闸：',
        '      ① 候选只从串口这一类里取，HID / 厂商自定义 / 存储根本进不来',
        '      ② 还要已有 COM 号或设备类为 Ports，否则一个字都不写',
        '  · 纯 USB 设备不会被写端口号，也不会在号池里占位',
        '  · 两类设备插同一台机互不影响，转 COM 的老机型照旧固定号',
        '',
        '一个物理约束（软件绕不过去）',
        '  没有序列号的设备，Windows 按「插在哪个 USB 口」生成记录。',
        '  同一台设备换到另一个 USB 口 = 新记录 = 重新分号。',
        '  所以固定号的前提是固定插同一个口；要换口就让「固定守护」开着。',
        '',
        '安全边界',
        '  · 只删「已经拔掉」的旧记录，正在插着的设备一条都不动',
        '  · 集线器 / USB 控制器永久保护',
        '  · 键盘鼠标、声卡、摄像头、网卡、打印机、蓝牙一律不碰',
        '  · 复合设备若有受保护的子接口，连父设备也一起跳过',
        '  · 三道自检：拿不到在线列表不删；连主板根集线器都被判离线也不删',
        '  · 全程留底，可一键还原',
        '',
        '报告在哪',
        '  桌面\设备检查报告.txt      完整检查报告（每次都会刷新）',
        '  桌面\USB修复-出错报告.txt  只在出错时生成',
        '  留底：C:\ProgramData\ComFix\backup\fix-日期-时间\',
        '',
        '重要提醒',
        '  · 必须用管理员权限运行',
        '  · 修复和还原之后都要重启电脑',
        '  · 不改芯片、不刷固件、不动产品本身和生产软件',
        '  · 第一次先在一台机上试，别整厂一起推'
    )
}

function Get-DiscLines {
    if ($script:LANG -eq 'en') {
        return @(
            'DISCLAIMER',
            '',
            'This tool modifies Windows device records and the COM port allocation table.',
            'Although it is designed to be safe (only offline records, full snapshot,',
            'restorable at any time), system-level changes always carry some risk.',
            '',
            '1. Use at your own risk. The author is not liable for any direct or',
            '   indirect loss caused by using this tool, including but not limited to',
            '   production downtime, data loss, or device detection failures.',
            '',
            '2. Always take the built-in snapshot before repairing, and verify the',
            '   result on ONE machine before rolling out to a whole production line.',
            '',
            '3. This tool does not touch firmware, chips, the product itself, or any',
            '   production software. It only works on Windows device records.',
            '',
            '4. A reboot is required for changes to take full effect. Do not power off',
            '   while the tool is running.',
            '',
            '5. If it does not solve the problem, use "Restore" to roll back, then',
            '   send the Desktop report to the developer.',
            '',
            'By using this tool you accept the terms above.'
        )
    }
    return @(
        '免责声明',
        '',
        '本工具会修改 Windows 的设备记录与 COM 号分配表。',
        '虽然设计上已尽量安全（只动离线记录、全程留底、随时可还原），',
        '但涉及系统层面的改动，始终存在一定风险。',
        '',
        '一、使用本工具所产生的任何直接或间接损失，包括但不限于',
        '　　生产停滞、数据丢失、设备无法识别等，作者不承担任何责任。',
        '',
        '二、修复前请务必使用内置留底功能，并且先在单台电脑上验证结果，',
        '　　确认有效后再推广到整条产线。',
        '',
        '三、本工具不修改固件、不刷写芯片、不触碰产品本身，',
        '　　也不修改任何生产软件，只处理 Windows 的设备记录。',
        '',
        '四、修改需要重启电脑才能完全生效。工具运行过程中请勿断电。',
        '',
        '五、如果修复后问题依旧，请先用「还原上次」回退，',
        '　　再把桌面生成的报告发给开发。',
        '',
        '使用本工具即表示您已理解并接受以上条款。'
    )
}

function Get-AboutLines {
    if ($script:LANG -eq 'en') {
        return @(
            'USB / USB-Serial Port Fix',
            '',
            'Version   : 3.0',
            'Author    : Lanlan Eternal',
            'Platform  : Windows 7 / 8 / 10 / 11, 32-bit and 64-bit',
            'Engine    : PowerShell 5.1 + WinForms (no install, portable)',
            '',
            'Purpose',
            '  Fix USB / serial devices that are no longer detected after plugging in,',
            '  while keeping production-required fixed COM numbers.',
            '  One click runs every automatically fixable repair by itself.',
            '',
            'What it handles (all auto-repaired, no item-by-item clicking)',
            '  - device install policy that blocks new devices (old ones still work)',
            '  - corrupted registry Enum permissions (new devices cannot be recorded)',
            '  - leftover device-class filter drivers (driver gone, filter still set)',
            '  - disabled USB storage driver / device install services',
            '  - leftover offline device records (all USB categories, not just serial)',
            '  - COM port pool inconsistencies (COM Name Arbiter bit map)',
            '  - failed-install / reinstall-pending flags',
            '  - hardware rescan',
            '  - pinning serial devices to a fixed port',
            '',
            'Safety design',
            '  - only offline records are removed',
            '  - hubs / controllers permanently protected',
            '  - keyboard, mouse, audio, camera, network, printer, Bluetooth untouched',
            '  - three independent self-checks before any deletion',
            '  - full snapshot + one-click restore',
            '',
            'Reports',
            '  Desktop\Device-Check-Report.txt  full inspection report',
            '  Desktop\USB-Fix-Error-Report.txt  error report',
            '',
            '© Lanlan Eternal'
        )
    }
    return @(
        'USB / 串口 一键修复',
        '',
        '版本     : 3.0',
        '作者     : 永远的兰兰',
        '适用系统 : Windows 7 / 8 / 10 / 11，32 位 / 64 位',
        '运行方式 : PowerShell 5.1 + WinForms，免安装、绿色便携',
        '',
        '用途',
        '  修好插上后认不出来的 USB / 串口设备，同时保住生产需要的固定 COM 号。',
        '  点一次「一键修复」，所有能自动处理的项它自己全部做完。',
        '',
        '能处理的问题（全部自动修复，不用逐项点）',
        '  · 设备安装策略禁止安装新设备（老设备能用、新设备一律不行）',
        '  · 注册表 Enum 权限被改坏（新设备建不了记录，插上毫无反应）',
        '  · 设备类里过滤驱动残留（驱动服务已删、过滤项还在）',
        '  · USB 存储驱动 / 设备安装服务被停用',
        '  · 拔掉后残留的离线设备记录（覆盖全部 USB 类别，不只串口）',
        '  · COM 号池不一致（COM Name Arbiter 位图）',
        '  · 「安装失败 / 待重装」的异常标记',
        '  · 硬件重新扫描',
        '  · 把串口设备固定到指定端口号',
        '',
        '安全设计',
        '  · 只删离线记录，插着的设备不动',
        '  · 集线器 / 控制器永久保护',
        '  · 键鼠、声卡、摄像头、网卡、打印机、蓝牙一律不碰',
        '  · 删除前有三道独立自检',
        '  · 全程留底，一键还原',
        '',
        '报告',
        '  桌面\设备检查报告.txt      完整检查报告',
        '  桌面\USB修复-出错报告.txt  出错报告',
        '',
        '© 永远的兰兰'
    )
}

function Show-TextDialog([string]$title, [string[]]$lines) {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $title
    $d.ClientSize = New-Object System.Drawing.Size(620, 500)
    $d.StartPosition = 'CenterParent'
    $d.BackColor = $C_BG
    $d.FormBorderStyle = 'FixedSingle'
    $d.MaximizeBox = $false
    $d.MinimizeBox = $false
    $d.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true
    $tb.ReadOnly = $true
    $tb.ScrollBars = 'Vertical'
    $tb.WordWrap = $true
    $tb.BackColor = $C_PANEL
    $tb.ForeColor = $C_TEXT
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $tb.Location = New-Object System.Drawing.Point(14, 14)
    $tb.Size = New-Object System.Drawing.Size(592, 400)
    $tb.Text = ($lines -join "`r`n")
    $tb.SelectionStart = 0
    $tb.SelectionLength = 0
    $tb.TabStop = $false
    $d.Controls.Add($tb)

    $b = New-Object System.Windows.Forms.Button
    $b.Text = T 'btn.ok'
    $b.Location = New-Object System.Drawing.Point(262, 430)
    $b.Size = New-Object System.Drawing.Size(96, 34)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $C_BLUE
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $b.DialogResult = 'OK'
    $d.Controls.Add($b)
    $d.AcceptButton = $b
    $d.ActiveControl = $b

    # 焦点千万别落在文本框上，否则多行 TextBox 会把全文选中，看起来像被刷蓝
    $d.Add_Shown({
        try {
            $tb.SelectionStart = 0
            $tb.SelectionLength = 0
            $d.ActiveControl = $b
        } catch { }
    })

    if ("$script:ShotDlgPath" -ne '') {
        $d.Add_Shown({
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 600
            $w = $d.Width
            $h = $d.Height
            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $d.DrawToBitmap($bmp, $rect)
            $bmp.Save($script:ShotDlgPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            $d.Close()
        })
    }

    [void]$d.ShowDialog($form)
    $d.Dispose()
}
$script:ShotDlgPath = ''

$mProbe.Add_Click({
    $probe = Join-Path $PSScriptRoot 'usbprobe.ps1'
    if (-not (Test-Path $probe)) {
        [System.Windows.Forms.MessageBox]::Show((T 'log.probe.nofile'), (T 'hdr.about'), 'OK', 'Warning') | Out-Null
        return
    }
    Set-Busy $true
    Set-Status (T 'log.probe.run') 'run'
    Add-LogLine '' 'info'
    Add-LogLine ('====== ' + (T 'log.probe.run') + ' ======') 'info'
    try {
        $desk = ''
        try { $desk = [Environment]::GetFolderPath('Desktop') } catch { $desk = $env:TEMP }
        if ($desk -eq '') { $desk = $env:TEMP }

        # 取证脚本会把结论打到控制台；GUI 里没有控制台，所以直接读报告
        & $probe -NoOpen -OutDir $desk 2>&1 | Out-Null

        $probeName = $(if ($script:LANG -eq 'en') { 'USB-Not-Detected-Report.txt' } else { 'USB认不出-取证报告.txt' })
        $f = Join-Path $desk $probeName
        if (Test-Path $f) {
            Add-LogLine '' 'info'
            Add-LogLine ('------ ' + (T 'log.probe.result') + ' ------') 'info'
            $lines = @(Get-Content $f -Encoding UTF8)
            $start = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match '十、结论') { $start = $i; break }
            }
            if ($start -ge 0) {
                for ($i = $start + 2; $i -lt $lines.Count; $i++) {
                    $ln = $lines[$i]
                    if ($ln -match '^-----') { break }
                    if ($ln.Trim() -ne '') { Add-LogLine $ln 'info' }
                }
            }
            Add-LogLine '' 'info'
            Add-LogLine (T 'log.probe.done') 'ok'
            Set-Status (T 'log.probe.done') 'ok'
            try { Start-Process notepad.exe $f } catch { }
        } else {
            Add-LogLine (T 'log.probe.nofile') 'err'
            Set-Status (T 'log.probe.nofile') 'err'
        }
    } catch {
        Add-LogLine ('取证出错：' + $_.Exception.Message) 'err'
        Set-Status '取证出错' 'err'
    }
    Set-Busy $false
})

$mHelp.Add_Click({ Show-TextDialog (T 'hdr.help') (Get-HelpLines) })
$mDisc.Add_Click({ Show-TextDialog (T 'hdr.disc') (Get-DiscLines) })
$mAbout.Add_Click({
    Show-TextDialog (T 'hdr.about') (Get-AboutLines)
})

# ---------- 语言切换 ----------
function Switch-Lang([string]$l) {
    if ($script:Busy) {
        [System.Windows.Forms.MessageBox]::Show((T 'd.stopb'), (T 'd.stop'), 'OK', 'Information') | Out-Null
        return
    }
    if ($l -eq $script:LANG) { return }
    $script:LANG = $l
    Save-LangPref $l
    Apply-Lang
    $logBox.Clear()
    Show-Welcome
}

$mZh.Add_Click({ Switch-Lang 'zh' })
$mEn.Add_Click({ Switch-Lang 'en' })

# =====================================================================
#  启动体检
# =====================================================================
function Show-Welcome {
    Add-LogLine (T 'l.ready1') 'info'
    Add-LogLine (T 'l.ready2') 'info'
    Add-LogLine '' 'info'
    Show-QuickHealth
    Set-Status (T 'st.ready')
}

function Show-QuickHealth {
    try {
        CF-ResetPresentCache
        $h = CF-HealthCheck
        Add-LogLine (Fmt 'l.pool' @{a = $h.Used; b = $h.Free; c = $h.MaxUsed }) 'info'
        Add-LogLine (Fmt 'l.serial' @{a = $h.Online; b = $h.Offline; c = $h.BadFlags }) 'info'
        $dupN = 0
        foreach ($d in $h.Duplicates) { $dupN++ }
        if ($dupN -gt 0) { Add-LogLine (Fmt 'l.dup' @{a = $dupN }) 'warn' }
        if ($h.Orphans.Count -gt 0) { Add-LogLine (Fmt 'l.orphan' @{a = $h.Orphans.Count }) 'warn' }

        Add-LogLine '' 'info'
        Add-LogLine (Fmt 'l.usbtot' @{a = $h.UsbTotal; b = $h.UsbOffline }) 'info'
        $cats = @($h.CatCount.Keys | Sort-Object)
        foreach ($k in $cats) {
            Add-LogLine (Fmt 'l.catrow' @{name = (CF-CatName $k); a = $h.CatCount[$k]; b = $h.CatOnline[$k]; c = $h.CatOff[$k] }) 'info'
        }

        $hot = @(CF-GetUsbGroups | Where-Object { -not $_.Protected -and $_.Offline -ge 20 } |
                 Sort-Object -Property Offline -Descending | Select-Object -First 3)
        foreach ($g in $hot) {
            Add-LogLine (Fmt 'l.hot' @{a = $g.Group; b = $g.Offline; c = (CF-CatName $g.Category) }) 'warn'
        }

        $env2 = CF-CheckEnvironment
        foreach ($i in $env2.Issues) { Add-LogLine ('[!] ' + $i) 'warn' }

        # 「插上完全没反应」专项：有问题才刷出来，没问题不占版面
        $deep = CF-CheckDeep
        foreach ($i in $deep.Issues) { Add-LogLine ('[重点] ' + $i) 'err' }
    } catch {
        Add-LogLine (Fmt 'l.errcheck' @{a = $_.Exception.Message }) 'err'
    }
}

# =====================================================================
#  一键修复
# =====================================================================
$btnFix.Add_Click({
    $target = Get-TargetPort
    $scope = Get-Scope
    $sn = CF-ScopeName $scope (Get-IncludeHid)

    $body = (Fmt 'd.fix.s1' @{a = $sn }) + "`n`n" +
            (T 'd.fix.l0') + "`n" + (T 'd.fix.lb') + "`n"
    if ($scope -eq 'Serial') {
        $body += (T 'd.fix.l1s') + "`n"
    } else {
        $body += (T 'd.fix.l1') + "`n"
    }
    $body += (T 'd.fix.l2') + "`n" + (T 'd.fix.l3') + "`n" + (T 'd.fix.l4') + "`n" +
             (Fmt 'd.fix.l5' @{a = $target }) + "`n`n"
    if ($scope -eq 'Serial') {
        $body += (T 'd.fix.only')
    } else {
        $body += (T 'd.fix.safe') + "`n" + (T 'd.fix.safeA') + "`n" + (T 'd.fix.safeB')
    }
    $body += "`n`n" + (T 'd.fix.q')

    $ans = [System.Windows.Forms.MessageBox]::Show($body, (T 'd.fix.title'), 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }

    Set-Busy $true
    Set-Status (T 'st.fixing') 'run'
    Add-LogLine '' 'info'
    Add-LogLine (Fmt 'l.start' @{a = $sn; b = $target }) 'info'
    try {
        $r = CF-FullFix -KeepPort $target -Scope $scope -IncludeHid:(Get-IncludeHid)
        Add-LogLine '' 'info'
        Add-LogLine (T 'l.done') 'info'
        if ($r.Blocks) {
            if ($r.Blocks.Fixed -gt 0) {
                Add-LogLine (Fmt 'l.blocks' @{a = $r.Blocks.Fixed }) 'ok'
            } elseif ($r.Blocks.Fail -gt 0) {
                Add-LogLine (Fmt 'l.blocksfail' @{a = $r.Blocks.Fail }) 'err'
            }
        }
        if ($r.Dead.Skipped) { Add-LogLine (T 'l.skipped') 'warn' }
        Add-LogLine (Fmt 'l.dead' @{a = $r.Dead.Ok; b = $r.Dead.Total }) 'info'
        if ($r.Dead.ByCat -and $r.Dead.ByCat.Count -gt 0) {
            foreach ($k in $r.Dead.ByCat.Keys) {
                Add-LogLine (Fmt 'l.deadcat' @{name = (CF-CatName $k); a = $r.Dead.ByCat[$k] }) 'info'
            }
        }
        Add-LogLine (Fmt 'l.flags' @{a = $r.Flags.Ok; b = $r.Flags.Total }) 'info'
        Add-LogLine (Fmt 'l.arb' @{a = $r.Arb.Before; b = $r.Arb.After; c = $r.Arb.Freed }) 'info'
        if ($r.Pin.Total -gt 0) {
            Add-LogLine (Fmt 'l.pin' @{a = $target; b = $r.Pin.Ok; c = $r.Pin.Total }) 'info'
        } else {
            Add-LogLine '' 'info'
            Add-LogLine (T 'l.nopin') 'warn'
            Add-LogLine (T 'l.next') 'info'
            Add-LogLine (Fmt 'l.next1' @{a = $target }) 'info'
            Add-LogLine (T 'l.next2') 'info'
            Add-LogLine (T 'l.next3') 'info'
        }
        Set-Status (T 'st.fixdone') 'ok'

        $rep = ''
        try { $rep = Save-DeskReport 'ok' } catch { }
        if ($rep -ne '') {
            Add-LogLine '' 'info'
            Add-LogLine (Fmt 'l.saved' @{a = (Split-Path $rep -Leaf) }) 'info'
        }

        if ($r.Pin.Total -gt 0) {
            $tip = (Fmt 'd.done.pin' @{a = $r.Pin.Ok; b = $target }) + "`n`n" + (T 'd.done.tip') + "`n`n" + (T 'd.reboot')
        } else {
            $tip = (T 'd.done.nopin') + "`n`n" + (T 'd.done.after') + "`n" +
                   (T 'd.done.a1') + "`n" + (T 'd.done.a2') + "`n" + (T 'd.done.a3') + "`n`n" + (T 'd.reboot')
        }
        $ans2 = [System.Windows.Forms.MessageBox]::Show($tip, (T 'd.done.title'), 'YesNo', 'Question')
        if ($ans2 -eq 'Yes') { Restart-Computer -Force }
    } catch {
        $raw = Format-ErrText $_
        Add-LogLine (Fmt 'l.errfix' @{a = $_.Exception.Message }) 'err'
        $ef = ''
        try { $ef = Save-DeskReport 'err' $raw } catch { }
        if ($ef -ne '') { Add-LogLine (Fmt 'l.errfile' @{a = (Split-Path $ef -Leaf) }) 'err' }
        else { Add-LogLine (T 'l.errfilebad') 'err' }
        Set-Status (T 'st.fixerr') 'err'
    }
    Set-Busy $false
})

# ---------- 只检查 ----------
$btnCheck.Add_Click({
    Set-Busy $true
    Set-Status (T 'st.checking') 'run'
    Add-LogLine '' 'info'
    Add-LogLine (T 'l.checkhdr') 'info'
    try {
        Show-QuickHealth
        $rep = Save-DeskReport 'ok'
        Add-LogLine '' 'info'
        if ($rep -ne '' -and (Test-Path $rep)) {
            Add-LogLine (Fmt 'l.saved' @{a = (Split-Path $rep -Leaf) }) 'info'
            Start-Process notepad.exe $rep
        } else {
            Add-LogLine (T 'l.notsaved') 'warn'
        }
    } catch {
        $raw = Format-ErrText $_
        Add-LogLine (Fmt 'l.errcheck' @{a = $_.Exception.Message }) 'err'
        $ef = ''
        try { $ef = Save-DeskReport 'err' $raw } catch { }
        if ($ef -ne '') { Add-LogLine (Fmt 'l.errfile' @{a = (Split-Path $ef -Leaf) }) 'err' }
    }
    Set-Status (T 'st.checkdone') 'ok'
    Set-Busy $false
})

# ---------- 还原 ----------
$btnUndo.Add_Click({
    $dir = CF-GetLatestBackup
    if (-not $dir) {
        [System.Windows.Forms.MessageBox]::Show((T 'd.undo.none.b'), (T 'd.undo.none.t'), 'OK', 'Information') | Out-Null
        return
    }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        (T 'd.undo.body') + "`n`n" + $dir + "`n`n" + (T 'd.fix.q'), (T 'd.undo.title'), 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Set-Busy $true
    Set-Status (T 'st.restoring') 'run'
    Add-LogLine '' 'info'
    Add-LogLine (Fmt 'l.restorehdr' @{a = $dir }) 'info'
    try {
        CF-Restore $dir | Out-Null
        Set-Status (T 'st.restored') 'ok'
    } catch {
        $raw = Format-ErrText $_
        Add-LogLine (Fmt 'l.errrestore' @{a = $_.Exception.Message }) 'err'
        $ef = ''
        try { $ef = Save-DeskReport 'err' $raw } catch { }
        if ($ef -ne '') { Add-LogLine (Fmt 'l.errfile' @{a = (Split-Path $ef -Leaf) }) 'err' }
        Set-Status (T 'st.restoreerr') 'err'
    }
    Set-Busy $false
})

# ---------- 固定守护 ----------
$script:Watching = $false
$script:LastPinned = @{}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000

$timer.Add_Tick({
    if (-not $script:Watching) { return }
    $target = Get-TargetPort
    try {
        CF-ResetPresentCache
        $inst = @(CF-GetSerialInstances | Where-Object { $_.Online })
        foreach ($x in $inst) {
            $key = $x.InstanceId
            if ($x.PortNum -eq $target) {
                if ($script:LastPinned[$key] -ne 'done') {
                    Add-LogLine (Fmt 'l.already' @{a = $key; b = $target }) 'info'
                    $script:LastPinned[$key] = 'done'
                }
                continue
            }
            if ($script:LastPinned[$key] -eq 'trying') { continue }
            $script:LastPinned[$key] = 'trying'
            Add-LogLine (Fmt 'l.found' @{a = $x.PortNum; b = $target }) 'info'
            $ok = CF-PinDevice -Instance $x -Target $target
            if ($ok) {
                $script:LastPinned[$key] = 'done'
                Add-LogLine (Fmt 'l.pinned' @{a = $key }) 'info'
            } else {
                $script:LastPinned.Remove($key)
            }
        }
    } catch {
        $script:Watching = $false
        $timer.Stop()
        $btnWatch.Text = T 'btn.watch.off'
        $btnWatch.BackColor = $C_BLUE
        try { Add-LogLine (Fmt 'l.errwatch' @{a = $_.Exception.Message }) 'err' } catch { }
        Set-Status (T 'st.watcherr') 'err'
    }
})

$btnWatch.Add_Click({
    $script:Watching = -not $script:Watching
    if ($script:Watching) {
        $script:LastPinned = @{}
        $timer.Start()
        $btnWatch.Text = T 'btn.watch.on'
        $btnWatch.BackColor = $C_RED
        Set-Status (Fmt 'st.watching' @{n = (Get-TargetPort) }) 'ok'
        Add-LogLine '' 'info'
        Add-LogLine (Fmt 'l.watchon' @{a = (Get-TargetPort) }) 'info'
        Add-LogLine (T 'l.watchhint') 'info'
    } else {
        $timer.Stop()
        $btnWatch.Text = T 'btn.watch.off'
        $btnWatch.BackColor = $C_BLUE
        Set-Status (T 'st.watchoff')
        Add-LogLine (T 'l.watchoff') 'info'
    }
})

# ---------- 关闭 ----------
$form.Add_FormClosing({
    if ($script:Watching) {
        $ans = [System.Windows.Forms.MessageBox]::Show((T 'd.exit.b'), (T 'd.exit.t'), 'YesNo', 'Question')
        if ($ans -ne 'Yes') { $_.Cancel = $true; return }
    }
    $timer.Stop()
})

# =====================================================================
#  显示
# =====================================================================
Apply-Lang

$form.Add_Shown({
    if ($Shot -ne '') { return }
    Show-Welcome
})

# 对话框截图模式（自测用）
if ($ShotDlg -ne '' -and $Shot -ne '') {
    $form.Add_Shown({
        $script:ShotDlgPath = $Shot
        $form.Show()
        switch ($ShotDlg) {
            'help'  { Show-TextDialog (T 'hdr.help') (Get-HelpLines) }
            'disc'  { Show-TextDialog (T 'hdr.disc') (Get-DiscLines) }
            'about' { Show-TextDialog (T 'hdr.about') (Get-AboutLines) }
        }
        $script:ShotDlgPath = ''
        $form.Close()
    })
}
elseif ($Shot -ne '') {
    $form.Add_Shown({
        Show-Welcome
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 800
        $w = $form.Width
        $h = $form.Height
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $form.DrawToBitmap($bmp, $rect)
        $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $form.Close()
    })
}

# ---------- 自测 ----------
if ($SelfTest) {
    $f1 = Save-DeskReport 'ok'
    Write-Output ('[main] ' + $(if ($f1 -ne '') { $f1 + ' (' + (Get-Item $f1).Length + ' bytes)' } else { 'FAILED' }))
    $fake = "error: simulated failure`r`nline: 321`r`ncommand: CF-FullFix -KeepPort 3"
    $f2 = Save-DeskReport 'err' $fake
    Write-Output ('[err ] ' + $(if ($f2 -ne '' -and (Test-Path $f2)) { $f2 + ' (' + (Get-Item $f2).Length + ' bytes)' } else { 'FAILED' }))
    Write-Output ('[lang] ' + $script:LANG)
    exit
}

# ---------- 全局异常兜底 ----------
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
        [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch { }

try {
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            $t = ''
            try { $t = $e.Exception.Message } catch { }
            Save-DeskReport 'err' ("UI thread exception`r`n" + $t) | Out-Null
            [System.Windows.Forms.MessageBox]::Show(
                (Fmt 'd.err.b' @{a = $t }), (T 'd.err.t'), 'OK', 'Error') | Out-Null
        } catch { }
    })
} catch { }

try {
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $e)
        try {
            $t = ''
            try { $t = [string]$e.ExceptionObject } catch { }
            Save-DeskReport 'err' ("Unhandled exception`r`n" + $t) | Out-Null
        } catch { }
    })
} catch { }

[void]$form.ShowDialog()
