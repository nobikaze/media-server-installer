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

# https://github.com/nobikaze/media-server-installer/
# MIT LICENSE

# System Maintenance Script

set -e

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
""
"System Maintenance Script"
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

# ─── Variables ───────────────────────────────────────────────

CONTAINERS_DIR="/srv/media/containers"

# ─── System Checks ───────────────────────────────────────────

for cmd in apt docker; do
    print_status "Checking $cmd"
    require_command "$cmd"
    pause
    print_success "$cmd is installed"
done

systemctl is-active --quiet docker || abort "Docker service is not running"

print_status "Checking root privileges"
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi
print_success "Root privileges"

pause

# ─── System Updates ─────────────────────────────────────────

print_status "Updating system"
apt update &>/dev/null && apt upgrade -y &>/dev/null || abort "System update failed"
print_success "System updated"

print_status "Removing unnecessary packages"
apt autoremove --purge -y &>/dev/null
print_success "Unnecessary packages removed"

# ─── Docker compose operations ───────────────────────────────

DOCKER_COMPOSE_FILE="$CONTAINERS_DIR/docker-compose.yml"

print_status "Checking docker-compose.yml"
if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    abort "docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
fi
pause
print_success "docker-compose.yml exists"

print_status "Pulling latest Docker images"
docker compose -f "$DOCKER_COMPOSE_FILE" pull &>/dev/null || abort "Docker Compose failed"
print_success "Latest Docker images pulled"

print_status "Recreating containers with latest images"
docker compose -f "$DOCKER_COMPOSE_FILE" up -d --remove-orphans &>/dev/null || abort "Docker Compose failed"
print_success "Containers with latest images have been recreated"

print_status "Pruning unused Docker images"
docker image prune -f &>/dev/null || abort "Docker Compose failed"
print_success "Unused Docker images have been pruned"

# ─── Final Info ─────────────────────────────────────────────

echo "Docker system maintenance completed successfully."

exit 0