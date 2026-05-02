#!/bin/bash
set -e

# Go to the workspace root
cd "$(dirname "$0")/.."

echo "Initializing Kimera workspace..."

# Initialize git if not already
if [ ! -d ".git" ]; then
    git init
fi

# Add submodules
echo "Adding Kimera submodules..."

function add_submodule() {
    local url=$1
    local path=$2
    if [ ! -d "$path" ]; then
        git submodule add "$url" "$path"
    else
        echo "Submodule $path already exists, skipping..."
    fi
}

add_submodule https://github.com/MIT-SPARK/Kimera-VIO.git src/Kimera-VIO
add_submodule https://github.com/MIT-SPARK/Kimera-Semantics.git src/Kimera-Semantics
add_submodule https://github.com/MIT-SPARK/Kimera-RPGO.git src/Kimera-RPGO
add_submodule https://github.com/ethz-asl/voxblox.git src/voxblox
# kalibr provides kalibr_bagcreater, used by scripts/download_datasets.sh
# to convert the EuRoC ASL-format zips into ROS bags.
add_submodule https://github.com/ethz-asl/kalibr.git src/kalibr

# Initialize and update submodules recursively
echo "Updating submodules..."
git submodule update --init --recursive

echo "Kimera workspace initialized successfully."
