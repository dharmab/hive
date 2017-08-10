#!/usr/bin/env python3

import json
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


def swarm_service(
    name,
    *,
    image,
    tag='latest',
    environment={},
    ports=[],
    bind_mounts={},
    is_global=False,
    replicas=1
):
    return {
        'name': name,
        'image': '{}:{}'.format(image, tag),
        'environment': environment,
        'ports': ports,
        'bind_mounts': bind_mounts,
        'global': is_global,
        'replicas': replicas
    }


def port(*, host_port, container_port, protocol='tcp'):
    return {
        'host': host_port,
        'container': container_port,
        'protocol': protocol
    }


def bind_mount(*, host_path, container_path, access='rw'):
    return {
        'host': host_path,
        'container': container_path,
        'access': access
    }


docker_swarm_dropin = dropin(
    'docker-swarm.conf',
    contents="""
    [Service]
    ExecStartPost=/usr/bin/docker swarm init
    """
)

swarm_unit = unit(
    name='swarm-init.service',
    enabled=True,
    contents="""
    [Unit]
    Description=Create Docker Swarm services
    Requires=docker.service
    After=docker.service

    [Service]
    Type=oneshot
    ExecStart=/opt/hive/bin/swarm
    StandardOutput=journal

    [Install]
    WantedBy=multi-user.target
    """
)

default_services = [
    swarm_service('nginx', image='nginx', ports=[
        port(host_port=8080, container_port=80)
    ]),
]

with open('swarm.sh') as f:
    swarm_script = f.read()

ignition = {
    'systemd': {
        'units': [
            unit('docker.service', enabled=True, dropins=[docker_swarm_dropin]),
            swarm_unit
        ]
    },
    'storage': {
        'files': [
            _file('/opt/hive/etc/swarm-services.json', mode=600, contents=json.dumps(default_services)),
            _file('/opt/hive/bin/swarm', mode=700, contents=swarm_script)
        ]
    }
}


sys.stdout.write(yaml.dump(ignition))
