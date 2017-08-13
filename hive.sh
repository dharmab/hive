#!/bin/bash

config_file=/opt/hive/etc/services.json
services="$(cat "$config_file")"

get_value() {
    object="$1"
    key="$2"
    value="$(echo "$object" | jq -r ".\"$key\"")"
    echo "$value"
}

hash_json() {
    json="$1"
    echo "$json" | jq '.' -c | sha512sum | cut -d ' ' -f 1
}

while ! docker service ls &> /dev/null; do
    echo "Waiting for swarm to initialize..."
    sleep 15
done

echo -n "Validating $config_file..."
if ! echo "$services" | jq -e '.' > /dev/null; then
    exit 1
fi
echo " Success!"

config_cache_dir="/opt/hive/var/configcache"
if ! [[ -d "$config_cache_dir" ]]; then
    echo "Creating config cache directory..."
    mkdir -p "$config_cache_dir"
fi

for service in $(echo "$services" | jq -r 'map(.name)[]'); do
    service_config=$(echo "$services" | jq '.[] | select(.name == "'"$service"'")')
    config_hash_file="$config_cache_dir/$service"

    # Check if configuration has changed
    if [[ -f "$config_hash_file" ]]; then
        if [[ "$new_service_hash" == "$previous_service_hash" ]]; then
            echo "Configuration of service '$service' in $config_file has not changed"
            continue
        fi
    fi

    args=()

    # Service name
    args+=('--name' "$service")

    # Don't wait for the service to start before creating the next one
    args+=('--detach=true')

    # Environment variables
    for var in $(echo "$service_config" | jq -r '.environment | keys[]'); do
        value="$(get_value "$(get_value "$service_config" "environment")" "$var")"
        args+=('--env' "$var=$value")
    done

    # Bind mounts
    for ((i=0; i<$(echo "$service_config" | jq '.bind_mounts | length');i++)); do
        mount_config="$(echo "$service_config" | jq ".bind_mounts[$i]")"
        host_mount="$(get_value "$mount_config" "host")"
        container_mount="$(get_value "$mount_config" "container")"
        is_read_only="$(get_value "$mount_config" "read_only")"
        args+=('--mount' "type=bind,target=$container_mount,source=$host_mount,readonly=$is_read_only")
    done

    # Published ports
    for ((i=0; i<$(echo "$service_config" | jq '.ports | length');i++)); do
        port_config="$(echo "$service_config" | jq ".ports[$i]")"
        host_port="$(get_value "$port_config" "host")"
        container_port="$(get_value "$port_config" "container")"
        protocol="$(get_value "$port_config" "protocol")"
        args+=('--publish' "mode=host,target=$container_port,published=$host_port,protocol=$protocol")
    done
    
    # Image
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

    # Save hash of current config for later config change checks
    echo "$new_service_hash" > "$config_hash_file"
done;
