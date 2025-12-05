#!/bin/bash
# install_plugins.sh - Automated Jellyfin plugin installation
# Run after Jellyfin container is up and running

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="${1:-jellyfin}"
JELLYFIN_VERSION="10.11.4"

# Plugin definitions: name|version|download_url
PLUGINS=(
    "File Transformation|2.5.1.0|https://github.com/IAmParadox27/jellyfin-plugin-file-transformation/releases/download/2.5.1.0/Release-10.11.4.zip"
    "Jellyfin Enhanced|9.6.2.0|https://github.com/n00bcodr/Jellyfin-Enhanced/releases/download/9.6.2.0/Jellyfin.Plugin.JellyfinEnhanced_10.11.0.zip"
    "Media Bar|2.4.4.0|https://github.com/IAmParadox27/jellyfin-plugin-media-bar/releases/download/2.4.4.0/Release-10.11.4.zip"
)

echo "=== Jellyfin Plugin Installer ==="
echo "Container: $CONTAINER_NAME"
echo "Jellyfin Version: $JELLYFIN_VERSION"
echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "ERROR: Container '$CONTAINER_NAME' is not running"
    exit 1
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

install_plugin() {
    local name="$1"
    local version="$2"
    local url="$3"
    local plugin_dir="${name}_${version}"
    
    echo "Installing: $name v$version"
    
    # Check if already installed
    if docker exec "$CONTAINER_NAME" test -d "/config/data/plugins/$plugin_dir" 2>/dev/null; then
        echo "  ✓ Already installed, skipping"
        return 0
    fi
    
    # Download
    local zip_file="$TEMP_DIR/${name}.zip"
    echo "  Downloading..."
    if ! curl -sL -o "$zip_file" "$url"; then
        echo "  ✗ Failed to download"
        return 1
    fi
    
    # Extract
    local extract_dir="$TEMP_DIR/$plugin_dir"
    mkdir -p "$extract_dir"
    if ! unzip -q -o "$zip_file" -d "$extract_dir"; then
        echo "  ✗ Failed to extract"
        return 1
    fi
    
    # Copy to container
    if ! docker cp "$extract_dir" "$CONTAINER_NAME:/config/data/plugins/"; then
        echo "  ✗ Failed to copy to container"
        return 1
    fi
    
    # Fix permissions
    docker exec "$CONTAINER_NAME" chown -R abc:abc "/config/data/plugins/$plugin_dir"
    
    echo "  ✓ Installed successfully"
    return 0
}

# Install each plugin
INSTALLED=0
for plugin in "${PLUGINS[@]}"; do
    IFS='|' read -r name version url <<< "$plugin"
    if install_plugin "$name" "$version" "$url"; then
        ((INSTALLED++)) || true
    fi
done

echo ""
echo "=== Installation Complete ==="
echo "Plugins processed: ${#PLUGINS[@]}"
echo "Newly installed: $INSTALLED"

if [ "$INSTALLED" -gt 0 ]; then
    echo ""
    echo "Restarting Jellyfin to load new plugins..."
    docker restart "$CONTAINER_NAME"
    echo "Done! Wait ~10 seconds for Jellyfin to start."
fi
