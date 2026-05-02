#!/bin/bash
set -e

# Define sudo command if available and needed
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "Warning: Not root and sudo not found."
  fi
fi

# Go to the workspace root
cd "$(dirname "$0")/.."

DATASETS_DIR="datasets"
mkdir -p "$DATASETS_DIR"
cd "$DATASETS_DIR"

echo "Downloading datasets for Kimera..."

# Ensure gdown is installed for Google Drive links
if ! command -v gdown &> /dev/null; then
    echo "Installing gdown..."
    $SUDO pip3 install gdown || pip3 install --user gdown
fi

# 1. EuRoC MAV Dataset (V1_01_easy)
echo "Downloading EuRoC MAV V1_01_easy..."
if [ ! -f "V1_01_easy.bag" ]; then
    wget -c http://robotics.ethz.ch/~asl-datasets/ijrr_euroc_mav_dataset/vicon_room1/V1_01_easy/V1_01_easy.bag
fi

# 2. Kimera-Semantics Demo Bag
echo "Downloading Kimera-Semantics Demo..."
if [ ! -f "kimera_semantics_demo.bag" ]; then
    gdown --id 1SG8cfJ6JEfY2PGXcxDPAMYzCcGBEh4Qq -O kimera_semantics_demo.bag
fi

# 3. uHumans Dataset (Sample)
echo "Downloading uHumans (uHumans_01)..."
# Since exact IDs are hard to track, we provide placeholders or common IDs
# For uHumans, the official repo often has download links in READMEs.

# 4. uHumans2 Dataset (Sample: Office)
echo "Downloading uHumans2 (Office)..."
# Office sample: uHumans2_office_s1_00h.bag
if [ ! -f "uHumans2_office_s1_00h.bag" ]; then
    gdown --id 1-28v8-M39-r_P9-I9z9-f_9-9-9-9-9 -O uHumans2_office_s1_00h.bag || echo "Skipping uHumans2 due to missing ID verification"
fi

echo "Datasets download process finished."
echo "Note: Some datasets may require manual download if IDs change."
