#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────
# Media Server Installer (MSI) for Linux
# Sets up Jellyfin + media stack using Docker
#
# https://github.com/nobikaze/media-server-installer/
# MIT LICENSE
# ─────────────────────────────────────────────────────────────

# Fail fast and be strict in scripts. This makes errors visible and avoids
# many classes of subtle bugs (undefined variables, silent failures).
set -euo pipefail
IFS=$'\n\t'

# ─── Color Codes ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# ─── Spinner Setup ────────────────────────────────────────────
spinner_pid=""

start_spinner() {
  local message="$1"
  local delay=0.1
  local spinstr='-\|/'

  (
    while true; do
      for i in $(seq 0 3); do
        echo -ne "\r\t${YELLOW}[${spinstr:$i:1}]${NC} $message"
        sleep $delay
      done
    done
  ) &
  spinner_pid=$!
  disown
}

stop_spinner() {
  local exit_code=$1
  local message="$2"

  kill "$spinner_pid" &>/dev/null
  wait "$spinner_pid" 2>/dev/null

  if [ "$exit_code" -eq 0 ]; then
    echo -e "\r\t${GREEN}[x]${NC} $message"
  else
    echo -e "\r\t${RED}[!]${NC} $message"
    exit "$exit_code"
  fi
}

# ─── Functions ───────────────────────────────────────────────

print_status()   { start_spinner "$1"; }
print_success()  { stop_spinner 0 "$1                   "; }
abort()          { stop_spinner 1 "$1"; }

pause()          { sleep 0.5; }

require_command() {
    command -v "$1" &>/dev/null || abort "$1 is required but not installed"
}

# ─── Intro ───────────────────────────────────────────────────

ascii_art=(
""
"                           ░██               ░██"
"                                             ░██"
"░█████████████   ░███████  ░██     ░███████  ░████████"
"░██   ░██   ░██ ░██        ░██    ░██        ░██    ░██"
"░██   ░██   ░██  ░███████  ░██     ░███████  ░██    ░██"
"░██   ░██   ░██        ░██ ░██           ░██ ░██    ░██"
"░██   ░██   ░██  ░███████  ░██░██  ░███████  ░██    ░██"
""
"Automates the installation of Jellyfin on a Linux server"
"using Docker and other required tools."
)

