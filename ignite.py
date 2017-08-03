#!/usr/bin/env python3

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


docker_swarm_dropin = dropin(
    'docker-swarm.conf',
    contents="""
    [Service]
    ExecStartPost=/usr/bin/docker swarm init
    """

)

ignition = {
    'systemd': {
        'units': [
            unit('docker.service', enabled=True, dropins=[docker_swarm_dropin]),
        ]
    },
}


sys.stdout.write(yaml.dump(ignition))
