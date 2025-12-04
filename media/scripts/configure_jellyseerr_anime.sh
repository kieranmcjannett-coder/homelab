#!/bin/bash
set -e

# Configure Jellyseerr to use anime profiles from Sonarr and Radarr
# This script should be run AFTER configure_sonarr_anime.sh and configure_radarr_anime.sh
# so that the anime profiles already exist in Sonarr/Radarr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$MEDIA_DIR"

# Load CONFIG_DIR from .env
CONFIG_DIR="."
if [[ -f .env ]]; then
  CONFIG_DIR=$(grep -E "^CONFIG_DIR=" .env | cut -d'=' -f2 || echo ".")
  CONFIG_DIR="${CONFIG_DIR:-.}"
fi

JELLYSEERR_PORT=${JELLYSEERR_PORT:-5055}
JELLYSEERR_HOST="http://localhost:$JELLYSEERR_PORT"
SONARR_PORT=${SONARR_PORT:-8989}
SONARR_HOST="http://localhost:$SONARR_PORT"
RADARR_PORT=${RADARR_PORT:-7878}
RADARR_HOST="http://localhost:$RADARR_PORT"

echo "🎌 Configuring Jellyseerr for Anime"
echo "====================================="
echo ""
echo "This configures Jellyseerr to automatically use anime profiles"
echo "when users request anime content."
echo ""

# Check if Jellyseerr is running
if ! curl -s "$JELLYSEERR_HOST/api/v1/settings/public" > /dev/null 2>&1; then
    echo "⚠️  Jellyseerr is not running or not accessible"
    echo "Please start the media stack first: docker compose up -d"
    exit 0
fi

# Get API keys
SONARR_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' "$CONFIG_DIR/sonarr/config.xml" 2>/dev/null | tr -d '[:space:]' || echo "")
RADARR_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' "$CONFIG_DIR/radarr/config.xml" 2>/dev/null | tr -d '[:space:]' || echo "")

if [[ -z "$SONARR_API_KEY" || -z "$RADARR_API_KEY" ]]; then
    echo "⚠️  Could not find Sonarr/Radarr API keys"
    exit 0
fi

# Get anime profile ID from Sonarr
echo "Looking up Sonarr anime profile..."
SONARR_ANIME_PROFILE=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_HOST/api/v3/qualityprofile" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    profiles = json.load(sys.stdin)
    for p in profiles:
        if 'anime' in p.get('name', '').lower():
            print(json.dumps({'id': p['id'], 'name': p['name']}))
            break
except:
    pass
" 2>/dev/null || echo "")

if [[ -z "$SONARR_ANIME_PROFILE" ]]; then
    echo "⚠️  No anime profile found in Sonarr"
    echo "Run configure_sonarr_anime.sh first"
    SONARR_ANIME_ID=""
    SONARR_ANIME_NAME=""
