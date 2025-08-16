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

# ─── Transaction Management ─────────────────────────────────
readonly TRANSACTION_LOG="/var/log/msi/transactions.log"
declare -i TRANSACTION_ID
declare -A TRANSACTION_STEPS=()
declare CURRENT_STEP=""

begin_transaction() {
    local description="$1"
    TRANSACTION_ID=$(date +%s)
    mkdir -p "$(dirname "$TRANSACTION_LOG")"
    echo "BEGIN TRANSACTION $TRANSACTION_ID: $description" >> "$TRANSACTION_LOG"
    debug "Started transaction $TRANSACTION_ID: $description"
}

commit_transaction() {
    echo "COMMIT TRANSACTION $TRANSACTION_ID" >> "$TRANSACTION_LOG"
    debug "Committed transaction $TRANSACTION_ID"
    TRANSACTION_ID=0
    TRANSACTION_STEPS=()
}

rollback_transaction() {
    local reason="$1"
    echo "ROLLBACK TRANSACTION $TRANSACTION_ID: $reason" >> "$TRANSACTION_LOG"
    error "Rolling back transaction $TRANSACTION_ID: $reason"

    # Execute registered rollback commands
    execute_rollback "Transaction rollback: $reason"

    TRANSACTION_ID=0
    TRANSACTION_STEPS=()
}

add_step() {
    local step="$1"
    local rollback_cmd="$2"

    CURRENT_STEP="$step"
    TRANSACTION_STEPS["$step"]=1
    echo "STEP $TRANSACTION_ID: $step" >> "$TRANSACTION_LOG"

    if [[ -n "$rollback_cmd" ]]; then
        register_rollback "$rollback_cmd"
    fi
}

# ─── Constants ────────────────────────────────────────────────
readonly SCRIPT_VERSION="1.0.0"

# ─── Network Validation Functions ─────────────────────────────

# Essential domains for the media server
readonly -a REQUIRED_DOMAINS=(
    "docker.io"
    "registry-1.docker.io"
    "auth.docker.io"
    "production.cloudflare.docker.com"
    "download.docker.com"
    "raw.githubusercontent.com"
    "github.com"
)

validate_network_connectivity() {
    local result=0
    print_status "Validating network connectivity"

    # Check basic internet connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        error "No internet connectivity detected"
        return 1
    }

    # Check DNS resolution
    if ! nslookup google.com &>/dev/null; then
        error "DNS resolution failure"
        return 1
    }

    # Check required domains
    for domain in "${REQUIRED_DOMAINS[@]}"; do
        if ! timeout 5 bash -c "echo > /dev/tcp/${domain}/443" 2>/dev/null; then
            error "Cannot connect to required domain: ${domain}"
            ((result++))
        fi
    done

    # Check proxy settings if configured
    if [[ -n "${http_proxy:-}" ]] || [[ -n "${https_proxy:-}" ]]; then
        debug "Proxy detected, validating proxy connectivity"
        local proxy_url
        proxy_url="${https_proxy:-${http_proxy}}"
        proxy_url="${proxy_url#*://}"
        proxy_host="${proxy_url%:*}"
        proxy_port="${proxy_url##*:}"

        if ! timeout 5 bash -c "echo > /dev/tcp/${proxy_host}/${proxy_port}" 2>/dev/null; then
            error "Cannot connect to proxy: ${proxy_host}:${proxy_port}"
            ((result++))
        fi
    fi

    # Check firewall status and required ports
    if command -v ufw &>/dev/null; then
        if ! ufw status | grep -q "Status: active"; then
            warn "UFW firewall is not active"
        fi
        for port in "${REQUIRED_PORTS[@]}"; do
            if ! ufw status | grep -qE "^$port/tcp.*ALLOW"; then
                warn "Port $port is not explicitly allowed in UFW"
            fi
        done
    fi

    # Validate network interface configuration
    local default_interface
    default_interface=$(ip route | awk '/default/ {print $5}' | head -n1)
    if [[ -z "$default_interface" ]]; then
        error "No default network interface found"
        ((result++))
    else
        # Check interface status
        if ! ip link show "$default_interface" | grep -q "UP"; then
            error "Default interface $default_interface is down"
            ((result++))
        fi
        # Check for valid IP address
        if ! ip addr show "$default_interface" | grep -qE "inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+"; then
            error "No valid IP address configured on $default_interface"
            ((result++))
        fi
    fi

    return $result
}
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

