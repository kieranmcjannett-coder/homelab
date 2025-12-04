#!/bin/bash
set -e

# Fix Jellyseerr API keys by removing whitespace

cd "$(dirname "$0")/.."

echo "Getting API keys..."
SONARR_KEY=$(grep -oP '<ApiKey>\K[^<]+' sonarr/config.xml | tr -d '[:space:]')
RADARR_KEY=$(grep -oP '<ApiKey>\K[^<]+' radarr/config.xml | tr -d '[:space:]')

cd jellyfin

echo "Stopping Jellyseerr..."
docker compose stop jellyseerr

echo "Updating settings.json..."
sudo python3 -c "
import json

with open('jellyseerr/settings.json', 'r') as f:
    config = json.load(f)

config['radarr'][0]['apiKey'] = '$RADARR_KEY'
config['sonarr'][0]['apiKey'] = '$SONARR_KEY'

with open('jellyseerr/settings.json', 'w') as f:
    json.dump(config, f, indent=2)

print('✓ API keys updated')
print('Radarr key: $RADARR_KEY')
print('Sonarr key: $SONARR_KEY')
"

echo "Starting Jellyseerr..."
docker compose start jellyseerr

echo "Waiting for startup..."
sleep 8

echo ""
echo "Checking logs..."
docker logs jellyseerr --tail 20 | grep -iE "radarr|sonarr|error|ready" || echo "No errors found"