else
    SONARR_ANIME_ID=$(echo "$SONARR_ANIME_PROFILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    SONARR_ANIME_NAME=$(echo "$SONARR_ANIME_PROFILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    echo "✓ Found Sonarr anime profile: $SONARR_ANIME_NAME (ID: $SONARR_ANIME_ID)"
fi

# Get anime profile ID from Radarr
echo "Looking up Radarr anime profile..."
RADARR_ANIME_PROFILE=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_HOST/api/v3/qualityprofile" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    profiles = json.load(sys.stdin)
    for p in profiles:
        if 'anime' in p.get('name', '').lower():
            print(json.dumps({'id': p['id'], 'name': p['name']}))
            break
except:
    pass
" 2>/dev/null || echo "")

if [[ -z "$RADARR_ANIME_PROFILE" ]]; then
    echo "⚠️  No anime profile found in Radarr"
    echo "Run configure_radarr_anime.sh first"
    RADARR_ANIME_ID=""
    RADARR_ANIME_NAME=""
else
    RADARR_ANIME_ID=$(echo "$RADARR_ANIME_PROFILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    RADARR_ANIME_NAME=$(echo "$RADARR_ANIME_PROFILE" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    echo "✓ Found Radarr anime profile: $RADARR_ANIME_NAME (ID: $RADARR_ANIME_ID)"
fi

# Get anime tag IDs
echo "Looking up anime tags..."
SONARR_ANIME_TAG=$(curl -s -H "X-Api-Key: $SONARR_API_KEY" "$SONARR_HOST/api/v3/tag" 2>/dev/null | \
    python3 -c "import sys,json; tags=json.load(sys.stdin); print(next((t['id'] for t in tags if t.get('label','').lower()=='anime'),''))" 2>/dev/null || echo "")

RADARR_ANIME_TAG=$(curl -s -H "X-Api-Key: $RADARR_API_KEY" "$RADARR_HOST/api/v3/tag" 2>/dev/null | \
    python3 -c "import sys,json; tags=json.load(sys.stdin); print(next((t['id'] for t in tags if t.get('label','').lower()=='anime'),''))" 2>/dev/null || echo "")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Updating Jellyseerr Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SETTINGS_FILE="$CONFIG_DIR/jellyfin/jellyseerr/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
    # Try alternate location
    SETTINGS_FILE="jellyfin/jellyseerr/settings.json"
fi

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "⚠️  Jellyseerr settings.json not found"
    echo "Please complete Jellyseerr initial setup first"
    exit 0
fi

# Create backup
cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak"

# Update settings with anime configuration
python3 << PYEOF
import json

settings_file = "$SETTINGS_FILE"
sonarr_anime_id = "$SONARR_ANIME_ID" if "$SONARR_ANIME_ID" else None
sonarr_anime_tag = int("$SONARR_ANIME_TAG") if "$SONARR_ANIME_TAG".isdigit() else None
radarr_anime_id = "$RADARR_ANIME_ID" if "$RADARR_ANIME_ID" else None
radarr_anime_tag = int("$RADARR_ANIME_TAG") if "$RADARR_ANIME_TAG".isdigit() else None

with open(settings_file, 'r') as f:
    config = json.load(f)

updated = False

# Update Sonarr anime settings
if config.get('sonarr') and len(config['sonarr']) > 0:
    sonarr = config['sonarr'][0]
    
    if sonarr_anime_id:
        sonarr['activeAnimeProfileId'] = int(sonarr_anime_id)
        sonarr['activeAnimeDirectory'] = '/data/shows'  # Same directory, just different profile
        updated = True
        print(f"  ✓ Set Sonarr anime profile ID: {sonarr_anime_id}")
    
    if sonarr_anime_tag:
        sonarr['animeTags'] = [sonarr_anime_tag]
        updated = True
        print(f"  ✓ Set Sonarr anime tag ID: {sonarr_anime_tag}")

# For Radarr, we need to either:
# 1. Add a second Radarr server entry for anime, or
# 2. Since Radarr doesn't have native anime profile support in Jellyseerr,
#    we rely on the post-add script to apply the anime profile

# Option: Add anime-specific Radarr server if profile exists
if radarr_anime_id and config.get('radarr') and len(config['radarr']) > 0:
    # Check if anime Radarr already exists
    has_anime_radarr = any(r.get('name', '').lower() == 'radarr (anime)' for r in config['radarr'])
    
    if not has_anime_radarr:
        base_radarr = config['radarr'][0].copy()
        anime_radarr = {
            "id": max(r['id'] for r in config['radarr']) + 1,
            "name": "Radarr (Anime)",
            "hostname": base_radarr.get('hostname', 'radarr'),
            "port": base_radarr.get('port', 7878),
            "apiKey": base_radarr.get('apiKey', ''),
            "useSsl": base_radarr.get('useSsl', False),
            "baseUrl": base_radarr.get('baseUrl', ''),
            "activeProfileId": int(radarr_anime_id),
            "activeProfileName": "HD - Anime",
            "activeDirectory": "/data/movies",
            "tags": [radarr_anime_tag] if radarr_anime_tag else [],
            "is4k": False,
            "minimumAvailability": "released",
            "isDefault": False,  # Not default - users select this for anime
            "externalUrl": "",
            "syncEnabled": True
        }
        config['radarr'].append(anime_radarr)
        updated = True
        print(f"  ✓ Added 'Radarr (Anime)' server with profile ID: {radarr_anime_id}")
    else:
        # Update existing anime Radarr
        for r in config['radarr']:
            if r.get('name', '').lower() == 'radarr (anime)':
                r['activeProfileId'] = int(radarr_anime_id)
                if radarr_anime_tag:
                    r['tags'] = [radarr_anime_tag]
                updated = True
                print(f"  ✓ Updated 'Radarr (Anime)' server with profile ID: {radarr_anime_id}")
                break

if updated:
    with open(settings_file, 'w') as f:
        json.dump(config, f, indent=1)
    print("")
    print("Settings saved!")
else:
    print("No updates needed")
PYEOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Jellyseerr Anime Configuration Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "What was configured:"
if [[ -n "$SONARR_ANIME_ID" ]]; then
    echo "  ✓ Sonarr anime profile for anime TV shows"
fi
if [[ -n "$RADARR_ANIME_ID" ]]; then
    echo "  ✓ Radarr (Anime) server for anime movies"
fi
echo ""
echo "How it works:"
echo "  • For anime TV shows: Jellyseerr auto-detects anime and uses"
echo "    the anime profile with Japanese audio preference"
echo ""
echo "  • For anime movies: Users should select 'Radarr (Anime)' when"
echo "    requesting anime movies to get Japanese audio preference"
echo ""
echo "Note: Restart Jellyseerr to apply changes:"
echo "  docker compose -f jellyfin/compose.yaml restart jellyseerr"
echo ""
