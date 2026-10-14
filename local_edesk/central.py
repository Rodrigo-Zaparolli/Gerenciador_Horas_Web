"""Explicit access control for a shared integration on a private LAN."""
import ipaddress
import json
import os
import threading
from pathlib import Path

_lock = threading.Lock()
_networks = tuple(ipaddress.ip_network(value) for value in
                  ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))


def private_address(value):
    try:
        address = ipaddress.ip_address(value)
        return any(address in network for network in _networks)
    except ValueError:
        return False


def enabled():
    return os.environ.get('EDESK_CENTRAL_MODE') == 'true'


def address():
    value = os.environ.get('EDESK_CENTRAL_HOST', '')
    if not private_address(value):
        raise ValueError('Informe um endereço IPv4 da rede privada para a central.')
    return value


def _path():
    return Path(os.environ.get('EDESK_CENTRAL_ACCESS_PATH') or
                Path(__file__).resolve().parents[1] / '.edesk-local/central-access.json')


def _read():
    path = _path()
    if not path.exists():
        return {'owner': None, 'users': []}
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or not isinstance(data.get('users'), list):
        raise ValueError('Configuração da central inválida.')
    return data


def _write(data):
    path = _path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data), encoding='utf-8')
    temporary.chmod(0o600)
    temporary.replace(path)


def permitted(uid):
    if not enabled():
        return True
    with _lock:
        return uid in _read()['users']


def pair(uid):
    with _lock:
        data = _read()
        if data['owner'] not in (None, uid):
            raise PermissionError('A central já pertence a outra conta.')
        if data['owner'] is None:
            data = {'owner': uid, 'users': [uid]}
            _write(data)
        return data


def access(uid, users=None):
    with _lock:
        data = _read()
        if data['owner'] != uid:
            raise PermissionError('Somente a conta responsável pode autorizar outras contas.')
        if users is not None:
            if (not isinstance(users, list) or len(users) > 100 or any(
                    not isinstance(value, str) or not value or len(value) > 128
                    for value in users)):
                raise ValueError('Lista de contas inválida.')
            data['users'] = sorted(set([uid, *users]))
            _write(data)
        return data
