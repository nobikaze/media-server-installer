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

# 🌌 Philosophy & Design Principles

Building a media server is not just about standing up containers or streaming files — it’s about creating a **digital ecosystem** that balances performance, security, and sustainability. `msi.sh` was designed with this broader perspective in mind, and its guiding principles reflect the lessons learned from years of experimentation in homelabs, cloud deployments, and production environments.

1. **Simplicity as Power**
   Automation is not about hiding complexity but about *managing* it. `msi.sh` follows a declarative approach where your intent (a working media server) is more important than the step-by-step commands. By reducing cognitive overhead, you spend less time debugging arcane Docker flags and more time enjoying your content.

2. **Security by Default**
   Self-hosting carries risks. That’s why this installer defaults to **local binding** and requires **explicit tunneling** for remote access. Instead of exposing dashboards to the open internet, it nudges you toward safer, VPN-like workflows. This philosophy ensures that convenience never comes at the cost of your privacy or data safety.

3. **Sustainability & Efficiency**
   Media consumption often leans on power-hungry machines and bloated setups. With `msi.sh`, the philosophy is **lean first**: containers are trimmed, transcoding is discouraged (favoring direct play), and maintenance is designed to be light. This helps you save on electricity bills, reduce e-waste, and contribute to a greener digital ecosystem without sacrificing functionality.

4. **Community over Perfection**
   This script will never be "finished." Instead, it is meant to **evolve with its users**. Issues, pull requests, and forks are not signs of weakness but proof of a living project. By encouraging collaboration, the installer grows in directions a single developer could never anticipate.

5. **Future-Readiness**
   The world of self-hosting is fast-moving. New services appear, protocols shift, and yesterday’s best practices quickly become obsolete. By keeping the installer modular and transparent, `msi.sh` ensures you are never locked into one “way of doing things.” It’s a foundation, not a cage — flexible enough to adapt to the technologies of tomorrow.

In essence, `msi.sh` is less about pushing a button and more about embracing a mindset: **automation that respects your time, protects your data, and scales with your imagination.** Whether you are setting up your very first Jellyfin server or integrating a complex homelab stack, this project is built to grow alongside you.

---

### 📖 Why Media Servers Matter in 2025

Self-hosting a media server is more than just convenience; it’s a **cultural and philosophical statement** about the way we interact with digital content. In a world where large corporations increasingly dictate how, when, and where we consume media, a personal media server restores **agency and autonomy** to the individual. Instead of being at the mercy of subscription services that rotate catalogs monthly, self-hosters curate their own collections, ensuring permanence, stability, and freedom.

From a technical standpoint, a media server is an excellent case study in **distributed systems**: it involves storage optimization, network management, data redundancy, and container orchestration. It becomes a personal lab where abstract concepts like reverse proxies, certificate management, or bandwidth shaping turn into practical, lived experiences.

From a sustainability angle, self-hosting fosters **digital stewardship**. By reusing old hardware and optimizing for direct play, one reduces reliance on sprawling server farms that consume enormous amounts of energy. The philosophy aligns with the principles of the **degrowth movement in technology** — doing more with less, reducing waste, and encouraging mindful consumption.

And on the human level? Media servers embody the **joy of ownership**. When you stream a film from Jellyfin that you personally archived, you engage with media in a deeper, more meaningful way. You are not a renter in someone else’s ecosystem; you are the custodian of your own library, a digital archivist preserving culture for yourself and those you care about.

---

### 📚 Long-Form Technical Deep Dive: Automation and Declarative Infrastructure

At its core, `msi.sh` operates on the principle of **infrastructure-as-code**. While larger organizations rely on tools like Terraform, Ansible, or Kubernetes, this project demonstrates that the same philosophy can be scaled down to the homelab. The installer defines not just *what* should be running (e.g., Sonarr, Radarr, Jellyfin), but also *how* those services interconnect.

This declarative approach has several key advantages:

1. **Idempotence** – Running the script multiple times should lead to the same stable outcome, avoiding the "works on my machine" problem.
2. **Reproducibility** – A user can destroy and recreate their setup without worrying about drift. The configuration is encoded in a version-controlled repository, not scattered across undocumented shell commands.
3. **Portability** – Because the stack is containerized, the same script can deploy on bare-metal servers, VMs, or even cloud instances with minimal modification.
4. **Transparency** – Unlike black-box installers, `msi.sh` is entirely open and inspectable, teaching users how things *actually work*.

This reflects a broader shift in computing: moving from artisanal, hand-crafted server setups toward automated, self-documenting infrastructure. What enterprises achieve with DevOps pipelines, the self-hoster achieves with a single script.

---

### 🌍 The Social Impact of Self-Hosting

We often treat self-hosting as a purely technical pursuit, but it has **social and political implications**. By running your own media server, you reduce reliance on centralized platforms that track behavior, monetize attention, and enforce censorship. This aligns with the philosophy of the **decentralized web**, where individuals reclaim power from gatekeepers.

A future with millions of self-hosted nodes creates a more **resilient internet**: if one service disappears, knowledge and culture persist elsewhere. In this way, even a single Jellyfin box in someone’s basement contributes to the broader vision of a **federated, user-owned digital commons**.

---

### 🧠 A Note on Learning by Doing

Perhaps the most important feature of `msi.sh` is not the software it installs, but the **learning pathway** it creates. Each user who runs the script steps into the world of:

* Docker container management
* Linux networking
* Systemd services
* Security principles like SSH tunneling and firewalls
* Automation workflows

The installer lowers the barrier to entry, but it also leaves enough room for curiosity. Once you’ve got a media server running, you might ask: *What else can I self-host?* That question is the spark that fuels homelabs, side projects, and even future careers in DevOps, SRE, and system architecture.

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