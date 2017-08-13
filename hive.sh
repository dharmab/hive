#!/bin/bash

set -e

config_file=/opt/hive/etc/services.json
services="$(cat "$config_file")"
orchestrator="$1"

get_value() {
    local object="$1"
    local key="$2"
    local value="$(echo "$object" | jq -er ".\"$key\"")"
    echo "$value"
}

hash_json() {
    local json="$1"
    echo "$json" | jq '.' -ec | sha512sum | cut -d ' ' -f 1
}

manage_swarm_service() {
    local args=()

    # Service name
    local name="$(get_value "$service_config" "name")"
    args+=('--name' "$name")

    # Don't wait for the service to start before creating the next one
    args+=('--detach=true')

    # Environment variables
    for var in $(echo "$service_config" | jq -er '.environment | keys[]'); do
        value="$(get_value "$(get_value "$service_config" "environment")" "$var")"
        args+=('--env' "$var=$value")
    done

    # Bind mounts
    for ((i=0; i<$(echo "$service_config" | jq -e '.bind_mounts | length');i++)); do
        local mount_config="$(echo "$service_config" | jq -e ".bind_mounts[$i]")"
        local host_mount="$(get_value "$mount_config" "host")"
        local container_mount="$(get_value "$mount_config" "container")"
        local is_read_only="$(get_value "$mount_config" "read_only")"
        args+=('--mount' "type=bind,target=$container_mount,source=$host_mount,readonly=$is_read_only")
    done

    # Published ports
    for ((i=0; i<$(echo "$service_config" | jq -e '.ports | length');i++)); do
        local port_config="$(echo "$service_config" | jq -e ".ports[$i]")"
        local host_port="$(get_value "$port_config" "host")"
        local container_port="$(get_value "$port_config" "container")"
        local protocol="$(get_value "$port_config" "protocol")"
        args+=('--publish' "mode=host,target=$container_port,published=$host_port,protocol=$protocol")
    done
    
    # Image
    local image=$(get_value "$service_config" "image")
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

    for service in $(echo "$services" | jq -er 'map(.name)[]'); do
        local service_config=$(echo "$services" | jq '.[] | select(.name == "'"$service"'")')
        local config_hash_file="$config_cache_dir/$service"

        # Check if configuration has changed
        if [[ -f "$config_hash_file" ]]; then
            if [[ "$(hash_json "$service_config")" == "$(cat "$config_hash_file")" ]]; then
                echo "Configuration of service '$service' in $config_file has not changed"
                continue
            fi
        fi

        if [[ "$orchestrator" == "swarm" ]]; then
            manage_swarm_service "$service_config"
        fi

        # Save hash of current config for later config change checks
        echo "$new_service_hash" > "$config_hash_file"
    done;
}

main
