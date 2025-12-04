#!/bin/bash
set -e

# Configure NZBGet authentication after container starts
# This script modifies the NZBGet config with credentials from .credentials file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$MEDIA_DIR"

# Load credentials
if [ ! -f .config/.credentials ]; then
    echo "Error: .config/.credentials file not found"
    exit 1
fi

source .config/.credentials

# Wait for NZBGet to create its default config
echo "Waiting for NZBGet to create default config..."
for i in {1..30}; do
    if [ -f nzbget/nzbget.conf ]; then
        echo "Config file found."
        break
    fi
    sleep 1
done

if [ ! -f nzbget/nzbget.conf ]; then
    echo "Error: NZBGet config not created after 30 seconds"
    exit 1
fi

# Update credentials in the config
echo "Updating NZBGet credentials..."
sed -i "s/^ControlUsername=.*/ControlUsername=$USERNAME/" nzbget/nzbget.conf
sed -i "s/^ControlPassword=.*/ControlPassword=$PASSWORD/" nzbget/nzbget.conf

# Update download paths to use /data
echo "Updating download paths..."
sed -i "s|^MainDir=.*|MainDir=/data/downloads/nzbget|" nzbget/nzbget.conf
sed -i "s|^DestDir=.*|DestDir=/data/downloads/nzbget/completed|" nzbget/nzbget.conf
sed -i "s|^InterDir=.*|InterDir=/data/downloads/nzbget/intermediate|" nzbget/nzbget.conf
sed -i "s|^NzbDir=.*|NzbDir=/data/downloads/nzbget/nzb|" nzbget/nzbget.conf
sed -i "s|^QueueDir=.*|QueueDir=/data/downloads/nzbget/queue|" nzbget/nzbget.conf
sed -i "s|^TempDir=.*|TempDir=/data/downloads/nzbget/tmp|" nzbget/nzbget.conf

echo "NZBGet configuration updated. Restarting container..."
docker compose restart nzbget

echo "Waiting for NZBGet to be ready..."
sleep 5

echo "Done! NZBGet should now be accessible with your credentials."
