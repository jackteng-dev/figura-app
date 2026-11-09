"""Native Android acceptance against an owned disposable loopback backend.

Requires an already booted test emulator/device; never installs on every device.
Private fixture/logs/APKs stay in ignored work/. Evidence contains no credentials.
Build native_main.dart with API_BASE_URL=http://10.0.2.2:29102/ELPSY/api/;
build production main.dart with the same URL and a higher build number.
For USB devices use adb reverse and http://127.0.0.1:29102/ELPSY/api/ instead.
"""
import argparse
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import xml.etree.ElementTree as ET


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--adb', default='adb')
    p.add_argument('--serial', required=True)
    p.add_argument('--fixture', required=True)
    p.add_argument('--probe-apk', required=True)
    p.add_argument('--app-apk', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--backend-port', type=int, default=29092)
    p.add_argument('--controller-port', type=int, default=29102)
    p.add_argument('--reverse-app-port', type=int,
                   help='Map an App loopback port to the owned test controller (e.g. 9090)')
    p.add_argument('--no-impeller', action='store_true',
                   help='Use the debug renderer override for a software emulator')
    p.add_argument('--resume-core',
                   help='Resume UI checks using matching safe evidence from completed core phases')
    a = p.parse_args()
    fixture = json.loads(Path(a.fixture).read_text())
    fixture.update(OTHER_USERNAME='dev_' + secrets.token_hex(10),
                   OTHER_PASSWORD=secrets.token_urlsafe(24))
    state = {'phase': '', 'result': None, 'checks': [], 'requests': [],
             'secrets': [], 'dropped_order': False, 'dropped_cart': False,
             'read_failed': False, 'order': None, 'order_ids': [], 'system_ui_waits': 0}
    event = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def send_json(self, body):
            raw = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            self.handle_request()

        def do_POST(self):
            self.handle_request()

        def do_PUT(self):
            self.handle_request()

        def do_PATCH(self):
            self.handle_request()

        def do_DELETE(self):
            self.handle_request()

        def handle_request(self):
            raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            if self.path == '/__fixture' and self.command == 'GET':
                self.send_json(fixture | {'phase': state['phase']})
                return
            if self.path == '/__result' and self.command == 'POST':
                state['result'] = json.loads(raw)
                self.send_json({'ok': True})
                event.set()
                return
            if not self.path.startswith('/ELPSY/api/'):
                self.send_error(404)
                return
            if (state['phase'] == 'resume' and not state['read_failed'] and
                    self.command == 'GET' and self.path.endswith('/orders/' + state['order'])):
                state['read_failed'] = True
                self.send_response(503)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"code":503,"data":null}')
                return
            headers = {k: v for k, v in self.headers.items()
                       if k.lower() not in ('host', 'connection', 'content-length')}
            conn = http.client.HTTPConnection('127.0.0.1', a.backend_port, timeout=30)
            try:
                conn.request(self.command, self.path, raw if raw else None, headers)
                res = conn.getresponse()
                reply = res.read()
                body = json.loads(raw) if raw else None
                state['requests'].append((state['phase'], self.command, self.path, body, res.status))
                if self.path.endswith(('/auth/login', '/auth/refresh')) and res.status == 200:
                    tokens = json.loads(reply)['data']
                    state['secrets'].extend([tokens['accessToken'], tokens['refreshToken']])
                    if body and 'deviceId' in body:
                        state['secrets'].append(body['deviceId'])
                drop = False
                if self.command == 'POST' and self.path.endswith('/customer/orders') and res.status == 200:
                    state['order'] = json.loads(reply)['data']['order']['id']
                    state['order_ids'].append(state['order'])
                    if state['phase'] == 'seed' and not state['dropped_order']:
                        state['dropped_order'] = drop = True
                if (state['phase'] == 'version' and self.command == 'PUT' and
                        '/cart/items/' in self.path and res.status == 200 and not state['dropped_cart']):
                    state['dropped_cart'] = drop = True
                if drop:
                    # The backend response was consumed in full; its transaction committed.
                    # Close only this client socket to reproduce a lost acknowledgement.
                    self.close_connection = True
                    self.connection.shutdown(2)
                    self.connection.close()
                    return
                self.send_response(res.status)
                self.send_header('Content-Type', res.getheader('Content-Type', 'application/json'))
                self.send_header('Content-Length', str(len(reply)))
                self.end_headers()
                self.wfile.write(reply)
            finally:
                conn.close()

    package = 'com.elpsy.elpsy_shop'
    component = package + '/.MainActivity'

    def adb(*args, timeout=90):
        return subprocess.check_output([a.adb, '-s', a.serial, *args],
                                       timeout=timeout, stderr=subprocess.STDOUT)

    def check(name, ok):
        if not ok:
            raise RuntimeError(name)
        state['checks'].append(name)
        print('PASS:', name, flush=True)

    def launch():
        args = ['shell', 'am', 'start', '-n', component]
        if a.no_impeller:
            args.extend(['--ez', 'enable-impeller', 'false'])
        output = adb(*args)
        if b'Error:' in output or b'Exception' in output:
            raise RuntimeError('Android could not launch the activity')

    def phase(name):
        state['phase'], state['result'] = name, None
        event.clear()
        print('RUN native phase:', name, flush=True)
        adb('shell', 'am', 'force-stop', package)
        launch()
        if not event.wait(300):
            raise RuntimeError('native probe timed out: ' + name)
        result = state['result']
        if not result['passed']:
            print('Completed native checks:', json.dumps(result['checks']), flush=True)
        check('native phase ' + name, result['passed'] and result['phase'] == name)
        state['checks'].extend(result['checks'])

    def nodes():
        adb('shell', 'uiautomator', 'dump', '/data/local/tmp/elpsy-window.xml', timeout=45)
        return list(ET.fromstring(adb('shell', 'cat', '/data/local/tmp/elpsy-window.xml')).iter('node'))

    def find(label, timeout=90):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            window = nodes()
            # Software emulators can time out Android's own System UI. Record
            # each recovery. Never dismiss an ELPSY App ANR or other dialog.
            if any(n.get('text') == "System UI isn't responding" for n in window):
                if state['system_ui_waits'] >= 10:
                    raise RuntimeError('System UI remains unresponsive on this test emulator')
                wait = next(n for n in window if n.get('text') == 'Wait')
                x1, y1, x2, y2 = map(int, re.findall(r'\d+', wait.get('bounds')))
                adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))
                state['system_ui_waits'] += 1
                print('RECOVERY: owned emulator System UI wait', state['system_ui_waits'], flush=True)
                continue
            for n in window:
                labels = (n.get('text', '') + '\n' + n.get('content-desc', '')).splitlines()
                if label in labels:
                    return n
            time.sleep(1)
        raise RuntimeError('native UI element unavailable: ' + ('account' if label.startswith('@') else label))

    def tap(label):
        n = find(label)
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds')))
        adb('shell', 'input', 'tap', str((x1 + x2) // 2), str((y1 + y2) // 2))

    server = ThreadingHTTPServer(('127.0.0.1', a.controller_port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        check('device booted', adb('shell', 'getprop', 'sys.boot_completed').strip() == b'1')
        if a.reverse_app_port:
            adb('reverse', f'tcp:{a.reverse_app_port}', f'tcp:{a.controller_port}')
        probe, app = Path(a.probe_apk), Path(a.app_apk)
        check('production artifact differs from test probe', hashlib.sha256(probe.read_bytes()).digest() != hashlib.sha256(app.read_bytes()).digest())
        if a.resume_core:
            core = json.loads(Path(a.resume_core).read_text())
            check('resumed core evidence matches these exact test artifacts',
                  core['appApkSha256'] == hashlib.sha256(app.read_bytes()).hexdigest() and
                  core['probeApkSha256'] == hashlib.sha256(probe.read_bytes()).hexdigest() and
                  core['device'] == a.serial and core['coreComplete'] is True)
            state['checks'].extend(core['checks'])
            state['dropped_order'], state['dropped_cart'], state['read_failed'] = True, True, True
        else:
            # This package belongs to this disposable test device. No global adb selector.
            adb('install', '-r', str(probe), timeout=180)
            adb('shell', 'pm', 'clear', package)
            for name in ('seed', 'resume', 'version', 'resolve'):
                phase(name)
            orders = [r for r in state['requests'] if r[1] == 'POST' and r[2].endswith('/customer/orders')]
            check('exact UUID/body replay reached backend twice, without another order command',
                  len(orders) == 2 and orders[0][3] == orders[1][3] and all(r[4] == 200 for r in orders))
            check('committed response and replay identify the same single order',
                  len(state['order_ids']) == 2 and len(set(state['order_ids'])) == 1)
            updates = [r for r in state['requests'] if r[0] in ('version', 'resolve') and r[1] == 'PUT' and '/cart/items/' in r[2]]
            check('unknown versioned cart write was sent only once', len(updates) == 1)
            prefs = adb('shell', f"run-as {package} sh -c 'cat shared_prefs/*.xml'")
            check('native preference files contain no plaintext session/device credentials',
                  len(prefs) > 0 and all(s.encode() not in prefs for s in state['secrets']))
            core = {'coreComplete': True, 'device': a.serial, 'checks': list(state['checks']),
                    'appApkSha256': hashlib.sha256(app.read_bytes()).hexdigest(),
                    'probeApkSha256': hashlib.sha256(probe.read_bytes()).hexdigest()}
            Path(a.output + '.core.json').write_text(json.dumps(core, ensure_ascii=False, indent=2) + '\n')
        adb('shell', 'am', 'force-stop', package)
        adb('install', '-r', str(app), timeout=180)
        state['phase'] = 'production'
        launch()
        tap('會員')
        find('@' + fixture['APP_TEST_USERNAME'])
        check('production APK upgrade restores native session in real account UI', True)
        pid = adb('shell', 'pidof', package).strip()
        adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
        launch()
        find('@' + fixture['APP_TEST_USERNAME'])
        check('background return keeps the running account session', pid == adb('shell', 'pidof', package).strip())
        adb('shell', 'am', 'force-stop', package)
        launch()
        tap('會員')
        find('@' + fixture['APP_TEST_USERNAME'])
        check('production process restart restores account from native secure storage', True)
        tap('登出此裝置')
        find('收藏，從這裡開始。')
        check('production UI logout returns to sign-in', True)
        deadline = time.monotonic() + 60
        while not any(r[0] == 'production' and r[2].endswith('/auth/logout') and r[4] == 200 for r in state['requests']):
            if time.monotonic() > deadline:
                raise RuntimeError('logout acknowledgement did not reach the native app')
            time.sleep(0.2)
        check('production logout reached server after local credential deletion', True)
        adb('shell', 'am', 'force-stop', package)
        # Disposable debug probe only: intentional downgrade, same development key.
        adb('install', '-r', '-d', str(probe), timeout=180)
        phase('loggedout')
        adb('shell', 'am', 'force-stop', package)
        adb('install', '-r', str(app), timeout=180)
        state['phase'] = 'production'
        launch()
        tap('會員')
        find('收藏，從這裡開始。')
        check('production relaunch remains signed out after logout', True)
        output = {
            'date': '2026-10-08', 'synthetic': True, 'platform': 'Android',
            'device': a.serial, 'apiLevel': adb('shell', 'getprop', 'ro.build.version.sdk').decode().strip(),
            'physicalDevice': False if a.serial.startswith('emulator-') else True,
            'debugRendererOverride': 'Skia' if a.no_impeller else None,
            'systemUiAnrRecoveries': state['system_ui_waits'],
            'resumedCoreEvidence': bool(a.resume_core),
            'passed': len(state['checks']), 'checks': state['checks'],
            'appApkSha256': hashlib.sha256(app.read_bytes()).hexdigest(),
            'probeApkSha256': hashlib.sha256(probe.read_bytes()).hexdigest(),
            'faults': {'lostCommittedOrderResponse': state['dropped_order'],
                       'lostCommittedVersionedCartResponse': state['dropped_cart'],
                       'readFailureAfterAcknowledgement': state['read_failed']},
        }
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Path(a.output).write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
        print('Native Android acceptance:', len(state['checks']), 'passed')
    finally:
        server.shutdown()
        server.server_close()
        if a.reverse_app_port:
            adb('reverse', '--remove', f'tcp:{a.reverse_app_port}')


if __name__ == '__main__':
    main()
