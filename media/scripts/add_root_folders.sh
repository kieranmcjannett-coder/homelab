#!/usr/bin/env bash
set -euo pipefail

# Add root folders to Arr apps via API after services have started
# This script waits for services to be ready and adds root folders automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$MEDIA_DIR"

# Load DATA_DIR from .env
DATA_DIR="/data"
if [[ -f .env ]]; then
  DATA_DIR=$(grep -E "^DATA_DIR=" .env | tail -n1 | cut -d'=' -f2)
  DATA_DIR=${DATA_DIR:-/data}
fi

# Function to wait for service and add root folder
add_root_folder() {
  local SERVICE=$1
  local PORT=$2
  local API_KEY_FILE=$3
  local ROOT_PATH=$4
  
  echo "Waiting for $SERVICE to be ready..."
  for i in {1..30}; do
    if curl -s "http://localhost:$PORT/ping" > /dev/null 2>&1; then
      echo "  $SERVICE is up!"
      break
    fi
    if [[ $i -eq 30 ]]; then
      echo "  Warning: $SERVICE did not respond after 60 seconds"
      return 1
    fi
    sleep 2
  done
  
  # Extract API key from config.xml
  if [[ ! -f "$API_KEY_FILE" ]]; then
    echo "  Warning: Config file not found: $API_KEY_FILE"
    return 1
  fi
  
  API_KEY=$(grep -oP '<ApiKey>\K[^<]+' "$API_KEY_FILE" 2>/dev/null | tr -d '[:space:]' || echo "")
  
  if [[ -z "$API_KEY" ]]; then
    echo "  Warning: Could not find API key for $SERVICE"
    return 1
  fi
  
  # Check if root folder already exists
  EXISTING=$(curl -s -H "X-Api-Key: $API_KEY" "http://localhost:$PORT/api/v3/rootfolder" || echo "[]")
  
  if echo "$EXISTING" | grep -q "\"path\":\"$ROOT_PATH\""; then
    echo "  ✓ Root folder already exists for $SERVICE: $ROOT_PATH"
    return 0
  fi
  
  # Add root folder via API
  echo "  Adding root folder to $SERVICE: $ROOT_PATH"
  RESULT=$(curl -s -X POST -H "X-Api-Key: $API_KEY" -H "Content-Type: application/json" \
    -d "{\"path\":\"$ROOT_PATH\"}" "http://localhost:$PORT/api/v3/rootfolder" 2>&1 || echo "failed")
  
  # Check if it failed because folder already exists (this is actually success)
  if echo "$RESULT" | grep -q "already configured as a root folder"; then
    echo "  ✓ Root folder already configured for $SERVICE: $ROOT_PATH"
    return 0
  elif [[ "$RESULT" == "failed" || "$RESULT" == *"\"errorCode\""* ]]; then
    echo "  ✗ Failed to add root folder to $SERVICE"
    echo "    Response: $RESULT"
    return 1
  else
    echo "  ✓ Root folder added successfully to $SERVICE"
    return 0
  fi
}

echo "Adding root folders to Arr apps..."
echo ""

add_root_folder "Sonarr" "8989" "./sonarr/config.xml" "$DATA_DIR/shows"
add_root_folder "Radarr" "7878" "./radarr/config.xml" "$DATA_DIR/movies"
add_root_folder "Lidarr" "8686" "./lidarr/config.xml" "$DATA_DIR/music"

echo ""
echo "Root folder configuration complete!"
