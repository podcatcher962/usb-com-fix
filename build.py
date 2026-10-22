# -*- coding: utf-8 -*-
"""
把 src/ 打包成可直接发给别人的目录 + zip。

为什么需要这个脚本：
  - PowerShell 5.1 读 .ps1 要求 UTF-8 **带 BOM**，且换行 CRLF
  - cmd 读 .bat 要求 **GBK**，且换行 CRLF
  这两步用编辑器另存很容易漏，所以统一在这里做。

用法：
    python build.py
"""
import os
import shutil
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'src')
DOCS = os.path.join(HERE, 'docs')
ROOT = 'USB串口一键修复'
OUT_DIR = os.path.join(HERE, ROOT)
OUT_ZIP = os.path.join(HERE, ROOT + '.zip')

PS1 = ['comfix-gui.ps1', 'comfix-core.ps1', 'usbprobe.ps1', 'report-launch-fail.ps1']

BAT = '''@echo off
chcp 936 >nul
title USB / 串口 一键修复
cd /d "%~dp0"

if not exist "%~dp0_program\\comfix-gui.ps1" goto nofile

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Include *.ps1 | Unblock-File" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_program\\comfix-gui.ps1" > "%TEMP%\\usbfix_out.txt" 2>&1
if errorlevel 1 goto failed
goto end

:nofile
echo.
echo   找不到程序文件。请把整个文件夹一起拷过去，不要只拷 bat。
echo.
pause
exit /b 1

:failed
echo.
echo   程序异常退出，正在把错误信息写到桌面...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0_program\\report-launch-fail.ps1" "%TEMP%\\usbfix_out.txt"
echo   已写报告：USB修复-启动失败.txt
echo.
pause

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
    b = os.path.join(OUT_DIR, '请双击这个-USB串口一键修复.bat')
    open(b, 'w', encoding='gbk', newline='').write(to_crlf(BAT))
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
