#!/bin/bash

# Check if running on a supported system
if [ ! -f /etc/os-release ]; then
    echo "This script requires a system with /etc/os-release"
    exit 1
fi

. /etc/os-release
if [[ ! "$ID" =~ ^(debian|ubuntu)$ ]]; then
    echo "This script is only supported on Debian/Ubuntu systems"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi

# Check for Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "Docker Compose is not installed"
    exit 1
fi

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
      for ((i=0; i<${#spinstr}; i++)); do
        echo -ne "\r\t${YELLOW}[${spinstr:$i:1}]${NC} $message"
        sleep "$delay"
      done
    done
  ) &
  spinner_pid=$!
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

# Clean up spinner if script exits or is interrupted
trap '[[ -n "$spinner_pid" ]] && kill "$spinner_pid" &>/dev/null' EXIT

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
LAST_RUN_FILE="/var/log/media-maintenance-last-run.log"

# ─── System Checks ───────────────────────────────────────────

for cmd in apt docker; do
  print_status "Checking $cmd"
  require_command "$cmd"
  pause
  print_success "$cmd is installed"
done

print_status "Checking Docker service"
systemctl is-active --quiet docker || abort "Docker service is not running"
print_success "Docker service is running"

print_status "Checking root privileges"
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Use sudo."
   exit 1
fi
print_success "Root privileges"

pause

print_status "Checking date -d support"
if ! date -d "2020-01-01" &>/dev/null; then
    abort "'date -d' is not supported on this system. Install GNU coreutils or use a compatible Linux distribution."
fi
print_success "date -d is supported"
pause

print_status "Checking last run timestamp"
if [[ -f "$LAST_RUN_FILE" ]]; then
    LAST_RUN=$(cat "$LAST_RUN_FILE")
    LAST_RUN_EPOCH=$(date -d "$LAST_RUN" +%s)
    NOW_EPOCH=$(date +%s)
    DIFF_SEC=$((NOW_EPOCH - LAST_RUN_EPOCH))

    if (( DIFF_SEC < 60 )); then
        VALUE=$DIFF_SEC
        UNIT="second"
    elif (( DIFF_SEC < 3600 )); then
        VALUE=$((DIFF_SEC / 60))
        UNIT="minute"
    elif (( DIFF_SEC < 86400 )); then
        VALUE=$((DIFF_SEC / 3600))
        UNIT="hour"
    else
        VALUE=$((DIFF_SEC / 86400))
        UNIT="day"
    fi

    # Pluralize if needed
    if (( VALUE != 1 )); then
        UNIT="${UNIT}s"
    fi

    DELTA="$VALUE $UNIT ago"
    print_success "Last run: $LAST_RUN ($DELTA)"
else
    print_success "No previous run recorded"
fi
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

if [[ ! -f "$LAST_RUN_FILE" ]]; then
    touch "$LAST_RUN_FILE"
    chown root:root "$LAST_RUN_FILE"
    chmod 644 "$LAST_RUN_FILE"
fi

date '+%Y-%m-%d %H:%M:%S' > "$LAST_RUN_FILE"

pause

exit 0