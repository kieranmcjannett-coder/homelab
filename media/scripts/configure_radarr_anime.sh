#!/bin/bash
set -e

# Configure Radarr for Anime Movies with Japanese Audio Preference
# This script seeds the anime configuration into Radarr:
# 1. Creates a custom format for Japanese audio
# 2. Creates an anime quality profile with Japanese audio preference
# 3. Applies configuration to existing anime movies
#
# This is part of the standard media stack automation and runs automatically
# during initial setup via automate_all.sh
#
# Can also be run manually to re-apply anime config to new movies:
#   bash configure_radarr_anime.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$MEDIA_DIR"

# Load CONFIG_DIR from .env (defaults to current directory)
CONFIG_DIR="."
if [[ -f .env ]]; then
  CONFIG_DIR=$(grep -E "^CONFIG_DIR=" .env | cut -d'=' -f2 || echo ".")
  CONFIG_DIR="${CONFIG_DIR:-.}"
fi

RADARR_PORT=${RADARR_PORT:-7878}
RADARR_HOST="http://localhost:$RADARR_PORT"
MAX_WAIT_TIME=60

echo "🎌 Configuring Radarr for Anime Movies (Japanese Audio)"
echo "========================================================"
echo ""

# Wait for Radarr to be ready
echo "Waiting for Radarr to be ready (max ${MAX_WAIT_TIME}s)..."
WAITED=0
while [ $WAITED -lt $MAX_WAIT_TIME ]; do
    if curl -s "$RADARR_HOST/ping" > /dev/null 2>&1; then
        echo "✓ Radarr is responding!"
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

if [ $WAITED -ge $MAX_WAIT_TIME ]; then
    echo "⚠️  Radarr did not respond after ${MAX_WAIT_TIME}s"
    echo "Continuing anyway - anime config will be applied when Radarr is ready"
    exit 0
fi

# Extract API key from config
API_KEY=$(grep -oP '<ApiKey>\K[^<]+' "$CONFIG_DIR/radarr/config.xml" 2>/dev/null | tr -d '[:space:]' || echo "")

