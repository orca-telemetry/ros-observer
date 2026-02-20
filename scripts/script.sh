#!/usr/bin/env bash

# --- Configuration ---
BINARY_URL="https://github.com/orca-telemetry/..."
BINARY_NAME="orca-ros-introspect"
INSTALL_DIR="$HOME/.local/bin/"
mkdir -p "$INSTALL_DIR"

set -euo pipefail

# 1. Determine ROS version + Source setup
# We look for Jazzy first, then fallback to any installed ROS 2 distro
if [[ -z "${ROS_DISTRO:-}" ]]; then
    echo "Scanning for ROS 2 installation..." >&2
    for _d in /opt/ros/jazzy /opt/ros/humble /opt/ros/rolling; do
        if [[ -f "${_d}/setup.bash" ]]; then
            set +u  # Disable 'unbound variable' checks
            source "${_d}/setup.bash"
            set -u  # Re-enable 'unbound variable' checks
            echo "Sourced ${_d}" >&2
            break
        fi
    done
fi

if [[ -z "${ROS_VERSION:-}" ]]; then
    echo "Error: ROS 2 environment not detected. Please install ROS 2 or source it manually." >&2
    exit 1
fi

# 2. Download the binary (if not present or if you want to force update)
TARGET_PATH="${INSTALL_DIR}/${BINARY_NAME}"
if [[ ! -f "$TARGET_PATH" ]]; then
    echo "Downloading ${BINARY_NAME}..." >&2
    # -L follows redirects, -s is silent, -S shows errors
    curl -L -sS -o "$TARGET_PATH" "$BINARY_URL"
    chmod +x "$TARGET_PATH"
fi

# 3. Run the binary
# We pass all script arguments ($@) directly to the Zig binary
if [[ ! -s "$TARGET_PATH" ]]; then
    echo "Error: Binary is empty or missing at $TARGET_PATH" >&2
    exit 1
fi
exec "$TARGET_PATH" provision --token "$@"

# now run the "discover" endpoint
