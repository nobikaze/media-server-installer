#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}WARNING: This will REMOVE all media server containers, config, users, and firewall rules installed by msi.sh!${NC}"
read -p "Are you sure you want to continue? (y/N): " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || exit 1

# Stop and remove containers
if [ -f /srv/media/containers/docker-compose.yml ]; then
    echo "Stopping and removing containers..."
    docker compose -f /srv/media/containers/docker-compose.yml down --volumes --remove-orphans
fi

# Remove Docker images (optional, only those used by the stack)
echo "Removing related Docker images..."
docker image rm jellyfin/jellyfin:latest \
    lscr.io/linuxserver/sonarr:latest \
    lscr.io/linuxserver/radarr:latest \
    lscr.io/linuxserver/prowlarr:latest \
    lscr.io/linuxserver/bazarr:latest \
    lscr.io/linuxserver/qbittorrent:latest \
    jlesage/jdownloader-2 || true

# Remove media directories
echo "Removing /srv/media directory..."
rm -rf /srv/media

# Remove update script
echo "Removing msi-update command..."
rm -f /usr/local/bin/msi-update

# Remove UFW rules
echo "Removing UFW Jellyfin app and rules..."
rm -f /etc/ufw/applications.d/jellyfin
ufw reload

# Remove SSH tunnel user (prompt for confirmation)
read -p "Remove SSH tunnel user created by installer? (y/N): " deluser
if [[ "$deluser" == "y" || "$deluser" == "Y" ]]; then
    read -p "Enter tunnel username to remove: " tunnel_user
    userdel -r "$tunnel_user" || echo "User $tunnel_user not found or could not be removed."
    # Remove SSH config block for tunnel user
    sed -i "/^Match User $tunnel_user$/,/^$/d" /etc/ssh/sshd_config
    systemctl restart ssh || systemctl restart sshd
fi

# Remove last run log
rm -f /var/log/media-maintenance-last-run.log

echo -e "${GREEN}Uninstall complete. System cleaned up.${NC}"
exit 0