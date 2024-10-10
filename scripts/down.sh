#!/bin/bash

# Check if cwd is range
if [[ ! -d "./checkers" && -d "./services" && -d "./.docker" ]]; then
    echo "Please run this script from the range directory (i.e. sh scripts/down.sh))"
    exit 1
fi

API_KEY=""
TEAM_COUNT=2
VPN_PER_TEAM=1
SERVER_URL="localhost"
VPN_PORT=0
API_PORT=0
TEAM_TOKENS=""

source .env set
source .env.live set

SERVICE_LIST=$(echo $SERVICES | tr ',' '\n')
CHECKER_LIST=$(echo $CHECKERS | tr ',' '\n')

# If checker list is empty, default to all services
if [ -z "$CHECKERS" ]; then
    CHECKERS=$SERVICES
    CHECKER_LIST=$SERVICE_LIST
fi

for SERVICE_NAME in $CHECKER_LIST; do
    dir="./checkers/$SERVICE_NAME"
    # If the file is a directory
    if [ -d "$dir" ]; then
        # Generate a random root password
        HOSTNAME=$(echo "checker-$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
        echo "Stopping $HOSTNAME..."
        docker stop $HOSTNAME -t 1 >/dev/null &
    fi
done

# Loop from 1 to $TEAM_COUNT
for TEAM_ID in $(seq 1 $TEAM_COUNT); do
    for SERVICE_NAME in $SERVICE_LIST; do
        dir="./services/$SERVICE_NAME"
        # If the file is a directory
        if [ -d "$dir" ]; then
            # Generate a random root password
            HOSTNAME=$(echo "team$TEAM_ID-$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
            echo "Stopping $HOSTNAME..."
            docker stop $HOSTNAME -t 1 >/dev/null &
        fi
    done
    echo "Stopping team $TEAM_ID proxy..."
    docker stop "team$TEAM_ID-proxy" >/dev/null &
done

sleep 2

echo "Stopping range services..."
API_KEY="" PEERS="" TEAM_TOKENS="" START_TIME_PATH="" CHECKERS=$CHECKERS docker compose down -t 2 >/dev/null
