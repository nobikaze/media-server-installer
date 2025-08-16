# AI Agent Instructions for Media Server Installer

## Project Overview
This is a Bash-based installer script (`msi.sh`) that automates the setup of a containerized media server stack on Linux systems. The project follows a transaction-based approach for reliable installation and rollback capabilities.

## Key Architecture Concepts
- **Transaction System**: All operations are wrapped in transactions with logging (`/var/log/msi/transactions.log`)
- **Docker-based**: Services run in containers with defined network topology
- **SystemD Integration**: Uses systemd-friendly paths and service management
- **Security-first**: Implements SSH tunneling and firewall rules by default

## Developer Workflows

### Installation
```bash
chmod +x msi.sh
sudo ./msi.sh [OPTIONS]
```

Key options:
- `--debug`: Enable debug logging
- `--backup`: Create backup before installation
- `--unattended`: Non-interactive mode with defaults
- `--skip-docker`: Skip Docker installation

### Updates and Maintenance
- Use `msi-update.sh` for updating containers and system packages
- Use `msi-uninstall.sh` for clean removal

## Project Conventions

### Script Structure
1. Command-line parsing and validation
2. Transaction management
3. System checks and prerequisites
4. Component installation
5. Service configuration
6. Validation and completion

### Error Handling
- Uses `set -euo pipefail` for strict error checking
- All operations should be wrapped in transaction blocks
- Implement rollback handlers for failed operations

### Configuration
- Service configs stored in `/etc/msi/`
- Data persisted in `/var/lib/msi/`
- Logs written to `/var/log/msi/`

## Integration Points
1. **Docker**: Primary container runtime
2. **SystemD**: Service management
3. **UFW/Firewall**: Network security
4. **SSH**: Tunnel configuration

## Common Development Tasks

### Adding New Services
1. Define service configuration in `configs/`
2. Add Docker Compose service definition
3. Implement installation function
4. Add to transaction system
5. Update documentation

### Testing Changes
- Test both fresh installs and updates
- Verify unattended mode works
- Check rollback functionality
- Validate service accessibility

## Key Files
- `msi.sh`: Main installer script
- `msi-update.sh`: Update script
- `msi-uninstall.sh`: Uninstallation script
- `/var/log/msi/transactions.log`: Installation history
