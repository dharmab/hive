#!/bin/bash

config_file=/opt/hive/etc/services.json
services="$(cat "$config_file")"
orchestrator="$1"

get_value() {
    local object="$1"
    local key="$2"
    local value
    value="$(echo "$object" | jq -er ".$key")"
    echo "$value"
}

hash_json() {
    local json="$1"
    echo "$json" | jq '.' -ec | sha512sum | cut -d ' ' -f 1
}

manage_swarm_service() {
    local service_config="$1"

    local args=()

    # Service name
    local name
    name="$(get_value "$service_config" "name")"
    args+=('--name' "$name")

    # Don't wait for the service to start before creating the next one
    args+=('--detach=true')

    # Environment variables
    for var in $(echo "$service_config" | jq -er '.environment | keys[]'); do
        value="$(get_value "$(get_value "$service_config" "environment")" "$var")"
        args+=('--env' "$var=$value")
    done

    # Bind mounts
    local mount_config
    local host_mount
    local container_mount
    local is_read_only
    for ((i=0; i<$(echo "$service_config" | jq -e '.bind_mounts | length');i++)); do
        mount_config="$(echo "$service_config" | jq -e ".bind_mounts[$i]")"
        host_mount="$(get_value "$mount_config" "host")"
        container_mount="$(get_value "$mount_config" "container")"
        is_read_only="$(get_value "$mount_config" "read_only")"
        args+=('--mount' "type=bind,target=$container_mount,source=$host_mount,readonly=$is_read_only")
    done

    # Published ports
    local port_config
    local host_port
    local container_port
    local protocol
    for ((i=0; i<$(echo "$service_config" | jq -e '.ports | length');i++)); do
        port_config="$(echo "$service_config" | jq -e ".ports[$i]")"
        host_port="$(get_value "$port_config" "host")"
        container_port="$(get_value "$port_config" "container")"
        protocol="$(get_value "$port_config" "protocol")"
        args+=('--publish' "mode=host,target=$container_port,published=$host_port,protocol=$protocol")
    done

    # Image
    local image
    image=$(get_value "$service_config" "image")
    args+=("$image")

    # Optional command override
    if echo "$service_config" | jq -e '.command[]' &> /dev/null; then
        readarray -t cmd <<< "$(get_value "$service_config" '.command[]')"
        args+=("${cmd[@]}")
    fi

    # Stop old instance (if running)
    if docker service inspect "$service" &> /dev/null; then
        echo "Stopping $service"
        docker service remove "$service"
    fi

    # Start new instance (if enabled)
    if echo "$service_config" | jq -e '.is_enabled == true' &> /dev/null; then
        echo "Starting $service"
        docker service create "${args[@]}"
    fi
}

manage_systemd_service() {
    local service_config="$1"

    args=("--rm")

    # Service name
    local name
    name="hive-$(get_value "$service_config" "name")"
    args+=("--name" "$name")

    # Bind mounts
    local mount_config
    local host_mount
    local container_mount
    local is_read_only
    for ((i=0; i<$(echo "$service_config" | jq -e '.bind_mounts | length');i++)); do
        mount_config="$(echo "$service_config" | jq -e ".bind_mounts[$i]")"
        host_mount="$(get_value "$mount_config" "host")"
        container_mount="$(get_value "$mount_config" "container")"
        is_read_only="$(get_value "$mount_config" "read_only")"
        args+=("--mount" "type=bind,target=$container_mount,source=$host_mount,readonly=$is_read_only")
    done

    # Published ports
    local port_config
    local host_port
    local container_port
    local protocol
    for ((i=0; i<$(echo "$service_config" | jq -e '.ports | length');i++)); do
        port_config="$(echo "$service_config" | jq -e ".ports[$i]")"
        host_port="$(get_value "$port_config" "host")"
        container_port="$(get_value "$port_config" "container")"
        protocol="$(get_value "$port_config" "protocol")"
        args+=("-p" "$container_port:$host_port/$protocol")
    done

    # Image
    local image
    image=$(get_value "$service_config" "image")
    args+=("$image")

    # Optional command override
    if echo "$service_config" | jq -e '.command[]' &> /dev/null; then
        readarray -t cmd <<< "$(get_value "$service_config" '.command[]')"
        args+=("${cmd[@]}")
    fi

    unit+="[Unit]\n"
    unit+="Description=$name\n"
    unit+="After=docker.service\n"
    unit+="Requires=docker.service\n"
    unit+="\n"
    unit+="[Service]\n"
    unit+="ExecStartPre=-/usr/bin/docker kill $name\n"
    unit+="ExecStartPre=-/usr/bin/docker rm $name\n"
    unit+="ExecStartPre=/usr/bin/docker pull $image\n"
    unit+="ExecStart=/usr/bin/docker run ${args[@]}\n"
    unit+="\n"
    unit+="[Install]\n"
    unit+="WantedBy=multi-user.target\n"

    # Environment variables
    environment="[Service]\n"
    for var in $(echo "$service_config" | jq -er '.environment | keys[]'); do
        value="$(get_value "$(get_value "$service_config" "environment")" "$var")"
        environment+="Environment=\"$var=$value\"\n"
    done

    # Stop old instance (if running)
    if systemctl is-active --quiet "$name"; then
        echo "Stopping $service"
        systemctl disable "$name" --now
    fi

    # Write service and environment variables
    echo -e "$unit" > "/etc/systemd/system/$name.service"
    mkdir -p "/etc/systemd/system/$name.service.d"
    echo -e "$environment" > "/etc/systemd/system/$name.service.d/override.conf"
    systemctl daemon-reload

    # Start new instance (if enabled)
    if echo "$service_config" | jq -e '.is_enabled == true' &> /dev/null; then
        echo "Starting $service"
        systemctl enable "$name" --now
    fi
}

main() {
    while  [[ "$orchestrator" == "swarm" ]] && ! docker service ls &> /dev/null; do
        echo "Waiting for swarm to initialize..."
        sleep 15
    done

    echo -n "Validating $config_file... "
    if ! echo "$services" | jq -e '.' > /dev/null; then
        exit 1
    fi
    echo "Success!"

    config_cache_dir="/opt/hive/var/configcache"
    if ! [[ -d "$config_cache_dir" ]]; then
        echo "Creating config cache directory..."
        mkdir -p "$config_cache_dir"
    fi

    local service_config
    local config_hash_file
    local new_service_hash
    for service in $(echo "$services" | jq -er 'map(.name)[]'); do
        service_config=$(echo "$services" | jq '.[] | select(.name == "'"$service"'")')
        config_hash_file="$config_cache_dir/$service"

        # Check if configuration has changed
        new_service_hash="$(hash_json "$service_config")"
        if [[ -f "$config_hash_file" ]]; then
            if [[ "$new_service_hash" == "$(cat "$config_hash_file")" ]]; then
                echo "Configuration of service '$service' in $config_file has not changed"
                continue
            fi
        fi

        if [[ "$orchestrator" == "systemd" ]]; then
            manage_systemd_service "$service_config"
        else
            manage_swarm_service "$service_config"
        fi

        # Save hash of current config for later config change checks
        echo "$new_service_hash" > "$config_hash_file"
    done;
}

main
