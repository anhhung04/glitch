#!/bin/bash

SERVICES=""

source .env set

NGINX_CONFIG_DIR="./.docker/rangemaster/nginx"

BASE_HTTP_CONFIG=$(
    cat <<EOF
server {
    listen PORT_IN;
    location / {
        proxy_pass http://IP:PORT_OUT;
        proxy_http_version 1.1;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
)

BASE_PWN_CONFIG=$(
    cat <<EOF
server {
    listen PORT_IN;
    proxy_pass IP;
    proxy_timeout 300s;
}
EOF
)

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

SERVICE_LIST=$(echo $SERVICES | tr ',' '\n')
for SERVICE in $SERVICE_LIST; do
    read -p "What is type of service $SERVICE? (h/p)" service_type
    if [ "$service_type" == "h" ]; then
        SERVICE_LIST=$(echo $SERVICE_LIST | sed "s/$SERVICE/h-$SERVICE/g")
    elif [ "$service_type" == "p" ]; then
        SERVICE_LIST=$(echo $SERVICE_LIST | sed "s/$SERVICE/p-$SERVICE/g")
    fi

done
# Loop from 1 to $TEAM_COUNT - 1
for TEAM_ID in $(seq 1 $TEAM_COUNT); do
    echo "Creating config for team $TEAM_ID..."
    SERVICE_ID=0
    SERVICE_INDEX=0
    for SERVICE_NAME in $SERVICE_LIST; do
        SERVICE_INDEX=$(expr $SERVICE_INDEX + 1)
        if [ "$(echo $SERVICES | cut -d, -f$SERVICE_INDEX)" == "$(echo $SERVICES, | cut -d, -f$(expr $SERVICE_INDEX + 1))" ]; then
            continue
        fi
        SERVICE_ID=$(expr $SERVICE_ID + 1)
        RAW_SERVICE_NAME=$(echo $SERVICE_NAME | cut -d- -f2)
        dir="./services/$RAW_SERVICE_NAME/"
        echo "Creating config service $RAW_SERVICE_NAME for team $TEAM_ID..."
        # If the file is a directory
        if [ -d "$dir" ]; then
            exposed_ports=$(find_ports "./services/$RAW_SERVICE_NAME")
            for port in $exposed_ports; do
		echo "Create config for port $port of service $RAW_SERVICE_NAME"
                if [[ $SERVICE_NAME =~ h-* ]]; then
                    touch $NGINX_CONFIG_DIR/conf.d/$TEAM_ID-$RAW_SERVICE_NAME-$port.http.conf
                    echo $BASE_HTTP_CONFIG | sed -e "s/PORT_IN/80$TEAM_ID$SERVICE_INDEX/g" -e "s/IP/10.100.$TEAM_ID.1/g" -e "s/PORT_OUT/$port/g" | tee -a $NGINX_CONFIG_DIR/conf.d/$TEAM_ID-$RAW_SERVICE_NAME-$port.http.conf
                elif [[ $SERVICE_NAME =~ p-* ]]; then
                    touch $NGINX_CONFIG_DIR/conf.d/$TEAM_ID-$RAW_SERVICE_NAME-$port.stream.conf
                    echo $BASE_PWN_CONFIG | sed -e "s/PORT_IN/80$TEAM_ID$SERVICE_INDEX/g" -e "s/IP/10.100.$TEAM_ID.1/g" | tee -a $NGINX_CONFIG_DIR/conf.d/$TEAM_ID-$RAW_SERVICE_NAME-$port.stream.conf
                fi
            done
        fi
    done
done
