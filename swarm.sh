#!/bin/bash

swarm_service_conf='/opt/hive/etc/swarm-services.json'

services=$(jq -r '. | map(.name)[]' "$swarm_service_conf")

get_value() {
    object="$1"
    key="$2"
    value="$(echo "$object" | jq -r ".\"$key\"")"
    echo "$value"
}

while ! docker service ls &> /dev/null; do
    echo "Waiting for swarm to initialize..."
    sleep 15
done

for service in $services; do
    docker service remove "$service"

    service_config=$(jq '.[] | select(.name = "'"$service"'")' "$swarm_service_conf")
    image=$(get_value "$service_config" "image")

    docker service create \
        --name "$service" \
        "$image"
done;
