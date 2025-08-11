# msi.sh — Media Server Installer

<pre style="color:#00FFFF;">
                            ░██               ░██
                                              ░██
 ░█████████████   ░███████  ░██     ░███████  ░████████
 ░██   ░██   ░██ ░██        ░██    ░██        ░██    ░██
 ░██   ░██   ░██  ░███████  ░██     ░███████  ░██    ░██
 ░██   ░██   ░██        ░██ ░██           ░██ ░██    ░██
 ░██   ░██   ░██  ░███████  ░██░██  ░███████  ░██    ░██
</pre>

Automated installer script for setting up a self-hosted media server using **Docker** and services like **Jellyfin**, **Sonarr**, **Radarr**, **Prowlarr**, **Bazarr**, and **qBittorrent**.

## 📦 What It Does

`msi.sh` simplifies and automates the setup of a full-featured media stack on Linux systems. It configures:

- Containerized media services with **Docker**
- Secure SSH tunneling for *arr stack management
- Firewall rules to restrict access
- A systemd-friendly folder layout
- Easy update script for maintenance

## 👤 Who It's For

This script is ideal for:

- **Self-hosters** who want a local or remote media server without cloud dependency.
- **Linux-savvy users** who prefer containerization via Docker.
- **Developers and sysadmins** seeking automation for repeatable deployments.
- **Home lab enthusiasts** setting up lightweight media gateways for personal or family use.

## 💡 Ideal Use Case

A typical use case might look like:

> "I have a spare PC or VPS and I want to stream movies and shows using Jellyfin, automatically manage downloads via Sonarr/Radarr, and control access securely through SSH tunneling."

Whether you're deploying this on your LAN, cloud VM, or homelab node, `msi.sh` gives you a reliable, secure, and reproducible media server setup in minutes.

## 🚀 Getting Started

1. Download the script:
   ```bash
   git clone https://github.com/nobikaze/media-server-installer.git
   cd msi.sh
   chmod +x msi.sh
   ```

2. Run as root:
   ```bash
   sudo ./msi.sh
   ```

3. Follow the prompts to configure:
   - CIDR allowed IPs
   - Docker user
   - Timezone
   - SSH tunnel user credentials
   - MOTD location

4. When complete, use the printed SSH tunnel command to access services securely.

## 🔁 Maintenance

To update system packages and containers, run:

```bash
sudo msi-update
```

This will:
- Update system packages
- Pull the latest container images
- Restart updated containers
- Prune unused images

## 🛠 Services Deployed

| Service      | Port | Purpose             |
|--------------|------|---------------------|
| Jellyfin     | 8096 | Media streaming     |
| Sonarr       | 8989 | TV show automation  |
| Radarr       | 7878 | Movie automation     |
| Prowlarr     | 9696 | Indexer manager     |
| Bazarr       | 6767 | Subtitle management |
| qBittorrent  | 8080 | Torrent client      |

All services except **Jellyfin** are **bound to localhost** and accessible via **SSH tunnel only** by default for security.

## ⚠️ Notes

- Run only on clean or properly configured systems.
- Ensure enough disk space is available for media and containers.
- Script requires root privileges.
- **Jellyfin is configured for Direct Play only** — transcoding isn’t supported in this setup. It's recommended to disable transcoding in the server settings to lighten the load on your CPU, cut down on power use, and be a bit kinder to the planet.
- **Launching containers may take time, especially on first run,** depending on your internet connection speed.

## 📜 License

MIT License