# ─── Rollback System ─────────────────────────────────────────

declare -a ROLLBACK_STACK=()

register_rollback() {
    local command="$1"
    ROLLBACK_STACK+=("$command")
    debug "Registered rollback command: $command"
}

execute_rollback() {
    local reason="$1"
    local exit_code="${2:-1}"

    error "Initiating rollback: $reason"

    # Execute rollback commands in reverse order
    for ((i=${#ROLLBACK_STACK[@]}-1; i>=0; i--)); do
        local cmd="${ROLLBACK_STACK[i]}"
        warn "Executing rollback command: $cmd"
        eval "$cmd" || warn "Rollback command failed: $cmd"
    done

    # Clear the rollback stack
    ROLLBACK_STACK=()

    error "Rollback complete"
    return $exit_code
}

# Example rollback registrations:
# register_rollback "docker compose -f \"$DOCKER_COMPOSE_FILE\" down"
# register_rollback "rm -rf \"$CONTAINER_DIR\""
# register_rollback "userdel -r \"$tunnel_user\""

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

# ─── Error Recovery System ────────────────────────────────────

# Error status tracking
declare -A ERROR_STATUS
declare -i ERROR_COUNT=0
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5

# Error types
readonly E_GENERAL=1      # General error
readonly E_NETWORK=2      # Network-related error
readonly E_PERMISSION=3   # Permission-related error
readonly E_DOCKER=4      # Docker-related error
readonly E_FILESYSTEM=5   # Filesystem-related error
readonly E_DEPENDENCY=6   # Dependency-related error

# Recovery state file
readonly RECOVERY_STATE="/tmp/msi_recovery_state"

save_recovery_state() {
    local stage="$1"
    local data="${2:-}"

    mkdir -p "$(dirname "$RECOVERY_STATE")"
    echo "STAGE=$stage" > "$RECOVERY_STATE"
    echo "DATA=$data" >> "$RECOVERY_STATE"
    echo "TIMESTAMP=$(date +%s)" >> "$RECOVERY_STATE"
}

load_recovery_state() {
    if [[ -f "$RECOVERY_STATE" ]]; then
        source "$RECOVERY_STATE"
        return 0
    fi
    return 1
}

cleanup() {
    local exit_code=$?

    # Kill spinner if running
    if [[ -n "${spinner_pid:-}" ]]; then
        kill "${spinner_pid}" &>/dev/null || true
        wait "${spinner_pid}" 2>/dev/null || true
        spinner_pid=""
    fi

    # Cleanup temporary files
    rm -f "$RECOVERY_STATE"

    # If error occurred during Docker setup, ensure containers are stopped
    if [[ $exit_code -ne 0 && -f "$DOCKER_COMPOSE_FILE" ]]; then
        docker compose -f "$DOCKER_COMPOSE_FILE" down &>/dev/null || true
    fi

    # Log final status
    if [[ $exit_code -eq 0 ]]; then
        info "Script completed successfully"
    else
        error "Script failed with exit code $exit_code"
    fi

    exit $exit_code
}

error_handler() {
    local line_num=$1
    local error_code=$2
    local last_cmd=$3
    local retry_count=${4:-0}

    error "Error occurred in script at line: $line_num"
    error "Command: $last_cmd"
    error "Exit code: $error_code"

    # Track error
    ERROR_STATUS["$line_num"]=$error_code
    ((ERROR_COUNT++))

    # Determine error type
    local error_type
    case $error_code in
        126|127) error_type=$E_DEPENDENCY ;; # Command not found
        13)      error_type=$E_PERMISSION ;; # Permission denied
        28)      error_type=$E_NETWORK ;;    # Network timeout
        *)       error_type=$E_GENERAL ;;
    esac

    # Attempt recovery based on error type
    if [[ $retry_count -lt $MAX_RETRIES ]]; then
        warn "Attempting recovery (attempt $((retry_count + 1))/$MAX_RETRIES)..."

        case $error_type in
            $E_NETWORK)
                warn "Network error detected, waiting before retry..."
                sleep $((RETRY_DELAY * 2))
                ;;
            $E_PERMISSION)
                warn "Permission error detected, checking sudo..."
                if ! sudo -n true 2>/dev/null; then
                    error "Sudo access required but not available"
                    exit $E_PERMISSION
                fi
                ;;
            $E_DOCKER)
                warn "Docker error detected, attempting service restart..."
                systemctl restart docker &>/dev/null || true
                sleep $RETRY_DELAY
                ;;
            $E_FILESYSTEM)
                warn "Filesystem error detected, checking disk space..."
                if ! check_disk_space; then
                    error "Insufficient disk space"
                    exit $E_FILESYSTEM
                fi
                ;;
        esac

        # Save state for recovery
        save_recovery_state "ERROR" "LINE=$line_num CMD=$last_cmd TYPE=$error_type"

        # Retry the failed command
        warn "Retrying failed command..."
        sleep $RETRY_DELAY
        eval "$last_cmd"
        local retry_result=$?

        if [[ $retry_result -eq 0 ]]; then
            info "Recovery successful"
            return 0
        else
            error_handler "$line_num" "$retry_result" "$last_cmd" $((retry_count + 1))
        fi
    else
        error "Maximum retry attempts reached"
        error "Error recovery failed"
        display_error_summary
        exit $error_code
    fi
}

