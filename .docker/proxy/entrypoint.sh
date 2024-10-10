#!/bin/bash

set -e
ufw default allow incoming &&
    ufw default allow outgoing &&
    ufw --force enable

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

service ssh start && tail -f /dev/null
