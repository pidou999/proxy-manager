#!/usr/bin/env python3
"""
Proxy Manager v3 - Self-contained proxy with embedded sing-box engine.
"""
import os
import re
import json
import time
import urllib.parse
import subprocess
import signal
import logging
from pathlib import Path
from flask import Flask, render_template, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

basedir = os.path.abspath(os.path.dirname(__file__))
app = Flask(__name__, 
    static_folder=os.path.join(basedir, 'static'),
    template_folder=os.path.join(basedir, 'templates'))
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{os.path.join(basedir, "data", "proxies.db")}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# ---------- Paths ----------
BIN_DIR = os.path.join(basedir, 'bin')
SING_BOX_PATH = os.path.join(BIN_DIR, 'sing-box')
CONFIG_PATH = os.path.join(BIN_DIR, 'config.json')
LOG_PATH = os.path.join(BIN_DIR, 'sing-box.log')
PID_PATH = os.path.join(BIN_DIR, 'sing-box.pid')

os.makedirs(BIN_DIR, exist_ok=True)

# ---------- Database Models ----------
class ProxyGroup(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(128), nullable=False, default='默认分组')
    sort_order = db.Column(db.Integer, default=0)
    default_proxy_id = db.Column(db.Integer, db.ForeignKey('proxy_link.id'), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    proxies = db.relationship('ProxyLink', backref='group', lazy='dynamic',
                              foreign_keys='ProxyLink.group_id',
                              order_by='ProxyLink.sort_order')

class ProxyLink(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    group_id = db.Column(db.Integer, db.ForeignKey('proxy_group.id'), nullable=True)
    url = db.Column(db.String(1024), nullable=False)
    protocol = db.Column(db.String(32), default='vless')
    ps = db.Column(db.String(128), default='')
    server = db.Column(db.String(256), default='')
    port = db.Column(db.Integer, default=443)
    uuid = db.Column(db.String(128), default='')
    security = db.Column(db.String(32), default='')
    network = db.Column(db.String(32), default='tcp')
    flow = db.Column(db.String(64), default='')
    sni = db.Column(db.String(256), default='')
    pbk = db.Column(db.String(128), default='')
    sid = db.Column(db.String(64), default='')
    fp = db.Column(db.String(64), default='')
    enabled = db.Column(db.Boolean, default=True)
    sort_order = db.Column(db.Integer, default=0)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

with app.app_context():
    db.create_all()
    if not ProxyGroup.query.first():
        db.session.add(ProxyGroup(name='默认分组', sort_order=0))
        db.session.commit()

# ---------- Main Page ----------
@app.route('/')
def index():
    return render_template('index.html')

# ---------- URL Parsers ----------
def parse_vless(url: str) -> dict:
    info = {}
    info['protocol'] = 'vless'
    rest = url.replace('vless://', '')
    remark = ''
    if '#' in rest:
        rest, remark = rest.rsplit('#', 1)
    info['ps'] = urllib.parse.unquote(remark)
    if '@' in rest:
        userinfo, hostport = rest.split('@', 1)
        info['uuid'] = userinfo
    else:
        hostport = rest
    if '?' in hostport:
        hostport = hostport.split('?')[0]
    if ':' in hostport:
        host, p = hostport.rsplit(':', 1)
        info['server'] = host
        info['port'] = int(p)
    if '?' in rest:
        _, query = rest.split('?', 1)
        if '#' in query:
            query = query.split('#')[0]
        params = {k: v[0] for k, v in urllib.parse.parse_qs(query).items()}
        info['uuid'] = info.get('uuid', params.get('id', ''))
        info['security'] = params.get('security', '')
        info['network'] = params.get('type', 'tcp')
        info['flow'] = params.get('flow', '')
        info['sni'] = params.get('sni', '')
        info['pbk'] = params.get('pbk', '')
        info['sid'] = params.get('sid', '')
        info['fp'] = params.get('fp', '')
    return info

def parse_vmess(url: str) -> dict:
    info = {'protocol': 'vmess'}
    b64 = url.replace('vmess://', '')
    try:
        import base64
        padded = b64 + '=' * (4 - len(b64) % 4)
        decoded = base64.b64decode(padded).decode('utf-8')
        data = json.loads(decoded)
        info['server'] = data.get('add', '')
        info['port'] = int(data.get('port', 0))
        info['uuid'] = data.get('id', '')
        info['security'] = data.get('security', 'auto')
        info['network'] = data.get('net', 'tcp')
        info['ps'] = data.get('ps', '')
        info['sni'] = data.get('sni', '')
    except: pass
    return info

def parse_ss(url: str) -> dict:
    info = {'protocol': 'ss'}
    rest = url.replace('ss://', '')
    remark = ''
    if '#' in rest:
        rest, remark = rest.split('#', 1)
    info['ps'] = urllib.parse.unquote(remark)
    if '@' in rest:
        userinfo, hostport = rest.split('@', 1)
        try:
            import base64
            padded = userinfo + '=' * (4 - len(userinfo) % 4)
            userinfo = base64.b64decode(padded).decode('utf-8')
        except: pass
        info['uuid'] = userinfo
        if ':' in userinfo:
            info['security'] = userinfo.split(':')[0]
        if ':' in hostport:
            hp = hostport.rsplit(':', 1)
            info['server'] = hp[0]
            info['port'] = int(hp[1])
    return info

def parse_trojan(url: str) -> dict:
    info = {'protocol': 'trojan'}
    rest = url.replace('trojan://', '')
    remark = ''
    if '#' in rest:
        rest, remark = rest.split('#', 1)
    info['ps'] = urllib.parse.unquote(remark)
    if '@' in rest:
        userinfo, hostport = rest.split('@', 1)
        info['uuid'] = userinfo
        hostport = hostport.split('?')[0]
        if ':' in hostport:
            host, p = hostport.rsplit(':', 1)
            info['server'] = host
            info['port'] = int(p)
    info['network'] = 'tcp'
    info['security'] = 'tls'
    return info

def parse_hysteria2(url: str) -> dict:
    info = {'protocol': 'hysteria2'}
    rest = url.replace('hysteria2://', '').replace('hy2://', '')
    remark = ''
    if '#' in rest:
        rest, remark = rest.split('#', 1)
    info['ps'] = urllib.parse.unquote(remark)
    if '@' in rest:
        userinfo, hostport = rest.split('@', 1)
        info['uuid'] = userinfo
    else:
        hostport = rest
    if '?' in hostport:
        hostport, query = hostport.split('?', 1)
    else:
        query = ''
    if ':' in hostport:
        hp = hostport.rsplit(':', 1)
        info['server'] = hp[0]
        info['port'] = int(hp[1])
    if query:
        params = {k: v[0] for k, v in urllib.parse.parse_qs(query).items()}
        info['sni'] = params.get('sni', '')
        info['security'] = 'tls'
        info['network'] = 'udp'
    return info

def parse_tuic(url: str) -> dict:
    info = {'protocol': 'tuic'}
    rest = url.replace('tuic://', '')
    remark = ''
    if '#' in rest:
        rest, remark = rest.split('#', 1)
    info['ps'] = urllib.parse.unquote(remark)
    if '@' in rest:
        userinfo, hostport = rest.split('@', 1)
        if ':' in userinfo:
            parts = userinfo.split(':', 1)
            info['uuid'] = parts[0]
        else:
            info['uuid'] = userinfo
    else:
        hostport = rest
    if '?' in hostport:
        hostport, query = hostport.split('?', 1)
    else:
        query = ''
    if ':' in hostport:
        hp = hostport.rsplit(':', 1)
        info['server'] = hp[0]
        info['port'] = int(hp[1])
    info['security'] = 'tls'
    info['network'] = 'udp'
    if query:
        params = {k: v[0] for k, v in urllib.parse.parse_qs(query).items()}
        info['sni'] = params.get('sni', '')
    return info

def parse_proxy_url(url: str) -> dict:
    url = url.strip()
    if url.startswith('vless://'): return parse_vless(url)
    elif url.startswith('vmess://'): return parse_vmess(url)
    elif url.startswith('ss://'): return parse_ss(url)
    elif url.startswith('trojan://'): return parse_trojan(url)
    elif url.startswith('hysteria2://') or url.startswith('hy2://'): return parse_hysteria2(url)
    elif url.startswith('tuic://'): return parse_tuic(url)
    else: return {'protocol': 'unknown'}

# ---------- API: Groups ----------
@app.route('/api/groups', methods=['GET'])
def get_groups():
    groups = ProxyGroup.query.order_by(ProxyGroup.sort_order).all()
    result = []
    for g in groups:
        proxies = ProxyLink.query.filter_by(group_id=g.id).order_by(ProxyLink.sort_order).all()
        proxy_list = [{
            'id': p.id, 'url': p.url, 'protocol': p.protocol, 'ps': p.ps,
            'server': p.server, 'port': p.port, 'uuid': p.uuid,
            'security': p.security, 'network': p.network, 'flow': p.flow,
            'sni': p.sni, 'pbk': p.pbk, 'sid': p.sid, 'fp': p.fp,
            'enabled': p.enabled, 'sort_order': p.sort_order,
            'is_default': (p.id == g.default_proxy_id),
        } for p in proxies]
        result.append({'id': g.id, 'name': g.name, 'sort_order': g.sort_order,
                       'default_proxy_id': g.default_proxy_id, 'proxies': proxy_list})
    return jsonify(result)

@app.route('/api/groups', methods=['POST'])
def create_group():
    data = request.get_json()
    name = data.get('name', '新分组').strip()
    if not name: return jsonify({'error': 'Group name required'}), 400
    max_order = db.session.query(db.func.max(ProxyGroup.sort_order)).scalar() or 0
    group = ProxyGroup(name=name, sort_order=max_order + 1)
    db.session.add(group); db.session.commit()
    return jsonify({'id': group.id, 'name': group.name}), 201

@app.route('/api/groups/<int:gid>', methods=['PUT'])
def update_group(gid):
    group = ProxyGroup.query.get_or_404(gid)
    data = request.get_json()
    if 'name' in data: group.name = data['name'].strip()
    if 'default_proxy_id' in data: group.default_proxy_id = data['default_proxy_id']
    db.session.commit()
    return jsonify({'message': 'Updated'})

@app.route('/api/groups/<int:gid>', methods=['DELETE'])
def delete_group(gid):
    group = ProxyGroup.query.get_or_404(gid)
    ProxyLink.query.filter_by(group_id=gid).update({'group_id': None})
    db.session.delete(group); db.session.commit()
    return jsonify({'message': 'Deleted'})

# ---------- API: Links ----------
@app.route('/api/links', methods=['POST'])
def add_link():
    data = request.get_json()
    url = data.get('url', '').strip()
    if not url: return jsonify({'error': 'Empty url'}), 400
    if ProxyLink.query.filter_by(url=url).first():
        return jsonify({'message': 'Already exists'}), 200
    group_id = data.get('group_id')
    if group_id is None:
        g = ProxyGroup.query.order_by(ProxyGroup.sort_order).first()
        group_id = g.id if g else None
    parsed = parse_proxy_url(url)
    max_order = db.session.query(db.func.max(ProxyLink.sort_order)).scalar() or 0
    link = ProxyLink(
        url=url, group_id=group_id,
        protocol=parsed.get('protocol', 'unknown'),
        ps=parsed.get('ps', ''), server=parsed.get('server', ''),
        port=parsed.get('port', 0), uuid=parsed.get('uuid', ''),
        security=parsed.get('security', ''), network=parsed.get('network', 'tcp'),
        flow=parsed.get('flow', ''), sni=parsed.get('sni', ''),
        pbk=parsed.get('pbk', ''), sid=parsed.get('sid', ''),
        fp=parsed.get('fp', ''), enabled=True, sort_order=max_order + 1,
    )
    db.session.add(link); db.session.commit()
    return jsonify({'message': 'Added', 'id': link.id}), 201

@app.route('/api/links/<int:lid>', methods=['PUT'])
def update_link(lid):
    link = ProxyLink.query.get_or_404(lid)
    data = request.get_json()
    if 'enabled' in data: link.enabled = data['enabled']
    if 'group_id' in data: link.group_id = data['group_id']
    if 'sort_order' in data: link.sort_order = data['sort_order']
    if 'ps' in data: link.ps = data['ps']
    db.session.commit()
    return jsonify({'message': 'Updated'})

@app.route('/api/links/<int:lid>', methods=['DELETE'])
def delete_link(lid):
    link = ProxyLink.query.get_or_404(lid)
    db.session.delete(link); db.session.commit()
    return jsonify({'message': 'Deleted'})

@app.route('/api/links/export')
def export_links():
    proxies = ProxyLink.query.order_by(ProxyLink.created_at).all()
    text = '\n'.join(p.url for p in proxies)
    resp = app.response_class(response=text, status=200, mimetype='text/plain')
    resp.headers['Content-Disposition'] = 'attachment; filename=proxy_links.txt'
    return resp

@app.route('/api/links/import', methods=['POST'])
def import_links():
    data = request.get_data(as_text=True)
    if not data: return jsonify({'error': 'No data'}), 400
    try:
        items = json.loads(data)
        if isinstance(items, str): items = [items]
    except: items = [l.strip() for l in data.split('\n') if l.strip()]
    if not isinstance(items, list): items = [items]
    g = ProxyGroup.query.order_by(ProxyGroup.sort_order).first()
    group_id = g.id if g else None
    imported = 0; skipped = 0
    for url in items:
        if not url or not isinstance(url, str): continue
        url = url.strip()
        if not url: continue
        if ProxyLink.query.filter_by(url=url).first(): skipped += 1; continue
        parsed = parse_proxy_url(url)
        db.session.add(ProxyLink(url=url, group_id=group_id, **{k: parsed.get(k, '') for k in 
            ['protocol','ps','server','port','uuid','security','network','flow','sni','pbk','sid','fp']
            if k != 'port'}, port=parsed.get('port', 0), enabled=True))
        imported += 1
    db.session.commit()
    return jsonify({'imported': imported, 'skipped': skipped})

# ---------- Test Proxy ----------
@app.route('/api/links/<int:lid>/test', methods=['POST'])
def test_proxy(lid):
    import socket as sock_mod
    link = ProxyLink.query.get_or_404(lid)
    host = link.server
    port = link.port
    protocol = link.protocol
    if not host or not port: return jsonify({'error': 'No server/port'}), 400
    results = {}
    udp_protocols = ('hysteria2', 'hy2', 'tuic')
    is_udp = protocol in udp_protocols
    # DNS
    dns_start = time.time()
    try:
        addr = sock_mod.getaddrinfo(host, port, sock_mod.AF_INET, sock_mod.SOCK_STREAM)
        results['dns'] = {'ok': True, 'ip': addr[0][4][0], 'latency_ms': round((time.time()-dns_start)*1000, 1)}
    except Exception as e:
        results['dns'] = {'ok': False, 'message': str(e)}
        return jsonify(results)
    # ICMP ping
    try:
        ping_start = time.time()
        proc = subprocess.run(['ping', '-c', '1', '-W', '3', host], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0:
            ping_ms = None
            for line in proc.stdout.split('\n'):
                if 'time=' in line:
                    try: ping_ms = float(line.split('time=')[1].split()[0].replace('ms',''))
                    except: pass
            results['icmp'] = {'reachable': True, 'latency_ms': ping_ms or round((time.time()-ping_start)*1000, 1)}
        else:
            results['icmp'] = {'reachable': False}
    except: results['icmp'] = {'reachable': False}
    # Protocol-specific
    if is_udp:
        udp_sock = sock_mod.socket(sock_mod.AF_INET, sock_mod.SOCK_DGRAM)
        udp_sock.settimeout(3)
        try:
            udp_sock.sendto(b'\x00', (host, port))
            try:
                udp_start = time.time()
                udp_sock.recvfrom(1024)
                udp_lat = round((time.time()-udp_start)*1000, 1)
                results['udp'] = {'reachable': True, 'latency_ms': udp_lat, 'message': f'UDP response in {udp_lat}ms'}
            except sock_mod.timeout:
                results['udp'] = {'reachable': True, 'latency_ms': None, 'message': 'UDP 已发送（协议无响应）'}
        except Exception as e: results['udp'] = {'reachable': False, 'latency_ms': None, 'message': str(e)}
        finally: udp_sock.close()
        # Fallback TCP 443
        try:
            tcp_sock = sock_mod.socket(sock_mod.AF_INET, sock_mod.SOCK_STREAM)
            tcp_sock.settimeout(4)
            tcp_start = time.time()
            tcp_sock.connect((host, 443))
            fb_ms = round((time.time()-tcp_start)*1000, 1)
            if results.get('udp', {}).get('latency_ms') is None:
                results['udp']['latency_ms'] = fb_ms
            results['tcp_fallback'] = {'reachable': True, 'latency_ms': fb_ms}
            tcp_sock.close()
        except: pass
    else:
        tcp_sock = sock_mod.socket(sock_mod.AF_INET, sock_mod.SOCK_STREAM)
        tcp_sock.settimeout(5)
        tcp_start = time.time()
        try:
            tcp_sock.connect((host, port))
            tcp_ms = round((time.time()-tcp_start)*1000, 1)
            results['tcp'] = {'reachable': True, 'latency_ms': tcp_ms, 'message': f'TCP {tcp_ms}ms'}
        except Exception as e:
            results['tcp'] = {'reachable': False, 'latency_ms': None, 'message': str(e)}
        finally: tcp_sock.close()
    return jsonify(results)

# ---------- sing-box Config Generator ----------
def build_sing_outbound(proxy: ProxyLink):
    """Convert a ProxyLink into a sing-box outbound."""
    tag = f'proxy-{proxy.id}'
    p = proxy.protocol
    svr = proxy.server
    pt = proxy.port
    uid = proxy.uuid

    if p == 'vless':
        out = {
            "type": "vless",
            "tag": tag,
            "server": svr,
            "server_port": pt,
            "uuid": uid,
            "flow": proxy.flow or "",
        }
        if proxy.security in ('tls', 'reality'):
            tls = {
                "enabled": True,
                "server_name": proxy.sni or svr,
            }
            if proxy.security == 'reality':
                tls['utls'] = {"enabled": True, "fingerprint": proxy.fp or "chrome"}
                tls['reality'] = {
                    "enabled": True,
                    "public_key": proxy.pbk or "",
                    "short_id": proxy.sid or "",
                }
            out['tls'] = tls
        return out

    elif p == 'vmess':
        return {
            "type": "vmess",
            "tag": tag,
            "server": svr,
            "server_port": pt,
            "uuid": uid,
            "security": proxy.security or "auto",
            "tls": {
                "enabled": proxy.security == 'tls',
                "server_name": proxy.sni or svr,
            }
        }

    elif p == 'ss':
        method, password = uid.split(':', 1) if ':' in uid else (uid, uid)
        return {
            "type": "shadowsocks",
            "tag": tag,
            "server": svr,
            "server_port": pt,
            "method": method,
            "password": password,
        }

    elif p == 'trojan':
        return {
            "type": "trojan",
            "tag": tag,
            "server": svr,
            "server_port": pt,
            "password": uid,
            "tls": {
                "enabled": True,
                "server_name": proxy.sni or svr,
            }
        }

    elif p in ('hysteria2', 'hy2'):
        return {
            "type": "hysteria2",
            "tag": tag,
            "server": svr,
            "server_port": pt,
            "password": uid,
            "tls": {
                "enabled": True,
                "server_name": proxy.sni or svr,
            }
        }

    elif p == 'tuic':
        return {
            "type": "tuic",
            "tag": tag,
            "server": svr,
            "server_port": pt,
            "uuid": uid,
            "password": "",
            "tls": {
                "enabled": True,
                "server_name": proxy.sni or svr,
            }
        }

    return None


def generate_sing_config():
    """Generate sing-box config from all enabled proxies."""
    proxies = ProxyLink.query.filter_by(enabled=True).order_by(ProxyLink.sort_order).all()
    if not proxies:
        return None

    outbounds = []
    primary_tag = None
    for p in proxies:
        ob = build_sing_outbound(p)
        if ob:
            outbounds.append(ob)
            if primary_tag is None:
                primary_tag = ob['tag']

    if not outbounds:
        return None

    # Check group default proxy
    groups = ProxyGroup.query.all()
    for g in groups:
        if g.default_proxy_id:
            for ob in outbounds:
                if ob['tag'] == f'proxy-{g.default_proxy_id}':
                    primary_tag = ob['tag']
                    break

    outbounds.append({"type": "direct", "tag": "direct"})

    config = {
        "log": {
            "level": "warn",
            "output": LOG_PATH
        },
        "inbounds": [
            {
                "type": "socks",
                "tag": "socks-in",
                "listen": "0.0.0.0",
                "listen_port": 1080,
                "users": []
            },
            {
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "0.0.0.0",
                "listen_port": 1081,
                "users": []
            }
        ],
        "outbounds": outbounds,
        "route": {
            "rules": [
                {
                    "inbound": ["socks-in", "mixed-in"],
                    "outbound": primary_tag or "direct"
                }
            ]
        }
    }
    return config

# ---------- sing-box Process Management ----------
def is_sing_box_running():
    if os.path.exists(PID_PATH):
        try:
            with open(PID_PATH) as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)  # check if alive
            return True
        except: pass
    return False

def get_sing_box_pid():
    if os.path.exists(PID_PATH):
        try:
            with open(PID_PATH) as f:
                return int(f.read().strip())
        except: pass
    return None

@app.route('/api/core/status')
def core_status():
    running = is_sing_box_running()
    pid = get_sing_box_pid()
    # Check if binary exists
    binary_exists = os.path.exists(SING_BOX_PATH)
    return jsonify({
        'running': running,
        'pid': pid,
        'binary_exists': binary_exists,
        'binary_path': SING_BOX_PATH,
    })

# ---------- Auto-start (crontab @reboot) ----------
DAEMON_SCRIPT = os.path.join(basedir, 'start-daemon.sh')
CRONTAB_MARKER = '# proxy-manager-autostart'

def _autostart_crontab_entry():
    """Return the crontab line for autostart."""
    return f'@reboot cd {basedir} && bash {DAEMON_SCRIPT} > /tmp/proxy-manager-boot.log 2>&1 {CRONTAB_MARKER}'

def _is_autostart_enabled():
    """Check if autostart is configured in crontab."""
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            return CRONTAB_MARKER in result.stdout
    except: pass
    return False

def _set_autostart(enable: bool):
    """Enable or disable autostart via crontab @reboot."""
    try:
        # Get current crontab
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            lines = result.stdout.splitlines()
        else:
            lines = []
        # Remove existing autostart lines
        lines = [l for l in lines if CRONTAB_MARKER not in l]
        if enable:
            lines.append(_autostart_crontab_entry())
        # Write back
        input_str = '\n'.join(lines) + '\n'
        proc = subprocess.run(['crontab', '-'], input=input_str, capture_output=True, text=True, timeout=5)
        return proc.returncode == 0
    except Exception as e:
        return False

@app.route('/api/settings/autostart', methods=['GET'])
def get_autostart():
    enabled = _is_autostart_enabled()
    return jsonify({'enabled': enabled})

@app.route('/api/settings/autostart', methods=['POST'])
def set_autostart():
    data = request.get_json()
    enable = data.get('enabled', True)
    ok = _set_autostart(enable)
    if ok:
        return jsonify({'enabled': enable, 'message': '开机自启已' + ('开启' if enable else '关闭')})
    else:
        return jsonify({'error': '设置失败，请检查 crontab 权限'}), 500

@app.route('/api/core/download', methods=['POST'])
def core_download():
    """Download sing-box binary."""
    import platform
    import urllib.request
    import zipfile
    import io

    arch = platform.machine()
    arch_map = {'x86_64': 'amd64', 'aarch64': 'arm64', 'armv7l': 'armv7'}
    a = arch_map.get(arch, 'amd64')

    # Get latest version
    try:
        req = urllib.request.Request(
            'https://api.github.com/repos/SagerNet/sing-box/releases/latest',
            headers={'Accept': 'application/json'}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            version = data['tag_name'].lstrip('v')
    except Exception as e:
        return jsonify({'error': f'Failed to get latest version: {str(e)}'}), 500

    download_url = f'https://github.com/SagerNet/sing-box/releases/download/v{version}/sing-box-{version}-linux-{a}.tar.gz'

    try:
        req = urllib.request.Request(download_url, headers={'Accept': '*/*'})
        with urllib.request.urlopen(req, timeout=30) as resp:
            import tarfile
            with tarfile.open(fileobj=io.BytesIO(resp.read()), mode='r:gz') as tar:
                # Extract sing-box binary
                for member in tar.getmembers():
                    if member.name.endswith('sing-box') and not member.name.startswith('.'):
                        f = tar.extractfile(member)
                        if f:
                            with open(SING_BOX_PATH, 'wb') as out:
                                out.write(f.read())
                        break
        os.chmod(SING_BOX_PATH, 0o755)
        return jsonify({'message': f'Downloaded sing-box v{version}', 'path': SING_BOX_PATH})
    except Exception as e:
        return jsonify({'error': f'Download failed: {str(e)}'}), 500

@app.route('/api/core/start', methods=['POST'])
def core_start():
    if not os.path.exists(SING_BOX_PATH):
        return jsonify({'error': 'sing-box binary not found. Click "下载引擎" first.'}), 400

    # Generate config
    config = generate_sing_config()
    if not config:
        return jsonify({'error': 'No enabled proxies to configure'}), 400

    with open(CONFIG_PATH, 'w') as f:
        json.dump(config, f, indent=2)

    if is_sing_box_running():
        return jsonify({'message': 'Already running'})

    # Start process
    try:
        with open(LOG_PATH, 'w') as log:
            proc = subprocess.Popen(
                [SING_BOX_PATH, 'run', '-c', CONFIG_PATH],
                stdout=log, stderr=subprocess.STDOUT,
                cwd=BIN_DIR,
            )
        with open(PID_PATH, 'w') as f:
            f.write(str(proc.pid))
        # Wait a moment to check if it stays alive
        time.sleep(1)
        if proc.poll() is not None:
            with open(LOG_PATH) as f:
                err = f.read()[-500:]
            return jsonify({'error': f'Process exited. Log: {err}'}), 500
        return jsonify({'message': 'Started', 'pid': proc.pid})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/core/stop', methods=['POST'])
def core_stop():
    pid = get_sing_box_pid()
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
            time.sleep(1)
            try:
                os.kill(pid, 0)
                os.kill(pid, signal.SIGKILL)
            except: pass
            if os.path.exists(PID_PATH):
                os.remove(PID_PATH)
            return jsonify({'message': 'Stopped'})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    return jsonify({'message': 'Not running'})

@app.route('/api/core/config')
def core_config():
    """Download current sing-box config."""
    config = generate_sing_config()
    if not config:
        return jsonify({'error': 'No enabled proxies'}), 400
    resp = app.response_class(response=json.dumps(config, indent=2), status=200, mimetype='application/json')
    resp.headers['Content-Disposition'] = 'attachment; filename=sing-box_config.json'
    return resp

# ---------- Start ----------
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5003, debug=True)
