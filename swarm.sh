#!/bin/bash

services="$(cat /opt/hive/etc/swarm-services.json)"

get_value() {
    object="$1"
    key="$2"
    value="$(echo "$object" | jq -r ".\"$key\"")"
    echo "$value"
}

get_array() {
    object="$1"
    key="$2"
    array="$(echo "$object" | jq -r ". | map(.\"$key\")[]")"
    echo "$array"
}

while ! docker service ls &> /dev/null; do
    echo "Waiting for swarm to initialize..."
    sleep 15
done

for service in $(get_array "$services" "name"); do
    service_config=$(echo "$services" | jq '.[] | select(.name == "'"$service"'")')
    if docker service inspect "$service" &> /dev/null; then
        docker service remove "$service"
    fi

    if echo "$service_config" | jq -e '.is_enabled == false' &> /dev/null; then
        continue
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
        readarray -t cmd <<< "$(get_array "$service_config" 'command')"
        args+=("${cmd[@]}")
    fi

    docker service create "${args[@]}"
done;
