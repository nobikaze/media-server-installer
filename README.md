# Media Server Installer (`msi.sh`)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/nobikaze/media-server-installer?color=blue&label=Release)](https://github.com/nobikaze/media-server-installer/releases)
[![GitHub stars](https://img.shields.io/github/stars/nobikaze/media-server-installer?color=yellow)](https://github.com/nobikaze/media-server-installer/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/nobikaze/media-server-installer?color=orange)](https://github.com/nobikaze/media-server-installer/issues)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker&logoColor=white)](https://www.docker.com/)
[![Made for Linux](https://img.shields.io/badge/OS-Linux-darkgreen?logo=linux&logoColor=white)](#)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/nobikaze/media-server-installer/pulls)

---

Automated installer script for setting up a self-hosted media server using **Docker** and services like **Jellyfin**, **Sonarr**, **Radarr**, **Prowlarr**, **Bazarr**, **qBittorrent**, and **JDownloader 2**.

---

# 🚀 Now Powered by AI Innovation

This project now leverages an **AI-driven developer approach** to ensure it’s modern, efficient, and future-ready. By integrating innovative AI principles into its design and documentation, the project gains:

- **Smarter automation** – reducing repetitive tasks and simplifying complex setups.
- **Improved reliability** – AI-assisted code refinement helps minimize errors and edge cases.
- **Developer productivity** – freeing up time to focus on what matters, while AI handles boilerplate.
- **Future-proofing** – staying aligned with modern DevOps and self-hosting practices.

In short, this installer isn’t just about media servers anymore — it’s about bringing the **best of AI-enhanced development** into your homelab.

By adopting an AI-driven development approach, this project not only improves its immediate usability but also secures its long-term evolution. AI enables faster iteration cycles, where installation workflows, security practices, and documentation can be continuously analyzed, tested, and refined with greater precision. This reduces the likelihood of configuration errors, ensures compatibility across diverse environments, and promotes more resilient system design. Moreover, AI-driven insights help identify performance bottlenecks and streamline deployment strategies, making the installer more adaptive to future technological shifts. For contributors and maintainers, this means less time spent on repetitive fixes and more energy devoted to innovation, community-driven features, and sustainable growth. Ultimately, integrating AI into the development lifecycle transforms this project from a static installer into a living, intelligent framework — one that learns, adapts, and scales alongside the needs of modern self-hosters and developers.

---

## 📦 Overview

`msi.sh` simplifies and automates the setup of a full-featured media stack on Linux systems. It configures:

- Containerized media services with **Docker**
- Secure SSH tunneling for *arr stack management
- Firewall rules to restrict access
- A systemd-friendly folder layout
- Easy update script for maintenance

---

## 👤 Target Audience

This script is ideal for:

- **Self-hosters** who want a local or remote media server without cloud dependency.
- **Linux-savvy users** who prefer containerization via Docker.
- **Developers and sysadmins** seeking automation for repeatable deployments.
- **Home lab enthusiasts** setting up lightweight media gateways for personal or family use.

---

## 💡 Use Case

A typical use case might look like:

> "I have a spare PC or VPS and I want to stream movies and shows using Jellyfin, automatically manage downloads via Sonarr/Radarr, and control access securely through SSH tunneling."

Whether you're deploying this on your LAN, cloud VM, or homelab node, `msi.sh` gives you a reliable, secure, and reproducible media server setup in minutes.

---

## 📋 Prerequisites

- Linux (Debian 11+, Ubuntu 20.04+, or compatible)
- Root access
- At least 2GB RAM and 20GB free storage
- Internet connection

---

## 🚀 Installation

### 📥 Recommended Method — Install from Latest Release

1. Download the **latest** `.zip` from the [GitHub Releases page](https://github.com/nobikaze/media-server-installer/releases).
2. Extract the archive:
   ```bash
   unzip media-server-installer-*.zip
   cd media-server-installer
   ```
3. Make the script executable:
   ```bash
   chmod +x msi.sh
   ```
4. Run as root:
   ```bash
   sudo ./msi.sh
   ```

### 🛠 Alternative Method (Advanced) — Install from Git Repository

1. Clone the repository:
   ```bash
   git clone https://github.com/nobikaze/media-server-installer.git
   cd media-server-installer
   chmod +x msi.sh
   ```
2. Run as root:
   ```bash
   sudo ./msi.sh
   ```

---

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

---

## 🛠 Services Deployed

| Service      | Port | Purpose             |
|--------------|------|---------------------|
| Jellyfin     | 8096 | Media streaming     |
| Sonarr       | 8989 | TV show automation  |
| Radarr       | 7878 | Movie automation    |
| Prowlarr     | 9696 | Indexer manager     |
| Bazarr       | 6767 | Subtitle management |
| qBittorrent  | 8080 | Torrent client      |
| JDownloader 2| 5800 | Downloader manager  |

All services except **Jellyfin** are **bound to localhost** and accessible via **SSH tunnel only** by default for security.

---

## ⚠️ Notes

- Run only on clean or properly configured systems.
- Ensure enough disk space is available for media and containers.
- Script requires root privileges.
- **Jellyfin is configured for Direct Play only** — transcoding isn’t supported in this setup. It's recommended to disable transcoding in the server settings to lighten the load on your CPU, cut down on power use, and be a bit kinder to the planet.
- **Launching containers may take time, especially on first run,** depending on your internet connection speed.

---

## 🐛 Troubleshooting

- **Port already in use:** Edit `docker-compose.yml` and change the conflicting port.
- **Docker permission denied:** Ensure your user is in the `docker` group or run with `sudo`.

---

## 🧹 Uninstallation

To completely remove all containers, configuration, users, firewall rules, and packages installed by `msi.sh`, use the uninstall script:

> **Note:** For the cleanest recovery, it is highly recommended to create a system snapshot or backup before running these scripts. Restoring from a snapshot is often simpler and more reliable than manual uninstallation.

```bash
chmod +x msi-uninstall.sh
sudo ./msi-uninstall.sh
```

The script will prompt for confirmation before removing users, disabling the firewall, and uninstalling packages. Follow the prompts to clean up your system.

---

## 📜 License

MIT License