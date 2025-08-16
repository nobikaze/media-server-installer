#!/usr/bin/env bash

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Media Server Installer (MSI) for Linux
Sets up Jellyfin + media stack using Docker

Options:
    -h, --help              Show this help message
    -v, --version          Show version information
    -d, --debug            Enable debug logging
    -b, --backup           Create a backup before installation
    -r, --restore FILE     Restore from backup file
    --skip-docker          Skip Docker installation
    --unattended          Run in unattended mode with defaults

Examples:
    $(basename "$0")              # Normal installation
    $(basename "$0") --debug      # Installation with debug logging
    $(basename "$0") --backup     # Installation with backup

For more information, visit:
https://github.com/nobikaze/media-server-installer/
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -v|--version)
            echo "Media Server Installer v${SCRIPT_VERSION}"
            exit 0
            ;;
        -d|--debug)
            LOG_LEVEL=$LOG_LEVEL_DEBUG
            shift
            ;;
        -b|--backup)
            DO_BACKUP=1
            shift
            ;;
        -r|--restore)
            RESTORE_FILE="$2"
            shift 2
            ;;
        --skip-docker)
            SKIP_DOCKER=1
            shift
            ;;
        --unattended)
            UNATTENDED=1
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────
# Media Server Installer (MSI) for Linux
# Sets up Jellyfin + media stack using Docker
#
# Version:     1.0.0
# Author:      nobikaze
# Repository:  https://github.com/nobikaze/media-server-installer/
# License:     MIT
#
# Dependencies:
#   - bash (>= 4.0)
#   - docker (>= 20.10)
#   - systemd
#   - curl
#   - openssl
# ─────────────────────────────────────────────────────────────

# ─── Script Settings ────────────────────────────────────────
# Fail fast and be strict in scripts
set -euo pipefail
IFS=$'\n\t'

# ─── Constants ────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
readonly MIN_BASH_VERSION="4.0"
readonly MIN_DOCKER_VERSION="20.10"
readonly REQUIRED_COMMANDS=(apt curl openssl awk id useradd systemctl)
readonly DEFAULT_TIMEZONE="UTC"
readonly MIN_PASSWORD_LENGTH=6

# ─── Directories ──────────────────────────────────────────────
readonly BASE_DIR="/srv/media"
readonly CONTAINER_DIR="${BASE_DIR}/containers"
readonly LIBRARY_DIR="${BASE_DIR}/library"
readonly DOCKER_COMPOSE_FILE="${CONTAINER_DIR}/docker-compose.yml"

# ─── Color Codes and Logging ─────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[1;36m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ $level -ge $LOG_LEVEL ]]; then
        case $level in
            $LOG_LEVEL_DEBUG)
                echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" >&2
                ;;
            $LOG_LEVEL_INFO)
                echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" >&2
                ;;
            $LOG_LEVEL_WARN)
                echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" >&2
                ;;
            $LOG_LEVEL_ERROR)
                echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" >&2
                ;;
        esac
    fi
}

debug() { log $LOG_LEVEL_DEBUG "$1"; }
info() { log $LOG_LEVEL_INFO "$1"; }
warn() { log $LOG_LEVEL_WARN "$1"; }
error() { log $LOG_LEVEL_ERROR "$1"; }

# ─── Spinner Setup ────────────────────────────────────────────
spinner_pid=""

