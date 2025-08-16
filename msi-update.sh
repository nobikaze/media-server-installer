#!/bin/bash

# ─── Script Settings and Constants ──────────────────────────
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

# Enable stricter bash settings
set -euo pipefail
IFS=$'\n\t'

# ─── Logging System ──────────────────────────────────────────
readonly LOG_FILE="/var/log/msi/update.log"
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

setup_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" || return 1
    fi

    # Rotate logs if they exceed 10MB
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE") -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi

    # Ensure log file exists and has correct permissions
    touch "$LOG_FILE" || return 1
    chmod 640 "$LOG_FILE" || return 1
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ $level -ge $LOG_LEVEL ]]; then
        case $level in
            $LOG_LEVEL_DEBUG)
                echo -e "${timestamp} [DEBUG] $message" >> "$LOG_FILE"
                ;;
            $LOG_LEVEL_INFO)
                echo -e "${timestamp} [INFO] $message" >> "$LOG_FILE"
                ;;
            $LOG_LEVEL_WARN)
                echo -e "${timestamp} [WARN] $message" >> "$LOG_FILE"
                ;;
            $LOG_LEVEL_ERROR)
                echo -e "${timestamp} [ERROR] $message" >> "$LOG_FILE"
                ;;
        esac
    fi
}

debug() { log $LOG_LEVEL_DEBUG "$1"; }
info() { log $LOG_LEVEL_INFO "$1"; }
warn() { log $LOG_LEVEL_WARN "$1"; }
error() { log $LOG_LEVEL_ERROR "$1"; }

# Initialize logging
if ! setup_logging; then
    echo "Failed to setup logging" >&2
    exit 1
fi

# ─── Error Handling ────────────────────────────────────────
cleanup() {
    local exit_code=$?

    if [[ -n "${spinner_pid:-}" ]]; then
        kill "${spinner_pid}" &>/dev/null || true
        wait "${spinner_pid}" 2>/dev/null || true
        spinner_pid=""
    fi

    # Log final status
    if [[ $exit_code -eq 0 ]]; then
        info "Update completed successfully"
    else
        error "Update failed with exit code $exit_code"
    fi

    exit $exit_code
}

error_handler() {
    local line_num=$1
    local error_code=$2
    local last_cmd=$3

    error "Error occurred in script at line: $line_num"
    error "Command: $last_cmd"
    error "Exit code: $error_code"

    # Attempt recovery based on error type
    case $error_code in
        126|127) # Command not found
            error "Missing required command"
            ;;
        13) # Permission denied
            error "Permission denied - check your privileges"
            ;;
        28) # Operation timed out
            error "Operation timed out - check network connectivity"
            ;;
    esac
}

trap cleanup EXIT
trap 'error_handler ${LINENO} $? "$BASH_COMMAND"' ERR

# Check if running on a supported system
if [ ! -f /etc/os-release ]; then
    echo "This script requires a system with /etc/os-release"
    exit 1
fi

# Source OS release info
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
trap 'if [[ -n "${spinner_pid:-}" ]]; then kill "${spinner_pid}" &>/dev/null || true; wait "${spinner_pid}" 2>/dev/null || true; spinner_pid=""; fi' EXIT

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

# Define critical paths
readonly CONTAINERS_DIR="/srv/media/containers"
readonly DOCKER_COMPOSE_FILE="${CONTAINERS_DIR}/docker-compose.yml"
readonly LAST_RUN_FILE="/var/log/media-maintenance-last-run.log"

# Ensure required paths exist
if [[ ! -d "${CONTAINERS_DIR}" ]]; then
    abort "Container directory ${CONTAINERS_DIR} does not exist"
fi

# ─── System Health Checks ────────────────────────────────────

# System requirements
readonly MIN_DISK_SPACE=5120  # 5GB in MB
readonly MIN_MEMORY=1024      # 1GB in MB
readonly CRITICAL_LOAD=0.9    # 90% CPU load threshold

check_system_health() {
    local result=0
    print_status "Performing system health checks"

    # Check disk space
    local available_space
    available_space=$(df -BM "$CONTAINERS_DIR" | awk 'NR==2 {print $4}' | tr -d 'M')
    if [[ $available_space -lt $MIN_DISK_SPACE ]]; then
        error "Low disk space: ${available_space}MB available (minimum ${MIN_DISK_SPACE}MB required)"
        ((result++))
    fi

    # Check memory
    local available_memory
    available_memory=$(free -m | awk '/^Mem:/ {print $7}')
    if [[ $available_memory -lt $MIN_MEMORY ]]; then
        error "Low memory: ${available_memory}MB available (minimum ${MIN_MEMORY}MB required)"
        ((result++))
    fi

    # Check system load
    local cpu_cores
    local load_1min
    cpu_cores=$(nproc)
    load_1min=$(awk '{print $1}' /proc/loadavg)
    if awk -v load="$load_1min" -v cores="$cpu_cores" -v thresh="$CRITICAL_LOAD" \
        'BEGIN {exit !(load/cores > thresh)}'; then
        warn "High system load: $load_1min (${cpu_cores} cores available)"
    fi

    # Check Docker system status
    if ! docker info &>/dev/null; then
        error "Docker system is not responding"
        ((result++))
    fi

    # Check container status
    local running_containers
    running_containers=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps --services --filter "status=running" 2>/dev/null | wc -l)
    local total_containers
    total_containers=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps --services 2>/dev/null | wc -l)

    if [[ $running_containers -lt $total_containers ]]; then
        error "Not all containers are running ($running_containers/$total_containers)"
        ((result++))
    fi

    return $result
}

