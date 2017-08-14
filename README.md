# Hive

A very tiny container manager.

This was written to POC a solution for running containers on Mesos masters. Mesos only supports running workloads on agents, but it can be useful to run containerized services on master nodes as well (e.g. monitoring and log aggregation agents).

This POC uses Docker Swarm or systemd to manage containerized services. It intentionally only supports a small subset of Docker's capabilities to keep things simple.

# Dependencies:

- Vagrant
- Docker
- Make

# Configuration

Copy `config.yml.example` to `config.yml` and edit it to define which services should run on the node.

`config.yml` may contain the following configuration, with **bold** configuration options being mandatory and all others being optional.

- orchestrator: What software to use to manage the services. Either 'systemd' or 'swarm'. Default: 'swarm'
- services: List of definitions of services to run. Default: empty list.
  - **name**: Name of the Docker Swarm service this dictionary defines. Must consist of lowercase letters, numbers and '-' only.
  - **image**: Docker image that the service will run.
  - is_enabled: If False, the service will be disabled if present and not created if not present. Otherwise, the service will be created and enabled. This is useful to force a service to be disabled if present. Default: False.
  - command: List containing command and arguments to run instead of the image's default. Example: `["ping", "-c", "5", "docker.com"]`
  - environment: Dictionary containing environment variables where each key is a variable name and each value is the variable's string value. Default: empty dictionary.
  - ports: List of host port bindings. Default: empty list.
    - **container**: Port inside the container to bind.
    - **host**: Port on the host to bind.
    - protocol: 'tcp' or 'udp'. Default: 'tcp'
  - bind_mounts: List of bind mounts. Default: empty list.
    - **container**: Path inside the container to bind.
    - **host**: Path on the host to bind.
    - read_only: If True, mount will be read-only. If False, mount will be read-write. Default: False

# Try It

```bash
make deploy
vagrant ssh

# If using swarm
docker service ls
docker service inspect <service name>

# If using systemd
systemctl status hive-<service name>
```