check_disk_space() {
    local min_space=5242880 # 5GB in KB
    local available
    available=$(df -k "$BASE_DIR" | awk 'NR==2 {print $4}')
    [[ $available -ge $min_space ]]
}

display_error_summary() {
    if [[ $ERROR_COUNT -gt 0 ]]; then
        error "Error Summary:"
        error "Total errors encountered: $ERROR_COUNT"
        for line in "${!ERROR_STATUS[@]}"; do
            error "  Line $line: Exit code ${ERROR_STATUS[$line]}"
        done
    fi
}trap cleanup EXIT
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

# ─── Installation Process ─────────────────────────────────────

run_installation() {
    begin_transaction "Media Server Installation"

    # System Checks
    add_step "System requirements verification"
    for cmd in apt curl openssl awk id useradd systemctl; do
        print_status "Checking $cmd"
        if ! require_command "$cmd"; then
            rollback_transaction "Missing required command: $cmd"
            return $E_DEPENDENCY
        fi
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

# ─── Environmental Compatibility Checks ──────────────────────

readonly -A REQUIRED_KERNEL_PARAMS=(
    ["net.ipv4.ip_forward"]="1"
    ["net.bridge.bridge-nf-call-iptables"]="1"
    ["fs.inotify.max_user_watches"]="524288"
)

readonly -a REQUIRED_FILESYSTEMS=(
    "overlay"
    "overlay2"
)

validate_environment() {
    local result=0
    print_status "Validating system environment"

    # Check kernel version
    local kernel_version
    kernel_version=$(uname -r)
    if ! awk -v ver="$kernel_version" 'BEGIN{if (ver < "4.0.0") exit 1; exit 0}'; then
        error "Kernel version $kernel_version is too old (minimum 4.0.0 required)"
        ((result++))
    fi

    # Check system architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            debug "Architecture $arch is supported"
            ;;
        aarch64|arm64)
            debug "Architecture $arch is supported"
            ;;
        *)
            error "Unsupported architecture: $arch"
            ((result++))
            ;;
    esac

    # Validate kernel parameters
    for param in "${!REQUIRED_KERNEL_PARAMS[@]}"; do
        local expected="${REQUIRED_KERNEL_PARAMS[$param]}"
        local actual
        actual=$(sysctl -n "$param" 2>/dev/null)
        if [[ -z "$actual" ]]; then
            error "Kernel parameter $param is not set"
            ((result++))
        elif [[ "$actual" != "$expected" ]]; then
            error "Kernel parameter $param=$actual (expected $expected)"
            ((result++))
        fi
    done

    # Check required filesystems
    local missing_fs=0
    for fs in "${REQUIRED_FILESYSTEMS[@]}"; do
        if ! grep -q "$fs" /proc/filesystems; then
            error "Required filesystem $fs is not available"
            ((missing_fs++))
        fi
    done
    ((result+=missing_fs))

    # Check system entropy
    local entropy
    entropy=$(cat /proc/sys/kernel/random/entropy_avail)
    if [[ $entropy -lt 1000 ]]; then
        warn "Low entropy pool ($entropy bytes available)"
    fi

    # Check system locale
    if [[ -z "${LANG:-}" ]]; then
        warn "LANG environment variable is not set"
    elif ! locale -a | grep -q "${LANG%.*}"; then
        error "System locale $LANG is not installed"
        ((result++))
    fi

    # Check system time synchronization
    if command -v timedatectl &>/dev/null; then
        if ! timedatectl status | grep -q "synchronized: yes"; then
            warn "System time is not synchronized"
        fi
    fi

    # Check for required device nodes
    for device in /dev/stdin /dev/stdout /dev/stderr /dev/null /dev/random /dev/urandom; do
        if [[ ! -e "$device" ]]; then
            error "Required device node $device is missing"
            ((result++))
        fi
    done

    # Check SELinux/AppArmor status
    if command -v getenforce &>/dev/null; then
        local selinux_mode
        selinux_mode=$(getenforce 2>/dev/null)
        case "$selinux_mode" in
            Enforcing)
                warn "SELinux is in enforcing mode, might need configuration"
                ;;
            Disabled)
                debug "SELinux is disabled"
                ;;
        esac
    fi

    if command -v aa-status &>/dev/null; then
        if aa-status --enabled 2>/dev/null; then
            warn "AppArmor is enabled, might need configuration"
        fi
    fi

    return $result
}

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

