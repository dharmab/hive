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
    docker service remove "$service"

    service_config=$(echo "$services" | jq '.[] | select(.name == "'"$service"'")')
    image=$(get_value "$service_config" "image")

    docker service create \
        --name "$service" \
        $(
            for ((i=0; i<$(echo "$service_config" | jq '.bind_mounts | length');i++)); do
                mount_config="$(echo "$service_config" | jq ".bind_mounts[$i]")"
                echo -n " --mount type=bind,target=$(get_value "$mount_config" "container"),source=$(get_value "$mount_config" "host"),readonly=$(get_value "$mount_config" "read_only")"
            done
        ) \
        $(
            for ((i=0; i<$(echo "$service_config" | jq '.ports | length');i++)); do
                port_config="$(echo "$service_config" | jq ".ports[$i]")"
                echo -n " --publish mode=host,target=$(get_value "$port_config" "container"),published=$(get_value "$port_config" "host")"
            done
        ) \
        "$image"
done;
