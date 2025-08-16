#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}WARNING: This will REMOVE all media server containers, config, users, firewall rules, and packages installed by msi.sh!${NC}"
read -p "Are you sure you want to continue? (y/N): " confirm
[[ "$confirm" == "y" || "$confirm" == "Y" ]] || exit 1

# Stop and remove containers and volumes
if [ -f /srv/media/containers/docker-compose.yml ]; then
    echo "Stopping and removing containers and volumes..."
    docker compose -f /srv/media/containers/docker-compose.yml down --volumes --remove-orphans
fi

# Remove Docker images
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

# Remove last run log
rm -f /var/log/media-maintenance-last-run.log

# Remove UFW Jellyfin app and rules
echo "Removing UFW Jellyfin app and rules..."
rm -f /etc/ufw/applications.d/jellyfin
ufw delete allow 8096/tcp || true
ufw reload || true

# Optionally disable UFW if it was enabled by the installer
if ufw status | grep -q "Status: active"; then
    read -p "Disable UFW firewall? (y/N): " disable_ufw
    if [[ "$disable_ufw" == "y" || "$disable_ufw" == "Y" ]]; then
        ufw disable
    fi
fi

# Remove SSH tunnel user and SSH config block
read -p "Remove SSH tunnel user created by installer? (y/N): " deluser
if [[ "$deluser" == "y" || "$deluser" == "Y" ]]; then
    read -p "Enter tunnel username to remove: " tunnel_user
    userdel -r "$tunnel_user" || echo "User $tunnel_user not found or could not be removed."
    # Remove SSH config block for tunnel user
    sed -i "/^Match User $tunnel_user$/,/^$/d" /etc/ssh/sshd_config
    systemctl restart ssh || systemctl restart sshd
fi

# Remove Docker repository and GPG key
echo "Removing Docker repository and GPG key..."
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.asc

# Optionally uninstall Docker, UFW, and OpenSSH
read -p "Uninstall Docker, UFW, and OpenSSH packages? (y/N): " remove_pkgs
if [[ "$remove_pkgs" == "y" || "$remove_pkgs" == "Y" ]]; then
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ufw openssh-server
    apt-get autoremove -y
fi

echo -e "${GREEN}Uninstall complete. System cleaned up.${NC}"
exit 0