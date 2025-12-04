#!/usr/bin/env bash
set -euo pipefail

# Copy seed configs to service directories if they don't exist
# This runs before containers start to ensure fresh deploys have configs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEDIA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$MEDIA_DIR"
CONFIG_DIR="$MEDIA_DIR/.config"

# Load DATA_DIR from .env
DATA_DIR="/data"
if [[ -f .env ]]; then
  DATA_DIR=$(grep -E "^DATA_DIR=" .env | tail -n1 | cut -d'=' -f2)
  DATA_DIR=${DATA_DIR:-/data}
fi

echo "Checking for seed configs..."

# qBittorrent
if [[ ! -f ./qbittorrent/qBittorrent/qBittorrent.conf && -f "$CONFIG_DIR/qbittorrent/qBittorrent.conf" ]]; then
  echo "  Copying qBittorrent config..."
  mkdir -p ./qbittorrent/qBittorrent
  # Copy config and remove any authentication bypass settings
  grep -v "AuthSubnetWhitelist" "$CONFIG_DIR/qbittorrent/qBittorrent.conf" > ./qbittorrent/qBittorrent/qBittorrent.conf
fi

# NZBGet
if [[ ! -f ./nzbget/nzbget.conf && -f "$CONFIG_DIR/nzbget/nzbget.conf" ]]; then
  echo "  Copying NZBGet config..."
  mkdir -p ./nzbget
  cp "$CONFIG_DIR/nzbget/nzbget.conf" ./nzbget/nzbget.conf
fi

# Sonarr
if [[ ! -f ./sonarr/config.xml && -f "$CONFIG_DIR/sonarr/config.xml" ]]; then
  echo "  Copying Sonarr config..."
  cp "$CONFIG_DIR/sonarr/config.xml" ./sonarr/config.xml
fi

# Radarr
if [[ ! -f ./radarr/config.xml && -f "$CONFIG_DIR/radarr/config.xml" ]]; then
  echo "  Copying Radarr config..."
  cp "$CONFIG_DIR/radarr/config.xml" ./radarr/config.xml
fi

# Lidarr
if [[ ! -f ./lidarr/config.xml && -f "$CONFIG_DIR/lidarr/config.xml" ]]; then
  echo "  Copying Lidarr config..."
  cp "$CONFIG_DIR/lidarr/config.xml" ./lidarr/config.xml
fi

# Prowlarr
if [[ ! -f ./prowlarr/config.xml && -f "$CONFIG_DIR/prowlarr/config.xml" ]]; then
  echo "  Copying Prowlarr config..."
  cp "$CONFIG_DIR/prowlarr/config.xml" ./prowlarr/config.xml
fi

# Bazarr
if [[ ! -f ./bazarr/config/config.yaml && -f "$CONFIG_DIR/bazarr/config.yaml" ]]; then
  echo "  Copying Bazarr config..."
  mkdir -p ./bazarr/config
  cp "$CONFIG_DIR/bazarr/config.yaml" ./bazarr/config/config.yaml
fi

echo "Config initialization complete."
echo ""
echo "Note: After services start, run add_root_folders.sh to configure root folders via API."