# ─── Configuration Validation ─────────────────────────────────

# Configuration schema
declare -A CONFIG_SCHEMA=(
    ["cidr"]="required|cidr"
    ["docker_user"]="required|existing_user"
    ["USER_TZ"]="required|timezone"
    ["tunnel_user"]="required|valid_username"
    ["tunnel_pass"]="required|min:6"
    ["motd_path"]="optional|file_path"
)

# Configuration constraints
readonly MIN_MEMORY_MB=2048
readonly MIN_DISK_GB=20
readonly REQUIRED_PORTS=(8096 6767 7878 8080 8989 9696 5800)

validate_config_schema() {
    local key="$1"
    local value="$2"
    local rules="${CONFIG_SCHEMA[$key]}"
    local IFS='|'
    local result=0

    debug "Validating $key=$value against rules: $rules"

    for rule in $rules; do
        case "$rule" in
            "required")
                if [[ -z "$value" ]]; then
                    error "Configuration error: $key is required"
                    return 1
                fi
                ;;
            "optional")
                [[ -z "$value" ]] && return 0
                ;;
            "cidr")
                if ! validate_cidr "$value"; then
                    error "Configuration error: $key must be a valid CIDR notation"
                    return 1
                fi
                ;;
            "existing_user")
                if ! id "$value" &>/dev/null; then
                    error "Configuration error: User $value does not exist"
                    return 1
                fi
                ;;
            "timezone")
                if ! validate_timezone "$value"; then
                    error "Configuration error: Invalid timezone $value"
                    return 1
                fi
                ;;
            "valid_username")
                if ! validate_username "$value"; then
                    error "Configuration error: Invalid username format for $value"
                    return 1
                fi
                ;;
            min:*)
                local min_length="${rule#min:}"
                if [[ ${#value} -lt $min_length ]]; then
                    error "Configuration error: $key must be at least $min_length characters"
                    return 1
                fi
                ;;
            "file_path")
                if [[ -n "$value" && ! -e "$(dirname "$value")" ]]; then
                    error "Configuration error: Directory for $value does not exist"
                    return 1
                fi
                ;;
        esac
    done

    return $result
}

validate_system_requirements() {
    local result=0

    # Check memory
    local total_memory
    total_memory=$(awk '/MemTotal/ {print $2/1024}' /proc/meminfo)
    if [[ ${total_memory%.*} -lt $MIN_MEMORY_MB ]]; then
        error "Insufficient memory: ${total_memory%.*}MB (minimum ${MIN_MEMORY_MB}MB required)"
        result=1
    fi

    # Check disk space
    local available_space
    available_space=$(df -BG "$BASE_DIR" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $available_space -lt $MIN_DISK_GB ]]; then
        error "Insufficient disk space: ${available_space}GB (minimum ${MIN_DISK_GB}GB required)"
        result=1
    fi

    # Check port availability
    for port in "${REQUIRED_PORTS[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            error "Port $port is already in use"
            result=1
        fi
    done

    # Check Docker configuration
    if command -v docker &>/dev/null; then
        if ! docker info &>/dev/null; then
            error "Docker daemon is not running or not accessible"
            result=1
        fi
    fi

    return $result
}

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
    local validation_errors=0

    # First, load defaults
    for key in "${!DEFAULT_CONFIG[@]}"; do
        config["$key"]="${DEFAULT_CONFIG[$key]}"
    done

    if [[ -f "$config_file" ]]; then
        debug "Loading configuration from $config_file"

        # Validate file permissions
        if [[ $(stat -c %a "$config_file") != "600" ]]; then
            warn "Configuration file has unsafe permissions"
            chmod 600 "$config_file" || {
                error "Failed to set secure permissions on config file"
                return 1
            }
        }

        # Parse and validate configuration
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue

            # Trim whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            # Validate against schema if exists
            if [[ -n "${CONFIG_SCHEMA[$key]:-}" ]]; then
                if ! validate_config_schema "$key" "$value"; then
                    error "Invalid configuration value for $key: $value"
                    ((validation_errors++))
                    continue
                fi
            else
                warn "Unknown configuration key: $key"
            fi

            config["$key"]="$value"
        done < "$config_file"
    else
        debug "No existing configuration found, using defaults"
    fi

    # Validate all required configurations are present
    for key in "${!CONFIG_SCHEMA[@]}"; do
        local rules="${CONFIG_SCHEMA[$key]}"
        if [[ $rules == *"required"* && -z "${config[$key]:-}" ]]; then
            error "Missing required configuration: $key"
            ((validation_errors++))
        fi
    fi

    # Perform system requirement validation
    if ! validate_system_requirements; then
        ((validation_errors++))
    fi

    # If there were validation errors, prompt for fix
    if [[ $validation_errors -gt 0 ]]; then
        error "$validation_errors configuration validation error(s) found"
        if [[ -z "${UNATTENDED:-}" ]]; then
            read -r -p "Would you like to reconfigure? [Y/n] " response
            [[ ${response,,} =~ ^(yes|y|)$ ]] && return 2
        fi
        return 1
    fi

    return 0
}# ─── User Permission Validation ────────────────────────────

