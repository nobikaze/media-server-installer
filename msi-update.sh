#!/bin/bash

#                            ░██               ░██
#                                              ░██
# ░█████████████   ░███████  ░██     ░███████  ░████████
# ░██   ░██   ░██ ░██        ░██    ░██        ░██    ░██
# ░██   ░██   ░██  ░███████  ░██     ░███████  ░██    ░██
# ░██   ░██   ░██        ░██ ░██           ░██ ░██    ░██
# ░██   ░██   ░██  ░███████  ░██░██  ░███████  ░██    ░██

# Automates the installation of Jellyfin on a Linux server
# using Docker and other required tools.

# System Maintenance Script

# https://github.com/nobikaze/media-server-installer/
# MIT LICENSE

set -e

CONTAINERS_DIR="/srv/media/containers"
LOG_FILE="/var/log/msi-update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi

log "Starting Docker system maintenance..."

log "Updating system packages..."
apt update && apt upgrade -y

log "Removing unnecessary packages..."
apt autoremove --purge -y

# Docker compose operations
DOCKER_COMPOSE_FILE="$CONTAINERS_DIR/docker-compose.yml"

if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    log "Error: docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
    exit 1
fi

log "Pulling latest Docker images..."
docker compose -f "$DOCKER_COMPOSE_FILE" pull

log "Recreating containers with latest images..."
docker compose -f "$DOCKER_COMPOSE_FILE" up -d --remove-orphans

log "Pruning unused Docker images..."
docker image prune -f

log "Docker system maintenance completed successfully."