if [[ -z "$API_KEY" ]]; then
    echo "⚠️  Warning: Could not find Radarr API key in config.xml"
    echo "Anime configuration will be skipped"
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Japanese Audio Custom Format"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if Japanese Audio custom format already exists
EXISTING_CF=$(curl -s -H "X-Api-Key: $API_KEY" "$RADARR_HOST/api/v3/customformat" | python3 -c "
import sys, json
try:
    formats = json.load(sys.stdin)
    for fmt in formats:
        if 'Japanese' in fmt.get('name', '') or 'japanese' in fmt.get('name', '').lower():
            print(fmt.get('id', ''))
            break
except:
    pass
" 2>/dev/null || echo "")

if [[ -n "$EXISTING_CF" ]]; then
    echo "✓ Japanese Audio custom format already exists (ID: $EXISTING_CF)"
    CF_ID=$EXISTING_CF
else
    echo "Creating 'Japanese Audio' custom format..."
    
    RESPONSE=$(curl -s -X POST \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        "$RADARR_HOST/api/v3/customformat" \
        -d '{
            "name": "Japanese Audio",
            "specifications": [
                {
                    "name": "Japanese Language",
                    "implementation": "ReleaseTitleSpecification",
                    "negate": false,
                    "required": false,
                    "fields": [
                        {
                            "order": 0,
                            "name": "value",
                            "label": "Regular Expression",
                            "value": "(?i)(japanese|jap\\b|jpn|日本)"
                        }
                    ]
                },
                {
                    "name": "Japanese Audio Track",
                    "implementation": "LanguageSpecification",
                    "negate": false,
                    "required": false,
                    "fields": [
                        {
                            "order": 0,
                            "name": "value",
                            "label": "Language",
                            "value": 8
                        }
                    ]
                }
            ],
            "includeCustomFormatWhenRenaming": false
        }')
    
    CF_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null || echo "")
    
    if [[ -n "$CF_ID" && "$CF_ID" != "" ]]; then
        echo "✓ Created Japanese Audio custom format (ID: $CF_ID)"
    else
        echo "⚠️  Could not create custom format (may already exist)"
        CF_ID=""
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Anime Tag"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get or create anime tag
TAGS=$(curl -s -H "X-Api-Key: $API_KEY" "$RADARR_HOST/api/v3/tag")
ANIME_TAG_ID=$(echo "$TAGS" | python3 -c "
import sys, json
try:
    tags = json.load(sys.stdin)
    for tag in tags:
        if tag.get('label', '').lower() == 'anime':
            print(tag.get('id', ''))
            break
except:
    pass
" 2>/dev/null || echo "")

if [[ -n "$ANIME_TAG_ID" ]]; then
    echo "✓ Anime tag already exists (ID: $ANIME_TAG_ID)"
else
    echo "Creating 'anime' tag..."
    TAG_RESPONSE=$(curl -s -X POST \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        "$RADARR_HOST/api/v3/tag" \
        -d '{"label": "anime"}')
    
    ANIME_TAG_ID=$(echo "$TAG_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null || echo "")
    
    if [[ -n "$ANIME_TAG_ID" ]]; then
        echo "✓ Created anime tag (ID: $ANIME_TAG_ID)"
    else
        echo "⚠️  Could not create anime tag"
        ANIME_TAG_ID="1"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Anime Quality Profile"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get existing quality profiles to clone from
PROFILES=$(curl -s -H "X-Api-Key: $API_KEY" "$RADARR_HOST/api/v3/qualityprofile")

# Check if anime profile already exists
ANIME_PROFILE_ID=$(echo "$PROFILES" | python3 -c "
import sys, json
try:
    profiles = json.load(sys.stdin)
    for prof in profiles:
        name = prof.get('name', '').lower()
        if 'anime' in name:
            print(prof.get('id', ''))
            break
except:
    pass
" 2>/dev/null || echo "")

if [[ -n "$ANIME_PROFILE_ID" ]]; then
    echo "✓ Anime quality profile already exists (ID: $ANIME_PROFILE_ID)"
else
    echo "Creating 'HD - Anime' quality profile..."
    
    # Get the first HD profile to use as a template
    PROFILE_TEMPLATE=$(echo "$PROFILES" | python3 -c "
import sys, json
try:
    profiles = json.load(sys.stdin)
    # Find HD-1080p or similar profile to clone
    for prof in profiles:
        name = prof.get('name', '').lower()
        if '1080' in name or 'hd' in name:
            # Remove the id so we create a new profile
            prof.pop('id', None)
            prof['name'] = 'HD - Anime'
            # Add custom format score for Japanese Audio if we have the CF_ID
            if '$CF_ID':
                cf_id = int('$CF_ID') if '$CF_ID'.isdigit() else 0
                if cf_id > 0:
                    prof['formatItems'] = prof.get('formatItems', [])
                    # Check if already has this format
                    has_cf = any(f.get('format') == cf_id for f in prof.get('formatItems', []))
                    if not has_cf:
                        prof['formatItems'].append({
                            'format': cf_id,
                            'score': 1000
                        })
            print(json.dumps(prof))
            break
    else:
        # Fallback - use first available profile
        if profiles:
            prof = profiles[0]
            prof.pop('id', None)
            prof['name'] = 'HD - Anime'
            print(json.dumps(prof))
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null || echo "")

    if [[ -n "$PROFILE_TEMPLATE" && "$PROFILE_TEMPLATE" != "" ]]; then
        PROFILE_RESPONSE=$(curl -s -X POST \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            "$RADARR_HOST/api/v3/qualityprofile" \
            -d "$PROFILE_TEMPLATE")
        
        ANIME_PROFILE_ID=$(echo "$PROFILE_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('id', ''))" 2>/dev/null || echo "")
        
        if [[ -n "$ANIME_PROFILE_ID" && "$ANIME_PROFILE_ID" != "" ]]; then
            echo "✓ Created anime quality profile (ID: $ANIME_PROFILE_ID)"
        else
            echo "⚠️  Could not create anime quality profile"
            echo "    Create it manually: Settings → Quality Profiles → Add"
            ANIME_PROFILE_ID=""
        fi
    else
        echo "⚠️  No existing profile to clone from"
        echo "    Create anime profile manually: Settings → Quality Profiles → Add"
    fi
fi

# Update existing profile with Japanese Audio custom format score
if [[ -n "$ANIME_PROFILE_ID" && -n "$CF_ID" ]]; then
    echo ""
    echo "Updating anime profile with Japanese Audio preference..."
    
    # Get current profile
    CURRENT_PROFILE=$(curl -s -H "X-Api-Key: $API_KEY" "$RADARR_HOST/api/v3/qualityprofile/$ANIME_PROFILE_ID")
    
    # Update with custom format score
    UPDATED_PROFILE=$(echo "$CURRENT_PROFILE" | python3 -c "
import sys, json
try:
    prof = json.load(sys.stdin)
    cf_id = int('$CF_ID')
    
    # Ensure formatItems exists
    if 'formatItems' not in prof:
        prof['formatItems'] = []
    
    # Check if Japanese Audio format already has a score
    found = False
    for item in prof['formatItems']:
        if item.get('format') == cf_id:
            item['score'] = 1000
            found = True
            break
    
    if not found:
        prof['formatItems'].append({
            'format': cf_id,
            'score': 1000
        })
    
    print(json.dumps(prof))
except Exception as e:
    print('')
" 2>/dev/null || echo "")

    if [[ -n "$UPDATED_PROFILE" ]]; then
        curl -s -X PUT \
            -H "X-Api-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            "$RADARR_HOST/api/v3/qualityprofile/$ANIME_PROFILE_ID" \
            -d "$UPDATED_PROFILE" > /dev/null
        echo "✓ Added Japanese Audio preference (score: +1000) to anime profile"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Auto-detect and Configure Anime Movies"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Process movies directly in Python to avoid shell variable issues
echo "Scanning movies for anime..."
API_KEY="$API_KEY" ANIME_TAG_ID="$ANIME_TAG_ID" ANIME_PROFILE_ID="$ANIME_PROFILE_ID" RADARR_HOST="$RADARR_HOST" python3 << 'PYTHON_SCRIPT'
import json, urllib.request, os

radarr_host = os.environ.get('RADARR_HOST', 'http://localhost:7878')
api_key = os.environ.get('API_KEY', '')
anime_tag_id_str = os.environ.get('ANIME_TAG_ID', '0')
anime_profile_id_str = os.environ.get('ANIME_PROFILE_ID', '0')
anime_tag_id = int(anime_tag_id_str) if anime_tag_id_str.isdigit() else 0
anime_profile_id = int(anime_profile_id_str) if anime_profile_id_str.isdigit() else 0

# Fetch movies from Radarr API
try:
    req = urllib.request.Request(
        f'{radarr_host}/api/v3/movie',
        headers={'X-Api-Key': api_key}
    )
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
except Exception as e:
    print(f"⚠️  Could not fetch movies from Radarr: {e}")
    data = []

if not data:
    print("No movies found in Radarr yet")
    exit(0)

# Known anime studios (common ones from TMDb)
ANIME_STUDIOS = [
    'studio ghibli', 'toei animation', 'madhouse', 'bones', 'a-1 pictures',
    'kyoto animation', 'ufotable', 'mappa', 'wit studio', 'production i.g',
    'sunrise', 'gainax', 'trigger', 'shaft', 'j.c.staff', 'pierrot',
    'gonzo', 'deen', 'xebec', 'tms entertainment', 'nippon animation',
    'toho animation', 'aniplex', 'funimation', 'crunchyroll', 'sentai',
    'comix wave films', 'science saru', 'cloverworks', 'polygon pictures',
    'orange', 'david production', 'white fox', 'feel', 'silver link',
    'lerche', 'p.a. works', 'kinema citrus', 'brains base', 'manglobe',
    'artland', 'asread', 'project no.9', 'doga kobo', 'seven arcs'
]

# Anime-related keywords in titles
ANIME_KEYWORDS = [
    'ghibli', 'anime', 'dragon ball', 'naruto', 'one piece', 'bleach',
    'sword art online', 'attack on titan', 'my hero academia', 'demon slayer',
    'jujutsu kaisen', 'evangelion', 'gundam', 'sailor moon', 'pokemon',
    'digimon', 'yu-gi-oh', 'fairy tail', 'hunter x hunter', 'fullmetal',
    'death note', 'code geass', 'steins', 'fate/', 'no game no life',
    'konosuba', 'overlord', 'rezero', 're:zero', 'isekai', 'shonen',
    'makoto shinkai', 'hayao miyazaki', 'mamoru hosoda', 'satoshi kon',
    'akira', 'ghost in the shell', 'paprika', 'perfect blue', 'weathering',
    'your name', 'kimi no na wa', 'spirited away', 'howl', 'totoro',
    'mononoke', 'ponyo', 'kiki', 'laputa', 'nausicaa', 'porco rosso',
    'whisper of the heart', 'the wind rises', 'arrietty', 'marnie',
    'suzume', 'tenki no ko', 'josee', 'belle', 'promare', 'redline'
]

updated = 0
anime_movies = 0
already_configured = 0

for movie in data:
    movie_id = movie['id']
    title = movie.get('title', '')
    title_lower = title.lower()
    original_title = movie.get('originalTitle', '').lower()
    genres = [g.lower() for g in movie.get('genres', [])]
    original_language = movie.get('originalLanguage', {}).get('name', '').lower()
    studio = movie.get('studio', '').lower() if movie.get('studio') else ''
    certification = movie.get('certification', '').lower() if movie.get('certification') else ''
    existing_tags = movie.get('tags', [])
    
    is_anime = False
    detection_reason = []
    
    # Method 1: Already tagged as anime
    if anime_tag_id > 0 and anime_tag_id in existing_tags:
        is_anime = True
        detection_reason.append('tagged')
    
    # Method 2: Animation genre + Japanese original language (most reliable)
    if not is_anime and 'animation' in genres and original_language == 'japanese':
        is_anime = True
        detection_reason.append('animation+japanese')
    
    # Method 3: Known anime studio
    if not is_anime and studio:
        for anime_studio in ANIME_STUDIOS:
            if anime_studio in studio:
                is_anime = True
                detection_reason.append(f'studio:{studio}')
                break
    
    # Method 4: Anime keywords in title (specific anime titles, directors, franchises)
    if not is_anime:
        for keyword in ANIME_KEYWORDS:
            if keyword in title_lower or keyword in original_title:
                is_anime = True
                detection_reason.append(f'keyword:{keyword}')
                break
    
    # Note: We do NOT use generic "Animation" genre alone as that would match
    # Western animation (Pixar, Disney, DreamWorks, etc.). We require Japanese
    # origin via language, studio, or specific anime keywords.
    
    if is_anime:
        anime_movies += 1
        needs_update = False
        updates = []
        
        # Check if tag needs adding
        if anime_tag_id > 0 and anime_tag_id not in movie.get('tags', []):
            movie['tags'] = movie.get('tags', []) + [anime_tag_id]
            updates.append('tag')
            needs_update = True
        
        # Check if profile needs updating
        current_profile = movie.get('qualityProfileId')
        if anime_profile_id > 0 and current_profile != anime_profile_id:
            movie['qualityProfileId'] = anime_profile_id
            updates.append('profile')
            needs_update = True
        
        if needs_update:
            reason_str = ', '.join(detection_reason)
            print(f'  🎬 {title}')
            print(f'     detected: {reason_str}')
            if 'tag' in updates:
                print(f'     → Adding anime tag')
            if 'profile' in updates:
                print(f'     → Updating quality profile to anime')
            
            # Update via API
            req = urllib.request.Request(
                f'{radarr_host}/api/v3/movie/{movie_id}',
                data=json.dumps(movie).encode('utf-8'),
                headers={
                    'X-Api-Key': api_key,
                    'Content-Type': 'application/json'
                },
                method='PUT'
            )
            try:
                urllib.request.urlopen(req)
                updated += 1
            except Exception as e:
                print(f'     ⚠️  Update failed: {e}')
        else:
            already_configured += 1

print(f"")
if anime_movies == 0:
    print("No anime movies detected in library")
    print("Tip: When Jellyseerr adds anime movies, run this script again")
    print("     Movies with Animation genre + Japanese language will be detected")
else:
    print(f"Summary:")
    print(f"  • Found {anime_movies} anime movies")
    print(f"  • Updated {updated} movies")
    print(f"  • Already configured: {already_configured}")
PYTHON_SCRIPT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Radarr Anime Configuration Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "What was configured:"
if [[ -n "$CF_ID" ]]; then
    echo "  ✓ Japanese Audio custom format (ID: $CF_ID)"
fi
if [[ -n "$ANIME_TAG_ID" ]]; then
    echo "  ✓ Anime tag (ID: $ANIME_TAG_ID)"
fi
if [[ -n "$ANIME_PROFILE_ID" ]]; then
    echo "  ✓ Anime quality profile (ID: $ANIME_PROFILE_ID)"
    echo "    → Japanese Audio gets +1000 score (preferred over dubs)"
fi
echo ""
echo "Auto-detection:"
echo "  Movies are auto-detected as anime if they have:"
echo "  • Animation genre + Japanese original language"
echo "  • Known anime studio (Ghibli, MAPPA, ufotable, etc.)"
echo "  • Anime keywords in title (Dragon Ball, Ghibli, etc.)"
echo "  • Already tagged with 'anime'"
echo ""
echo "Jellyseerr integration:"
echo "  When Jellyseerr adds anime movies, run this script to configure them:"
echo "    bash scripts/configure_radarr_anime.sh"
echo ""
echo "  Or set up a cron job to auto-run periodically:"
echo "    0 */6 * * * cd $MEDIA_DIR && bash scripts/configure_radarr_anime.sh"
echo ""
echo ""