readonly -a REQUIRED_USER_GROUPS=(
    "docker"
    "sudo"
)

validate_user_permissions() {
    local username="$1"
    local result=0
    print_status "Validating user permissions for $username"

    # Check if user exists
    if ! id "$username" &>/dev/null; then
        error "User $username does not exist"
        return 1
    }

    # Get user's UID and primary group
    local user_uid
    local user_gid
    user_uid=$(id -u "$username")
    user_gid=$(id -g "$username")

    # Check UID (avoid system user range)
    if [[ $user_uid -lt 1000 ]]; then
        error "User $username has system UID ($user_uid). Regular user UID should be >= 1000"
        ((result++))
    fi

    # Check required groups membership
    for group in "${REQUIRED_USER_GROUPS[@]}"; do
        if ! getent group "$group" &>/dev/null; then
            error "Required group $group does not exist"
            ((result++))
        elif ! groups "$username" | grep -q "\b$group\b"; then
            error "User $username is not a member of required group $group"
            ((result++))
        fi
    done

    # Check home directory
    local user_home
    user_home=$(getent passwd "$username" | cut -d: -f6)
    if [[ ! -d "$user_home" ]]; then
        error "Home directory $user_home does not exist"
        ((result++))
    else
        # Check home directory permissions
        local home_perms
        home_perms=$(stat -c "%a" "$user_home")
        if [[ $home_perms != "755" && $home_perms != "750" ]]; then
            warn "Home directory $user_home has potentially unsafe permissions: $home_perms"
        fi
    fi

    # Check sudo access if required
    if [[ " ${REQUIRED_USER_GROUPS[*]} " == *" sudo "* ]]; then
        if ! sudo -l -U "$username" &>/dev/null; then
            error "User $username does not have sudo privileges"
            ((result++))
        fi
    fi

    # Validate Docker permissions
    if command -v docker &>/dev/null; then
        if ! docker info &>/dev/null; then
            if ! groups "$username" | grep -q "\bdocker\b"; then
                error "User $username cannot access Docker daemon"
                ((result++))
            fi
        fi
    fi

    return $result
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

