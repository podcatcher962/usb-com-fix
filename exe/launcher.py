# -*- coding: utf-8 -*-
"""
USB / 串口 一键修复 —— 单文件启动器

为什么要有这一层：
  这套工具本身是 PowerShell + WinForms 脚本（GUI / 核心 / 取证 / 体检四个文件）。
  直接发脚本，现场要面对「解压后一堆文件、双击哪个、被杀软拦、执行策略拦」四道坎。
  打成一个 exe 以后：双击 → UAC 点「是」→ 界面出来，中间没有任何选择要做。

它做四件事：
  1. 不是管理员就自己提权重开（失败时弹一句人话，不留一个闪退）；
  2. 把内嵌的 .ps1 释放到 %LOCALAPPDATA%\\USBComFix\\bin\\<版本>\\（内容没变就不重写）；
  3. 上次启动没正常完成 → 这次自动进安全模式（跳过启动体检），不会再卡第二遍；
  4. 按系统位宽挑 powershell：64 位系统优先用 64 位那一份。

位宽约定：本 exe 用 32 位 Python 打包，32 / 64 位 Windows 都能直接跑。
  - 32 位系统：System32 里的 powershell 就是 32 位的，直接用；
  - 64 位系统：32 位进程看不到真 System32，走 Sysnative 拿 64 位的 powershell。
  pnputil 那边同样有 Sysnative 兜底（在 comfix-core.ps1 里）。
"""
import os
import sys
import ctypes
import subprocess
import hashlib

APP_NAME = 'USB / 串口 一键修复'
VER = '3.7.0'

PS1_FILES = [
    'comfix-gui.ps1',
    'comfix-core.ps1',
    'usbprobe.ps1',
    'healthprobe.ps1',
    'elevate.ps1',
    'report-launch-fail.ps1',
]

MB_ICONWARNING = 0x30
MB_ICONERROR = 0x10


# --------------------------------------------------------------------------
#  小工具
# --------------------------------------------------------------------------
def msgbox(text, flags=MB_ICONWARNING):
    try:
        ctypes.windll.user32.MessageBoxW(0, text, APP_NAME, flags)
    except Exception:
        pass


def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        return False


def app_root():
    base = os.environ.get('LOCALAPPDATA') or os.environ.get('TEMP') or '.'
    return os.path.join(base, 'USBComFix')


