# Hive

A very tiny container manager.

This was written to POC a solution for running containers on Mesos masters. Mesos only supports running workloads on agents, but it can be useful to run containerized services on master nodes as well (e.g. monitoring and log aggregation agents).

This POC uses Docker Swarm to launch containers on a single-node Swarm "cluster". It intentionally only supports a small subset of Swarm's capabilities to keep things simple.

# Dependencies:

- Vagrant
- Docker
- Make

# Configuration

Copy `services.yml.example` to `services.yml` and edit it to define which services should run on the node.

`services.yml` should be a list of service definition dictionaries. Each service definition dictionary contains the following key-value pairs, with *bold* keys being mandatory and all others being optional.

- *name*: Name of the Docker Swarm service this dictionary defines.
- *image*: Docker image that the service will run.
- environment: Dictionary containing environment variables where each key is a variable name and each value is the variable's string value. Default: empty dictionary.
- ports: List of host port bindings. Default: empty list.
  - *container*: Port inside the container to bind.
  - *host*: Port on the host to bind.
  - protocol: 'tcp' or 'udp'. Default: 'tcp'
- bind_mounts: List of bind mounts. Default: empty list.
  - *container*: Path inside the container to bind.
  - *host*: Path on the host to bind.
  - read_only: If True, mount will be read-only. If False, mount will be read-write. Default: False

# Try It

```bash
make deploy
vagrant ssh
docker service ls
docker service inspect <service name>
```
