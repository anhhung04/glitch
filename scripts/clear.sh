#!/bin/bash

# Check if cwd is range
if [[ ! -d "./checkers" && -d "./services" && -d "./.docker" ]]; then
    echo "Please run this script from the range directory (i.e. sh scripts/clear.sh))"
    exit 1
fi

TEAM_TOKENS=""

source .env set
source .env.live set

echo "Stopping all containers..."
bash scripts/down.sh

# Wait for all the docker stop commands to finish
sleep 5

echo "Deleting all containers..."

docker rm -f api >/dev/null
docker rm -f ticker >/dev/null
docker rmi -f api >/dev/null
docker rmi -f ticker >/dev/null

SERVICE_LIST=$(echo $SERVICES | tr ',' '\n')
CHECKER_LIST=$(echo $CHECKERS | tr ',' '\n')

# If checker list is empty, default to all services
if [ -z "$CHECKERS" ]; then
    CHECKERS=$SERVICES
    CHECKER_LIST=$SERVICE_LIST
fi

# Loop from 1 to $TEAM_COUNT
for TEAM_ID in $(seq 1 $TEAM_COUNT); do
    # Loop over every service
    echo "Deleting team $TEAM_ID..."
    for SERVICE_NAME in $SERVICE_LIST; do
        dir="./services/$SERVICE_NAME"
        # If the file is a directory
        if [ -d "$dir" ]; then
            HOSTNAME=$(echo "team$TEAM_ID-$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
            echo "Deleting $HOSTNAME..."
            docker rm -f $HOSTNAME >/dev/null 2>&1
            docker rmi -f $HOSTNAME-service >/dev/null 2>&1
            docker rmi -f ${HOSTNAME}_service >/dev/null 2>&1
        fi
    done
    HOSTNAME="team$TEAM_ID-proxy"
    docker rm -f $HOSTNAME >/dev/null 2>&1
    docker rmi -f $HOSTNAME >/dev/null 2>&1

done

# Loop over every checker
for SERVICE_NAME in $CHECKER_LIST; do
    dir="./checkers/$SERVICE_NAME"
    # If the file is a directory
    if [ -d "$dir" ]; then
        echo "Deleting $SERVICE_NAME checker..."
        HOSTNAME=$(echo "checker-$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
        echo "Deleting $HOSTNAME..."
        docker rm -f $HOSTNAME >/dev/null 2>&1
        docker rmi -f $HOSTNAME-checker >/dev/null 2>&1
        docker rmi -f ${HOSTNAME}_checker >/dev/null 2>&1
    fi
done

# Delete all the vpn files
rm -rf ./.docker/vpn/* >/dev/null

# Delete all the teamdata files
rm ./teamdata.txt
rm -rf ./.docker/api/teamdata/* >/dev/null

# Prune docker containers
docker container prune -f >/dev/null

# Prune docker images
docker image prune -f >/dev/null

# Prune docker volumes
docker volume rm glitch_db >/dev/null
docker volume prune -f >/dev/null

# Prune docker networks
docker network prune -f >/dev/null

# Clear debug log
rm ./debug.log >/dev/null 2>&1

# Clear .env.live
rm .env.live >/dev/null 2>&1
