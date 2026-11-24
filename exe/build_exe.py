# -*- coding: utf-8 -*-
"""
把 src 里的 .ps1 打成一个单文件 exe。

用 32 位 Python + PyInstaller：32 位 exe 在 32 / 64 位 Windows 上都能跑，
不用发两个包，也不用让使用者自己判断该下哪个。
"""
import hashlib
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_SCRIPTS = r'E:\_usbfix_bench\pkg\_program'
SRC = os.path.join(HERE, 'src')
DIST = os.path.join(HERE, 'dist')
BUILD = os.path.join(HERE, 'build')

PY = r'C:\Users\shenq\AppData\Local\Programs\Python\Python311-32\python.exe'

PS1 = ['comfix-gui.ps1', 'comfix-core.ps1', 'usbprobe.ps1',
       'healthprobe.ps1', 'elevate.ps1', 'report-launch-fail.ps1']

EXE_NAME = 'USB串口一键修复'


def prep():
    if os.path.isdir(SRC):
        shutil.rmtree(SRC)
    os.makedirs(SRC)
    for n in PS1:
        p = os.path.join(SRC_SCRIPTS, n)
        if not os.path.exists(p):
            print('缺文件:', p)
            sys.exit(1)
        # 原样拷贝，不动编码 —— 已经是 UTF-8 BOM + CRLF
        shutil.copy2(p, os.path.join(SRC, n))
        print('  %-24s %7d B' % (n, os.path.getsize(p)))


def build():
    args = [
        PY, '-m', 'PyInstaller',
        '--onefile',
        ('--console' if os.environ.get('EXE_CONSOLE') == '1' else '--noconsole'),
        '--clean',
        '--noconfirm',
        '--name', 'usbfix',
        '--icon', os.path.join(HERE, 'usbfix.ico'),
        '--splash', os.path.join(HERE, 'splash.png'),
        '--distpath', DIST,
        '--workpath', BUILD,
        '--specpath', HERE,
    ]
    for n in PS1:
        args += ['--add-data', os.path.join(SRC, n) + ';.']
    args.append(os.path.join(HERE, 'launcher.py'))

    print('\n[pyinstaller] 开始打包…')
    r = subprocess.run(args, capture_output=True)
    out = (r.stdout or b'').decode('utf-8', 'replace')
    err = (r.stderr or b'').decode('utf-8', 'replace')
    tail = '\n'.join([l for l in (out + err).splitlines() if l.strip()][-18:])
    print(tail)
    if r.returncode != 0:
        print('打包失败')
        sys.exit(2)

    raw = os.path.join(DIST, 'usbfix.exe')
    if not os.path.exists(raw):
        print('没产出 exe')
        sys.exit(3)
    final = os.path.join(DIST, EXE_NAME + '.exe')
    if os.path.exists(final):
        os.remove(final)
    os.rename(raw, final)

    b = open(final, 'rb').read()
    print('\n[产出] %s' % final)
    print('       大小    %d 字节 (%.1f MB)' % (len(b), len(b) / 1048576.0))
    print('       sha256  %s' % hashlib.sha256(b).hexdigest())
    return final


if __name__ == '__main__':
    prep()
    build()