start_spinner() {
    local message="${1:-}"
    local delay=0.1
    local spinstr='-\|/'
    local temp_pid

    (
        trap 'exit 0' SIGTERM
        while :; do
            for ((i=0; i<${#spinstr}; i++)); do
                printf "\r\t${YELLOW}[%c]${NC} %s" "${spinstr:$i:1}" "$message"
                sleep "$delay"
            done
        done
    ) &
    temp_pid=$!
    # Avoid race condition by declaring after subprocess starts
    spinner_pid=$temp_pid
    disown
}

stop_spinner() {
  local exit_code=$1
  local message="$2"

  if [[ -n "$spinner_pid" ]]; then
    kill "$spinner_pid" &>/dev/null
    wait "$spinner_pid" 2>/dev/null || true
    spinner_pid=""
  fi

  # Clear spinner line before printing final status
  echo -ne "\r\033[K"

  if [ "$exit_code" -eq 0 ]; then
    echo -e "\t${GREEN}[x]${NC} $message"
  else
    echo -e "\t${RED}[!]${NC} $message"
    exit "$exit_code"
  fi
}

# ─── Backup Functions ────────────────────────────────────────

create_backup() {
    local backup_dir="/var/backups/msi"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/msi_backup_${timestamp}.tar.gz"

    print_status "Creating backup"

    # Ensure backup directory exists
    mkdir -p "$backup_dir"

    # Create backup of configuration and important directories
    tar -czf "$backup_file" \
        -C "$(dirname "$CONTAINER_DIR")" "$(basename "$CONTAINER_DIR")" \
        /etc/msi \
        2>/dev/null || {
        abort "Failed to create backup"
        return 1
    }

    print_success "Backup created at $backup_file"
    return 0
}

restore_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        abort "Backup file not found: $backup_file"
        return 1
    }

    print_status "Restoring from backup"

    # Stop running containers
    docker compose -f "$DOCKER_COMPOSE_FILE" down 2>/dev/null || true

    # Restore backup
    tar -xzf "$backup_file" -C / || {
        abort "Failed to restore backup"
        return 1
    }

    print_success "Backup restored from $backup_file"
    return 0
}

# ─── Error Handling ────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ -n "${spinner_pid:-}" ]]; then
        kill "${spinner_pid}" &>/dev/null || true
        wait "${spinner_pid}" 2>/dev/null || true
        spinner_pid=""
    fi
    # Additional cleanup tasks can be added here
    exit $exit_code
}

error_handler() {
    local line_num=$1
    local error_code=$2
    local last_cmd=$3
    echo -e "\n${RED}Error occurred in script at line: ${line_num}${NC}"
    echo -e "${RED}Last command executed: ${last_cmd}${NC}"
    echo -e "${RED}Exit code: ${error_code}${NC}"
    exit $error_code
}

trap cleanup EXIT
trap 'error_handler ${LINENO} $? "$BASH_COMMAND"' ERR

# ─── Functions ───────────────────────────────────────────────

# Logging and status functions
print_status() {
    local message="$1"
    start_spinner "$message"
}

print_success() {
    local message="$1"
    stop_spinner 0 "$message                   "
}

abort() {
    local message="$1"
    stop_spinner 1 "$message"
}

pause() {
    sleep 0.5
}

# Command validation function
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        abort "$cmd is required but not installed"
        return 1
    fi
    return 0
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

for cmd in apt curl openssl awk id useradd systemctl; do
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

# ─── System Validation Functions ────────────────────────────

check_bash_version() {
    local current_version
    current_version=$(bash --version | head -n1 | cut -d' ' -f4 | cut -d'.' -f1-2)
    if ! awk -v v1="$current_version" -v v2="$MIN_BASH_VERSION" 'BEGIN{exit !(v1 >= v2)}'; then
        abort "Bash version $MIN_BASH_VERSION or higher is required (current: $current_version)"
    fi
}

check_docker_version() {
    if command -v docker &>/dev/null; then
        local current_version
        current_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null | cut -d'.' -f1-2)
        if ! awk -v v1="$current_version" -v v2="$MIN_DOCKER_VERSION" 'BEGIN{exit !(v1 >= v2)}'; then
            abort "Docker version $MIN_DOCKER_VERSION or higher is required (current: $current_version)"
        fi
    fi
}

check_system_requirements() {
    print_status "Checking system requirements"
    check_bash_version

    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        require_command "$cmd"
    done

    if ! openssl passwd -6 test &>/dev/null; then
        abort "OpenSSL does not support -6 option for password hashing"
    fi
    print_success "System requirements met"
}

# ─── Configuration Management ─────────────────────────────────

# Configuration defaults
declare -A DEFAULT_CONFIG=(
    ["cidr"]="192.168.1.0/24"
    ["USER_TZ"]="$DEFAULT_TIMEZONE"
    ["motd_path"]="/etc/motd"
)

