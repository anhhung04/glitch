#!/bin/bash

# Check if cwd is range
if [[ ! -d "./checkers" && -d "./services" && -d "./.docker" ]]; then
  echo "Please run this script from the range directory (i.e. sh scripts/up.sh))"
  exit 1
fi

# Create randomized api key
API_KEY="$(openssl rand -hex 16)"
# Set default values
TEAM_COUNT=2
VPN_PER_TEAM=1
FLAG_LIFETIME=5
SERVER_URL="localhost"
FRONTEND_PORT=80
VPN_PORT=51820
API_PORT=8000
VPN_DNS="8.8.8.8"
SERVICES=""
TICK_SECONDS=60
CAPTURE_PCAPS=false
# Use date if on unix, use gdate if on mac
if [[ "$(uname)" == "Darwin" ]]; then
  START_TIME=$(gdate -u +"%Y-%m-%dT%H:%M:%SZ")
  END_TIME=$(gdate -u +"%Y-%m-%dT%H:%M:%SZ" -d "+$(expr $TICK_SECONDS \* 100) seconds")
else
  START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ" -d "+$(expr $TICK_SECONDS \* 100) seconds")
fi
MEM_LIMIT="1G"
CPU_LIMIT="1"

cp .env .env.live
source .env set

VPN_COUNT=$(expr $TEAM_COUNT \* $VPN_PER_TEAM)
SERVICE_LIST=$(echo $SERVICES | tr ',' '\n')
CHECKER_LIST=$(echo $CHECKERS | tr ',' '\n')

START_TIME_PATH=$(echo $START_TIME | tr ':' '-')

# If checker list is empty, default to all services
if [ -z "$CHECKERS" ]; then
  CHECKERS=$SERVICES
  CHECKER_LIST=$SERVICE_LIST
fi

info() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Check if the length of the checker list is equal to the length of the service list
if [ "$(echo $SERVICE_LIST | wc -w)" != "$(echo $CHECKER_LIST | wc -w)" ]; then
  error "The number of checkers must be equal to the number of services."
  exit 1
fi

info "Creating empty teamdata directory..."
# Create empty teamdata directory
rm -rf ./.docker/api/teamdata
mkdir ./.docker/api/teamdata
echo "Team data download links (distribute one link to each team):" >./teamdata.txt

info "Generating team tokens..."
# Generate team tokens
TEAM_TOKENS=""
for TEAM_ID in $(seq 1 $TEAM_COUNT); do
  # Generate team token
  TEAM_TOKEN="$(openssl rand -hex 16)"
  TEAM_TOKENS="$TEAM_TOKENS,$TEAM_TOKEN"
  # Create teamdata directory and credentials file
  mkdir ./.docker/api/teamdata/$TEAM_TOKEN
  mkdir ./.docker/api/teamdata/$TEAM_TOKEN/vpn
  echo -e "Team $TEAM_ID Range Credentials:\n" >./.docker/api/teamdata/$TEAM_TOKEN/creds.txt
  echo -e "API Token: $TEAM_TOKEN\n" >>./.docker/api/teamdata/$TEAM_TOKEN/creds.txt
  echo "Team $TEAM_ID: http://$SERVER_URL:$API_PORT/teamdata/$TEAM_TOKEN/rangedata.zip" >>./teamdata.txt
done
# Strip leading comma
TEAM_TOKENS="${TEAM_TOKENS:1}"

info "Starting range services..."
API_KEY=$API_KEY TEAM_COUNT=$TEAM_COUNT PEERS=$VPN_COUNT FLAG_LIFETIME=$FLAG_LIFETIME TICK_SECONDS=$TICK_SECONDS START_TIME=$START_TIME END_TIME=$END_TIME START_TIME_PATH=$START_TIME_PATH SERVERURL=$SERVER_URL FRONTEND_PORT=$FRONTEND_PORT API_PORT=$API_PORT VPN_PORT=$VPN_PORT VPN_DNS=$VPN_DNS TEAM_TOKENS=$TEAM_TOKENS SERVICES=$SERVICES CHECKERS=$CHECKERS docker compose up -d --force-recreate >>./debug.log 2>&1

