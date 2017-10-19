#!/usr/bin/env python3

import json
import re
import sys
import textwrap
import yaml


def cleanup_contents(s):
    return ''.join(textwrap.dedent(s).strip())


def unit(name, *, contents=None, enabled=True, dropins=None):
    """
    :param name: the name of the unit. This must be suffixed with a valid unit
    type (e.g. "thing.service").
    :param contents: the contents of the unit
    :param enabled: whether or not the service shall be enabled. When true, the
    service is enabled. In order for this to have any effect, the unit must have
    an install section.
    :param dropins: collection of drop-ins for the unit
    :return Container Linux systemd unit object
    """
    unit = {
        'name': name,
        'enable': enabled,
    }
    if contents:
        unit['contents'] = cleanup_contents(contents)
    if dropins:
        unit['dropins'] = dropins
    return unit


def dropin(name, *, contents):
    """
    :param the name of the drop-in. This must be suffixed with ".conf".
    :param contents: the contents of the drop-in.
    : return Container Linux systemd drop-in object
    """
    return {
        'name': name,
        'contents': cleanup_contents(contents)
    }


def _file(path, *, contents='', mode=644):
    return {
        'filesystem': 'root',
        'path': path,
        'contents': {
            'inline': contents
        },
        'mode': mode
    }


def load_service(config):
    if not re.match("[a-z0-9-]+", config["name"]):
        raise ValueError("'{}' is not a valid service name".format(config["name"]))

    ports = []
    for port in config.get('ports', []):
        ports.append({
            "host": int(port['host']),
            "container": int(port['container']),
            "protocol": port.get('protocol', 'tcp')
        })

    bind_mounts = []
    for mount in config.get('bind_mounts', []):
        bind_mounts.append({
            "host": mount['host'],
            "container": mount['container'],
            "read_only": mount.get('read_only', False)
        })

    service = {
        'name': config['name'],
        'image': config['image'],
        'environment': config.get('environment', {}),
        'ports': ports,
        'bind_mounts': bind_mounts,
        'is_enabled': bool(config.get('is_enabled', True))
    }

    command = config.get('command', None)
    if command:
        service['command'] = command

    return service


with open('hive.sh') as f:
    hive_script = f.read()

with open('config.yml') as f:
    config = yaml.load(f)
services = [load_service(s) for s in config.get('services', [])]
hive_unit = unit(
    name='hive.service',
    enabled=True,
    contents="""
    [Unit]
    Description=Create and manage Docker Swarm services
    Requires=docker.service
    After=docker.service

    [Service]
    Type=oneshot
    ExecStart=/opt/hive/bin/hive {}
    StandardOutput=journal+console

    [Install]
    WantedBy=multi-user.target
    """.format(config.get('orchestrator', 'swarm'))
)

docker_swarm_dropin = dropin(
    'docker-swarm.conf',
    contents="""
    [Service]
    ExecStartPost=-/usr/bin/docker swarm init
    """
)


ignition = {
    'systemd': {
        'units': [
            unit('docker.service', enabled=True, dropins=[docker_swarm_dropin]),
            hive_unit
        ]
    },
    'storage': {
        'files': [
            _file('/opt/hive/etc/services.json', mode=600, contents=json.dumps(services)),
            _file('/opt/hive/bin/hive', mode=700, contents=hive_script)
        ]
    }
}


sys.stdout.write(yaml.dump(ignition))
