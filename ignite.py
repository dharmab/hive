#!/usr/bin/env python3

import json
import sys
import textwrap


def unit(name, *, contents=None, enabled=True):
    unit = {
        'name': name,
        'enabled': enabled,
    }
    if contents:
        unit['contents'] = ''.join(textwrap.dedent(contents).strip())
    return unit

docker_swarm_unit = unit(
    'docker-swarm.service',
    contents="""
    [Unit]
    Description=Launch Docker Swarm in standalone mode
    Requires=docker.service

    [Service]
    Type=oneshot
    ExecStart=/usr/bin/docker swarm init
    StandardOutput=journal+console

    [Install]
    WantedBy=multi-user.target
    """
)

ignition = {
    'ignition': {
        'version': '2.1.0',
    },
    'systemd': {
        'units': [
            unit('docker.service', enabled=True),
            docker_swarm_unit
        ]
    },
}


sys.stdout.write(json.dumps(ignition))