save_config() {
    local config_file="/etc/msi/config"
    local config_dir="/etc/msi"

    mkdir -p "$config_dir"

    {
        echo "# Media Server Installer Configuration"
        echo "# Generated on: $(date)"
        echo "# Version: $SCRIPT_VERSION"
        echo
        for key in "${!config[@]}"; do
            echo "${key}=${config[$key]}"
        done
    } > "$config_file"

    chmod 600 "$config_file"
    debug "Configuration saved to $config_file"
}

load_config() {
    local config_file="/etc/msi/config"

    if [[ -f "$config_file" ]]; then
        debug "Loading configuration from $config_file"
        while IFS='=' read -r key value; do
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            config["$key"]="$value"
        done < "$config_file"
    else
        debug "No existing configuration found"
        # Load defaults
        for key in "${!DEFAULT_CONFIG[@]}"; do
            config["$key"]="${DEFAULT_CONFIG[$key]}"
        done
    fi
}

# ─── Input Validation Functions ──────────────────────────────

validate_cidr() {
    local cidr="$1"
    [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]
}

validate_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]
}

validate_timezone() {
    local tz="$1"
    [[ -f "/usr/share/zoneinfo/$tz" ]] && \
    [[ "$tz" =~ ^[A-Za-z]+/[A-Za-z_-]+$ ]] && \
    TZ="$tz" date > /dev/null 2>&1
}