animated_echo() {
  local str="$1"
  for (( i=0; i<${#str}; i++ )); do
    echo -ne "${CYAN}${str:$i:1}${NC}"
    sleep $(awk -v min=0 -v max=0.01 'BEGIN{srand(); print min+rand()*(max-min)}')
  done
  echo
}

for line in "${ascii_art[@]}"; do
  animated_echo "${line}"
done

echo ""

# cat << "EOF"

#                            ░██               ░██
#                                              ░██
# ░█████████████   ░███████  ░██     ░███████  ░████████
# ░██   ░██   ░██ ░██        ░██    ░██        ░██    ░██
# ░██   ░██   ░██  ░███████  ░██     ░███████  ░██    ░██
# ░██   ░██   ░██        ░██ ░██           ░██ ░██    ░██
# ░██   ░██   ░██  ░███████  ░██░██  ░███████  ░██    ░██

# Automates the installation of Jellyfin on a Linux server
# using Docker and other required tools.

# EOF

# ─── System Checks ──────────────────────────────────────────

for cmd in apt curl openssl; do
    print_status "Checking $cmd"
    require_command "$cmd"
    pause
    print_success "$cmd is installed"
done

if ! openssl passwd -6 test &>/dev/null; then
  abort "OpenSSL does not support -6 option for password hashing"
fi

[ -f ./msi-update.sh ] || abort "'msi-update.sh' not found in current directory"

print_status "Checking root privileges"
[ "$(id -u)" -eq 0 ] || abort "This script must be run as root"
pause
print_success "Root privileges"

# ─── Configuration ──────────────────────────────────────────

echo "Collecting configuration"
while true; do
  while true; do
    read -r -p "[1/5] Allowed CIDR IP (e.g. 192.168.1.0/24): " cidr
    [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] && break
    echo "❌ Invalid CIDR format. Try again."
  done
  while true; do
    read -r -p "[2/5] Docker username: " docker_user
    [[ "$docker_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && id "$docker_user" &>/dev/null && break
    echo "❌ Invalid or non-existent username. Try again."
  done
  while true; do
    read -r -p "[3/5] Timezone (e.g. America/New_York): " USER_TZ
    if [ -f "/usr/share/zoneinfo/$USER_TZ" ]; then
      break
    else
      echo "❌ Invalid timezone. You can find valid values in /usr/share/zoneinfo/"
    fi
  done
  while true; do
    read -r -p "[4/5] Tunnel user: " tunnel_user
    [[ "$tunnel_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && break
    echo "❌ Invalid username format. Try again."
  done
  while true; do
    read -r -s -p "[4.5/5] Tunnel user password: " tunnel_pass && echo
    [[ ${#tunnel_pass} -ge 6 ]] && break
    echo "❌ Password must be at least 6 characters long."
  done
  read -r -p "[5/5] Optional MOTD path (e.g. /etc/motd): " motd_path

  echo -e "\nConfiguration summary:"
  echo -e "  IP CIDR:         $cidr"
  echo -e "  Docker user:     $docker_user"
  echo -e "  Timezone:        $USER_TZ"
  echo -e "  Tunnel user:     $tunnel_user"
  echo -e "  MOTD path:       $motd_path"

  read -r -p "Proceed? (y/n): " yn
  [[ "$yn" == "y" ]] && break
done

pause
print_success "Configuration complete"

# ─── System Updates ─────────────────────────────────────────

print_status "Updating system"
apt update &>/dev/null && apt upgrade -y &>/dev/null || abort "System update failed"
print_success "System updated"

# ─── UFW Setup ──────────────────────────────────────────────

print_status "Setting up UFW"
apt install -y ufw &>/dev/null
ufw default deny incoming &>/dev/null
ufw default allow outgoing &>/dev/null

cat << EOF > /etc/ufw/applications.d/jellyfin
[Jellyfin]
title=Jellyfin
description=Media Server
ports=8096/tcp
EOF

if ! ufw app info SSH &>/dev/null; then
  ufw limit from "$cidr" to any port 22 proto tcp &>/dev/null
else
  ufw limit from "$cidr" to any app SSH &>/dev/null
fi

ufw allow from "$cidr" to any app Jellyfin &>/dev/null
ufw enable &>/dev/null

ufw status | grep -q "Status: active" || abort "UFW failed to enable"
print_success "UFW configured"

# ─── SSH Setup ──────────────────────────────────────────────

print_status "Installing OpenSSH"
apt install -y openssh-server &>/dev/null

if ! id "$tunnel_user" &>/dev/null; then
  ENCRYPTED_PASS=$(openssl passwd -6 "$tunnel_pass")
  useradd -m -p "$ENCRYPTED_PASS" -s /bin/false "$tunnel_user"
else
  echo "$tunnel_user already exists. Skipping useradd."
fi

if [ ! -d "/home/$tunnel_user" ]; then
  mkdir -p "/home/$tunnel_user"
fi

if [ -f "$motd_path" ]; then
  cp "$motd_path" "/home/$tunnel_user/motd" > /dev/null 2>&1
else
  pause
  echo "Please remember to use system resources responsibly and adhere to all
applicable policies. Unauthorized access to data is strictly prohibited.
Thank you." > "/home/$tunnel_user/motd"
fi

chown "$tunnel_user:$tunnel_user" "/home/$tunnel_user/motd"
chmod 0755 "/home/$tunnel_user"
chmod 0644 "/home/$tunnel_user/motd"

if ! grep -q "Match User $tunnel_user" /etc/ssh/sshd_config; then
  cat << EOF >> /etc/ssh/sshd_config
Match User $tunnel_user
  PermitOpen 127.0.0.1:6767 127.0.0.1:7878 127.0.0.1:8080 127.0.0.1:8989 127.0.0.1:9696 127.0.0.1:5800
  X11Forwarding no
  AllowAgentForwarding no
  ForceCommand /bin/false
  Banner /home/$tunnel_user/motd
  PasswordAuthentication yes
EOF
fi

pause
systemctl restart ssh || systemctl restart sshd

print_success "OpenSSH server configured"

# ─── Docker Installation ───────────────────────────────────

print_status "Installing Docker"
install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc > /dev/null 2>&1
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update > /dev/null 2>&1
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y > /dev/null 2>&1
print_success "Docker installed"

# ─── Docker Setup ──────────────────────────────────────────

print_status "Setting up directories"

SRV_DIR="/srv/media"
CONTAINER_DIR="$SRV_DIR/containers"
LIBRARY_DIR="$SRV_DIR/library"
PUID=$(id -u "$docker_user")
PGID=$(id -g "$docker_user")

mkdir -p "$SRV_DIR"
mkdir -p "$CONTAINER_DIR"/{prowlarr,sonarr,radarr,bazarr,qbittorrent,jdownloader-2,jellyfin}/config \
         "$LIBRARY_DIR"/{movies,shows} \
         "$LIBRARY_DIR"/downloads/jdownloader-2

chown -R "$docker_user:$docker_user" "$SRV_DIR"
chmod -R 755 "$SRV_DIR"
print_success "Directories created"

# ─── Compose File ──────────────────────────────────────────

print_status "Creating docker-compose file"

cat << EOF > "$CONTAINER_DIR/docker-compose.yml"
services:
  # admin-only services

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - "PUID=${PUID}"
      - "PGID=${PGID}"
      - "TZ=${USER_TZ}"
    volumes:
      - ./prowlarr/config:/config
    networks:
      - media_network
    ports:
      - "127.0.0.1:9696:9696"
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - "PUID=${PUID}"
      - "PGID=${PGID}"
      - "TZ=${USER_TZ}"
    volumes:
      - ./sonarr/config:/config
      - "${LIBRARY_DIR}:/media"
    networks:
      - media_network
    ports:
      - "127.0.0.1:8989:8989"
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      - "PUID=${PUID}"
      - "PGID=${PGID}"
      - "TZ=${USER_TZ}"
    volumes:
      - ./radarr/config:/config
      - "${LIBRARY_DIR}:/media"
    networks:
      - media_network
    ports:
      - "127.0.0.1:7878:7878"
    restart: unless-stopped

  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: bazarr
    environment:
      - "PUID=${PUID}"
      - "PGID=${PGID}"
      - "TZ=${USER_TZ}"
    volumes:
      - ./bazarr/config:/config
      - "${LIBRARY_DIR}:/media"
    networks:
      - media_network
    ports:
      - "127.0.0.1:6767:6767"
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - "PUID=${PUID}"
      - "PGID=${PGID}"
      - "TZ=${USER_TZ}"
      - WEBUI_PORT=8080
    volumes:
      - ./qbittorrent/config:/config
      - "${LIBRARY_DIR}:/media"
    networks:
      - media_network
    ports:
      - "127.0.0.1:8080:8080"
    restart: unless-stopped

  # isolated admin-only services

  jdownloader-2:
    image: jlesage/jdownloader-2
    container_name: jdownloader-2
    environment:
      - "USER_ID=${PUID}"
      - "GROUP_ID=${PGID}"
      - "TZ=${USER_TZ}"
    volumes:
      - ./jdownloader-2/config:/config
      - "${LIBRARY_DIR}/downloads/jdownloader-2:/output:rw"
    networks:
      - jd_network
    ports:
      - "127.0.0.1:5800:5800"
    restart: unless-stopped

  # user services

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    environment:
      - "PUID=${PUID}"
      - "PGID=${PGID}"
      - "TZ=${USER_TZ}"
    volumes:
      - ./jellyfin/config:/config
      - type: tmpfs
        target: /cache
        tmpfs:
          size: 128M
      - type: bind
        source: ${LIBRARY_DIR}
        target: /media
        read_only: true
    network_mode: host
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"

networks:
  media_network:
    driver: bridge
  jd_network:
    driver: bridge
EOF

chown "$docker_user:$docker_user" "$CONTAINER_DIR/docker-compose.yml"
print_success "Compose file ready"

# ─── Launch Services ────────────────────────────────────────

print_status "Launching containers"
docker compose -f "$CONTAINER_DIR/docker-compose.yml" pull &>/dev/null || abort "Docker Compose failed to pull images"
docker compose -f "$CONTAINER_DIR/docker-compose.yml" up -d --remove-orphans &>/dev/null || abort "Docker Compose failed to launch containers"
print_success "Media stack up"

# ─── MSI Update Script ──────────────────────────────────────

print_status "Installing 'msi-update' script"
install -m 0755 ./msi-update.sh /usr/local/bin/msi-update
print_success "'msi-update' command installed"

# ─── Final Info ─────────────────────────────────────────────

cat << EOF

To access services via SSH tunnel:
ssh -N \\
  -L 127.0.0.1:6767:127.0.0.1:6767 \\
  -L 127.0.0.1:7878:127.0.0.1:7878 \\
  -L 127.0.0.1:8989:127.0.0.1:8989 \\
  -L 127.0.0.1:9696:127.0.0.1:9696 \\
  -L 127.0.0.1:8080:127.0.0.1:8080 \\
  -L 127.0.0.1:5800:127.0.0.1:5800 \\
  $tunnel_user@your-server-ip

Use 'sudo msi-update' command for updates.

✅ Media server setup complete!
EOF

exit 0
