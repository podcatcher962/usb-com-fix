# -*- coding: utf-8 -*-
"""
把 src/ 打包成可分发的目录 + zip。

为什么需要这个脚本：
  - PowerShell 5.1 读 .ps1 要求 UTF-8 **带 BOM**，且换行 CRLF
  - cmd 读 .bat 要求 **GBK**，且换行 CRLF
  这两步用编辑器另存很容易漏，所以统一在这里做。

用法：
    python build.py
"""
import base64
import os
import shutil
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'src')
DOCS = os.path.join(HERE, 'docs')
ROOT = 'USB串口一键修复'
OUT_DIR = os.path.join(HERE, ROOT)
OUT_ZIP = os.path.join(HERE, ROOT + '.zip')

# elevate.ps1 已不在启动路径上（bat 改用 -EncodedCommand 内联提权），
# 保留它只是为了兼容旧包和留个对照，别删。
PS1 = ['comfix-gui.ps1', 'comfix-core.ps1', 'usbprobe.ps1', 'elevate.ps1', 'report-launch-fail.ps1']


def ps_enc(src):
    """PowerShell -EncodedCommand 要的是 UTF-16LE 再 base64。"""
    return base64.b64encode(src.encode('utf-16-le')).decode('ascii')


# ---------------------------------------------------------------------------
#  提权脚本（bat 在非管理员时执行）
#  为什么要 base64 编进 bat：-EncodedCommand 等价于 -Command，不受
#  PowerShell 执行策略限制；而且纯 ASCII，中文路径和代码页都不会出问题。
# ---------------------------------------------------------------------------
ELEVATE_PS = r'''
try {
    Start-Process -FilePath $env:USB_FIX_SELF -Verb RunAs -ErrorAction Stop | Out-Null
} catch {
    $n = [char]13 + [char]10
    $m = '这个工具要修改设备记录和系统设置，必须以管理员身份运行。' + $n + $n +
         '刚才屏幕上有没有弹出「用户账户控制」窗口？' + $n +
         '  弹出了 → 点「是」，程序就会正常打开' + $n +
         '  没弹 / 被拒了 / 被安全软件拦了 → 请右键这个 bat 文件，选「以管理员身份运行」' + $n + $n +
         'Administrator rights are required. Right-click the .bat file and choose "Run as administrator".'
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [void][System.Windows.Forms.MessageBox]::Show($m, 'USB / Serial Port Fix', 0, 48)
    } catch { }
    exit 1
}
'''

# ---------------------------------------------------------------------------
#  主程序没能启动时的兜底弹框（report-launch-fail.ps1 本身也可能被拦）
# ---------------------------------------------------------------------------
FAIL_PS = r'''
$n = [char]13 + [char]10
$m = '程序没能打开窗口。' + $n + $n +
     '请先把整个压缩包解压到硬盘，再双击里面的 bat（不要在压缩包里直接点）。' + $n +
     '如果已经解压了，就右键 bat 文件，选「以管理员身份运行」。' + $n + $n +
     'The program could not start. Extract the whole folder to disk first, ' + $n +
     'then right-click the .bat file and choose "Run as administrator".'
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [void][System.Windows.Forms.MessageBox]::Show($m, 'USB / Serial Port Fix', 0, 48)
} catch { }
'''

