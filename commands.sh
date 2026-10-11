#!/usr/bin/env bash
set -Eeuo pipefail

NETWORK_NAME="app-net"
VOLUME_NAME="db-data"
DB_CONTAINER="db-server"
APP_CONTAINER="app-container"
DB_NAME="${POSTGRES_DB:-appdb}"
DB_USER="${POSTGRES_USER:-appuser}"
DB_PASSWORD="${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD before running}"
BACKEND_IMAGE="${BACKEND_IMAGE:-hw-backend:multistage}"

for container_name in "$DB_CONTAINER" "$APP_CONTAINER"; do
    if docker container inspect "$container_name" >/dev/null 2>&1; then
        printf 'Container %s already exists; inspect it before removing or reusing it.\n' "$container_name" >&2
        exit 1
    fi
done

docker image inspect "$BACKEND_IMAGE" >/dev/null
docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || docker network create "$NETWORK_NAME"
docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1 || docker volume create "$VOLUME_NAME"

start_database() {
    docker run -d \
        --name "$DB_CONTAINER" \
        --network "$NETWORK_NAME" \
        --network-alias db-server \
        --volume "$VOLUME_NAME:/var/lib/postgresql/data" \
        --env "POSTGRES_DB=$DB_NAME" \
        --env "POSTGRES_USER=$DB_USER" \
        --env "POSTGRES_PASSWORD=$DB_PASSWORD" \
        --health-cmd="pg_isready -U $DB_USER -d $DB_NAME" \
        --health-interval=2s \
        --health-timeout=3s \
        --health-retries=30 \
        postgres:15-alpine >/dev/null

    for _ in $(seq 1 60); do
        health="$(docker inspect --format '{{.State.Health.Status}}' "$DB_CONTAINER")"
        if [[ "$health" == healthy ]]; then
            printf 'Database is ready: %s\n' "$DB_CONTAINER"
            return 0
        fi
        sleep 1
    done

    docker logs "$DB_CONTAINER"
    printf 'Database did not become healthy in time.\n' >&2
    return 1
}

start_database

docker run -d \
    --name "$APP_CONTAINER" \
    --network "$NETWORK_NAME" \
    --publish 8081:3000 \
    --env DB_HOST=db-server \
    --env DB_PORT=5432 \
    --env "DB_NAME=$DB_NAME" \
    --env "DB_USER=$DB_USER" \
    --env "DB_PASSWORD=$DB_PASSWORD" \
    "$BACKEND_IMAGE" >/dev/null

health_ready=false
for _ in $(seq 1 30); do
    if curl --fail --silent http://localhost:8081/api/health >/dev/null; then
        health_ready=true
        break
    fi
    sleep 1
done
if [[ "$health_ready" != true ]]; then
    docker logs "$APP_CONTAINER"
    printf 'Backend did not become healthy in time.\n' >&2
    exit 1
fi

docker exec "$APP_CONTAINER" ping -c 2 db-server
curl --fail --silent --show-error http://localhost:8081/api/health
printf '\n'

curl --fail --silent --show-error \
    --request POST \
    --header 'Content-Type: text/plain; charset=utf-8' \
    --data-binary 'Docker volume persistence check' \
    http://localhost:8081/api/records
printf '\n'

printf 'Records before database container recreation: '
curl --fail --silent --show-error http://localhost:8081/api/records
printf '\n'

docker rm -f "$DB_CONTAINER" >/dev/null
start_database

records="$(curl --fail --silent --show-error http://localhost:8081/api/records)"
printf 'Records after database container recreation: %s\n' "$records"
grep --fixed-strings --quiet 'Docker volume persistence check' <<<"$records"
printf 'Persistence verification passed. Container %s and volume %s are retained.\n' "$APP_CONTAINER" "$VOLUME_NAME"