validate_password() {
    local pass="$1"
    [[ ${#pass} -ge 6 ]]
}

# ─── Configuration ──────────────────────────────────────────

echo -e "\n${CYAN}Collecting configuration${NC}"
declare -A config

collect_input() {
    local prompt="$1"
    local var_name="$2"
    local validator="$3"
    local error_msg="$4"
    local silent="${5:-false}"
    local input

    while true; do
        if [[ "$silent" == "true" ]]; then
            read -r -s -p "$prompt" input && echo
        else
            read -r -p "$prompt" input
        fi

        if [[ -n "$validator" ]] && ! $validator "$input"; then
            echo -e "${RED}$error_msg${NC}"
            continue
        fi

        config[$var_name]="$input"
        break
    done
}

while true; do
    collect_input \
        "[1/5] Allowed CIDR IP (e.g. 192.168.1.0/24): " \
        "cidr" \
        validate_cidr \
        "❌ Invalid CIDR format. Try again."

    collect_input \
        "[2/5] Docker username: " \
        "docker_user" \
        validate_username \
        "❌ Invalid username format. Try again."

    # Additional check for existing user
    if ! id "${config[docker_user]}" &>/dev/null; then
        echo -e "${RED}❌ User does not exist${NC}"
        continue
    fi

    collect_input \
        "[3/5] Timezone (e.g. America/New_York): " \
        "USER_TZ" \
        validate_timezone \
        "❌ Invalid timezone. Format should be Region/City (e.g. America/New_York, Europe/London)
   You can find valid values in /usr/share/zoneinfo/"

    collect_input \
        "[4/5] Tunnel user: " \
        "tunnel_user" \
        validate_username \
        "❌ Invalid username format. Try again."

    collect_input \
        "[4.5/5] Tunnel user password: " \
        "tunnel_pass" \
        validate_password \
        "❌ Password must be at least 6 characters long." \
        "true"
    collect_input \
        "[5/5] Optional MOTD path (e.g. /etc/motd): " \
        "motd_path"

    echo -e "\n${CYAN}Configuration summary:${NC}"
    echo -e "  IP CIDR:         ${config[cidr]}"
    echo -e "  Docker user:     ${config[docker_user]}"
    echo -e "  Timezone:        ${config[USER_TZ]}"
    echo -e "  Tunnel user:     ${config[tunnel_user]}"
    echo -e "  MOTD path:       ${config[motd_path]:-None}"

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

# ─── Docker Functions ────────────────────────────────────────

setup_docker_repository() {
    local os_id="$1"
    local os_codename="$2"
    local repo_base="https://download.docker.com/linux/${os_id}"

    print_status "Setting up Docker repository"

    # Create keyrings directory
    install -m 0755 -d /etc/apt/keyrings

    # Download and verify Docker's GPG key
    if ! curl -fsSL "${repo_base}/gpg" -o /etc/apt/keyrings/docker.asc; then
        abort "Failed to download Docker GPG key"
    fi
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${repo_base} \
    ${os_codename} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_success "Docker repository configured"
}

install_docker_packages() {
    print_status "Installing Docker packages"

    if ! apt update > /dev/null 2>&1; then
        abort "Failed to update package list"
    fi

    local packages=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )

    if ! apt install "${packages[@]}" -y > /dev/null 2>&1; then
        abort "Failed to install Docker packages"
    fi

    print_success "Docker packages installed"
}

verify_docker_installation() {
    print_status "Verifying Docker installation"

    if ! docker --version > /dev/null 2>&1; then
        abort "Docker installation failed"
    fi

    if ! docker compose version > /dev/null 2>&1; then
        abort "Docker Compose installation failed"
    fi

    print_success "Docker verified successfully"
}

# ─── Docker Installation ───────────────────────────────────

print_status "Installing Docker"

# Determine OS for Docker repository
. /etc/os-release
if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
    abort "This script only supports Debian or Ubuntu"
fi

DOCKER_REPO_BASE="https://download.docker.com/linux/${ID}"

# Set up Docker repository
install -m 0755 -d /etc/apt/keyrings > /dev/null 2>&1
curl -fsSL "${DOCKER_REPO_BASE}/gpg" -o /etc/apt/keyrings/docker.asc || abort "Failed to download Docker GPG key"
chmod a+r /etc/apt/keyrings/docker.asc > /dev/null 2>&1

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_REPO_BASE} \
  ${VERSION_CODENAME} stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null || abort "Failed to add Docker repository"

# Install Docker
apt update > /dev/null 2>&1 || abort "Failed to update package list"
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y > /dev/null 2>&1 || abort "Failed to install Docker"

# Verify Docker installation
if ! docker --version > /dev/null 2>&1; then
    abort "Docker installation failed"
fi

if ! docker compose version > /dev/null 2>&1; then
    abort "Docker Compose installation failed"
fi

print_success "Docker installed"

# ─── Directory Management Functions ──────────────────────────

create_service_directories() {
    local user="$1"
    local puid
    local pgid

    print_status "Creating service directories"

    puid=$(id -u "$user")
    pgid=$(id -g "$user")

    # Create main directories
    mkdir -p "$BASE_DIR"

    # Create container config directories
    local container_dirs=(
        prowlarr
        sonarr
        radarr
        bazarr
        qbittorrent
        jdownloader-2
        jellyfin
    )

    for dir in "${container_dirs[@]}"; do
        mkdir -p "${CONTAINER_DIR}/${dir}/config"
    done

    # Create library directories
    mkdir -p "${LIBRARY_DIR}"/{movies,shows}
    mkdir -p "${LIBRARY_DIR}/downloads/jdownloader-2"

    # Set permissions
    chown -R "${user}:${user}" "$BASE_DIR"
    chmod -R 755 "$BASE_DIR"

    print_success "Service directories created"
    return 0
}

# ─── Docker Setup ──────────────────────────────────────────

create_service_directories "${config[docker_user]}"
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

# ─── Health Check Functions ─────────────────────────────────

check_container_health() {
    local container_name="$1"
    local max_attempts=${2:-30}
    local delay=${3:-2}
    local attempt=1

    print_status "Checking health of $container_name"

    while [[ $attempt -le $max_attempts ]]; do
        if docker container inspect "$container_name" &>/dev/null; then
            local status
            status=$(docker container inspect --format '{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")

            case "$status" in
                "healthy")
                    print_success "$container_name is healthy"
                    return 0
                    ;;
                "unhealthy")
                    abort "$container_name is unhealthy"
                    return 1
                    ;;
                "none")
                    # Container has no health check, check if it's running
                    if docker container inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null | grep -q "true"; then
                        print_success "$container_name is running"
                        return 0
                    fi
                    ;;
            esac
        fi

        debug "Waiting for $container_name (attempt $attempt/$max_attempts)"
        sleep "$delay"
        ((attempt++))
    done

    abort "Timeout waiting for $container_name to be healthy"
    return 1
}

verify_services() {
    print_status "Verifying all services"

    local services=(
        "jellyfin"
        "prowlarr"
        "sonarr"
        "radarr"
        "bazarr"
        "qbittorrent"
        "jdownloader-2"
    )

    for service in "${services[@]}"; do
        check_container_health "$service"
    done

    print_success "All services verified"
}

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