BAT = '''@echo off
chcp 936 >nul
title USB / 串口 一键修复
cd /d "%~dp0"

if not exist "%~dp0_program\\comfix-gui.ps1" goto nofile

rem ============================================================
rem  第一步：确认已经是管理员（不是就自己提权重开一遍）
rem  不让隐藏窗口里的脚本去请求提权 —— 那样 UAC 提示可能
rem  落在后台，表现成「双击没反应、右键管理员才打得开」。
rem ============================================================
fltmc >nul 2>&1
if errorlevel 1 if not "%USB_FIX_ELEV%"=="1" goto elevate
goto run

:elevate
rem 打上标记再提权：万一 fltmc 在这台机器上不可用，也不会反复弹 UAC 转圈
set "USB_FIX_ELEV=1"
set "USB_FIX_SELF=%~f0"
rem ------------------------------------------------------------
rem  ★★ 这行以前是个坑，别再改回 -File ★★
rem  老版本是：
rem    powershell -NoProfile -WindowStyle Hidden -File "...\\elevate.ps1" "%~f0"
rem  少写了 -ExecutionPolicy Bypass。Windows 客户端默认执行策略是 Restricted，
rem  -File 加载 .ps1 会被静默拦掉：脚本一行都不执行，窗口一闪就没了。
rem  现场看到的现象就是「双击没反应，只有右键以管理员身份运行才打得开」。
rem  现在改用 -EncodedCommand（等同 -Command，不受执行策略限制），脚本内容
rem  base64 编在这一行里，纯 ASCII，中文路径和代码页都不会拼坏。
rem  真要失败，脚本自己会弹一个提示框，不会再无声无息。
rem ------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand __ELEV__
rem 提权脚本返回 1 = 没成功（被取消 / 被拦 / 系统不给提权）
if errorlevel 1 goto elevfail
exit /b

:elevfail
rem 正常情况下上面已经弹过提示框。这里再在控制台留一句话，是最后一道保险 ——
rem 有些安全软件会把弹框也拦掉，至少让人看见该怎么办。
echo.
echo   需要管理员权限才能运行，这次没有提权成功。
echo   请关掉这个窗口，右键「请双击这个-USB串口一键修复.bat」，
echo   选「以管理员身份运行」。
echo.
echo   Administrator rights are required. Close this window, then
echo   right-click the .bat file and choose "Run as administrator".
echo.
pause
exit /b 1

:run
rem 从网盘/微信/压缩包来的脚本默认带「已阻止」标记，先解掉，否则可能加载失败
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Include *.ps1 | Unblock-File" >nul 2>&1

rem -WindowStyle Hidden：界面运行期间后台不再留一个空白黑框
rem （程序自己也会再藏一次，双保险）
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0_program\\comfix-gui.ps1" > "%TEMP%\\usbfix_out.txt" 2>&1
if errorlevel 1 goto failed
goto end

:nofile
echo.
echo   找不到程序文件。请把压缩包整个解压，再双击里面的 bat。
echo   只拷 bat 一个文件是不行的。
echo.
pause
exit /b 1

:failed
rem 这里不能用 pause：此时窗口是隐藏的，会卡成一个看不见的常驻进程
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0_program\\report-launch-fail.ps1" "%TEMP%\\usbfix_out.txt"
if errorlevel 1 goto failed2
goto end

:failed2
rem 连报错脚本都被拦了（组策略把执行策略锁死的情况），才走这一层
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand __FAIL__
goto end

:end
'''


def to_crlf(s):
    return s.replace('\r\n', '\n').replace('\n', '\r\n')


def build():
    if os.path.exists(OUT_DIR):
        shutil.rmtree(OUT_DIR)
    prog = os.path.join(OUT_DIR, '_program')
    os.makedirs(prog, exist_ok=True)

    # .ps1 -> UTF-8 BOM + CRLF
    for name in PS1:
        p = os.path.join(SRC, name)
        s = open(p, encoding='utf-8-sig').read()
        dst = os.path.join(prog, name)
        open(dst, 'w', encoding='utf-8-sig', newline='').write(to_crlf(s))
        print('  ps1 ', name, os.path.getsize(dst))

    # .bat -> GBK + CRLF
    bat = BAT.replace('__ELEV__', ps_enc(ELEVATE_PS)).replace('__FAIL__', ps_enc(FAIL_PS))
    b = os.path.join(OUT_DIR, '请双击这个-USB串口一键修复.bat')
    open(b, 'w', encoding='gbk', newline='').write(to_crlf(bat))
    print('  bat ', os.path.basename(b), os.path.getsize(b))

    # 文档与截图
    for src, dst in [
        ('使用说明（先看这个）.txt', '使用说明（先看这个）.txt'),
        ('screenshot-zh.png', '界面预览.png'),
        ('screenshot-en.png', '界面预览-英文.png'),
    ]:
        sp = os.path.join(DOCS if src.endswith('.png') else HERE, src)
        if not os.path.exists(sp):
            sp = os.path.join(DOCS, src)
        if os.path.exists(sp):
            shutil.copy2(sp, os.path.join(OUT_DIR, dst))
            print('  doc ', dst)
        else:
            print('  MISSING', src)

    # zip
    if os.path.exists(OUT_ZIP):
        os.remove(OUT_ZIP)
    with zipfile.ZipFile(OUT_ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
        for base, _, files in os.walk(OUT_DIR):
            for f in files:
                fp = os.path.join(base, f)
                arc = os.path.join(ROOT, os.path.relpath(fp, OUT_DIR))
                z.write(fp, arc)
    print('zip ->', OUT_ZIP, os.path.getsize(OUT_ZIP), 'bytes')


if __name__ == '__main__':
    build()