info "Waiting for VPN to start..."
sleep 5

# If capture pcaps is true, start tcpdump on the vpn interface for the network 10.101.0.0/16 writing to /pcaps/range_$START_TIME.pcap
if [ "$CAPTURE_PCAPS" = true ]; then
  info "Starting tcpdump on vpn interface..."
  mkdir -p ./pcaps/$START_TIME_PATH
  docker exec -d vpn sh -c 'apk update && apk add tcpdump && tcpdump -i any -G $TICK_SECONDS -w /pcaps/$START_TIME_PATH/range_$START_TIME_%Y-%m-%dT%H-%M-%SZ.pcap -s 0 -S net 10.101.0.0/15'
fi

find_ports() {
  local compose_file=$(find "$1" -name 'docker-compose.yaml' -o -name 'docker-compose.yml' | head -n 1)

  if [ ! -f "$compose_file" ]; then
    echo "Error: Docker Compose file not found in directory '$1'." >&2
    return ""
  fi
  local ports=$(grep -E '^\s*-\s*(["'\'']?)([0-9.:]+:)?[0-9]+:[0-9]+\1' "$compose_file" |
    sed -E 's/^\s*-\s*(["'\'']?)(([0-9.]+:)?([0-9]+):[0-9]+)\1.*/\4/' |
    sort -n |
    uniq |
    tr '\n' ' ' |
    sed 's/ $//')

  echo "$ports"
}

replace_placeholder() {
  local file="$1"
  local placeholder="$2"
  local replacement="$3"

  placeholder=$(printf '%s\n' "$placeholder" | sed -e 's/[]\/$*.^[]/\\&/g')
  replacement=$(printf '%s\n' "$replacement" | sed -e ':a;N;$!ba;s/\\n/\n/g')
  replacement=$(printf '%s\n' "$replacement" | sed -e 's/\//\\\//g')

  sed -i ':a;N;$!ba;s/'"$placeholder"'/'"$replacement"'/g' "$file"
}