def log(msg):
    try:
        d = app_root()
        if not os.path.isdir(d):
            os.makedirs(d)
        p = os.path.join(d, 'launcher.log')
        # 超过 200 KB 就重开，避免长年累月涨成大文件
        if os.path.exists(p) and os.path.getsize(p) > 200 * 1024:
            os.remove(p)
        import datetime
        line = '[%s] %s\n' % (datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'), msg)
        with open(p, 'a', encoding='utf-8') as f:
            f.write(line)
    except Exception:
        pass


def exe_path():
    if getattr(sys, 'frozen', False):
        return sys.executable
    return os.path.abspath(sys.argv[0])


# --------------------------------------------------------------------------
#  提权
# --------------------------------------------------------------------------
def relaunch_as_admin():
    """返回 True 表示已经交给提权后的新进程。用户点「否」时返回 False。"""
    exe = exe_path()
    params = subprocess.list2cmdline(sys.argv[1:]) if len(sys.argv) > 1 else ''
    try:
        r = ctypes.windll.shell32.ShellExecuteW(None, 'runas', exe, params, None, 1)
    except Exception as e:
        log('ShellExecuteW 异常: %r' % (e,))
        return False
    # ShellExecuteW 返回 > 32 才算成功；5 = 用户点了「否」
    if r and r > 32:
        log('已请求提权，r=%s' % r)
        return True
    log('提权被拒绝或不支持，r=%s' % r)
    return False


# --------------------------------------------------------------------------
#  释放内嵌脚本
# --------------------------------------------------------------------------
def resource_dir():
    if getattr(sys, 'frozen', False):
        return sys._MEIPASS
    return os.path.dirname(os.path.abspath(__file__))


def extract_scripts(dest):
    src = resource_dir()
    if not os.path.isdir(dest):
        os.makedirs(dest)
    ok = 0
    for name in PS1_FILES:
        s = os.path.join(src, name)
        if not os.path.exists(s):
            log('内嵌资源缺失: %s' % name)
            continue
        data = open(s, 'rb').read()
        d = os.path.join(dest, name)
        same = False
        if os.path.exists(d):
            try:
                same = (os.path.getsize(d) == len(data)) and open(d, 'rb').read() == data
            except Exception:
                same = False
        if not same:
            with open(d, 'wb') as f:
                f.write(data)
        ok += 1
    log('释放脚本 %d/%d -> %s' % (ok, len(PS1_FILES), dest))
    return ok


def cleanup_old_versions(keep):
    """删掉 bin 下别的版本目录，免得一堆旧脚本占地方、也免得人搞混"""
    try:
        b = os.path.join(app_root(), 'bin')
        if not os.path.isdir(b):
            return
        for n in os.listdir(b):
            p = os.path.join(b, n)
            if os.path.isdir(p) and os.path.abspath(p) != os.path.abspath(keep):
                for f in os.listdir(p):
                    try:
                        os.remove(os.path.join(p, f))
                    except Exception:
                        pass
                try:
                    os.rmdir(p)
                except Exception:
                    pass
    except Exception:
        pass


# --------------------------------------------------------------------------
#  powershell 选择
# --------------------------------------------------------------------------
def ps_exe():
    win = os.environ.get('SystemRoot') or r'C:\Windows'
    rel = os.path.join('WindowsPowerShell', 'v1.0', 'powershell.exe')
    # PROCESSOR_ARCHITEW6432 存在 = 64 位系统 + 当前是 32 位进程
    if os.environ.get('PROCESSOR_ARCHITEW6432'):
        p64 = os.path.join(win, 'Sysnative', rel)
        if os.path.exists(p64):
            return p64, 'Sysnative(64bit)'
    p32 = os.path.join(win, 'System32', rel)
    if os.path.exists(p32):
        return p32, 'System32'
    return 'powershell.exe', 'PATH'


# --------------------------------------------------------------------------
#  主流程
# --------------------------------------------------------------------------
def close_splash():
    try:
        import pyi_splash          # PyInstaller 注入的模块
        pyi_splash.close()
    except Exception:
        pass


def main():
    args = sys.argv[1:]
    want_safe = '--safe' in args or '/safe' in args

    log('--- 启动 ver=%s admin=%s args=%s' % (VER, is_admin(), args))

    if not is_admin():
        if os.environ.get('USB_FIX_SKIP_ELEVATE') == '1':
            log('调试模式：跳过提权，界面可以打开但修复会失败')
        elif relaunch_as_admin():
            return 0
        else:
            msgbox('这个工具要修改设备记录和系统设置，必须以管理员身份运行。\n\n'
               '刚才有没有弹出「用户账户控制」窗口？\n'
               '  弹出了 → 请点「是」，程序会自己继续\n'
               '  没弹 / 点了「否」/ 被安全软件拦了 → 请再双击一次这个 exe，弹出时点「是」\n\n'
               'Administrator rights are required.\n'
               'Double-click the .exe again and click "Yes" on the UAC prompt.')
            return 1

    bindir = os.path.join(app_root(), 'bin', VER)
    n = extract_scripts(bindir)
    if n == 0:
        close_splash()
        msgbox('程序文件没能释放出来，无法启动。\n\n'
               '请确认这个 exe 没有被安全软件隔离，然后重新双击一次。\n'
               '如果一直失败，把下面这个文件发给作者：\n'
               + os.path.join(app_root(), 'launcher.log'), MB_ICONERROR)
        return 2
    cleanup_old_versions(bindir)

    # ---- 上次没起来？这次自动进安全模式 ----
    flag = os.path.join(app_root(), 'running.flag')
    auto_safe = False
    if os.path.exists(flag) and not want_safe:
        auto_safe = True
        log('检测到上次启动未正常完成 -> 自动安全模式')
    if want_safe:
        log('命令行指定 --safe')

    try:
        with open(flag, 'w') as f:
            f.write('1')
    except Exception:
        pass

    gui = os.path.join(bindir, 'comfix-gui.ps1')
    if not os.path.exists(gui):
        close_splash()
        msgbox('找不到主程序 comfix-gui.ps1。\n请重新下载这个 exe（可能被安全软件删掉了一部分）。', MB_ICONERROR)
        return 3

    ps, how = ps_exe()
    log('powershell = %s (%s)' % (ps, how))

    env = os.environ.copy()
    if want_safe or auto_safe:
        env['USB_FIX_SAFE'] = '1'
    if auto_safe:
        env['USB_FIX_AUTOSAFE'] = '1'

    extra = [a for a in args if a not in ('--safe', '/safe')]
    cmd = [ps, '-NoProfile', '-ExecutionPolicy', 'Bypass',
           '-WindowStyle', 'Hidden', '-File', gui] + extra

    close_splash()
    try:
        CREATE_NO_WINDOW = 0x08000000
        p = subprocess.Popen(cmd, cwd=bindir, env=env, creationflags=CREATE_NO_WINDOW)
    except Exception as e:
        log('启动 powershell 失败: %r' % (e,))
        msgbox('没能启动 PowerShell。\n\n'
               '常见原因：系统里的 PowerShell 被组策略或安全软件禁用了。\n'
               '可以试试：开始菜单 → 运行 → 输入 powershell 回车，看能不能打开。\n\n'
               '错误：%s' % e, MB_ICONERROR)
        return 4

    log('powershell pid=%s' % p.pid)
    p.wait()
    log('powershell 退出 code=%s' % p.returncode)

    try:
        os.remove(flag)
    except Exception:
        pass
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:
        try:
            close_splash()
        except Exception:
            pass
        log('未捕获异常: %r' % (e,))
        msgbox('程序启动时出错：\n%s\n\n日志：%s' % (e, os.path.join(app_root(), 'launcher.log')), MB_ICONERROR)
        sys.exit(9)