# ─── Basic System Checks ────────────────────────────────────

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

# ─── Resource Cleanup ───────────────────────────────────────

# Resource limits and thresholds
readonly MAX_LOG_SIZE_MB=500
readonly MAX_BACKUP_AGE_DAYS=30
readonly MIN_FREE_SPACE_PERCENT=15
readonly MAX_DOCKER_CACHE_GB=10

cleanup_system_resources() {
    local result=0
    print_status "Performing system resource cleanup"

    # Clean up old log files
    find /var/log -type f -name "*.gz" -o -name "*.old" -mtime +7 -delete 2>/dev/null || warn "Failed to clean old logs"

    # Rotate large log files
    find /var/log -type f -size +100M | while read -r log_file; do
        if [[ -w "$log_file" ]]; then
            savelog -n -c 5 "$log_file" 2>/dev/null || warn "Failed to rotate $log_file"
        fi
    done

    # Clean up old backups
    local backup_path="/srv/media/containers/jellyfin/config"
    if [[ -d "$backup_path" ]]; then
        find "$backup_path" -name "backup_*.tar.gz" -mtime +${MAX_BACKUP_AGE_DAYS} -delete 2>/dev/null ||
            warn "Failed to clean old backups"
    fi

    # Clean up Docker resources
    cleanup_docker_resources || ((result++))

    # Clean up temporary files
    cleanup_temp_files || ((result++))

    # Clean up journald logs
    if command -v journalctl &>/dev/null; then
        journalctl --vacuum-time=7d --vacuum-size=1G &>/dev/null ||
            warn "Failed to clean journald logs"
    fi

    return $result
}

cleanup_docker_resources() {
    print_status "Cleaning Docker resources"
    local result=0

    # Remove unused containers
    docker container prune -f --filter "until=168h" &>/dev/null || ((result++))

    # Remove unused volumes
    docker volume prune -f --filter "all=true" &>/dev/null || ((result++))

    # Remove old images (keep last 2 versions)
    local images
    images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" || true)
    if [[ -n "$images" ]]; then
        echo "$images" | while read -r image; do
            local count
            count=$(docker images "$image" --format "{{.ID}}" | wc -l)
            if [[ $count -gt 2 ]]; then
                docker images "$image" --format "{{.ID}}" | tail -n +3 |
                    xargs -r docker rmi &>/dev/null || warn "Failed to remove old images for $image"
            fi
        done
    fi

    # Clean up build cache
    docker builder prune -f --keep-storage "${MAX_DOCKER_CACHE_GB}gb" &>/dev/null || ((result++))

    # Remove orphaned volumes
    docker volume ls -qf dangling=true | xargs -r docker volume rm &>/dev/null || ((result++))

    return $result
}

cleanup_temp_files() {
    print_status "Cleaning temporary files"
    local result=0

    # Clean /tmp files older than 7 days
    find /tmp -type f -atime +7 -delete 2>/dev/null || ((result++))

    # Clean empty directories in /tmp
    find /tmp -type d -empty -delete 2>/dev/null || true

    # Clean package manager cache
    if command -v apt-get &>/dev/null; then
        apt-get clean &>/dev/null || ((result++))
        apt-get autoremove -y &>/dev/null || ((result++))
    fi

    return $result
}

monitor_disk_usage() {
    local path="$1"
    local usage
    usage=$(df -h "$path" | awk 'NR==2 {print $5}' | tr -d '%')

    if [[ $usage -gt $((100 - MIN_FREE_SPACE_PERCENT)) ]]; then
        warn "Low disk space on $path: $usage% used"
        cleanup_system_resources

        # Check if cleanup helped
        usage=$(df -h "$path" | awk 'NR==2 {print $5}' | tr -d '%')
        if [[ $usage -gt $((100 - MIN_FREE_SPACE_PERCENT)) ]]; then
            error "Disk space is still critically low after cleanup"
            return 1
        fi
    fi
    return 0
}

# ─── Docker Operations ──────────────────────────────────────

readonly MAX_RETRIES=3
readonly RETRY_DELAY=5

docker_compose_operation() {
    local operation="$1"
    local description="$2"
    shift 2
    local retry_count=0

    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        print_status "$description (attempt $((retry_count + 1))/$MAX_RETRIES)"

        if docker compose -f "$DOCKER_COMPOSE_FILE" "$operation" "$@" &>/dev/null; then
            print_success "$description completed"
            return 0
        fi

        ((retry_count++))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            warn "Operation failed, retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        fi
    done

    abort "$description failed after $MAX_RETRIES attempts"
    return 1
}