# ─── Docker Configuration Validation ────────────────────────

validate_docker_config() {
    local result=0

    # Check Docker daemon configuration
    if [[ -f "/etc/docker/daemon.json" ]]; then
        if ! jq empty "/etc/docker/daemon.json" 2>/dev/null; then
            error "Invalid Docker daemon configuration file"
            result=1
        fi
    fi

    # Validate Docker network configuration
    if docker network ls &>/dev/null; then
        for network in "media_network" "jd_network"; do
            if docker network inspect "$network" &>/dev/null; then
                if ! docker network inspect "$network" | grep -q "\"Driver\": \"bridge\""; then
                    error "Network $network exists but is not a bridge network"
                    result=1
                fi
            fi
        done
    else
        error "Unable to inspect Docker networks"
        result=1
    fi

    # Check Docker storage driver
    local storage_driver
    storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null)
    case "$storage_driver" in
        overlay2|overlay)
            debug "Using recommended storage driver: $storage_driver"
            ;;
        *)
            warn "Using non-standard storage driver: $storage_driver"
            ;;
    esac

    # Validate Docker compose file
    if [[ -f "$DOCKER_COMPOSE_FILE" ]]; then
        if ! docker compose -f "$DOCKER_COMPOSE_FILE" config --quiet 2>/dev/null; then
            error "Invalid Docker compose configuration"
            result=1
        fi
    fi

    # Check available volume space
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
    if [[ -n "$docker_root" ]]; then
        local available_space
        available_space=$(df -BG "$docker_root" | awk 'NR==2 {print $4}' | tr -d 'G')
        if [[ $available_space -lt $MIN_DISK_GB ]]; then
            error "Insufficient space in Docker root directory: ${available_space}GB (minimum ${MIN_DISK_GB}GB required)"
            result=1
        fi
    fi

    return $result
}

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
