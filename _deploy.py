# -*- coding: utf-8 -*-
"""通过 GitHub REST API 把 _repo/ 上传成仓库（本机 git push 走不通，只能走 API）"""
import base64
import json
import os
import subprocess
import sys
import time

REPO = 'usb-com-fix'
DESC = ('Windows 小工具：修复插上认不出的新 USB / 串口设备，'
        '并把串口固定在指定 COM 号。中英双语，免安装，全程留底可还原。')
TOKEN = os.environ.get('GITHUB_TOKEN', '').strip()
if not TOKEN:
    print('请先设置环境变量 GITHUB_TOKEN（需要有 repo 权限的 Personal Access Token）')
    sys.exit(1)
ROOT = os.path.dirname(os.path.abspath(__file__))
API = 'https://api.github.com'


def curl(url, method='GET', body=None, timeout=60):
    cmd = ['curl', '-s', '-m', str(timeout), '-X', method,
           '-H', 'Authorization: token ' + TOKEN,
           '-H', 'Accept: application/vnd.github+json',
           '-H', 'User-Agent: wb-deploy',
           url]
    data = None
    if body is not None:
        data = json.dumps(body).encode('utf-8')
        cmd += ['-H', 'Content-Type: application/json', '--data-binary', '@-']
    r = subprocess.run(cmd, input=data, capture_output=True)
    txt = r.stdout.decode('utf-8', 'replace')
    try:
        return json.loads(txt)
    except Exception:
        return {'_raw': txt}


def main():
    me = curl(API + '/user')
    login = me.get('login')
    if not login:
        print('token 无效', me)
        sys.exit(1)
    print('login =', login)

    # 1) 建仓库（已存在则跳过）
    r = curl(f'{API}/user/repos', 'POST', {
        'name': REPO,
        'description': DESC,
        'private': False,
        'has_issues': True,
        'has_wiki': False,
        'has_projects': False,
        'auto_init': False,
    })
    if r.get('full_name'):
        print('仓库已创建:', r['full_name'])
    elif 'already exists' in str(r.get('errors', '')) or r.get('message') == 'Repository creation failed.':
        print('仓库已存在，继续上传')
    else:
        print('创建返回:', json.dumps(r, ensure_ascii=False)[:300])

    full = f'{login}/{REPO}'
    branch = 'main'

    # 2) 逐文件上传
    files = []
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
        for n in names:
            if n.endswith('.pyc'):
                continue
            fp = os.path.join(base, n)
            rel = os.path.relpath(fp, ROOT).replace(os.sep, '/')
            files.append((rel, fp))
    files.sort()

    ok = 0
    for rel, fp in files:
        raw = open(fp, 'rb').read()
        body = {
            'message': ('init: ' + rel) if ok == 0 else rel,
            'content': base64.b64encode(raw).decode('ascii'),
            'branch': branch,
        }
        # 已存在则带上 sha（更新）
        cur = curl(f'{API}/repos/{full}/contents/{rel}?ref={branch}')
        if isinstance(cur, dict) and cur.get('sha'):
            body['sha'] = cur['sha']
        r = curl(f'{API}/repos/{full}/contents/{rel}', 'PUT', body)
        if r.get('content') or r.get('commit'):
            ok += 1
            print(f'  ok  {rel}  {len(raw)} B')
        else:
            print(f'  FAIL {rel}  {json.dumps(r, ensure_ascii=False)[:200]}')
        time.sleep(0.25)

    print(f'\n上传 {ok}/{len(files)} 个文件')
    print('仓库地址: https://github.com/' + full)

    # 3) 补 topics
    r = curl(f'{API}/repos/{full}/topics', 'PUT', {
        'names': ['windows', 'powershell', 'usb', 'serial-port', 'com-port',
                  'device-manager', 'troubleshooting', 'sysadmin', 'bilingual',
                  'single-file', 'lanlan'],
    })
    print('topics:', r.get('names') or r.get('message'))


if __name__ == '__main__':
    main()