# Loop from 1 to $TEAM_COUNT - 1
for TEAM_ID in $(seq 1 $TEAM_COUNT); do
  info "Starting team $TEAM_ID..."
  TEAM_TOKEN="$(echo $TEAM_TOKENS | cut -d',' -f$TEAM_ID)"
  # Copy vpn files
  for VPN_ID in $(seq 1 $VPN_PER_TEAM); do
    VPN_NAME="peer$(expr $VPN_ID + $(expr $(expr $TEAM_ID - 1) \* $VPN_PER_TEAM))"
    cp ./.docker/vpn/$VPN_NAME/$VPN_NAME.conf ./.docker/api/teamdata/$TEAM_TOKEN/vpn/wg$VPN_ID.conf
  done
  # Create a counter for service IDs starting at 1
  SERVICE_ID=1
  SERVICE_INDEX=1
  IPTABLE_RULES=""
  for SERVICE_NAME in $SERVICE_LIST; do
    SERVICE_INDEX=$(expr $SERVICE_INDEX + 1)
    if [ "$(echo $SERVICES | cut -d, -f$(expr $SERVICE_INDEX - 1))" == "$(echo $SERVICES, | cut -d, -f$(expr $SERVICE_INDEX))" ]; then
      continue
    fi
    info "Starting service $SERVICE_NAME for team $TEAM_ID..."
    SERVICE_ID=$(expr $SERVICE_ID + 1)
    dir="./services/$SERVICE/"
    # If the file is a directory
    if [ -d "$dir" ]; then
      # Start docker compose in the /services directory with a volume mount of the directory
      # Generate a random root password
      exposed_ports=$(find_ports "./services/$SERVICE_NAME")
      for port in $exposed_ports; do
        IPTABLE_RULES=$IPTABLE_RULES"iptables -t nat -A PREROUTING -p tcp --dport $port -j DNAT --to-destination 10.100.$TEAM_ID.$SERVICE_ID:$port\n"
      done
      ROOT_PASSWORD="$(openssl rand -hex 16)"
      HOSTNAME=$(echo "team$TEAM_ID-$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
      IP=$(echo "10.100.$TEAM_ID.$SERVICE_ID" | tr '[:upper:]' '[:lower:]')
      # Write creds to creds.txt
      echo "$IP ($SERVICE_NAME) - root : $ROOT_PASSWORD" >>./.docker/api/teamdata/$TEAM_TOKEN/creds.txt
      IP=$IP HOSTNAME=$HOSTNAME TEAM_ID=$TEAM_ID SERVICE_ID=$SERVICE_ID SERVICE_NAME=$SERVICE_NAME ROOT_PASSWORD=$ROOT_PASSWORD CPU_LIMIT=$CPU_LIMIT MEM_LIMIT=$MEM_LIMIT docker compose -f ./services/docker-compose.yaml --project-name $HOSTNAME up -d >>./debug.log 2>&1
    fi
  done
  IPTABLE_RULES="$IPTABLE_RULES\niptables -t nat -A POSTROUTING -p tcp -d 10.100.$TEAM_ID.0/24 -j MASQUERADE"
  info "Starting proxy for $TEAM_ID..."
  # Start proxy for team
  info "IPTABLE_RULES:\n$IPTABLE_RULES"
  cp ./.docker/proxy/entrypoint.sh.bak ./.docker/proxy/entrypoint.sh
  replace_placeholder ./.docker/proxy/entrypoint.sh "IPTABLE_RULES" "$IPTABLE_RULES"
  IP=$(echo "10.100.$TEAM_ID.1" | tr '[:upper:]' '[:lower:]')
  HOSTNAME=$(echo "team$TEAM_ID-proxy" | tr '[:upper:]' '[:lower:]')
  echo "$IP ($HOSTNAME) - root : root" >>./.docker/api/teamdata/$TEAM_TOKEN/creds.txt
  IP=$IP HOSTNAME=$HOSTNAME TEAM_ID=$TEAM_ID docker compose -f ./.docker/proxy/docker-compose.yml --project-name $HOSTNAME up -d >>./debug.log 2>&1
  rm -f ./.docker/proxy/entrypoint.sh
  # Zip teamdata directory
  pushd ./.docker/api/teamdata >/dev/null
  zip -r $TEAM_TOKEN.zip $TEAM_TOKEN >/dev/null
  popd >/dev/null
  info "Finished starting team $TEAM_ID."
done

SERVICE_ID=1
CHECKER_ID=1
for SERVICE_NAME in $CHECKER_LIST; do
  dir="./checkers/$SERVICE_NAME/"
  # If the file is a directory
  if [ -d "$dir" ]; then
    HOSTNAME=$(echo "checker-$SERVICE_NAME" | tr '[:upper:]' '[:lower:]')
    IP=$(echo "10.103.2.$CHECKER_ID" | tr '[:upper:]' '[:lower:]')
    echo "Starting $HOSTNAME, connecting checker $CHECKER_ID to service $SERVICE_ID..."
    IP=$IP GATEWAY="10.103.1.1" HOSTNAME=$HOSTNAME SERVICE_ID=$SERVICE_ID SERVICE_NAME=$SERVICE_NAME TICK_SECONDS=$TICK_SECONDS docker compose -f ./checkers/docker-compose.yaml --project-name $HOSTNAME up -d >>./debug.log 2>&1
    if [ "$(echo $SERVICES | cut -d, -f$CHECKER_ID)" != "$(echo $SERVICES | cut -d, -f$(expr $CHECKER_ID + 1))" ]; then
      SERVICE_ID=$(expr $SERVICE_ID + 1)
    fi
    CHECKER_ID=$(expr $CHECKER_ID + 1)
  fi
done

# Print teamdata download links
echo "*******************************************************"
echo -e "\nAdmin API KEY: $API_KEY\n"
cat ./teamdata.txt
echo -e "\n(Team data stored in ./teamdata.txt)"