verify_docker_compose() {
    print_status "Verifying Docker Compose configuration"

    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        abort "docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
        return 1
    fi

    # Check file permissions
    local file_perms
    file_perms=$(stat -c "%a" "$DOCKER_COMPOSE_FILE")
    if [[ "$file_perms" != "644" ]]; then
        warn "Incorrect permissions on docker-compose.yml (found: $file_perms, expected: 644)"
        chmod 644 "$DOCKER_COMPOSE_FILE" || abort "Failed to set correct permissions"
    fi

    # Validate configuration
    if ! docker compose -f "$DOCKER_COMPOSE_FILE" config --quiet &>/dev/null; then
        abort "Invalid docker-compose.yml configuration"
        return 1
    fi

    print_success "Docker Compose configuration verified"
    return 0
}

update_containers() {
    # Pull latest images
    docker_compose_operation "pull" "Pulling latest Docker images" || return 1

    # Stop containers gracefully
    docker_compose_operation "stop" "Stopping containers" --timeout 30 || return 1

    # Start containers with new images
    docker_compose_operation "up" "Starting containers with latest images" -d --remove-orphans || return 1

    # Cleanup
    print_status "Cleaning up old images"
    if ! docker image prune -f &>/dev/null; then
        warn "Failed to clean up old images"
    fi
    print_success "Container update completed"
}

# ─── Docker Compose Operations ───────────────────────────────

verify_docker_compose
print_status "Beginning Docker operations"
if [[ ! -f "${DOCKER_COMPOSE_FILE}" ]]; then
    abort "docker-compose.yml not found at ${DOCKER_COMPOSE_FILE}"
fi

# Validate docker-compose file
if ! docker compose -f "${DOCKER_COMPOSE_FILE}" config --quiet &>/dev/null; then
    abort "Invalid docker-compose.yml configuration"
fi
pause
print_success "docker-compose.yml exists and is valid"

# Check disk space and perform cleanup if needed
monitor_disk_usage "$CONTAINERS_DIR" || {
    if [[ -z "${FORCE_UPDATE:-}" ]]; then
        abort "Critical disk space issue. Clean up disk space or use FORCE_UPDATE=1 to override."
    else
        warn "Proceeding with low disk space (FORCE_UPDATE is set)"
    fi
}

# Perform initial resource cleanup
print_status "Performing initial resource cleanup"
cleanup_system_resources
print_success "Initial cleanup completed"

# Perform system health check
if ! check_system_health; then
    if [[ -z "${FORCE_UPDATE:-}" ]]; then
        abort "System health check failed. Use FORCE_UPDATE=1 to override."
    else
        warn "Proceeding with update despite health check failure (FORCE_UPDATE is set)"
    fi
fi

# Create backup before update
print_status "Creating backup snapshot"
backup_timestamp=$(date +%Y%m%d_%H%M%S)
if ! docker compose -f "$DOCKER_COMPOSE_FILE" exec -T jellyfin tar czf "/config/backup_${backup_timestamp}.tar.gz" /config &>/dev/null; then
    warn "Failed to create backup snapshot"
else
    print_success "Backup created at /config/backup_${backup_timestamp}.tar.gz"
fi

# Perform the update
if ! update_containers; then
    if [[ -n "$backup_timestamp" ]]; then
        error "Update failed. Backup is available at /config/backup_${backup_timestamp}.tar.gz"
    else
        error "Update failed and no backup was created"
    fi
    exit 1
fi

# Verify services after update
print_status "Verifying services"
sleep 10  # Give services time to initialize

if ! check_system_health; then
    warn "Post-update health check shows issues"
fi

# Perform final cleanup
print_status "Performing post-update cleanup"

# Remove old backups keeping only the last 5
find "$CONTAINERS_DIR" -name "backup_*.tar.gz" -type f | sort -r | tail -n +6 | xargs -r rm 2>/dev/null ||
    warn "Failed to clean old backups"

# Final resource cleanup
cleanup_system_resources

# Report final disk usage
print_status "Checking final disk usage"
df -h "$CONTAINERS_DIR" | awk 'NR==2 {printf "Final disk usage: %s of %s (%s used)\n", $3, $2, $5}' || true

print_success "Post-update cleanup completed"

# ─── Final Info ─────────────────────────────────────────────

echo "Docker system maintenance completed successfully."

# Update last run timestamp with proper permissions
(
    umask 022
    if ! date '+%Y-%m-%d %H:%M:%S' > "${LAST_RUN_FILE}.tmp"; then
        abort "Failed to write timestamp"
    fi
    if ! mv "${LAST_RUN_FILE}.tmp" "${LAST_RUN_FILE}"; then
        rm -f "${LAST_RUN_FILE}.tmp"
        abort "Failed to update last run file"
    fi
    if ! chown root:root "${LAST_RUN_FILE}"; then
        abort "Failed to set ownership of last run file"
    fi
    if ! chmod 644 "${LAST_RUN_FILE}"; then
        abort "Failed to set permissions of last run file"
    fi
)

pause

exit 0